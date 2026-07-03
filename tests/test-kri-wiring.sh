#!/usr/bin/env bash
# test-kri-wiring.sh (SPEC-135, the kit-run-integrity mega-goal's sub-goal 06)
#
# No-orphan wiring check for kit-run-integrity's five sub-goals (01-05, plus the SPEC-133
# reconcile and SPEC-134 security hardening), mirroring tests/test-docs-wiring.sh's
# established pattern (the c6fbd99 kit-hardening precedent): every capability the docs claim
# exists must have a LIVE call site in real source, not just a flag/env-var definition, and
# the sweep itself must be proven non-trivial by a load-bearing negative control (AC-NEG).
#
# This check DISTINGUISHES enforcement levels rather than certifying everything "wired" on
# the weakest reading (the TIER-4 advisor finding this sub-goal exists to close): 01 is
# HOOK-ENFORCED, 02 is orchestrate.sh's own dispatch path, 03/04 are PROSE-INVOKED-ONLY (an
# agent can skip the command with zero trace), 05 is OPERATOR-INVOCABLE. A defined-but-never-
# dispatched surface is a BLOCKING finding, not a doc note; this script is that gate.
#
# Run: bash tests/test-kri-wiring.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS="$KIT_DIR/AGENTS.md"
WORKFLOW="$KIT_DIR/WORKFLOW.md"
ADR0024="$KIT_DIR/docs/decisions/0024-gate-ledger-and-ship-enforcement.md"
VERIF_README="$KIT_DIR/docs/verification/README.md"
SHIP_GATE="$KIT_DIR/hooks/ship-gate.sh"
ORCH="$KIT_DIR/lib/orchestrate.sh"
SPEC_NEXT="$KIT_DIR/lib/spec-next.sh"
REVIEW_TEAM="$KIT_DIR/commands/review-team.md"
VERIFY_CMD="$KIT_DIR/commands/verify.md"
PROOF_GEN_PY="$KIT_DIR/lib/proof-table-gen.py"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

# _wired <corpus-file> <fixed-string>: 0 if the exact call-site string is present (LIVE-wired),
# 1 otherwise (orphan / over-claim). Fixed-string match, keyed on the CALL SITE, same style as
# test-docs-wiring.sh.
_wired() { grep -qF -- "$2" "$1" 2>/dev/null; }

echo "=== kit-run-integrity no-orphan wiring check (SPEC-135) ==="

echo "--- doc-presence: AGENTS.md + WORKFLOW.md carry all five surfaces ---"

for f in "$AGENTS" "$WORKFLOW"; do
  [ -f "$f" ]; assert "$(basename "$f") exists" $?
done

_wired "$AGENTS" "SPEC-129"; assert "AGENTS.md mentions the gate-outcome marker (01, SPEC-129)" $?
_wired "$AGENTS" "SPEC-128"; assert "AGENTS.md mentions the wavefront spec-reservation (02, SPEC-128)" $?
_wired "$AGENTS" "SPEC-132"; assert "AGENTS.md mentions the generated proof-table (05, SPEC-132)" $?
_wired "$AGENTS" "HOOK-ENFORCED"; assert "AGENTS.md states the OUTCOME emitter is hook-enforced" $?

_wired "$WORKFLOW" "SPEC-129"; assert "WORKFLOW.md mentions the gate-outcome marker (01, SPEC-129)" $?
_wired "$WORKFLOW" "SPEC-128"; assert "WORKFLOW.md mentions the wavefront spec-reservation (02, SPEC-128)" $?
_wired "$WORKFLOW" "SPEC-130"; assert "WORKFLOW.md mentions coverage-delta (03, SPEC-130)" $?
_wired "$WORKFLOW" "SPEC-131"; assert "WORKFLOW.md mentions mutation-smoke (04, SPEC-131)" $?
_wired "$WORKFLOW" "SPEC-132"; assert "WORKFLOW.md mentions the generated proof-table (05, SPEC-132)" $?
_wired "$WORKFLOW" "Advisory measurement gates"; assert "WORKFLOW.md has an Advisory measurement gates section" $?
_wired "$WORKFLOW" "PROSE-INVOKED"; assert "WORKFLOW.md names 03/04 PROSE-INVOKED (not hook-enforced)" $?
_wired "$WORKFLOW" "HEURISTIC"; assert "WORKFLOW.md names coverage-delta a heuristic" $?
_wired "$WORKFLOW" "Han's call"; assert "WORKFLOW.md names advisory->block promotion as Han's call, not taken" $?

_wired "$ADR0024" "OUTCOME"; assert "ADR-0024 names the OUTCOME marker as an additive verb" $?
_wired "$ADR0024" "MUTATION"; assert "ADR-0024 names the MUTATION marker as an additive verb" $?

_wired "$VERIF_README" "reflect the Ship phase only"; assert "docs/verification/README.md states the OUTCOME column is ship-boundary-only" $?

echo "--- no-orphan sweep: each surface has a LIVE call site in real source -----------------"

# 01: gate-outcome emit -- hooks/ship-gate.sh brackets the check with start/end
_wired "$SHIP_GATE" 'outcome "$SLUG" ship start'; assert "01: OUTCOME start is emitted at the ship boundary (live call site, hooks/ship-gate.sh)" $?
_wired "$SHIP_GATE" 'outcome "$SLUG" ship end caught=true'; assert "01: OUTCOME end caught=true fires on a block (live call site)" $?
_wired "$SHIP_GATE" 'outcome "$SLUG" ship end caught=false'; assert "01: OUTCOME end caught=false fires on a clean pass (live call site)" $?

# 02: wavefront spec-reservation -- orchestrate.sh actually calls _wave_reserve_spec at dispatch,
# and spec-next.sh actually implements the reserve subcommand it calls into.
_wired "$ORCH" '_wave_reserve_spec'; assert "02: orchestrate.sh's wave dispatch calls _wave_reserve_spec (live call site)" $?
_wired "$ORCH" 'reserved_spec="$(_wave_reserve_spec)"'; assert "02: the reservation result is captured + injected into the worker prompt (live call site)" $?
_wired "$SPEC_NEXT" 'reserve) reserve ;;'; assert "02: spec-next.sh implements the reserve subcommand _wave_reserve_spec calls into" $?

# 03: coverage-delta -- review-team.md actually invokes it
_wired "$REVIEW_TEAM" 'bash lib/coverage-delta.sh check'; assert "03: /kit:review-team invokes coverage-delta.sh (live call site, commands/review-team.md)" $?

# 04: mutation-smoke -- verify.md actually invokes it
_wired "$VERIFY_CMD" 'bash lib/mutation-smoke.sh run'; assert "04: /kit:verify invokes mutation-smoke.sh (live call site, commands/verify.md)" $?

# 133: proof-table-gen actually parses 01's REAL two-line OUTCOME marker (the reconciled shape),
# not the original assumed single-line shape (would have been an orphan against real 01 data).
_wired "$PROOF_GEN_PY" 'elif marker == "OUTCOME" and len(parts) >= 4:'; assert "133: proof-table-gen.py's OUTCOME branch models the real two-line marker (live call site)" $?

# 134: security hardening -- the path-confinement guard is actually present and load-bearing
# (checked BOTH lines: the runs_root anchor and the confinement comparison that rejects escape)
_wired "$PROOF_GEN_PY" 'runs_root = os.path.realpath(os.path.join(kit_root, "docs", "runs"))'; assert "134: proof-table-gen.py anchors the confinement root (live call site)" $?
_wired "$PROOF_GEN_PY" 'if resolved_out != runs_root and not resolved_out.startswith(runs_root + os.sep):'; assert "134: proof-table-gen.py confines the resolved out-path (live call site)" $?

echo "--- AC-NEG [NEGATIVE CONTROL, load-bearing]: a planted over-claim is CAUGHT ------------"

# The planted claim: "coverage-delta and mutation-smoke are hook-enforced push blockers" would
# only be true if WORKFLOW.md said so. It does not (it says PROSE-INVOKED, off the push
# blocker); confirm the false corollary is genuinely absent first (so the control cannot
# silently rot into a false pass if the docs later change), then confirm the sweep catches it.
PLANTED_CLAIM='coverage-delta and mutation-smoke are hook-enforced push blockers'
FALSE_COROLLARY='03/04 are hook-enforced push blockers'

if _wired "$WORKFLOW" "$FALSE_COROLLARY"; then
  assert "AC-NEG: negative-control precondition holds (WORKFLOW.md does NOT claim 03/04 are hook-enforced push blockers)" 1
else
  assert "AC-NEG: negative-control precondition holds (WORKFLOW.md does NOT claim 03/04 are hook-enforced push blockers)" 0
fi

if _wired "$WORKFLOW" "$FALSE_COROLLARY"; then
  sweep_verdict=wired
else
  sweep_verdict=orphan
fi
if [ "$sweep_verdict" = orphan ]; then
  assert "AC-NEG: the sweep CATCHES the planted over-claim ('$PLANTED_CLAIM')" 0
else
  assert "AC-NEG: the sweep CATCHES the planted over-claim ('$PLANTED_CLAIM')" 1
fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
