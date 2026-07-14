# learn

The **Learn leg's** home (ADR-0034 decision 1: Specify / Execute / Observe / Govern / Learn).
The read-and-propose side of the loop. It reads what the harness recorded about itself, distills
it, and proposes work. It never does the work, and it never files it.

The whole module obeys one rule, **propose, do not dispose**: its only legal sink is the staging
buffer (`_meta/backlog-staging.md`). A human promotes with `board promote`. Nothing here writes a
board, rewrites a ledger, or edits a skill / CLAUDE.md.

```
   gate ledger telemetry ──┐
   stats lenses           ─┼──> learn propose ──┐
   a RETRO doc            ─┘                    │
                                                ├──> _meta/backlog-staging.md ──> board promote
   session transcripts ───> session audit/intel ┤          (the human gate)
   stats anomalies ───────> anomalies --propose ┘
                                                │
                              learn drain <─────┘   (review + expire)
```

## The callables

Entry point is `bin/learn <verb>` (stable; SPEC-184). Three verbs, all live.

| Verb | Script | What it does |
|---|---|---|
| `learn propose` | `propose.py` | The cross-run distiller (SPEC-195). A retro one layer up from `/kit:retro`: that reads one run, this reads many runs of ledger telemetry and proposes backlog rows. |
| `learn propose --retro FILE` | `propose.py` | Stages a RETRO doc's `## Action items`. Deterministic: no model call, the retro *is* the evidence. |
| `learn drain` | `drain.py` | The staging review (SPEC-196). Renders what is staged, grouped by Home. Expires anything past the window. |
| `learn debt <list\|collect\|mark-paid>` | `weekend-batch.sh` | The debt paydown (SPEC-126, ADR-0031). Reads `\| DEBT \|` markers off the gate ledger, surfaces the week's waved + deferred items, closes one with `mark-paid`. |

### `learn propose`, the three stages

1. **Aggregate** (deterministic, no model). Runs the `stats` lenses over a window and builds a
   signal table: `{id, lens, figure, rids, detail}`. Each lens fails independently, so a broken
   lens contributes zero signals instead of aborting the run. Honest-empty holds.
2. **Interpret** (one `claude -p sonnet` pass). Signals in, hypotheses out. Each hypothesis must
   cite exactly one signal id.
3. **Check and write.** Deterministic grounding (the cited signal must exist and carry a real
   figure), anchored dedup, then an adversarial refute pass (fail-closed), then the staged write.

Two disciplines are worth naming because they are what make the output trustworthy. The
**citation is rebuilt** from the deterministic aggregate, never taken from the model, so a model
cannot inject a fabricated figure. And **dedup is anchored and hard**: a proposal that was already
rejected or expired never reappears.

### `staging-format.py`, the one grammar

This is the point of the module. A staging file is a sequence of `## [<state>] <title>` blocks
followed by `- Field: value` lines. `staging-format.py` is the single definition of that grammar,
both directions:

| Function | Side | Used by |
|---|---|---|
| `parse_blocks(text)` | read | `drain`, and every dedup caller |
| `render_block(candidate)` | write | every proposer that has converged (below) |
| `existing_keys(*sources)` | dedup | `propose`, `session-audit`, `session-intel` |
| `norm(title)` | dedup key | all of the above |

`render_block` carries the guard that makes the grammar safe to feed with model-authored text:
it collapses **all** whitespace in every field. A block is a line-oriented grammar, so an embedded
newline in an `Intent` value forges a *second* `## [staged]` block that the parser reads as a real,
human-approved proposal. Since proposers now render LLM-extracted transcript text, that field
content is attacker-influenceable, and sanitising in the one shared renderer is the only place the
fix stays fixed.

The file is deliberately hyphenated, so it is not directly importable. Callers load it by path with
`importlib.util.spec_from_file_location`.

## The convergence is real, but it is not complete

The kit's stated contract (ADR-0034 decision 1, SPEC-200 I1, contract rule **C5**) is that every
proposer renders through this one module. As of 2026-07-15 that is true of four writers and false
of two:

| Proposer | Renders via | Status |
|---|---|---|
| `learn propose` (`propose.py`) | imports `staging-format.py` | converged |
| `learn propose --retro` (`propose.py`) | imports `staging-format.py` | converged |
| `session audit` (`lib/session/audit/bin/session-audit`) | imports `staging-format.py` | converged |
| `session intel` (`lib/session/intel/bin/session-intel`) | imports `staging-format.py` | converged |
| `stats anomalies --propose` (`lib/stats/src/stats/anomalies.py`) | its **own** `render_block()` | **copy** |
| session-end stager (`hooks/backlog-stage.py`) | its **own** `render_candidate()` | **copy** |

The two copies are not harmless duplication. They have already drifted: both predate
`render_block`'s whitespace-collapse guard and neither has it. `hooks/backlog-stage.py` uses a bare
`.strip()`, which removes only leading and trailing whitespace, so an embedded newline in a
model-extracted field survives into the staging file and forges a second block. That hook is fed
LLM-extracted transcript text, which is exactly the input the guard exists for. Detail, with a
reproduction, is in `docs/proof-of-done.md`.

C5 does not catch this, because it greps for a code reference to `render_block` / `render_candidate`
and a file that *defines* a function with that name matches its own grep. C5's negative control
plants the comment-mention evasion, not the define-your-own-copy evasion, so this shape was never
tested. Fixing it is a behavior change in two other modules and needs its own spec; it is recorded
here rather than left invisible.

`lib/board/bin/add-backlog` also keeps a private `parse_staging()` reader. That one is a known and
accepted duplicate (`staging-format.py`'s own docstring says so): it is the promoter, the single
human-gated edge into the board, and C5 exempts it by name.

## Specs and decisions

| Where | What |
|---|---|
| `docs/decisions/0034-harness-loop-taxonomy.md` | The five legs, `lib/learn/` as the Learn leg's one home, the three-verb grammar |
| `docs/decisions/0031-understanding-gate.md` | Understanding debt, and why waving is a first-class recorded choice |
| `docs/specs/SPEC-195-learn-propose.md` | The cross-run distiller |
| `docs/specs/SPEC-196-staging-drain.md` | The staging review + expiry |
| `docs/specs/SPEC-126-weekend-batch.md` | Debt collection and paydown |

This module has no module-local `SPEC.md`; its specs are the numbered ones at the repo root. That
is why `lib/learn/SPEC` is still an open IOU in `tests/kit-contract-known-gaps.txt`.

## Tests

```bash
bash tests/test-learn-propose.sh   # 41, grounding, dedup, fail-closed refute, --retro, sanitization
bash tests/test-learn-drain.sh     # 23, render, promote-numbering parity, expiry, move-not-delete
```

## The three things a newcomer gets wrong

**1. `drain` groups for display but numbers in file order.** The index it prints is the index
`board promote <n>` reads. It is assigned over the staged subset in *file* order, then the rows are
grouped by Home and sorted oldest-first for the human. So the numbers look shuffled on screen, and
that is correct. Re-numbering them to match the display would silently promote the wrong row.

**2. Expiry is a relabel, never a delete.** A stale candidate goes `## [staged]` to `## [expired]`,
header token only, everything else byte-identical. Nothing is ever removed, because `add-backlog`
already lists only `staged` blocks, so an expired row is unselectable without any change to the
promoter. If you find yourself deleting from the staging file, stop.

**3. Fail-closed means silence gets dropped.** The adversarial pass in `propose` treats an empty,
garbled, or errored verdict as REFUTED. A crashed interpreter degrades to zero candidates and
exit 0. The module never blocks anything and never guesses, so "it proposed nothing" is a normal,
correct outcome and not a bug to go fix.

One more. The expiry window is a plain constant with a `--days` override, deliberately **not** a
`kit.toml` key (an ADR-0034 pin). Do not "improve" it into config.
