#!/usr/bin/env bash
# test-right-arm-parity.sh -- SPEC-092, kit-hardening SG-04.
# Validates the 4 new right-arm-parity agents (brief-reviewer, acceptance-verifier,
# system-verifier, recheck-verifier): they exist, conform to ADR-0029, pass the SG-01
# gate, fill the previously agent-less Acceptance/System-test rows, carry the pinned
# re-execution-not-read-back semantics (recheck-verifier), and that execute.md wires the
# fresh-context re-audit lens over a right-arm PASS.
#
# Like test-advisor.sh / test-agent-effectiveness.sh, we cannot dispatch a live Claude
# agent in CI, so the load-bearing checks are PROMPT COMPLETENESS + a real negative-
# control fixture: the fixture literally carries a planted-bad PASS (a recorded verdict
# whose own command, re-run, fails), and the recheck-verifier prompt is asserted to carry
# the vocabulary needed to catch that exact class. The SG-01 gate mode (deterministic:
# read-only tools, valid model, on-axis name) is reused per-agent, not re-implemented.
#
# Run: bash tests/test-right-arm-parity.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/right-arm-parity"
ARCH="$KIT_DIR/docs/architecture.md"
EXEC="$KIT_DIR/commands/execute.md"
RECHECK="$KIT_DIR/agents/recheck-verifier.md"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

echo "=== right-arm review parity (SPEC-092 AC1-AC5) ==="

AGENTS="brief-reviewer acceptance-verifier system-verifier recheck-verifier"

# --- AC1: the 4 agents exist, conform (on-axis name, read-only-or-scoped-Bash tools, ----
# --- valid model), and each passes the SG-01 gate mode individually. -------------------
for NAME in $AGENTS; do
  A="$KIT_DIR/agents/$NAME.md"
  [ -f "$A" ]; assert "AC1: agents/$NAME.md exists" $?

  grep -qE "^name: *${NAME} *\$" "$A" 2>/dev/null; assert "AC1: $NAME frontmatter name matches filename" $?

  if awk '/^---$/{c++; next} c==1' "$A" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*(Edit|Write|NotebookEdit|MultiEdit)[[:space:]]*$|^[[:space:]]*-[[:space:]]*Bash[[:space:]]*$'; then
    assert "AC1: $NAME declares read-only-or-scoped tools only (no Edit/Write/NotebookEdit/bare-Bash)" 1
  else
    assert "AC1: $NAME declares read-only-or-scoped tools only (no Edit/Write/NotebookEdit/bare-Bash)" 0
  fi

  if bash "$KIT_DIR/tests/test-agent-effectiveness.sh" "$A" >/dev/null 2>&1; then
    assert "AC1: $NAME passes the SG-01 agent-effectiveness gate" 0
  else
    assert "AC1: $NAME passes the SG-01 agent-effectiveness gate" 1
  fi
done

# --- AC2: the Acceptance and System-test rows in the V-phase inventory are non-empty ---
[ -f "$ARCH" ]; assert "AC2: docs/architecture.md exists" $?
grep -q 'acceptance-verifier' "$ARCH"; assert "AC2: architecture.md's Acceptance row names acceptance-verifier" $?
grep -q 'system-verifier' "$ARCH"; assert "AC2: architecture.md's System-test row names system-verifier" $?
grep -qi 'brief-reviewer' "$ARCH"; assert "AC2: architecture.md carries a brief-reviewer row (the brief mirror)" $?
grep -qi 'recheck-verifier' "$ARCH"; assert "AC2: architecture.md carries a recheck-verifier row (the re-audit lens)" $?

# --- AC3: recheck-verifier carries the RE-EXECUTION (not read-back) semantics ----------
[ -f "$RECHECK" ]; assert "AC3: agents/recheck-verifier.md exists" $?
grep -qiE 're-execute|re-run|fresh context' "$RECHECK"; assert "AC3: recheck-verifier prompt carries re-execute/re-run/fresh-context vocabulary" $?
grep -qiE 'not a read-back|never a read-back of recorded evidence' "$RECHECK"
assert "AC3: recheck-verifier prompt explicitly states it is NOT a read-back of recorded evidence" $?

# --- AC4 [NEGATIVE CONTROL, load-bearing]: a planted-bad-PASS fixture, and the ---------
# --- recheck-verifier prompt carries the vocabulary to catch it. -----------------------
PLANTED="$FIX/planted-bad-pass.md"
[ -f "$PLANTED" ]; assert "AC4: tests/fixtures/right-arm-parity/planted-bad-pass.md exists" $?

grep -qE '^VERDICT: PASS' "$PLANTED"; assert "AC4: fixture literally claims VERDICT: PASS" $?

# Extract the fixture's recorded Command: line and prove that command, RE-RUN, actually
# fails -- this is what makes the fixture a real negative control, not just prose.
FIXTURE_CMD=$(grep -m1 '^- Command:' "$PLANTED" | sed -E 's/^- Command: `(.*)`$/\1/')
if [ -n "$FIXTURE_CMD" ]; then
  assert "AC4: fixture's recorded Command line is extractable" 0
  bash -c "$FIXTURE_CMD" >/dev/null 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then
    assert "AC4 [NEGATIVE CONTROL]: fixture's Command ('$FIXTURE_CMD') re-run FAILS (exit $RC), contradicting its own recorded PASS" 0
  else
    assert "AC4 [NEGATIVE CONTROL]: fixture's Command re-run FAILS, contradicting its recorded PASS" 1
  fi
else
  assert "AC4: fixture's recorded Command line is extractable" 1
  assert "AC4 [NEGATIVE CONTROL]: fixture's Command re-run FAILS, contradicting its recorded PASS" 1
fi

# The recheck-verifier prompt must carry the vocabulary needed to catch exactly this
# class: re-execute (already asserted in AC3) + the "assume fabricated/stale until
# reproduced" stance.
grep -qiE 'assume.*(fabricated|stale)' "$RECHECK"; assert "AC4: recheck-verifier prompt states 'assume fabricated/stale until reproduced'" $?
grep -qi 'planted' "$RECHECK"; assert "AC4: recheck-verifier prompt names the planted-bad/fabricated-PASS threat model" $?

# --- AC5: commands/execute.md wires the recheck-verifier re-audit over a right-arm PASS ---
[ -f "$EXEC" ]; assert "AC5: commands/execute.md exists" $?
RECHECK_HITS=$(grep -c 'recheck-verifier' "$EXEC" 2>/dev/null || echo 0)
[ "$RECHECK_HITS" -ge 2 ]; assert "AC5: execute.md dispatches recheck-verifier at 2+ sites ($RECHECK_HITS hits: after task-verifier + after integration-verifier)" $?
grep -qiE 're-execute|re-run|fresh' "$EXEC"; assert "AC5: execute.md's wiring uses re-execute/re-run/fresh vocabulary, not a read-back framing" $?
grep -qi 'advisory' "$EXEC" && grep -qi 'never a mid-flight hard block' "$EXEC"
assert "AC5: execute.md states the re-audit is advisory + recorded, never a mid-flight hard block (ADR-0024)" $?

# --- AC6 [NO-ORPHAN REGRESSION GUARD]: every SG-04 right-arm agent is DISPATCHED by ----
# --- at least one commands/ file. TIER-4 close-gate fix: brief-reviewer, acceptance-  ---
# --- verifier, and system-verifier existed (gated + rostered + documented) but had NO --
# --- command dispatching them; this pins the fix so the orphan cannot recur silently. --
for NAME in $AGENTS; do
  if grep -rl "$NAME" "$KIT_DIR/commands/" >/dev/null 2>&1; then
    assert "AC6 [NO-ORPHAN]: $NAME is dispatched by at least one file under commands/" 0
  else
    assert "AC6 [NO-ORPHAN]: $NAME is dispatched by at least one file under commands/" 1
  fi
done

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
