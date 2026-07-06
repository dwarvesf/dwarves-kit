# SPEC-093: Every-step review default (P4)

Status: VALIDATED
Date: 2026-07-02
Lane: full (WORKFLOW lane default + gate-ledger wiring for the enforcement surface)
Type: feature
Relates-to: ADR-0028 (P4 every-step review), ADR-0024 (gate-ledger, advisory-mid/hard-at-ship), SPEC-076 (V-model descent), SPEC-091 (advisor), SPEC-092 (right-arm parity)
Board: kit-hardening mega-goal SG-05

## Problem
ADR-0028 P4 requires that in the full-autonomous-to-final lane, EVERY V-model phase
(left + right arm) has a review step that RUNS and records to the gate-ledger, with no
phase `skip`. The reviewers exist (SG-03 advisor, SG-04 right-arm agents) but WORKFLOW
still described the right arm as executor-only with agent-less Acceptance/System rows
and acceptance-verifier as a "v2 candidate" -- stale after SG-04. Nothing documented
the phase -> review mapping as a lane default, and the ship-gate enforcement of a
missing phase-review was not covered by a test.

## Decision
Wire SG-03/04's reviewers into the full lane as the DEFAULT: document the complete
phase -> review mapping (every V-model phase -> the review that validates it), confirm
no review-bearing phase is `skip`, and prove the enforcement contract: each phase's
review RUNS and records; mid-flight a failing review is ADVISORY (never halts); the
only hard wall is the ship-gate, which refuses a push whose lane has a measure-twice
phase with no `ran`/`override` entry (ADR-0024, unchanged). This is WIRING, not new
reviewers or a new mid-flight block.

## Acceptance criteria
- AC1: every full-lane V-model phase maps to a review agent/command (the WORKFLOW every-step mapping); no review-bearing phase is `skip`.
- AC2 [negative control]: the ship-gate (gate-ledger check) BLOCKS a push whose lane has a required phase-review missing, and PASSES once it is recorded.
- AC3: enforcement is at ship only; a failing phase-review mid-flight is advisory and does not halt the run (no new hard stop).

## Tasks
- T1: update WORKFLOW.md V-model (ASCII V + duality table + mirror/coverage prose) for the SG-03/04 agents.
- T2: add the "Every-step review in the full-autonomous lane" mapping + enforcement section.
- T3: `tests/test-every-step-review.sh` covering AC1-AC3 with a real gate-ledger negative control.

## Verification
```
bash tests/test-every-step-review.sh   # AC1-AC3; real gate-ledger block/pass negative control
bash lib/gate/gate-ledger.sh required full   # the required phase set (every review-bearing phase)
bash tests/test-meta.sh                 # WORKFLOW/roster stays green
```
Proof-of-done: table-first run-table with the mapping-coverage rows + the block/pass negative control.

## Review
Integration-branch + gated-final (ADR-0028): targets `mega/kit-hardening`, auto-merges past its own ship-gate; single human review at the final `-> master` PR.

## Out of Scope
- Creating reviewers (SG-03/04 did that).
- Hard-gating any phase mid-flight (ADR-0024 + PHILOSOPHY stand).
- Adding review to lanes other than the full-autonomous lane.
