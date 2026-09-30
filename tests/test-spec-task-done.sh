#!/usr/bin/env bash
# test-spec-task-done.sh -- `spec.sh task-done` (lib/spec/spec-task-done.sh).
#
# Pins the /kit:execute end-of-build check-off edits: the verb checks off exactly the named task line,
# refuses a missing or already-checked ID with a named error and no write, and appends a
# verification-log entry carrying every field, creating the log when absent.
#
# Run: bash tests/test-spec-task-done.sh
# Exit 0 = all pass. Exit 1 = failures.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_SH="$KIT_DIR/lib/spec/spec.sh"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0; TOTAL=0

ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} $1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
expect() { if { trap '' PIPE; printf '%s' "$3" 2>/dev/null || :; } | grep -qF -- "$2"; then ok "$1"; else bad "$1 (missing '$2' in: $3)"; fi; }

D="$(mktemp -d "${TMPDIR:-/tmp}/kit-spec-task-done.XXXXXX")"
mk_spec() {
  cat > "$D/spec.md" <<'EOF'
# Spec: fixture

## Tasks
- [ ] TASK-1: first thing
- [ ] TASK-10: tenth thing
- [x] TASK-2 (DONE, commit abc1234, verified): second thing
  - [ ] TASK-3: third thing, indented
EOF
}

echo "=== flips the right task among several ==="
mk_spec
out="$(bash "$SPEC_SH" task-done "$D/spec.md" TASK-1 --commit 1234abc 2>&1)"; rc=$?
eq     "flip exits 0" "$rc" "0"
expect "flip reports the ID" "checked TASK-1" "$out"
expect "TASK-1 checked with the done tag" "- [x] TASK-1 (DONE, commit 1234abc, verified): first thing" "$(cat "$D/spec.md")"
expect "TASK-10 left unchecked (no prefix match)" "- [ ] TASK-10: tenth thing" "$(cat "$D/spec.md")"
expect "TASK-3 left unchecked" "  - [ ] TASK-3: third thing, indented" "$(cat "$D/spec.md")"
bash "$SPEC_SH" task-done "$D/spec.md" TASK-3 --commit 5678def >/dev/null 2>&1
expect "indented TASK-3 keeps its indent" "  - [x] TASK-3 (DONE, commit 5678def, verified): third thing, indented" "$(cat "$D/spec.md")"

echo "=== missing ID errors, spec unchanged ==="
mk_spec; before="$(cat "$D/spec.md")"
out="$(bash "$SPEC_SH" task-done "$D/spec.md" TASK-9 --commit 1234abc 2>&1)"; rc=$?
eq     "missing ID exits 1" "$rc" "1"
expect "missing ID names the error" "TASK-9 not found" "$out"
eq     "missing ID leaves the spec unchanged" "$(cat "$D/spec.md")" "$before"

echo "=== already-done ID errors, spec unchanged ==="
out="$(bash "$SPEC_SH" task-done "$D/spec.md" TASK-2 --commit 1234abc 2>&1)"; rc=$?
eq     "already-done exits 1" "$rc" "1"
expect "already-done names the error" "TASK-2 is already checked" "$out"
eq     "already-done leaves the spec unchanged" "$(cat "$D/spec.md")" "$before"

echo "=== two unchecked lines for one ID error, spec unchanged ==="
printf -- '- [ ] TASK-4: once\n- [ ] TASK-4: twice\n' > "$D/dup.md"; before="$(cat "$D/dup.md")"
out="$(bash "$SPEC_SH" task-done "$D/dup.md" TASK-4 --commit 1234abc 2>&1)"; rc=$?
eq     "ambiguous ID exits 1" "$rc" "1"
expect "ambiguous ID names the error" "TASK-4 has more than one unchecked line" "$out"
eq     "ambiguous ID leaves the spec unchanged" "$(cat "$D/dup.md")" "$before"

echo "=== the flip keeps the spec's file mode and leaves no temp file ==="
mk_spec; chmod 644 "$D/spec.md"
bash "$SPEC_SH" task-done "$D/spec.md" TASK-1 --commit 1234abc >/dev/null 2>&1
eq     "mode stays 644" "$(ls -l "$D/spec.md" | cut -c1-10)" "-rw-r--r--"
eq     "no temp file left beside the spec" "$(ls "$D" | grep -c '^spec\.md\.')" "0"

echo "=== verification entry: log created when absent, every field present ==="
mk_spec; LOG="$D/verification/fixture.md"
out="$(bash "$SPEC_SH" task-done "$D/spec.md" TASK-10 --commit 1234abc --verify-log "$LOG" \
  --command "bash tests/test-x.sh" --exit 0 --excerpt "$(printf 'Passed: 5 / 5\nall green')" \
  --verdict PASS --reaudit "fresh-context PASS" 2>&1)"; rc=$?
eq     "log call exits 0" "$rc" "0"
expect "log call says it does not commit" "not committed" "$out"
log="$(cat "$LOG" 2>/dev/null)"
eq     "log file created with the header" "$(head -1 "$LOG" 2>/dev/null)" "# Verification log"
expect "entry heading carries ID and title" "## TASK-10 tenth thing" "$log"
expect "entry Command field" '- Command: `bash tests/test-x.sh`' "$log"
expect "entry Exit field" "- Exit: 0" "$log"
expect "entry Output (excerpt) field" "- Output (excerpt):" "$log"
expect "excerpt line 1 indented in the fence" "  Passed: 5 / 5" "$log"
expect "excerpt line 2 indented in the fence" "  all green" "$log"
expect "entry Verdict field" "- Verdict: PASS" "$log"
expect "entry Re-audit field" "- Re-audit: fresh-context PASS" "$log"

echo "=== verification entry appends to an existing log ==="
bash "$SPEC_SH" task-done "$D/spec.md" TASK-1 --commit 1234abc --verify-log "$LOG" \
  --command "bash tests/test-y.sh" --exit 0 --excerpt "ok" --verdict PASS >/dev/null 2>&1
eq     "header written once" "$(grep -c '^# Verification log' "$LOG")" "1"
eq     "two entries present" "$(grep -c '^## TASK-' "$LOG")" "2"
eq     "Re-audit omitted when not given" "$(grep -c '^- Re-audit:' "$LOG")" "1"

echo "=== an excerpt holding a fence gets a longer fence ==="
bash "$SPEC_SH" task-done "$D/spec.md" TASK-3 --commit 1234abc --verify-log "$D/fence.md" \
  --command "x" --exit 0 --excerpt "$(printf 'a\n```\nb')" --verdict PASS >/dev/null 2>&1
eq     "four-backtick fence opens and closes the excerpt" "$(grep -c '^  ````$' "$D/fence.md")" "2"

echo "=== --verify-log without its fields errors before any write ==="
mk_spec; before="$(cat "$D/spec.md")"
out="$(bash "$SPEC_SH" task-done "$D/spec.md" TASK-1 --commit 1234abc --verify-log "$D/v2.md" 2>&1)"; rc=$?
eq     "missing log fields exits 1" "$rc" "1"
expect "missing log fields named" "needs --command, --exit, --excerpt and --verdict" "$out"
eq     "missing log fields leaves the spec unchanged" "$(cat "$D/spec.md")" "$before"

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASS${NC} / $TOTAL"
if [ "$FAIL" -gt 0 ]; then echo -e "${RED}$FAIL assertions failed.${NC}"; exit 1; fi
echo -e "${GREEN}spec-task-done green.${NC}"
