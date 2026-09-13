# Proof of done: `burn` splits each session's tokens by model, priced

2026-09-13. Acceptance: every `burn` row reports the per-model share of its own burn, biggest first,
priced through the existing `model_cost()` rather than counted. A row whose models all have a known
price family reports dollars; a row carrying one unknown family (fable) falls back to the list-price
token weight `burn_rank` already uses and marks itself with a trailing `~`. Lane: normal. Files:
`lib/session/observe/bin/session-observe`, `lib/session/observe/tests/smoke.sh`,
`lib/session/observe/README.md`, `lib/session/observe/tests/burn-edge/f7-priced.jsonl`,
`lib/session/observe/tests/burn-edge/f8-unpriced.jsonl`.

## Why this is needed

`burn` already ranked sessions correctly, so the expensive session was easy to name. What it could not
answer is WHY that session was expensive. The `models` column was a flat set of model ids, so a lead
that dispatched thirteen subagents on Opus rendered identically to one that dispatched them on Sonnet.

Diagnosing one real day of spend meant reading transcripts by hand: grouping subagent files under their
parent, summing usage per model, and comparing tiers. That took about twenty minutes and produced one
fact, that the top session ran 11 of its 14 contexts on Opus. The column now carries that fact.

## Why the share is priced, not counted

Counting tokens per model would be the smaller change and it would be wrong. `PRICING` lists Opus at
exactly five times Sonnet on every axis (input 15 against 3, output 75 against 15, cache-read 1.5
against 0.30, cache-write 18.75 against 3.75). A session that spent equal token counts on both did not
spend equal money on both: it spent 83 percent on Opus. A count would report 50/50 and point the
reader at the wrong tier.

`model_cost()` already existed for the `cost` view and takes `[input, output, cache_read, cache_write]`.
`burn_collect` now accumulates that same tuple per model, so the new code reuses the pricing table
rather than restating it.

## Why the fallback is all-or-nothing

`PRICING` has no fable entry, and `model_cost()` returns `None` for an unknown family. A row mixing
fable with Opus therefore cannot be priced end to end. Pricing the known models and token-weighting the
unknown one inside a single row would put dollars and token counts in the same percentage, comparing
two units. So one unknown family drops the WHOLE row to the token weight, and the trailing `~` tells
the reader which unit they are looking at.

## Green run

Command: `bash lib/session/observe/tests/smoke.sh`
Exit: 0
Output: `smoke: all 61 passed`
Verdict: PASS. The suite grew by 2 assertions, F7 and F8 below. The other 59 are unchanged and still
green, which covers the existing `burn` rank order, JSON shape, dedup, ctx selection, and the
mtime-window skip.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 852 / 852`
Verdict: PASS.

Command: `bash bin/lint --all`
Exit: 0
Verdict: PASS. No hit in any file this branch touches. Every hit the lint reports is a pre-existing
citation in an unrelated `docs/specs/*.md`.

## The two fixtures pin the pricing, not the plumbing

Both fixtures give their two models **identical token counts** (100 on every axis). That is the point:
a token count cannot distinguish them, so any assertion that separates them can only be reading price.

| Test | Fixture | Models | Asserted output |
|---|---|---|---|
| F7 | `f7-priced.jsonl` | opus + sonnet | `opus 83% sonnet 17%` |
| F8 | `f8-unpriced.jsonl` | opus + fable | `opus 50% fable 50% ~` |

## Negative control

Forcing the unpriced path for every row, which is the exact defect the change exists to prevent:

```
-    priced = all(c is not None for c in costs.values())
+    priced = False
```

Result:

```
[60] burn F7: model share is PRICED, not token-counted; equal opus and sonnet tokens read 83/17, not 50/50
  FAIL: F7 share not priced
[61] burn F8: one unknown family (fable) drops the whole row to the token weight, marked with a tilde
  ok: F8 unpriced row falls back to token weight, tilde present
smoke: 60 passed, 1 FAILED
```

F7 goes red and F8 stays green. That asymmetry is the control: F8 already exercises the token-weight
path, so it SHOULD survive the break, and F7 is therefore pinned to the pricing and to nothing else.
Restoring the line returns the suite to `smoke: all 61 passed`.

## Live run on real transcripts

Command: `session observe burn --since 300`
Exit: 0
Verdict: PASS. The top row reads `opus 91% sonnet 6% fable 4% ~` against 13 subagents, which is the
finding the hand investigation produced, now available from one command. A Sonnet-led session on the
same screen reads `sonnet 66% fable 34% ~`, so the column separates the two shapes at a glance.
