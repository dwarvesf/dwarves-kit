# Sub-goal 05: every-step review defaults (P4)

**Merge policy:** auto , a WORKFLOW default + gate-ledger wiring, testable.
**Time budget:** 2-4 hours.
**Proof:** run-table , in this lane no V-model phase is `skip`; each phase's review RUNS + records to the gate-ledger; the ship-gate blocks a push with a required phase-review missing; enforcement is at ship, NOT mid-flight.
**Depends on:** 03 + 04 (it wires the reviewers those sub-goals create into the no-skip lane).
Model: sonnet
Effort: high
**Branch:** feat/kit-harden-05-everystep
**PR base:** mega/kit-hardening

## Outcome

In the full-autonomous-to-final lane, EVERY V-model phase (left + right arm) has a review step that RUNS and records to the gate-ledger , a command, a predefined agent, or a runtime agent. No phase is `skip` in this lane. The reviews run + record mid-flight (advisory, never a hard block , PHILOSOPHY + ADR-0024 preserved); hard enforcement stays at ship, where the ship-gate refuses a push whose lane has a required phase-review with no `ran`/`override` entry.

## Quality bar

This is WIRING, not new reviewers: it connects the left-arm reviewers + the SG-03/04 additions into the lane default so the team inherits full-coverage review from bare `/kit:*`. It must NOT become a mid-flight hard-block , the review runs and records; the wall is at ship only. Every phase in the lane's `plan` has a mapped review agent/command.

## How to close the loop

Set the lane default in WORKFLOW.md (no phase `skip`), map each phase to its review agent/command, ensure each records via `lib/gate-ledger.sh`. Verify:

```
cd dwarves-kit && bash tests/test-every-step-review.sh   # no phase skip in lane; each records; ship-gate blocks a missing required review; no mid-flight block
bash lib/gate-ledger.sh plan full   # every phase has a review destination
```

Captured evidence: run-table at `docs/verification/every-step-review.md` , a row showing each lane phase maps to a review, a negative-control row (omit one phase-review, ship-gate blocks), and a row proving mid-flight is advisory (a phase review FAILING does not halt the run, only the ship-gate does).

**Done =** `test-every-step-review.sh` proves every V-model phase in the full lane records a review to the gate-ledger, the ship-gate blocks a push with a required phase-review missing, and no phase-review is a mid-flight hard block.

**Kit-adopted repo? Record the gates.** `bash lib/lane-classify.sh classify "every-step review default: no phase skip in full lane, records to gate-ledger"`, record build + review via `lib/gate-ledger.sh` before push.

## Handoff on completion

1. Flip 05's box, PR # + SHA.
2. HOT `HANDOFF.md`: next is 06-lane-escalation OR 07-deployable-done (both independent); first action per whichever remains.
3. WARM `DECISIONS.md`: the full lane now reviews every phase (advisory mid-flight, hard at ship); this is P4 realized.
4. Report IN records, EXIT.

## Scope edges

**In:** WORKFLOW.md lane defaults, the phase->review mapping, gate-ledger recording per phase, the ship-gate required-review check, tests.
**Out:** creating the reviewers (03/04 did that); the advisor's extra lens (03).
**Not:** hard-gating any phase mid-flight (ADR-0024 + PHILOSOPHY stand); adding review to lanes OTHER than the full-autonomous lane.

## Where to look

WORKFLOW.md (lane x phase table), `lib/gate-ledger.sh` (plan + record + the ship-gate read), `lib/lane-classify.sh`, ADR-0028 P4, AGENTS.md (the operate-contract the ship-gate enforces).

## PR body

Wires the every-step review default (kit-hardening SG-P4, ADR-0028): in the full-autonomous lane no V-model phase is `skip`; each phase's review runs + records to the gate-ledger; the ship-gate hard-enforces at push, mid-flight stays advisory.

Verify: `bash tests/test-every-step-review.sh` + `bash lib/gate-ledger.sh plan full`. Proof: `docs/verification/every-step-review.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. On the integration branch after SG-03 + SG-04.

## Notes

<empty>
