#!/usr/bin/env bash
# test-docdrift-refcheck.sh -- lib/docdrift/refcheck.sh, the Tier 1 path check of the
# kit:doc-drift audit loop.
#
# The central case is the noise filter. A doc names five things: a live in-repo path, a dead
# in-repo path, a path in a sibling repo, a placeholder, and a dead-looking path inside a code
# fence. Only the dead in-repo path may be reported. Remove the first-segment filter and the
# sibling-repo ref comes back as a hit, which is the 900-hit noise this scanner exists to avoid.
#
# Run: bash tests/test-docdrift-refcheck.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$KIT_DIR/lib/docdrift/refcheck.sh"
SKILL="$KIT_DIR/skills/doc-drift/SKILL.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

TMPS=()
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

mkrepo() {
  local d; d="$(_mk)"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "Refcheck Test"
  git -C "$d" config commit.gpgsign false
  printf '%s' "$d"
}
scan() { bash "$SCAN" scan --repo "$1" "${@:2}" 2>&1; }
rows() { printf '%s\n' "$1" | grep -v '^SUMMARY' | grep -c . ; }

echo "=== doc-drift refcheck ==="

echo "-- usage --"
OUT="$(bash "$SCAN" bogus 2>&1)"; RC=$?
assert "an unknown verb exits 2" $([ "$RC" -eq 2 ] && echo 0 || echo 1) "-- rc=$RC"
NOTREPO="$(_mk)"
OUT="$(scan "$NOTREPO")"; RC=$?
assert "a non-git target is refused" $([ "$RC" -ne 0 ] && echo 0 || echo 1) "-- rc=$RC $OUT"

echo "-- the noise filter: only the dead in-repo ref is reported --"
R="$(mkrepo)"
mkdir -p "$R/lib/thing" "$R/docs"
printf '#!/bin/sh\n' >"$R/lib/thing/live.sh"
cat >"$R/README.md" <<'DOC'
# Fixture

Live in-repo path: `lib/thing/live.sh`.
Dead in-repo path: `lib/thing/gone.sh`.
Sibling-repo path: `othertool/src/main.go`.
Placeholder path: `lib/<name>/run.sh`.

```
Inside a fence: `lib/thing/fenced-gone.sh`
```
DOC
git -C "$R" add -A && git -C "$R" commit -q -m seed
OUT="$(scan "$R")"
has "$OUT" "lib/thing/gone.sh" && A=0 || A=1
assert "the dead in-repo ref is reported" $A "-- got: $OUT"
assert "it is the only row" $([ "$(rows "$OUT")" -eq 1 ] && echo 0 || echo 1) "-- got: $OUT"
has "$OUT" "live.sh" && B=1 || B=0
assert "the live ref is not reported" $B
has "$OUT" "othertool" && B=1 || B=0
assert "the sibling-repo ref is not reported" $B
has "$OUT" "<name>" && B=1 || B=0
assert "the placeholder is not reported" $B
has "$OUT" "fenced-gone" && B=1 || B=0
assert "the ref inside a code fence is not reported" $B
printf '%s\n' "$OUT" | grep -q "^README.md	4	tick	lib/thing/gone.sh$"
assert "the row is doc<TAB>line<TAB>kind<TAB>ref" $?
printf '%s\n' "$OUT" | tail -1 | grep -q "^SUMMARY	1 docs	.*	1 dead$"
assert "a SUMMARY line closes the output" $? "-- got: $(printf '%s\n' "$OUT" | tail -1)"
scan "$R" >/dev/null; RC=$?
assert "exit 0 when the scan ran, though a ref is dead" $RC

echo "-- resolution rules --"
R="$(mkrepo)"
mkdir -p "$R/tools/alpha/bin" "$R/docs"
printf 'x\n' >"$R/tools/alpha/bin/run"
printf 'x\n' >"$R/docs/real.md"
cat >"$R/tools/alpha/README.md" <<'DOC'
Tool-relative, resolves against the owning tool dir: `bin/run`.
Tool-relative with a top-level first segment: `docs/real.md`.
Line suffix is stripped: `docs/real.md:12`.
Live link: [real](../../docs/real.md#top).
Dead link: [nope](../../docs/missing.md).
External link: [site](https://example.invalid/docs/x.md).
Anchor link: [here](#top).
Code, not a link: `[a](docs/nowhere.md)`.
DOC
printf 'untracked\n' >"$R/docs/local-only.md"
printf 'Untracked file present on disk: `docs/local-only.md`.\nDead dir: `docs/gone-dir/`.\n' >"$R/README.md"
git -C "$R" add tools docs/real.md README.md && git -C "$R" commit -q -m seed
OUT="$(scan "$R" --docs README.md --docs ':(glob)tools/*/README.md')"
assert "a dead relative link is reported" $(has "$OUT" "docs/missing.md" && echo 0 || echo 1) "-- got: $OUT"
assert "a dead directory ref is reported" $(has "$OUT" "docs/gone-dir/" && echo 0 || echo 1) "-- got: $OUT"
assert "exactly the two dead refs are reported" $([ "$(rows "$OUT")" -eq 2 ] && echo 0 || echo 1) "-- got: $OUT"
printf '%s\n' "$OUT" | tail -1 | grep -q "^SUMMARY	2 docs	"
assert "--docs overrides the default item set" $?

echo "-- the shipped skill points at the scanner --"
grep -q 'lib/docdrift/refcheck.sh' "$SKILL"; assert "SKILL.md step 3 names refcheck.sh" $?

echo
echo "Passed: $PASS / $TOTAL"
[ "$FAIL" -eq 0 ] && echo "All doc-drift refcheck tests passed." || { echo "FAILED: $FAIL"; exit 1; }
