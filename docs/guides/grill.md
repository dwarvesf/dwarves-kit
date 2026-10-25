# The grill

Use this when the kit interviews you before it works, or when it does not and you want to know why.

## What happens

- The kit checks whether the task is on unfamiliar ground. Three signals decide: the target paths have no recent commits (none, or the newest is over 90 days old), the task names a domain that appears nowhere in the code, the glossary or the specs, or you said you are new to it.
- If two signals fire, or you said you are new, the interview runs. Otherwise the kit skips it and writes the reason to the ledger. A signal the kit cannot check counts as fired.
- The interview asks one question at a time. Each question comes with a recommended answer and one line of reasoning, so you correct instead of writing from scratch.
- Each answer is saved where it belongs the moment it resolves: a glossary term in `CONTEXT.md`, a quality requirement in a quality notes file that the kit creates on first use (docs/QUALITY.md), a hard-to-reverse decision as a short decision record, and the full Q&A digest in the goal draft.
- The interview ends with a proposed `Done =` line plus two or three "must NOT happen" scenarios. The tiny lane never gets an interview.

## What you do

1. **Correct the recommendation.** "Yes" is a fine answer. "No, because X" is better, and X is the useful part.
2. **Expect the contradiction question first.** If your ask conflicts with a spec, a decision record or a standing policy, that comes before anything else. It is the costliest thing to get wrong, so take it seriously before you override it.
3. **Expect the order to follow blast radius.** After contradictions come questions that would change the architecture. Then come assumptions the kit states as defaults ("unless you say otherwise I will assume X"), so silence is still a recorded decision.
4. **React to mocks for taste calls.** Taste questions are not asked. The kit offers a quick mock with two or three directions for you to react to.
5. **Pick rows from the blindspot table.** On a new domain, the kit first shows 5 to 8 things you may not know to ask, each with the question that surfaces it. You choose which rows to drill.
6. **Wave it off only on purpose.** You can skip the interview. The skip is logged as your call. On genuinely new ground, you trade five questions now for rework later.
7. **Say it once if you still want your way.** After a contradiction, one sentence is enough. The override is recorded and the work goes on. The grill informs; it does not veto.
8. **Do not repeat yourself.** Answers land in durable records, not in chat. A question you answered last month should not come back. If it does, report it.

## What you will see

When the interview runs, the kit records how many questions it asked and how many contradictions it found. When the kit skips, the ledger line names one of three reasons. This is a real skip line:

```
2026-10-25T16:15:25Z | GATE | grill | skipped | reason=home-turf: recent commits on the target
```

| Reason | Meaning |
|---|---|
| `home-turf` | No signal fired. Code and domain are both familiar. |
| `density-low` | One signal fired. That is not enough to justify an interview. |
| `operator-wave` | You waved off an interview the signals would have run. |

A skip with no reason is refused by the ledger:

```
record: a grill skip needs reason=<home-turf|density-low|operator-wave> (bare, or followed by ':') as its reason (got: 'no reason')
```

Answers land in these places the moment they resolve:

| What you settled | Where it is written |
|---|---|
| A term or concept | The glossary, `CONTEXT.md` |
| A quality requirement (latency, cost, security) | The quality notes file, docs/QUALITY.md (created on first use) |
| A decision that is hard to reverse, surprising without context, and a real trade-off | A short decision record. A decision that fails any one test goes in the goal draft instead. |
| Every question, answer and contradiction | The `Context` section of the goal draft |

The questions come from a bank shaped to the type of work. The kit picks the three to six that the repo does not already answer. One sample from each bank:

| Type of work | A question it asks |
|---|---|
| incident | What changed in the window before it fired? |
| reconcile | What is the authoritative source, and what is suspected of drifting from it? |
| operate | What pre-checks make this run safe today? |
| planning | What was planned last cycle but did not happen, and why? |
| learning | What does "understood" mean for this unit? |
| eval | What decision will the numbers drive? |
| research | What question, phrased so it can be proved wrong, is this answering? |
| review | What exact artifact is under review? Pin the SHA. |
| doc | Who reads this, and what do they do right after? |
| migration | What is the rollback path, and has anyone rehearsed it? |
| data-tool | Where do credentials live, and what is the blast radius of the token? |
| spec-feature | What must NOT change? |

## When it breaks

| You see | Do this |
|---|---|
| The kit did not interview you | The ground was familiar. Read the skip reason in the ledger. Ask for an interview if you disagree. |
| It asks a question the repo already answers | Say so. A fact the code can answer should never be a question. |
| It asks many questions in one block | You are running under `bypassPermissions`. The one-at-a-time rhythm becomes one batched questionnaire with recommended answers pre-selected. |
| The ask conflicts with a decision record | Answer the contradiction first. Confirm the override or change the ask. |
| An unattended run answered for you | The board row carried an `#auto` marker that you wrote. Each answer is on the debt ledger with its reasoning. Review them at paydown. |
| The answers changed the type or weight of the work | The kit re-classifies the task and says so. The lane can only go up. |

## Related

- [spine.md](spine.md): where the grill sits between classification and the `Done =` line, and which lane skips it.
- [scenarios.md](scenarios.md): how the must-NOT-happen rows are produced and used.
- [autonomy.md](autonomy.md): how often the kit asks you anything.
