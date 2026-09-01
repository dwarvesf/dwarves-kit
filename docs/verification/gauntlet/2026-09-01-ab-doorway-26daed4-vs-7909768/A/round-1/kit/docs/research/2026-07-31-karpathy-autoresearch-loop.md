---
title: Karpathy's autoresearch loop, verified source, classification against loop-engineering, adoption verdict
date: 2026-07-31
source: web research (WebSearch/WebFetch) dispatched to a general-purpose agent; cross-checked against docs/PHILOSOPHY.md "AutoResearch optimization" and skills/loop-engineering/SKILL.md
feeds: docs/PHILOSOPHY.md "AutoResearch optimization" correction; any future prompt/hook auto-tuning work
benchmarked_against: skills/loop-engineering/SKILL.md Step 1 gate + Step 2 shapes, docs/patterns/audit-loop.md, docs/research/2026-07-30-loop-engine-prior-art.md
status: active
---

# Karpathy's autoresearch loop

## Why this note exists

`docs/PHILOSOPHY.md` cited "the Karpathy loop" as the source for AutoResearch optimization,
described as a three-file contract with LLM-as-judge scoring. Before trusting that citation, we
checked the primary source. It does not match the kit's description.

## The real source

[github.com/karpathy/autoresearch](https://github.com/karpathy/autoresearch). Not a tweet, not
a talk, a repository. Quoting `program.md`: "Tune train.py with an experimental idea by directly
hacking the code. git commit. Run the experiment... If val_bpb improved (lower), you 'advance'
the branch, keeping the git commit. If val_bpb is equal or worse, you git reset back to where
you started." And: "LOOP FOREVER... do NOT pause to ask the human if you should continue... The
loop runs until the human interrupts you, period."

Verified mechanics: one candidate per iteration, serial, a numeric metric (`val_bpb`, a training
loss) decides accept or discard, a fixed wall-clock budget per experiment (about 5 minutes, so
around 12 an hour, around 100 overnight), no LLM-as-judge anywhere in the source.

## What the kit's citation got wrong

`docs/PHILOSOPHY.md` described "the Karpathy loop" as already including a three-file contract
(program.md / skill.md / eval.py) with LLM-as-judge scoring. That extension is the kit's own
invention, applied to a domain (prompt quality) that has no cheap numeric metric the way
training loss does. The citation has been corrected in place to say so.

## Classification against loop-engineering

Two shapes already exist in this kit: the bounded-revise engine (converge on one artifact via
critique) and the audit-loop pattern (`docs/patterns/audit-loop.md`, enumerate an existing set,
verdict each item, apply, gate). Karpathy's loop matches neither. It generates or mutates
variants and hill-climbs a single lineage against a score, discarding losers outright. This is a
third shape: search-and-select, not audit, not critique-revise.

| | Karpathy's autoresearch | Bounded-revise engine | Audit-loop pattern |
|---|---|---|---|
| Unit of work | One mutated candidate per round | One artifact, revised in place | A discrete item set, enumerated up front |
| Decision | Accept if metric improves, else discard | Merge findings, revise, re-check | Verdict per item (OK/FIX/REMOVE/UNSURE/DANGER) |
| Bounded? | No, loops forever | Yes, hard cap of 3 | Yes, one pass per cadence |
| Signal on rejection | None, fully discarded | Findings carry into the next round | N/A, each item stands alone |

It also fails `skills/loop-engineering/SKILL.md` Step 1's first gate outright: bounded-in-session
only. Karpathy's loop is explicitly unbounded, and the kit's own "Loop boundaries" section
already declines that shape, regardless of source.

## Adoption verdict

Do not adopt the mechanic as written. It fails the kit's own gate, and it depends on a cheap
numeric metric that prompt or hook quality does not have.

The underlying need, auto-tuning command prompts and hook patterns once enough data exists, is
real and already queued in `_meta/BACKLOG.md` and in this same `docs/PHILOSOPHY.md` section. Its
own stated bar: manual iteration has plateaued, and 10+ (30+ for task-verifier) real transcripts
exist to evaluate against. As of 2026-07-31, `docs/runs/` holds zero transcripts. The bar is not
met.

When it is met, adopt the need, not the mechanic: bound the round count, score with an
LLM-as-judge instead of a numeric metric, and add an honest-halt reporting path instead of a
silent discard. That is a bounded search-and-select loop, a genuine third shape worth naming in
`skills/loop-engineering/SKILL.md` once it is actually built, not before.
