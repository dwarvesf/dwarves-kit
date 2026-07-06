#!/usr/bin/env bash
# test-advisor.sh -- SPEC-091, kit-hardening SG-03.
# Validates the generic advisor: two modes, additive (specialists still run),
# kit-default, tier knob, and that it passes the SG-01 effectiveness gate.
#
# Run: bash tests/test-advisor.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
A="$KIT_DIR/agents/advisor.md"
RT="$KIT_DIR/commands/review-team.md"
WF="$KIT_DIR/docs/WORKFLOW.md"  # bulk lives in docs/ (SPEC-185); root WORKFLOW.md is a thin stub
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

echo "=== advisor (SPEC-091 AC1-AC6) ==="

# AC1: exists, conforms, read-only tools
[ -f "$A" ]; assert "AC1: agents/advisor.md exists" $?
grep -qE '^name: *advisor *$' "$A"; assert "AC1: name is the named-noun 'advisor' (ADR-0029)" $?
if awk '/^---$/{c++; next} c==1' "$A" | grep -qE '^[[:space:]]*-[[:space:]]*(Edit|Write|NotebookEdit|MultiEdit)[[:space:]]*$|^[[:space:]]*-[[:space:]]*Bash[[:space:]]*$'; then
  assert "AC1: advisor declares read-only tools only" 1
else
  assert "AC1: advisor declares read-only tools only" 0
fi

# AC2: both modes documented in the agent AND in WORKFLOW.md
grep -qiE 'mode: *critique|critique \(P5\)|## Mode: critique' "$A"; assert "AC2: agent documents critique mode (P5)" $?
grep -qiE 'over-suggest|## Mode: over-suggest' "$A"; assert "AC2: agent documents over-suggest mode (P6)" $?
grep -qi 'over-suggest' "$WF" && grep -qi 'critique' "$WF"; assert "AC2: WORKFLOW.md documents both modes at the final boundary" $?

# AC3 [additive]: review-team still dispatches the 3 specialists AND adds the advisor
grep -qi 'security' "$RT" && grep -qi 'architecture' "$RT" && grep -qi 'test-coverage' "$RT"
assert "AC3: review-team still dispatches the 3 specialist lenses" $?
grep -qi 'advisor' "$RT"; assert "AC3: review-team adds the advisor lens (Step 2b)" $?
grep -qiE 'not replace|does NOT replace|additive' "$A"; assert "AC3: advisor prompt states it is additive, not a replacement" $?
grep -qiE 'not replace|does NOT replace|additive' "$RT"; assert "AC3: review-team wiring states additive, not a replacement" $?

# AC4 [kit-default]: wired as a default, not opt-in
grep -qi 'KIT DEFAULT\|kit-default' "$RT"; assert "AC4: review-team marks the advisor a KIT DEFAULT" $?
grep -qi 'KIT DEFAULT\|kit-default\|not opt-in' "$WF"; assert "AC4: WORKFLOW marks the advisor a kit default (not opt-in)" $?

# AC5 [tier knob]: default sonnet, documented as the cheap-first knob
grep -qE '^model: *sonnet *$' "$A"; assert "AC5: advisor model defaults to sonnet (cheap-first)" $?
grep -qiE 'config knob|tier knob|cheap-first' "$A"; assert "AC5: agent documents the model tier as a config knob" $?

# AC6 [gated]: passes the SG-01 effectiveness gate
if bash "$KIT_DIR/tests/test-agent-effectiveness.sh" "$A" >/dev/null 2>&1; then
  assert "AC6: advisor passes the SG-01 agent-effectiveness gate" 0
else
  assert "AC6: advisor passes the SG-01 agent-effectiveness gate" 1
fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
