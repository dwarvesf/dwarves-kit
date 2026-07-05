# Sub-goal 05: dogfood

**Time budget:** 2-4 hours of loop work, after PR-03 and PR-04 merge
**Depends on:** 02, 03, 04
**Branch:** `feat/north-star-05-dogfood` (dwarves-kit)

## Outcome

One REAL non-code task travels the entire new path, proving the destination exists:

1. Enqueue a real research task on the kit BACKLOG as `queued`. Suggested task (genuinely useful, feeds the next phase): "research: survey prior art for pull-based agent kanban + dynamic persona dispatch (OpenClaw Workboard, GSD v2 runtime, claude-code agent registries), cited report into docs/research/". A different real task is fine if it classifies as a non-code type; do not invent a toy.
2. Pull it with `/kit:assign --next` (or the lib equivalent from a non-kit cwd): the claim lands in goal-registry, the row flips `queued -> claimed`.
3. Its type-loop (research, per the 02 registry) runs: frame -> sweep -> verify claims -> cited report, executed by the agent mode the registry names.
4. Its test dialect (claim-verification matrix, per 04) is designed BEFORE the sweep and the verification runs are recorded per the verification framework (test-design + runs/, proof gate-visible).
5. The row walks `in-progress -> in-review -> done` on the board; the report + proof land in the PR.

Friction found anywhere in the chain goes to this mega-goal's `FEEDBACK.md` (skill-meta) and, when it is a kit defect, into NOTES.md Proposed additions.

## Quality bar

This is the acceptance test of the whole mega-goal: if any hop needs hand-holding that the docs do not describe, that is a finding, not a workaround to keep quiet. The report itself must be genuinely useful for the next phase (autonomous pull + persona dispatch), not a ceremony artifact.

## How to close the loop

```sh
cd ~/workspace/tieubao/dwarves-kit
bash lib/backlog.sh board | grep -A3 done                  # the dogfood item shows done
git log --oneline -5 -- _meta/BACKLOG.md                   # the status transitions are in history
ls docs/verification/ | grep -i kanban                      # the dogfood task's test-design + runs exist
grep -c 'claim' docs/research/*kanban*md                    # the report's claims are matrix-verified
bash tests/test-meta.sh && bash tests/test-hooks.sh         # nothing regressed
```

**Done =** the board shows the real task at `done` with its transitions in git history, the cited report exists with its claim-verification matrix + recorded runs (gate-visible), zero undocumented hand-holds were needed (or each one is filed in FEEDBACK.md/NOTES.md), suites green, PR open + CI green.

## Scope edges

**In:** one BACKLOG row lifecycle, the research report, its test-design + runs, FEEDBACK/NOTES entries, the PR.
**Out:** fixing 02/03/04 defects beyond one-line fix-up commits (bigger defects: file + mark blocked).
**Not:** building the autonomous-pull daemon or the persona engine the report surveys (that is the NEXT mega-goal's material); a second dogfood task.

## Where to look

Everything 02-04 shipped (registry, board lib, dialect table); ops-toolkit research/ frontmatter conventions if the report routes there instead (subject-of-doc rule decides: kit-machinery survey belongs in the kit's docs/research/).

## PR body

> Mega-goal acceptance: a real research task ran end-to-end through the new machinery (queued -> pulled via --next -> research type-loop -> claim-verification dialect -> proof recorded -> done on the board). Deliverable: the prior-art survey for pull-based agent kanban + persona dispatch, claim-matrix verified. Friction filed in the mega-goal's FEEDBACK.md. Verify: see "How to close the loop" in ops-toolkit `_meta/megagoals/kit-north-star/goals/05-dogfood.md`. Depends on PR-02/03/04.

## Notes

