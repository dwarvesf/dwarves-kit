# Proof of done: every-step review default (SPEC-093, ADR-0028 P4, kit-hardening SG-05)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | Every full-lane phase maps to a review; no review phase skip | WORKFLOW every-step mapping wires all reviewers (spec-validate, review-team, task/integration/acceptance/system-verifier, brief-reviewer, doc-verifier, recheck-verifier, advisor); required-full set includes spec+review+ship | PASS |
| AC2 [NEGATIVE CONTROL] | ship-gate blocks a missing required phase-review | real gate-ledger: `check full` BLOCKS with `review` missing, PASSES once recorded | PASS |
| AC3 | Enforcement at ship, not mid-flight | WORKFLOW states "Enforcement is at ship, never mid-flight"; a mid-flight failing review is advisory; no new hard stop added | PASS |

## Implementation

- `WORKFLOW.md` -- V-model ASCII + duality table updated for the SG-03/04 agents (brief-reviewer, acceptance-verifier, system-verifier, recheck-verifier, advisor); new "Every-step review in the full-autonomous lane (P4, SG-05)" section with the phase -> review mapping + the enforcement-at-ship-not-mid-flight contract; the stale "acceptance-verifier v2 candidate" prose corrected to SHIPPED.
- `tests/test-every-step-review.sh` -- AC1-AC3 incl. the real gate-ledger block/pass negative control.
- No matrix change: the full lane already had no review-phase skip (see impl-notes).

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-every-step-review.sh` | 0 | 17/17 passed |
| `bash tests/test-meta.sh` | 0 | All meta tests passed |
| `bash tests/test-hooks.sh` | 0 | All tests passed |

## Run detail

```
=== every-step review (SPEC-093 AC1-AC3) ===
  PASS AC1: WORKFLOW has the every-step review mapping section
  PASS AC1: mapping wires a review: spec-validate / review-team / task-verifier /
           integration-verifier / doc-verifier / acceptance-verifier / system-verifier /
           brief-reviewer / recheck-verifier / advisor
  PASS AC1: full lane's required set includes spec+review+ship (no review phase skipped)
  PASS AC2 [NEGATIVE CONTROL]: check BLOCKS when required 'review' gate is missing
  PASS AC2: check PASSES once every required phase-review is recorded
  PASS AC3: WORKFLOW states enforcement at ship, never mid-flight
  PASS AC3: a failing phase-review mid-flight is advisory, does not halt the run
  PASS AC3: every-step review did NOT become a new hard stop (still advisory + ship-gate only)
=== 17/17 passed, 0 failed ===
```

## NEGATIVE CONTROL (the load-bearing proof)

The risk (ADR-0028) is every-step review degrading into a mid-flight hard block, OR the
ship-gate NOT actually blocking a missing review. Both are controlled: AC2 runs the real
`gate-ledger check full` against an isolated ledger with `review` deliberately omitted
and asserts it BLOCKS (exit nonzero), then records `review` and asserts it PASSES. AC3
asserts the four-hard-stops table gained no phase-review blocker, so the enforcement
stayed at ship and mid-flight stayed advisory.

## Reproduce

```
cd dwarves-kit
bash tests/test-every-step-review.sh   # 17/17, exit 0
bash lib/gate-ledger.sh required full    # the required phase set
```
