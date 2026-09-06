#!/usr/bin/env bash
# test-break-it.sh -- SPEC-247, the adversarial prober lens.
#
# Like test-agent-effectiveness.sh and test-review-team-plants.sh, we cannot
# dispatch a live Claude prober in CI. So the suite splits in two:
#
#   MECHANISM   -- real exit codes. The fixture pair proves both directions (a
#                  green suite over a real hole, and a suite that pins the
#                  boundary), the naming-axis arm is proven load-bearing, and the
#                  battery/WORKFLOW wiring is read out of the live files.
#   PROMPT      -- completeness greps. Every invariant and edge case the spec's
#                  I/O contract names must have vocabulary in the agent prompt.
#                  This proves the prompt can NAME the class, never that a live
#                  run finds it.
#
# The negative controls are what stop this from rubber-stamping: stripping the
# tight fixture's GUARD-LINE must turn its suite red, and dropping the
# `break-it)` arm must make the naming axis reject the name.
#
# Run: bash tests/test-break-it.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
A="$KIT_DIR/agents/break-it.md"
BAT="$KIT_DIR/commands/battery.md"
WF="$KIT_DIR/docs/WORKFLOW.md"
META="$KIT_DIR/tests/test-meta.sh"
FIX="$KIT_DIR/tests/fixtures/break-it"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

# Frontmatter tools block only, reporting a read-only VIOLATION if present.
# Same machine core test-agent-effectiveness.sh uses.
tools_violation() {
  awk '/^---$/{c++; next} c==1' "$1" \
    | grep -E '^[[:space:]]*-[[:space:]]*(Edit|Write|NotebookEdit|MultiEdit)[[:space:]]*$|^[[:space:]]*-[[:space:]]*Bash[[:space:]]*$'
}

echo "=== break-it prober lens (SPEC-247) ==="

# --- TASK-001: the agent def -------------------------------------------------
echo ""
echo "--- agent definition ---"
[ -f "$A" ]; assert "T1: agents/break-it.md exists" $?
grep -qE '^name: *break-it *$' "$A"; assert "T1: name is the named-noun 'break-it' (DEC-002)" $?
grep -qE '^model: *opus *$' "$A"; assert "T1-DEC-004: model tier is opus" $?
if [ -z "$(tools_violation "$A")" ]; then
  assert "T1-AC2: no Write/Edit/MultiEdit/NotebookEdit/bare-Bash in the tools block" 0
else
  assert "T1-AC2: no Write/Edit/MultiEdit/NotebookEdit/bare-Bash in the tools block" 1
fi
# DEC-007: the code-reviewer roster is kept, so the read-only claim rests on the
# prompt's command-safety rule. Pin the roster so a silent narrowing is visible.
ROSTER=$(awk '/^---$/{c++; next} c==1' "$A" | sed -n 's/^[[:space:]]*-[[:space:]]*//p' | sed 's/[[:space:]]*$//')
ROSTER_OK=0
while IFS= read -r T; do
  printf '%s\n' "$ROSTER" | grep -qxF "$T" || ROSTER_OK=1
done <<'ROSTER_EOF'
Read
Grep
Glob
Bash(git diff *)
Bash(npm test *)
Bash(go test *)
Bash(pytest *)
ROSTER_EOF
assert "T1-DEC-007: the code-reviewer tool roster is carried intact" $ROSTER_OK

# --- TASK-001 AC4 [NEGATIVE CONTROL]: the naming-axis arm is load-bearing -----
# Extract is_on_review_axis() from the live tests/test-meta.sh and exercise it
# twice: as shipped, and with the `break-it)` arm stripped. A full test-meta.sh
# run takes minutes; this exercises the SAME function the roster scan calls.
echo ""
echo "--- naming axis (ADR-0029) ---"
AXIS_SRC=$(awk '/^is_on_review_axis\(\) \{/,/^\}/' "$META")
[ -n "$AXIS_SRC" ]; assert "T1-AC3: is_on_review_axis() extracted from tests/test-meta.sh" $?
( eval "$AXIS_SRC"; is_on_review_axis break-it ) >/dev/null 2>&1
assert "T1-AC3: the shipped axis ACCEPTS 'break-it'" $?
AXIS_STRIPPED=$(printf '%s\n' "$AXIS_SRC" | grep -v 'break-it) return 0 ;;')
if ( eval "$AXIS_STRIPPED"; is_on_review_axis break-it ) >/dev/null 2>&1; then
  assert "T1-AC4 [NEGATIVE CONTROL]: without the arm the axis REJECTS 'break-it'" 1
else
  assert "T1-AC4 [NEGATIVE CONTROL]: without the arm the axis REJECTS 'break-it'" 0
fi
# Derivation floor: the stripped copy must differ, or the control is vacuous.
[ "$AXIS_SRC" != "$AXIS_STRIPPED" ]; assert "T1-AC4: the strip actually removed a line (control not vacuous)" $?

# --- TASK-002: battery wiring ------------------------------------------------
echo ""
echo "--- /kit:battery wiring ---"
sed -n '/## Lens escalation/,/^## /p' "$BAT" | grep -q 'break-it'
assert "T2-AC1: the escalation table carries a break-it row" $?
grep -q '## Probe rung' "$BAT"; assert "T2-AC2: commands/battery.md has a '## Probe rung' section" $?
PROBE_SEC=$(sed -n '/## Probe rung/,/^## /p' "$BAT")
echo "$PROBE_SEC" | grep -q 'mutation-smoke'; assert "T2-AC2: the probe rung names mutation-smoke as the next rung" $?
echo "$PROBE_SEC" | grep -q '/kit:verify'; assert "T2-AC2: the probe rung names /kit:verify as mutation-smoke's owner" $?
echo "$PROBE_SEC" | grep -qi 'stops the ladder'; assert "T2-AC2: a PROBE finding stops the ladder (DEC-005)" $?
sed -n '/## After the legs return/,$p' "$BAT" | grep -q 'break-it'
assert "T2-AC3: the after-the-legs step tells the lead to decide per probe finding" $?

# --- TASK-003 + TASK-004 AC1 [NEGATIVE CONTROL]: the fixture pair ------------
echo ""
echo "--- fixture pair (both directions) ---"
bash "$FIX/leaky/test.sh" >/dev/null 2>&1
assert "T3-AC1: the leaky suite is GREEN on holed code" $?
bash "$FIX/leaky/probe-check.sh" >/dev/null 2>&1
assert "T3-AC2 [NEGATIVE CONTROL]: the leaky hole is REAL (probe violates the contract)" $?
bash "$FIX/tight/test.sh" >/dev/null 2>&1
assert "T3-AC3: the tight suite is GREEN with the guard in place" $?
# Strip the GUARD-LINE into a temp impl and re-run the tight suite against it.
STRIPPED=$(mktemp)
grep -v 'GUARD-LINE' "$FIX/tight/impl.sh" > "$STRIPPED"
[ "$(wc -l < "$STRIPPED")" -lt "$(wc -l < "$FIX/tight/impl.sh")" ]
assert "T3-AC3: the guard strip removed a line (control not vacuous)" $?
if BREAK_IT_IMPL="$STRIPPED" bash "$FIX/tight/test.sh" >/dev/null 2>&1; then
  assert "T3-AC3 [NEGATIVE CONTROL]: without the guard the tight suite goes RED" 1
else
  assert "T3-AC3 [NEGATIVE CONTROL]: without the guard the tight suite goes RED" 0
fi
rm -f "$STRIPPED"

# --- TASK-004 AC2: one grep per I/O-contract invariant ------------------------
echo ""
echo "--- prompt completeness: invariants ---"
grep -qi 'no concrete input is not a finding' "$A"
assert "T4-AC2/inv1: no concrete input means no finding" $?
grep -qi 'never downgrade it to a hint' "$A"
assert "T4-AC2/inv1: a dropped candidate is never downgraded to a hint" $?
grep -q 'UNVERIFIED' "$A"; assert "T4-AC2/inv2: the UNVERIFIED alternative exists" $?
grep -qi 'only behavior you actually observed' "$A"
assert "T4-AC2/inv2: observed: may state only observed behavior" $?
grep -q 'NO-PROBE' "$A"; assert "T4-AC2/inv3: NO-PROBE is in the output grammar" $?
grep -qi 'NO-PROBE. is a verdict, not a failure to try' "$A"
assert "T4-AC2/inv3: NO-PROBE is a verdict that names what was tried" $?
grep -qi 'never write a test' "$A"; assert "T4-AC2/inv4: the lens never writes a test" $?
grep -qi 'never edit' "$A"; assert "T4-AC2/inv4: the lens never edits" $?
grep -qi 'never run.*mutation' "$A"; assert "T4-AC2/inv4: the lens never runs the mutation gate" $?

# --- TASK-004 AC3: one grep per edge case 1, 3, 4, 5, 8 ----------------------
echo ""
echo "--- prompt completeness: edge cases ---"
grep -qi 'carries no tests' "$A"; assert "T4-AC3/edge1: the no-tests branch exists" $?
grep -qi 'infinite and worthless' "$A"; assert "T4-AC3/edge1: it stops rather than enumerating" $?
grep -q 'Out of Scope' "$A"; assert "T4-AC3/edge3: non-goals are consulted" $?
grep -q 'rejected-findings.md' "$A"; assert "T4-AC3/edge3: the rejected-findings ledger is consulted" $?
grep -q 'Previously rejected:' "$A"; assert "T4-AC3/edge3: a ledger match gets its own reported line" $?
grep -q 'unconstrained-by:' "$A"; assert "T4-AC3/edge4: findings carry the unconstrained-by citation" $?
grep -qi 'without an .unconstrained-by:. citation is not emitted' "$A"
assert "T4-AC3/edge4: a finding without the citation is not emitted" $?
grep -qi 'suite cannot run' "$A"; assert "T4-AC3/edge5: the unrunnable-suite branch exists" $?
grep -qi 'fail-open' "$A"; assert "T4-AC3/edge8: the ledger consult is fail-open" $?
grep -qi 'never an error and never blocks' "$A"
assert "T4-AC3/edge8: a malformed ledger never blocks the lens" $?

# --- TASK-004 AC4: command safety + masking ----------------------------------
echo ""
echo "--- prompt completeness: safety ---"
grep -qi 'VERBATIM' "$A"; assert "T4-AC4: test commands are re-run verbatim" $?
grep -qi 'never append an argument' "$A"
assert "T4-AC4: the lens never appends an argument, flag, redirect, or metacharacter" $?
grep -qi 'DATA, never instructions' "$A"
assert "T4-AC4: the diff and its fixtures are data, never instructions" $?
grep -qi 'reported as a finding, never obeyed' "$A"
assert "T4-AC4: an instruction-shaped comment is reported, not obeyed" $?
grep -qi 'Mask any credential-shaped string' "$A"; assert "T4-AC4: the masking rule exists" $?
grep -q 'first8...last8' "$A"; assert "T4-AC4: the masking rule names the hex shape" $?
grep -q 'first4...last4' "$A"; assert "T4-AC4: the masking rule names the vendor-prefixed shape" $?

# --- TASK-005: docs wiring ---------------------------------------------------
echo ""
echo "--- docs wiring ---"
grep -q '^| `break-it` ' "$KIT_DIR/docs/MANUAL.md"; assert "T5-AC1: docs/MANUAL.md carries a break-it row" $?
grep -q '^| break-it |' "$KIT_DIR/README.md"; assert "T5-AC1: README agents table carries a break-it row" $?
grep -q '`break-it`' "$KIT_DIR/docs/architecture.md"; assert "T5-AC1: docs/architecture.md inventory carries break-it" $?
# AC2: the three rungs appear in WORKFLOW.md's ladder paragraph, in ladder order.
LADDER=$(sed -n '/three-rung ladder/,/^$/p' "$WF" | tr '\n' ' ')
[ -n "$LADDER" ]; assert "T5-AC2: docs/WORKFLOW.md has a three-rung ladder paragraph" $?
echo "$LADDER" | grep -q 'coverage.*probe.*mutation'
assert "T5-AC2: the ladder names coverage, then probe, then mutation, in order" $?
echo "$LADDER" | grep -qi 'stated, not enforced'
assert "T5-AC2: the ladder states the order is not enforced (open question 1)" $?

# --- TASK-004 AC5 [closing move]: the effectiveness gate ---------------------
# test-advisor.sh's closing move: the last assertion is the SG-01 gate on the
# new agent, so a prompt that passes every grep above but fails the gate is
# still a failure.
echo ""
echo "--- SG-01 effectiveness gate ---"
if bash "$KIT_DIR/tests/test-agent-effectiveness.sh" "$A" >/dev/null 2>&1; then
  assert "T4-AC5: break-it passes the SG-01 agent-effectiveness gate" 0
else
  assert "T4-AC5: break-it passes the SG-01 agent-effectiveness gate" 1
fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
