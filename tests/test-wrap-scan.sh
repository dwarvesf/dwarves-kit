#!/usr/bin/env bash
# test-wrap-scan.sh -- the scan cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== scan: every verdict, for main, master and develop defaults ==="
# ===========================================================================
for pair in "rmain main" "rmaster master" "rdev develop"; do
  set -- $pair
  rname="$1"; def="$2"
  make_clone "scan-$def" "$rname" "$def" unmerged
  set_stub "$rname" "$def"
  out="$("$WRAP" scan "$TMPD/clone-scan-$def" 2>&1)"
  chk_has "scan/$def: ahead-behind line names origin/$def" "$out" "-- vs origin/$def: ahead="
  chk_has "scan/$def: merged-ancestor is SAFE-d" "$out" "merged-ancestor  [SAFE-d: ancestor of origin/$def]"
  chk_has "scan/$def: squash-ok is squash-merged" "$out" "squash-ok  [SQUASH-MERGED per gh: safe to -D]"
  chk_has "scan/$def: squash-stale is LEAVE" "$out" "squash-stale  [NOT merged / unknown: LEAVE]"
  chk_has "scan/$def: unmerged is LEAVE" "$out" "unmerged  [NOT merged / unknown: LEAVE]"
  chk_has "scan/$def: the open PR is listed" "$out" "#7 wrap the session [feat/wrap]"
  chk_has "scan/$def: checkout line" "$out" "-- checkout on: unmerged"
done

echo "=== scan: the gh calls carry the origin URL the repo actually has ==="
set_stub rmain main
SCAN_URL="$(git -C "$TMPD/clone-scan-main" remote get-url origin)"
: > "$GH_STUB_CALLS"
"$WRAP" scan "$TMPD/clone-scan-main" >/dev/null 2>&1
SCAN_CALLS="$(cat "$GH_STUB_CALLS")"
chk_has "scan: pr list names --repo and --head" "$SCAN_CALLS" \
  "pr list --repo ${SCAN_URL} --head squash-ok"
chk_has "scan: the open-PR query names --repo" "$SCAN_CALLS" "pr list --repo ${SCAN_URL} --state open"

echo "=== scan: a non-repo argument is skipped, the repo after it still reports ==="
out="$("$WRAP" scan "$TMPD/not-a-repo" "$TMPD/clone-scan-main" 2>&1)"
chk_has "scan: non-repo prints the skip line" "$out" "not a git repo, skipped"
chk_has "scan: the following repo still reports" "$out" "-- vs origin/main: ahead="

echo "=== scan, apply --under: every child repo of a root, sorted; other children skipped ==="
UROOT="$TMPD/under-root"; mkdir -p "$UROOT/plain-dir" "$UROOT/zeta" "$UROOT/alpha" "$TMPD/under-empty/plain"
git -C "$UROOT/zeta" init -q; git -C "$UROOT/alpha" init -q
out="$("$WRAP" scan --under "$UROOT" --under "$TMPD/under-empty" 2>&1)"; rc=$?
chk "under: scan exits 0" "$rc"
chk_has "under: scan reports the first repo" "$out" "== $UROOT/alpha"
chk_has "under: scan reports the second repo" "$out" "== $UROOT/zeta"
chk "under: the repos come in sorted order" \
  "$(printf '%s\n' "$out" | grep -E "^== $UROOT/" | tr '\n' ' ' | grep -qxF "== $UROOT/alpha == $UROOT/zeta "; echo $?)"
chk_no "under: the plain directory is skipped silently" "$out" "plain-dir"
chk_has "under: a root with no repos prints one line" "$out" "== $TMPD/under-empty: --under found no git repos"
chk "under: the empty root prints nothing else" "$(printf '%s\n' "$out" | grep -c "under-empty" | grep -qx 1; echo $?)"
out="$("$WRAP" apply "$TMPD/clone-scan-main" --under="$UROOT/" 2>&1)"; rc=$?
chk "under: apply exits 0" "$rc"
chk "under: apply appends the root's repos after the named one" \
  "$(printf '%s\n' "$out" | grep -E '^== /' | tr '\n' ' ' | grep -qxF "== $TMPD/clone-scan-main == $UROOT/alpha == $UROOT/zeta "; echo $?)"
out="$("$WRAP" apply --under 2>&1)"; rc=$?
chk "under: a missing directory is a usage error" "$([ "$rc" -eq 64 ]; echo $?)"

echo "=== scan --under with no directory: wrap.roots expansion ==="
UROOT2="$TMPD/under-root-2"; mkdir -p "$UROOT2/beta"
git -C "$UROOT2/beta" init -q
UNDER_KIT="$(mktemp -d "${TMPDIR:-/tmp}/dk-wrap-under-kit.XXXXXX")"
printf '[wrap]\nroots = "%s %s"\n' "$UROOT" "$UROOT2" > "$UNDER_KIT/kit.toml"
out="$(KIT_CONFIG_ROOT="$UNDER_KIT" "$WRAP" scan --under 2>&1)"; rc=$?
chk "under: bare --under with a two-root knob exits 0" "$rc"
chk_has "under: bare --under scans the first knob root's repos" "$out" "== $UROOT/alpha"
chk_has "under: bare --under scans the second knob root's repos" "$out" "== $UROOT2/beta"

out="$(KIT_CONFIG_ROOT="$UNDER_KIT" "$WRAP" scan --under 2>&1 >/dev/null)"
chk_no "under: bare --under with a filled knob names no error" "$out" "wrap.roots"

EMPTY_KIT="$(mktemp -d "${TMPDIR:-/tmp}/dk-wrap-under-empty-kit.XXXXXX")"
printf '[wrap]\nroots = ""\n' > "$EMPTY_KIT/kit.toml"
out="$(KIT_CONFIG_ROOT="$EMPTY_KIT" "$WRAP" scan --under 2>&1)"; rc=$?
chk "under: bare --under with an empty knob is a usage error" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "under: the empty-knob error names wrap.roots" "$out" "wrap.roots is empty"

echo "=== scan: flags packed into one positional are refused ==="
out="$("$WRAP" scan "$TMPD/clone-scan-main" "x --own y" 2>&1)"; rc=$?
chk "an embedded ' --' in a scan positional exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "scan: the embedded ' --' refusal is the packed-flags one" "$out" "looks like flags packed into one word"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-scan: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-scan: all $PASS passed"
