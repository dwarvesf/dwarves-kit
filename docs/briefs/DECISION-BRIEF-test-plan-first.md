# Decision Brief: test-plan-first as the default (mode-aware matrix sign-off)

Date: 2026-07-25 · Source: operator direction ("I want to be the one who works through the test
cases before implementation and planning", acpx-arc session). Status: DRAFT (backfilled from the
row per the brief-on-file rule; feeds ID-406's spec). Consuming row: ID-406. Records:
`docs/research/2026-07-25-acpx-absorption.md` + docs/verification/test-design-standard.md.

## Verified current state

/kit:test-plan + /kit:test-plan-review-team exist and are OPT-IN; N3's own gap statement says
"test-plan is opt-in, so most work skips design-first." The operator wants the matrix worked
BEFORE implementation, with himself as the signer in interactive work.

## The design (decisions made in-session)

1. **Default-on where a proof is owed**: /kit:spec runs /kit:test-plan by default when the task
   type owes a behavioral/stateful proof; dialect per the test-design-standard (BDD rows for
   features, metrics + HAND-VERIFIED seeds for evals, claim matrices for research).
2. **The human works the matrix**: rows are presented to tick / edit / ADD before spec sign-off;
   operator-added rows are the signal the generator cannot know. `## Test plan` gains an
   `approved-by:` marker.
3. **Mode-aware signing** (`Mode: delegate|handoff` header on the goal file):
   - **delegate** (mega, 100% hands-off; default for mega): the agent designs the matrix and the
     adversarial /kit:test-plan-review-team pass is the RECORDED substitute signer; no mid-run
     human gate (conforms N5: attention at define-done + judge-end only).
   - **handoff** (interactive assign/spec; default there): the human controls requirement (input)
     and matrix (output); handoff to execution happens AFTER sign-off; `approved-by: han`
     required.
4. **Enforcement split**: /kit:execute preflight WARNS when the marker is missing (advisory);
   the ship-gate REFUSES a full-lane ship without it (blocking lives at ship only, per ADR-0024).
5. **Surfaced §6 conflict + resolution**: N3's text rejects "a blocking test-first gate"; since
   the maintainer explicitly asks to be the gate, the same change AMENDS N3's reject-line
   (block at ship-gate only; execute stays advisory). The conflict is resolved by amendment,
   never silently.
6. **Dogfood + deliverable**: this spec is the first whose matrix the operator works (handoff
   mode); done includes a build-log article via narrate-log (private draft, privacy-gated
   promote).

## North-star conformance (§6)

N3 (flips design-first from opt-in to default) + the attention-at-two-points meta-principle (the
matrix IS the define-done attention point, front-loaded). Mode split preserves N5 for delegate
runs.

## Exit criteria

1. A spec owing a behavioral proof cannot full-lane ship without `approved-by` (ship-gate red),
   while execute merely warns (advisory verified).
2. Delegate-mode mega records the review-team pass as signer with zero mid-run prompts.
3. N3's amended text and the Mode header docs land in the same change (no doc drift).
