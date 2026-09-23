#!/usr/bin/env bash
# test-classify-md-inert.sh
# Pins the classify() fix: a markdown/txt-only diff is INERT regardless of the commit subject
# (a docs-only "migrate" commit is not stateful), while real stateful/behavioral signals are
# unchanged. Negative control: the pre-fix lib (read from the merge-base) classifies the same
# md-only "migrate" diff as stateful.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PROOF_LEDGER_LIB lets negctl --base-ref point the suite at an older lib.
LIB="${PROOF_LEDGER_LIB:-$KIT/lib/gate/proof-ledger.sh}"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# build a fixture: $1 dir, $2 = "md" | "code" | "codemd" content, $3 = commit subject
build() {
  local d="$1" kind="$2" subj="$3"
  rm -rf "$d"; mkdir -p "$d/docs" "$d/lib" "$d/tests" "$d/db/migrations"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo base > "$d/docs/x.md"; git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" checkout -qb feat/x
  case "$kind" in
    md)     echo more >> "$d/docs/x.md" ;;
    code)   echo 'echo hi' >> "$d/lib/y.sh" ;;
    codemd) echo more >> "$d/docs/x.md"; echo 'echo hi' >> "$d/lib/y.sh" ;;
    test)   echo 'echo hi' >> "$d/tests/test-helper.sh" ;;
    mig)    echo 'alter table t add c int;' >> "$d/db/migrations/002.sql"; echo 'echo hi' >> "$d/tests/test-helper.sh" ;;
    codetest) echo 'echo hi' >> "$d/lib/y.sh"; echo 'echo hi' >> "$d/tests/test-helper.sh" ;;
    deploy) echo 'echo hi' >> "$d/lib/deploy.sh" ;;
  esac
  git -C "$d" add -A; git -C "$d" commit -qm "$subj"
}
cls() { bash "$1" classify "$2" "$(git -C "$2" rev-parse main)"; }

# AC1: md-only + "migrate" subject -> inert (the fix)
F=/tmp/cls-md; build "$F" md "migrate eval + tool dialects"
[ "$(cls "$LIB" "$F")" = inert ] && pass "md-only 'migrate' diff -> inert" || fail "md-only 'migrate' should be inert, got $(cls "$LIB" "$F")"

# AC3a: code + "migrate" subject -> stateful (real signal preserved)
F=/tmp/cls-codemig; build "$F" code "migrate the database schema"
[ "$(cls "$LIB" "$F")" = stateful ] && pass "code+'migrate' diff -> stateful (preserved)" || fail "code+'migrate' should be stateful, got $(cls "$LIB" "$F")"

# AC3b: code-only, no keywords -> behavioral
F=/tmp/cls-code; build "$F" code "tweak the helper"
[ "$(cls "$LIB" "$F")" = behavioral ] && pass "code-only diff -> behavioral" || fail "code-only should be behavioral, got $(cls "$LIB" "$F")"

# AC2 negative control: a lib with the inert-FIRST block STRIPPED classifies md-only 'migrate'
# as stateful (the bug). History-independent: construct the pre-fix lib from the CURRENT one
# (awk the inert-FIRST block out), so this stays valid even after the fix is merged to master.
F=/tmp/cls-md   # reuse the md-only 'migrate' fixture
# The stripped copy MUST live beside the real lib: proof-ledger.sh resolves its siblings
# (lib/telemetry/kit-log-dir.sh) relative to its own path, so a copy in /tmp aborts with
# FATAL before it can classify anything. That dependency arrived after this test was
# written, which is why the control silently stopped reproducing the bug.
OLD="$(dirname "$LIB")/.cls-oldlib.tmp.sh"
trap 'rm -f "$OLD"' EXIT
# Strip the tests-only subject guard too: without it an md-only diff never reads its subject,
# so the inert-FIRST block alone would no longer be the only thing between md and stateful.
awk '/# inert FIRST/{s=1} /# Subject words count only/{s=0} !s' "$LIB" \
  | awk '/# Subject words count only/{s=1} s&&/^  fi$/{s=0; print "  subjects=\"$(_subjects \"$root\" \"$base\")\""; next} !s' > "$OLD"
if [ -s "$OLD" ] && grep -q 'stateful: deploy' "$OLD" && ! grep -q 'inert FIRST' "$OLD"; then
  [ "$(cls "$OLD" "$F")" = stateful ] && pass "inert-FIRST-stripped lib classifies md-only 'migrate' as stateful (the bug; fix is load-bearing)" || fail "stripped lib should reproduce the stateful bug, got $(cls "$OLD" "$F")"
else
  echo "[NO EXECUTABLE CHECK: could not strip the inert-FIRST block]"; fails=$((fails+1))
fi

# Subject-word trap: a tests-only diff is classified by its paths, never its subject.
# (a) tests-only + "restore" subject -> behavioral (the old lib read it stateful)
FA="$(mktemp -d)"; build "$FA" test "put the probe back: restore the helper"
[ "$(cls "$LIB" "$FA")" = behavioral ] && pass "tests-only 'restore' diff -> behavioral" || fail "tests-only 'restore' should be behavioral, got $(cls "$LIB" "$FA")"

# (b) migration file + test + "migrate" subject -> stateful (a non-test path keeps the signal)
F="$(mktemp -d)"; build "$F" mig "migrate the orders table"
[ "$(cls "$LIB" "$F")" = stateful ] && pass "migration+test 'migrate' diff -> stateful (preserved)" || fail "migration+test should be stateful, got $(cls "$LIB" "$F")"

# (b2) code + test + "backup" subject -> stateful (a mixed diff keeps the subject signal)
F="$(mktemp -d)"; build "$F" codetest "add the nightly backup"
[ "$(cls "$LIB" "$F")" = stateful ] && pass "code+test 'backup' diff -> stateful (preserved)" || fail "code+test 'backup' should be stateful, got $(cls "$LIB" "$F")"

# (b3) same mixed diff, but thousands of test paths sort after the source file: the guard
# must still see the source path (a `grep -q` early exit under pipefail read it as absent)
F="$(mktemp -d)"; build "$F" codetest "add the nightly backup"
for i in $(seq 1 4000); do : > "$F/tests/test-padding-file-with-a-long-name-$i.sh"; done
[ "$(cls "$LIB" "$F")" = stateful ] && pass "code+4000 tests 'backup' diff -> stateful (large diff)" || fail "large code+test 'backup' should be stateful, got $(cls "$LIB" "$F")"

# (c) source file on a stateful path, neutral subject -> stateful, same verdict as before
F="$(mktemp -d)"; build "$F" deploy "tweak the helper"
[ "$(cls "$LIB" "$F")" = stateful ] && pass "lib/deploy.sh, neutral subject -> stateful (unchanged)" || fail "stateful path should be stateful, got $(cls "$LIB" "$F")"

# (a) negative control: strip the tests-only guard from the current lib; the same fixture
# must read stateful again, so the guard is load-bearing.
OLD2="$(dirname "$LIB")/.cls-oldlib2.tmp.sh"
trap 'rm -f "$OLD" "$OLD2"' EXIT
awk '/# Subject words count only/{s=1} s&&/^  fi$/{s=0; print "  subjects=\"$(_subjects \"$root\" \"$base\")\""; next} !s' "$LIB" > "$OLD2"
if grep -q '^  subjects="\$(_subjects' "$OLD2" && ! grep -q 'Subject words count only' "$OLD2"; then
  [ "$(cls "$OLD2" "$FA")" = stateful ] && pass "guard-stripped lib classifies tests-only 'restore' as stateful (the bug; guard is load-bearing)" || fail "guard-stripped lib should reproduce the bug, got $(cls "$OLD2" "$FA")"
else
  echo "[NO EXECUTABLE CHECK: could not strip the tests-only guard]"; fails=$((fails+1))
fi

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS (10/10)"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
