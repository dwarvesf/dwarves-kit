# Sub-goal 04: test-dialects

**Time budget:** 2-4 hours of loop work, after PR-02 merges (parallel-safe with 03: different files)
**Depends on:** 02
**Branch:** `feat/north-star-04-dialects` (dwarves-kit)

## Outcome

Test design is shaped per work type, and it happens BEFORE execution:

- **Dialect table.** `docs/verification/test-design-standard.md` gains a per-type dialect section mapping each registry type to how its tests are designed: spec-feature -> BDD-style scenario/coverage matrix (the existing `## Test plan`); eval -> metrics + hand-verified seed data + falsifiability controls (the tool-eval-experiment shape); research -> claim-verification matrix (every load-bearing claim names its source + an adversarial check); migration/cleanup -> inventory + conform/drift coverage + rollback rehearsal; data-tool -> recorded live run + negative control; doc -> doc-verifier match. One spine (the standard's §1-§6), six bodies.
- **Wiring.** `/kit:test-plan` reads the task's type (from the 02 registry) and writes the matching dialect, not one-size BDD. The type registry's proof column cross-references the dialect.
- **Default, not opt-in.** In WORKFLOW's cycle table, test-plan moves from "opt-in" to default-suggested for normal/full lanes and for every type loop that owes a behavioral/stateful proof (tiny stays exempt). Suggested means the cycle names it and `/kit:start` nudges; it does not hard-block (that stays the ship-gate's job).

This is the SDD trace of north-star N3. Most machinery exists (test-design-standard, /kit:test-plan, /kit:test-plan-review-team, verification framework, proof gate); this sub-goal is the per-type shaping + the default flip.

## Quality bar

A test plan for an eval looks like an eval (numbers, seeds, controls), not a feature checklist wearing a lab coat. The standard stays ONE document: dialects specialize the spine, they do not fork it.

## How to close the loop

```sh
cd ~/workspace/tieubao/dwarves-kit
grep -c 'dialect' docs/verification/test-design-standard.md      # >= 6 (one per type)
grep -c 'task-type\|dialect' commands/test-plan.md               # >= 1 (wiring)
grep -A2 'Test plan' WORKFLOW.md | grep -vc 'opt-in'             # default flip visible in the cycle table
bash tests/test-meta.sh                                           # all green incl. new pins
bash lib/lane-classify.sh classify "per-type test-design dialects + default test-plan for normal and full"  # run that lane's gates
```

**Done =** the dialect table covers all six types, /kit:test-plan picks the dialect from the type, the cycle table shows test-plan as default for normal/full, pins + suites green, PR open + CI green.

## Scope edges

**In:** test-design-standard.md, commands/test-plan.md, WORKFLOW.md cycle table, docs/verification/task-types.md cross-refs, tests, a SPEC, CHANGELOG row.
**Out:** the loop definitions themselves (02); board states (03); /kit:test-plan-review-team (already shipped, untouched).
**Not:** a hard test-first block (advisory default only; "Detect, don't dictate"); per-type TEMPLATE files (the table in the standard is enough; files would fork the spine); changing the proof-ledger gate markers.

## Where to look

`docs/verification/test-design-standard.md` (the spine to specialize); `commands/test-plan.md`; the eval shape in ops-toolkit's tool-eval-experiment skill; SPEC-052's prompt-completeness-pin lesson for prose-artifact dialects.

## PR body

> Realizes north-star N3 (PHILOSOPHY §6): test design shaped per work type, before execution. test-design-standard gains the six-type dialect table (one spine, six bodies); /kit:test-plan picks the dialect from the type registry; test-plan flips from opt-in to default-suggested for normal/full. Advisory, never a block. Verify: see "How to close the loop" in ops-toolkit `_meta/megagoals/kit-north-star/goals/04-test-dialects.md`. Depends on PR-02.

## Notes

