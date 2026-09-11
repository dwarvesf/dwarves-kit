#!/usr/bin/env bash
# test-lint-scattered-ids.sh -- unit tests for lib/lint/scattered-ids.sh (C4 for the lint
# module). Confirms the enumerator finds a planted hit and drops an exempt one, and that the
# zones this repo already relies on report the counts they are supposed to.
#
# Run: bash tests/test-lint-scattered-ids.sh
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KIT" || exit 1
ENUM="lib/lint/scattered-ids.sh"

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()  { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); }
no()  { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); }

echo "=== scattered-ids.sh: script sanity ==="
[ -x "$ENUM" ] && ok "$ENUM is executable" || no "$ENUM is not executable"
bash -n "$ENUM" && ok "$ENUM parses (bash -n)" || no "$ENUM fails to parse"

echo ""
echo "=== scattered-ids.sh: unknown zone and no-args are refused ==="
bash "$ENUM" --zone made-up-zone >/dev/null 2>&1
[ $? -eq 1 ] && ok "an unknown zone exits 1" || no "an unknown zone did not exit 1"
bash "$ENUM" >/dev/null 2>&1
[ $? -eq 1 ] && ok "no --zone and no --all exits 1" || no "missing args did not exit 1"

echo ""
echo "=== scattered-ids.sh: planted hit vs exempt line ==="
# A real git-tracked fixture, planted for one call and torn down after: zone_files() reads
# `git ls-files`, so an untracked file would never be seen and the test would pass vacuously.
FIXTURE="hooks/zzz-test-lint-scattered-ids-fixture.sh"
cleanup() { git rm --cached -q "$FIXTURE" >/dev/null 2>&1; rm -f "$KIT/$FIXTURE"; }
trap cleanup EXIT

cat > "$KIT/$FIXTURE" <<'EOF'
#!/usr/bin/env bash
# planted for a test: see SPEC-999 for the (nonexistent) rationale
Relates-to: SPEC-999
EOF
git add "$FIXTURE" >/dev/null 2>&1

OUT="$(bash "$ENUM" --zone hooks 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -qF "$FIXTURE:2:# planted for a test: see SPEC-999"; then
  ok "a planted comment citation is caught"
else
  no "the planted comment citation was NOT caught"
fi
if printf '%s\n' "$OUT" | grep -qF "Relates-to: SPEC-999"; then
  no "an exempt Relates-to: line was NOT dropped"
else
  ok "an exempt Relates-to: line is dropped"
fi

cleanup
trap - EXIT

echo ""
echo "=== scattered-ids.sh: --count matches the line count of the bare listing ==="
for z in hooks bin skills; do
  n_list="$(bash "$ENUM" --zone "$z" 2>/dev/null | grep -c . || true)"
  n_count="$(bash "$ENUM" --zone "$z" --count 2>/dev/null)"
  [ "$n_list" = "$n_count" ] && ok "zone '$z': --count ($n_count) matches the listing ($n_list)" \
    || no "zone '$z': --count ($n_count) != listing ($n_list)"
done

echo ""
if [ "$FAIL" -gt 0 ]; then echo "test-lint-scattered-ids: $PASS passed, $FAIL FAILED" >&2; exit 1; fi
echo "test-lint-scattered-ids: all $PASS passed"
