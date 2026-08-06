# Implementation notes: SPEC-093 every-step review (kit-hardening SG-05)

Delta from SPEC-093 / ADR-0028 P4.

## 2026-07-02 No matrix change needed; the full lane already has no review-phase skip

Context: the goal says "set the lane default (no phase skip)". Inspection of the
WORKFLOW lane x phase matrix showed the full lane already has no `skip` for any
review-bearing phase (`bash lib/gate/gate-ledger.sh plan full` lists all 13 phases as
required/lite; only Debug (off-cycle, not in the linear V) and UI-design (run-lite,
downstream) are non-measure-twice, both legitimately). So SG-05 is WIRING + a
documented mapping + a test, NOT a matrix edit. Touching the matrix would have been
churn against a lane that was already correct.

## 2026-07-02 SG-05 also fixed WORKFLOW drift SG-04 left behind

SG-04 shipped acceptance-verifier / system-verifier / brief-reviewer / recheck-verifier
and updated docs/architecture.md, but WORKFLOW.md's V-model duality table + "coverage
gaps" prose still described the right arm as executor-only with acceptance-verifier as
a "v2 candidate". SG-05's mapping section is where those agents belong, so the WORKFLOW
update both wires the every-step mapping AND corrects that drift in one pass.

## 2026-07-02 The negative control exercises the real gate-ledger, not prose

AC2 is proven by isolating DWARVES_KIT_LOG_DIR to a temp dir, recording every required
full-lane gate EXCEPT `review`, and asserting `gate-ledger check full <rid>` exits
nonzero (blocks), then recording `review` and asserting it exits zero. This runs the
actual enforcement path the ship-gate calls, not a documentation grep.
