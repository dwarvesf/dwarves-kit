# User guides

Task guides for people who use the kit on their repos. Each one answers "what do I do and what will I see", nothing else. The contracts live in `docs/WORKFLOW.md`, the rationale in `docs/PHILOSOPHY.md`, and the per-command reference in `docs/MANUAL.md`. A guide translates those; it never overrides them.

## Start here

| Guide | Read it when |
|---|---|
| [adopt.md](adopt.md) | you installed the kit and want a repo to use it |
| [spine.md](spine.md) | you want the map: what comes after what, and how a change is sized into a lane |

## Do the work

| Guide | Read it when |
|---|---|
| [grill.md](grill.md) | the kit starts interviewing you before working |
| [debug.md](debug.md) | you said "fix this bug" and it went hunting for a root cause instead |
| [review.md](review.md) | a branch is done and you want it reviewed before it ships |
| [autonomy.md](autonomy.md) | you want the kit to check in more, or less |
| [wrap.md](wrap.md) | you are done for now and want the work landed and tidied |

## The checks

| Guide | Read it when |
|---|---|
| [gates-and-proof.md](gates-and-proof.md) | something BLOCKED (ship gate, proof of done) and you want the way through |
| [v-model.md](v-model.md) | all tasks passed but acceptance still failed, or you wonder why the kit tests at every level |
| [scenarios.md](scenarios.md) | the kit surfaces "survival scenarios" and "must-NOT-happen" rows while you shape work |
| [gauntlet.md](gauntlet.md) | an artifact (docs, a runbook, a spec) must survive a cold reader unaided |

## Several pieces

| Guide | Read it when |
|---|---|
| [mega-goal.md](mega-goal.md) | your ask is one destination reached through several pieces, or several disjoint specs that should run side by side |

## Reference

| Guide | Read it when |
|---|---|
| [loops.md](loops.md) | a command reported a round cap, an honest halt, or SOLID / REVISE / RECONSIDER |

## Page shape

Every guide uses one shape, so you can find the same answer in the same place:

1. **Use this when**: the situation, in your words.
2. **What happens**: what the kit does without being asked.
3. **What you do**: numbered steps, and every command shown exists.
4. **What you will see**: real output, copied from a run or from the command source.
5. **When it breaks**: a table of symptom and fix.
6. **Related**: two to four links.

A guide carries a figure only where the mechanism needs one. The figures are rendered from one model, `docs/figures/MODEL.md`, into `docs/figures/<id>.png`. A guide with no mechanism to draw has no figure.

New guide: name the file after the topic, follow the shape, and add a row in the right group above.
