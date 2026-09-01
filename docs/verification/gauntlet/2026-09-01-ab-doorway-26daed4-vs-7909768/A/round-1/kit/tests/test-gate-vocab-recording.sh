#!/usr/bin/env bash
# test-gate-vocab-recording.sh -- ID-091, orchestrator-finish mega-goal sub-goal 01.
#
# The vocabulary was already single-sourced (both the full-lane required-set and the
# recorded phase names pass through the SAME `normalize_phase()`, and the required-set is
# derived live from the WORKFLOW.md matrix, not hardcoded). The real defect was a RECORDING
# gap: three names in the full-lane required-set had no `/kit:*` command that ever called
# `gate-ledger.sh record` for them (build, design-critique, design-record), so a
# command-driven full-lane run was blocked at ship until an operator hand-recorded them.
#
# This file proves two things, kept honestly separate:
#
#  A) STATIC sweep (AC1-AC3): every full-lane `measure-twice` matrix row has a real, literal
#     `gate-ledger.sh record <rid> <name> ran` call in some commands/*.md file. Mirrors the
#     no-orphan pattern already established by tests/test-command-emit-sweep.sh.
#
#  B) DYNAMIC proof (AC4-AC5): the actual gate mechanism (`gate-ledger.sh check full <rid>`)
#     passes when all 12 required gates are recorded using the exact literal names the fixed
#     commands now emit, and the NEGATIVE CONTROL -- omitting just one (`build`) -- re-blocks
#     it, proving the fix is real, not just textually present.
#
# Run: bash tests/test-gate-vocab-recording.sh   (exit 0 = all checks green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$KIT_DIR/commands"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
assert_eq() { TOTAL=$((TOTAL+1)); if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

echo "=== gate-vocab-recording (ID-091) ==="
echo "--- Section A: static sweep -- every full-lane required name has a real owner ---"

echo "=== AC1: full-lane required set is the expected 12 names (live from WORKFLOW.md) ==="
REQUIRED_FULL="$(bash "$GL" required full)"
EXPECTED_REQUIRED="think
design
design-critique
spec
validate
design-record
test-plan
build
review
docs
ship
reflect"
SORTED_REQ="$(printf '%s\n' "$REQUIRED_FULL" | sort)"
SORTED_EXP="$(printf '%s\n' "$EXPECTED_REQUIRED" | sort)"
assert_eq "required full = the 12 measure-twice matrix rows, normalized" "$SORTED_REQ" "$SORTED_EXP"

echo ""
echo "=== AC2: each required name has a command that records it by its OWN literal name ==="

# owner map: required-name -> "command-file:record-phase-token-as-written"
declare -A OWNER=(
  [think]='think.md:Think'
  [design]='design.md:Design'
  [design-critique]='devs-team.md:design-critique'
  [spec]='spec.md:Spec'
  [validate]='spec-validate.md:Validate'
  [design-record]='spec-validate.md:design-record'
  [test-plan]='test-plan.md:test-plan'
  [build]='execute.md:build'
  [review]='review.md:review'
  [docs]='docs.md:Docs'
  [ship]='ship.md:Ship'
  [reflect]='retro.md:Reflect'
)

owner_recorded() {
  local file="$1" phase="$2"
  grep -qE "gate-ledger\.sh\"? *record <rid> [\"\`]?${phase}[\"\`]? ran" "$COMMANDS_DIR/$file"
}

for name in "${!OWNER[@]}"; do
  entry="${OWNER[$name]}"
  file="${entry%%:*}"; phase="${entry#*:}"
  owner_recorded "$file" "$phase"
  assert "'$name' is recorded by commands/$file (literal '$phase ran')" $?
done

echo ""
echo "=== AC3: no-orphan sweep -- every required name is recorded by SOME command, no exceptions ==="
missing=0
for name in $REQUIRED_FULL; do
  found=1
  for f in "$COMMANDS_DIR"/*.md; do
    grep -qE "gate-ledger\.sh\"? *record <rid> [\"\`]?[A-Za-z][A-Za-z -]*[\"\`]? ran" "$f" || continue
    # normalize every recorded token in this file the same way gate-ledger.sh does and compare
    while IFS= read -r tok; do
      norm="$(printf '%s' "$tok" | tr 'A-Z' 'a-z' | tr ' ' '-')"
      [ "$norm" = "$name" ] && { found=0; break; }
    done < <(grep -oE "record <rid> [\"\`]?[A-Za-z][A-Za-z -]*[\"\`]? ran" "$f" | sed -E 's/^record <rid> [\"`]?//; s/[\"`]? ran$//')
    [ "$found" -eq 0 ] && break
  done
  if [ "$found" -ne 0 ]; then
    echo "  MISSING-OWNER: $name (no command records this required full-lane gate)"
    missing=$((missing + 1))
  fi
done
assert "every full-lane required name has at least one command recording it (0 missing)" "$([ "$missing" -eq 0 ] && echo 0 || echo 1)"

echo ""
echo "--- Section B: dynamic proof -- the real gate mechanism, not just text ---"

gl() { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" "$@"; }
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }

echo "=== AC4: a command-driven full-lane run (all 12 gates recorded by literal name) reaches ship ==="
new_log
RID=demo-full-run
gl record "$RID" think ran "verdict thesis" >/dev/null
gl record "$RID" design ran "approaches=2 design-bearing=yes" >/dev/null
gl record "$RID" design-critique ran "SOLID findings=0" >/dev/null
gl record "$RID" spec ran "drafted" >/dev/null
gl record "$RID" validate ran "APPROVED critical=0 warnings=0" >/dev/null
gl record "$RID" design-record ran "design-bearing=yes pass" >/dev/null
gl record "$RID" test-plan ran "matrix rows=6" >/dev/null
gl record "$RID" build ran "tasks=4/4 verified=4 tests=pass" >/dev/null
gl record "$RID" review ran "APPROVED findings=0" >/dev/null
gl record "$RID" docs ran "files=3" >/dev/null
gl record "$RID" ship ran "shipping pr=#1" >/dev/null
gl record "$RID" reflect ran "action-items=0" >/dev/null
CHECK_OUT="$(gl check full "$RID" 2>&1)"; CHECK_RC=$?
assert "check full <rid> passes with all 12 gates recorded (exit 0)" "$CHECK_RC" "-- $CHECK_OUT"

echo ""
echo "=== AC5: NEGATIVE CONTROL -- drop just 'build' (execute.md's own gate), the same run re-blocks ==="
new_log
RID2=demo-missing-build
gl record "$RID2" think ran "verdict thesis" >/dev/null
gl record "$RID2" design ran "approaches=2 design-bearing=yes" >/dev/null
gl record "$RID2" design-critique ran "SOLID findings=0" >/dev/null
gl record "$RID2" spec ran "drafted" >/dev/null
gl record "$RID2" validate ran "APPROVED critical=0 warnings=0" >/dev/null
gl record "$RID2" design-record ran "design-bearing=yes pass" >/dev/null
gl record "$RID2" test-plan ran "matrix rows=6" >/dev/null
# build ran -- deliberately OMITTED (simulates execute.md's record call being removed/reverted)
gl record "$RID2" review ran "APPROVED findings=0" >/dev/null
gl record "$RID2" docs ran "files=3" >/dev/null
gl record "$RID2" ship ran "shipping pr=#1" >/dev/null
gl record "$RID2" reflect ran "action-items=0" >/dev/null
CHECK_OUT2="$(gl check full "$RID2" 2>&1)"; CHECK_RC2=$?
assert "check full <rid> FAILS when build is not recorded (exit != 0)" "$([ "$CHECK_RC2" -ne 0 ] && echo 0 || echo 1)"
case "$CHECK_OUT2" in *"MISSING-GATE: build"*) mg_ok=0 ;; *) mg_ok=1 ;; esac
assert "the check names 'build' as the missing gate" "$mg_ok" "-- $CHECK_OUT2"

echo ""
echo "=== AC6: command-name drift alias -- recording 'execute' satisfies 'build'; 'verify' never satisfies 'review' ==="
new_log
RID3=demo-execute-alias
gl record "$RID3" execute ran "6/6 tasks landed" >/dev/null
grep -q "| GATE | build | ran |" "$LOGD/runs/$RID3.log"
assert "record 'execute' lands in the ledger as phase 'build'" $?
CHECK_OUT3="$(gl check full "$RID3" 2>&1)"
case "$CHECK_OUT3" in *"MISSING-GATE: build"*) alias_ok=1 ;; *) alias_ok=0 ;; esac
assert "check no longer reports build missing after an 'execute' record" "$alias_ok" "-- $CHECK_OUT3"
gl record "$RID3" verify ran "task-verifiers PASS" >/dev/null
CHECK_OUT4="$(gl check full "$RID3" 2>&1)"
case "$CHECK_OUT4" in *"MISSING-GATE: review"*) noalias_ok=0 ;; *) noalias_ok=1 ;; esac
assert "NEGATIVE CONTROL: 'verify' does NOT satisfy the 'review' gate" "$noalias_ok" "-- $CHECK_OUT4"

echo ""
echo "=== Summary: $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
