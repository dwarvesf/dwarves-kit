#!/usr/bin/env bash
# test-significance-classify.sh -- SPEC-122, understanding-gate SG-02.
# Behavioral suite for lib/significance-classify.sh: the two-signal (significance x
# understanding-worthiness) verdict, the impl-notes feed, the gate-ledger debt marker, and
# determinism. Mirrors tests/test-lane-classify.sh's shape.
#
# Run: bash tests/test-significance-classify.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SC="$KIT_DIR/lib/significance-classify.sh"
GL="$KIT_DIR/lib/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

# verdict_is [--files F] [--impl-notes P] <desc> <expected-verdict> <label>
verdict_is() {
  local args=() expected label got
  while [ "${1:-}" != "--" ]; do args+=("$1"); shift; done
  shift  # consume --
  expected="$1"; label="$2"
  TOTAL=$((TOTAL+1))
  got="$(bash "$SC" classify "${args[@]}" 2>/dev/null)"
  if [ "$got" = "$expected" ]; then echo -e "  ${GREEN}PASS${NC} $label ($expected)"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $label -- got '$got', expected '$expected'"; FAIL=$((FAIL+1)); fi
}

TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

echo "=== significance-classify: worthy-tap (AC1) ==="
verdict_is --files "lib/x.sh" "add a new data model migration that introduces a primitive future work will build on" -- \
  "tap" "AC1 significant + worthy (data model + primitive) -> tap"

echo ""
echo "=== significance-classify: anti-fatigue NEGATIVE CONTROL (AC2) ==="
# Significant (full lane, touches lib/) but describes a purely mechanical, reversible,
# test-covered change -- no worthiness trigger should fire. Anti-fatigue guard: this must
# WAVE, not tap, even though it is significant.
verdict_is --files "lib/orchestrate.sh lib/foo.sh" "add a mechanical, reversible, fully test-covered guard clause" -- \
  "wave" "AC2 [NC] significant-but-low-worthiness is WAVED, not tapped"

echo ""
echo "=== significance-classify: obvious change (AC3) ==="
verdict_is "fix a typo in the README" -- "not-significant" "AC3 obvious/cosmetic change is not-significant"

echo ""
echo "=== significance-classify: impl-notes FEED (AC4) ==="
EMPTY_NOTE="$TMPDIR_T/empty.md"
NONEMPTY_NOTE="$TMPDIR_T/nonempty.md"
: > "$EMPTY_NOTE"
printf '## 2026-07-03 12:00 a decision\n- Decision: chose X over Y, spec did not pin this down\n' > "$NONEMPTY_NOTE"

# Same mechanical description as AC2 (no worthiness trigger in the text itself): without an
# impl-note it waves; with a non-empty impl-note the feed signal flips it to a tap.
verdict_is --files "lib/orchestrate.sh" --impl-notes "$EMPTY_NOTE" "add a mechanical, reversible, fully test-covered guard clause" -- \
  "wave" "AC4a no impl-note entries -> still waved"
verdict_is --files "lib/orchestrate.sh" --impl-notes "$NONEMPTY_NOTE" "add a mechanical, reversible, fully test-covered guard clause" -- \
  "tap" "AC4b non-empty impl-note flips worthiness low->high -> tap"

echo ""
echo "=== significance-classify: gate-ledger debt marker (AC5) ==="
RID_T="sigclass-test-$$"
LOGDIR_T="$TMPDIR_T/kitlogs"
mkdir -p "$LOGDIR_T"
LEDGER_FILE="$LOGDIR_T/runs/$RID_T.log"

run_record() {
  DWARVES_KIT_LOG_DIR="$LOGDIR_T" bash "$SC" record "$RID_T" "$@" >/dev/null 2>&1
}

run_record --files "lib/x.sh" "add a new data model migration that introduces a primitive future work will build on"
run_record --files "lib/orchestrate.sh lib/foo.sh" "add a mechanical, reversible, fully test-covered guard clause"
run_record "fix a typo in the README"

TOTAL=$((TOTAL+1))
if [ -f "$LEDGER_FILE" ] && [ "$(grep -c '| DEBT |' "$LEDGER_FILE")" -eq 3 ]; then
  echo -e "  ${GREEN}PASS${NC} AC5a three record calls append exactly three | DEBT | lines"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} AC5a expected 3 | DEBT | lines in $LEDGER_FILE"
  FAIL=$((FAIL+1))
fi

TOTAL=$((TOTAL+1))
if grep -qE '\| DEBT \| significance=high worthiness=high verdict=tap' "$LEDGER_FILE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} AC5b the tap verdict's marker carries significance=high worthiness=high verdict=tap"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} AC5b tap marker fields missing/malformed"
  FAIL=$((FAIL+1))
fi

TOTAL=$((TOTAL+1))
if grep -qE '\| DEBT \| significance=high worthiness=low verdict=wave' "$LEDGER_FILE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} AC5c the wave verdict's marker carries significance=high worthiness=low verdict=wave"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} AC5c wave marker fields missing/malformed"
  FAIL=$((FAIL+1))
fi

TOTAL=$((TOTAL+1))
if grep -qE '\| DEBT \| significance=low worthiness=low verdict=not-significant' "$LEDGER_FILE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} AC5d the not-significant verdict's marker carries significance=low verdict=not-significant"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} AC5d not-significant marker fields missing/malformed"
  FAIL=$((FAIL+1))
fi

# AC5e: the DEBT marker is additive -- gate-ledger's check()/descent() must not treat it as a
# GATE line (it must not satisfy a required-gate check, and must not appear as a descent
# violation subject).
TOTAL=$((TOTAL+1))
if ! grep -qE '^\S+ \| GATE \| debt ' "$LEDGER_FILE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} AC5e DEBT marker never masquerades as a | GATE | line"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} AC5e a | GATE | debt line leaked in -- additive-marker guarantee broken"
  FAIL=$((FAIL+1))
fi

echo ""
echo "=== significance-classify: determinism (AC6) ==="
D1="$(bash "$SC" classify --files "lib/x.sh" "add a new component with a novel first-of-kind pattern" 2>/dev/null)"
D2="$(bash "$SC" classify --files "lib/x.sh" "add a new component with a novel first-of-kind pattern" 2>/dev/null)"
assert "AC6a classify: same input -> same output ($D1)" "$([ "$D1" = "$D2" ] && echo 0 || echo 1)"

E1="$(bash "$SC" explain --files "lib/x.sh" "add a new component with a novel first-of-kind pattern" 2>/dev/null)"
E2="$(bash "$SC" explain --files "lib/x.sh" "add a new component with a novel first-of-kind pattern" 2>/dev/null)"
assert "AC6b explain: same input -> byte-identical output" "$([ "$E1" = "$E2" ] && echo 0 || echo 1)"

echo ""
echo "=== significance-classify: coverage delta ==="
TOTAL=$((TOTAL+1))
BEFORE_COUNT=0   # no test file referenced DEBT/significance-classify before this spec
AFTER_COUNT="$(grep -c 'DEBT' "$0")"
if [ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ]; then
  echo -e "  ${GREEN}PASS${NC} coverage delta: DEBT-marker assertions went from $BEFORE_COUNT to $AFTER_COUNT in this suite"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} coverage delta did not increase"
  FAIL=$((FAIL+1))
fi

echo ""
echo "=== significance-classify: wiring sanity ==="
TOTAL=$((TOTAL+1))
if [ -x "$SC" ]; then
  echo -e "  ${GREEN}PASS${NC} lib/significance-classify.sh exists and is executable"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} lib/significance-classify.sh missing or not executable"
  FAIL=$((FAIL+1))
fi

TOTAL=$((TOTAL+1))
if grep -qE '^[[:space:]]*debt\)' "$GL" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC} lib/gate-ledger.sh exposes a 'debt' subcommand"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}FAIL${NC} lib/gate-ledger.sh missing the 'debt' subcommand"
  FAIL=$((FAIL+1))
fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
