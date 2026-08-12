# SPEC-231: Auto review-fix loop as a default spine phase

**Status:** BUILT (the wiring edits land in this PR; this spec records the contract they implement)
Lane: full
**Foundation:** `docs/patterns/review-fix-loop.md` (the three moves + the scaling gate). **Brief:** `docs/briefs/DECISION-BRIEF-auto-review-loop.md`. **Relates:** `agents/advisor.md` (P5 critique + over-suggest, unchanged agent, now default-run on full lane), `commands/review-team.md` (gains convergence-rank + loop), SPEC-228 (scenario-gen wiring precedent for the one-edit-per-surface shape), ADR-0028 (SG-05 advisor).

## Problem

The multi-lens review is advisory-optional at every phase. The operator invokes
it by hand after a build, and it repeatedly finds real defects, including
critical money-path bugs that a prior fix batch introduced. A step this valuable
should not depend on the operator remembering to ask. Three specific gaps:

1. The review only runs on request, not by default.
2. `advisor` runs exactly once (P5). Nothing re-reviews a fix batch, so a fix
   that reopens a bug ships unseen.
3. Findings are not ranked by lens convergence, so single-lens taste reads
   equal to a defect two lenses hit independently.

## Decision

Promote the existing review agents to default phases on the FULL lane, add
convergence-ranking and a bounded re-review loop to `review-team`, and add a
default design-time pass at the spec stage. Auto-RUN, not auto-BLOCK: the verdict
stays advisory. The cost is gated by lane per the pattern's scaling table. No new
agents.

## Wiring (one edit per surface, marked `<!-- review-loop -->`)

| Surface | Edit |
|---|---|
| `commands/review-team.md` | the merge step tags each finding with its lens count and sorts convergent-first; a new closing section defines the bounded loop: after a fix batch clears the convergent findings, re-run over the FIX diff, stop at no-convergent-finding OR two rounds, report unresolved-at-cap |
| `commands/execute.md` | on the full lane, the Review phase runs `review-team` by default (not opt-in); the loop drives to the fix step and back |
| `commands/spec.md` | the full lane runs a default design-time pass (`devs-team` critique + `advisor` over-suggest) over the spec before it validates; normal keeps it opt-in |
| `agents/advisor.md` | over-suggest mode is default-run on the full lane at the design-time pass, not opt-in; the agent body is unchanged, only its trigger note |
| `docs/WORKFLOW.md` | the cycle table Review and Design-critique rows show "default (full lane)" instead of "opt-in"; the advisor P5/P6 section names the two firing points and the loop, and points at the pattern |

## Non-goals

- No auto-BLOCK. The verdict is advisory; only the existing hard gates stop a ship.
- No loop or default review on normal or tiny lanes (the scaling gate).
- No new lens agent. The lenses are the ones `review-team` already dispatches.
- No shift of test design up the left arm (unchanged; SPEC-228 territory).

## After state

- A full-lane build runs the review by default, with findings sorted convergent-first, and re-runs the review on each fix batch up to two rounds.
- A full-lane spec gets a design-time critique + over-suggest pass before it validates.
- Normal and tiny lanes are unchanged in cost.
- Every doc that lists the Review and Design-critique phases says "default (full lane)" where it said "opt-in."

## Verification

- `commands/review-team.md` contains a convergence-rank step and a bounded-loop section with a stated round cap; grep the `<!-- review-loop -->` markers and confirm each named surface carries one.
- `docs/WORKFLOW.md` cycle table shows the Review row as default for the full lane and references `docs/patterns/review-fix-loop.md`.
- A dry read of `commands/execute.md` shows the full-lane Review phase is no longer gated behind an operator opt-in.
- The pattern doc and the brief exist and cross-reference this spec.
- No normal/tiny-lane surface gained a default review (the scaling gate holds).
