# SPEC-228: Scenario generation wired into every workflow altitude

**Status:** BUILT (prompt-artifact edits land in this PR; this spec records the
wiring and its contract)
Lane: normal
**Foundation:** `docs/patterns/scenario-generation.md` (the shared three-move
method). **Relates:** SPEC-227 (the gauntlet's journey matrix is the pattern's
move 1 instance), SPEC-203 (test-generation loop, unchanged, now fed better
input), ID-423 (bench plane, unchanged).

## Problem

Scenario thinking fires in exactly one place today, inside `/kit:test-plan`,
after a spec exists, keyed to the spec's own acceptance criteria. Three costs:
the matrix inherits the spec's blind spots (criteria the author never thought
to write get no rows); scenarios surface at the most expensive altitude to act
on (post-contract); and beats that never reach a spec (loop definitions,
explorations, gauntlet prep) get no scenario set at all unless someone
improvises one.

## Decision

One shared generation method (the pattern doc's three moves: journey walk,
guarantee inversion, category sweep) + a small beat at each altitude that calls
it, with the DOWNHILL rule: generate once at the cheapest altitude that can see
the scenario, refine below, never regenerate blank.

## Wiring (one edit per surface, marked `<!-- scenario-gen -->`)

| Surface | Edit |
|---|---|
| `commands/think.md` | the Decision Brief gains a `Survival scenarios` block (3-5 rows, move-2-heavy, no oracles), seeded during Q5's "what breaks" beat |
| `commands/design.md` | the Solution section carries the sketch forward and may add rows; it never drops an upstream row without a stated reason |
| `commands/grill.md` | the closing `Done =` proposal now pairs with 2-3 must-NOT-happen scenarios (the negative space of done) |
| `commands/spec.md` | `## Edge Cases` is seeded from the brief's sketch and extended by a full three-move pass; the template says so instead of showing bare placeholders |
| `commands/test-plan.md` | Step 1 reads the spec's scenario set (Edge Cases + Failure modes) alongside ACs; if the spec carries none, run the three moves FIRST, write them back into the spec, then derive the matrix |
| `skills/loop-engineering/SKILL.md` | the anatomy gains a mandatory slot: a new loop ships its survival set (convergence, non-convergence, bad input, interrupted run, gamed metric) before it is considered designed |

## Non-goals

- No new command, no new agent, no lib code. Every edit is a prompt beat
  calling the shared pattern.
- No change to SPEC-203's loop mechanics; it now receives specs that already
  carry scenario sets, which is the point.
- Gauntlet-specific generation stays SPEC-227's (journey-as-spec is move 1 at
  full depth).

## Verification

- Grep contract: each of the six surfaces contains the marker
  `<!-- scenario-gen -->` and a reference to
  `docs/patterns/scenario-generation.md` (recorded run below in the proof).
- Negative control: reverting one surface drops its marker (grep fails).
- Behavioral acceptance (deferred to first live use, recorded then): the next
  `/kit:think` run produces a brief with a `Survival scenarios` block; the next
  spec written from it carries the rows into `## Edge Cases`.
