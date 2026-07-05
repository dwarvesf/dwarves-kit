# Sub-goal 03: wave-tokens (ID-094)

**Merge policy:** auto
**Time budget:** 1-3 hours of loop work
**Proof:** run-table showing per-sub-goal TOKENS captured on the wave (parallel) path + WAVE_CAP default single-sourced. Rung 2 (a negative control: a wave sub-goal with no token line is caught).
**Design:** obvious
**Depends on:** 02 (stacked for orchestrate.sh merge hygiene, no logical dep)
Model: sonnet
**Branch:** fix/orchfin-03-wave-tokens
**PR base:** fix/orchfin-02-tier4-split

## Outcome

The wave (parallel) execution path captures per-sub-goal TOKENS exactly like the sequential path, no accounting hole when sub-goals run in a wave. The `WAVE_CAP` default is reconciled: one source of truth, consistent between `orchestrate.sh` and `commands/mega.md` (no two different defaults).

## Quality bar

Every sub-goal's token spend lands in the ledger whether it ran solo or in a wave of five. The `WAVE_CAP` a reader sees in the docs is the one the code uses.

## How to close the loop

- Trace the wave path in `orchestrate.sh` and confirm where per-sub-goal TOKENS is (or isn't) extracted vs the sequential path.
- Add the per-sub-goal TOKENS extraction to the wave path, writing to the same ledger stream.
- Reconcile the `WAVE_CAP` default (grep both `orchestrate.sh` and `mega.md`; single-source it).
- Test: run/simulate a 2-sub-goal wave; assert both token lines land; assert the WAVE_CAP default matches between code and doc.

**Done =** the wave path writes per-sub-goal TOKENS for every sub-goal in the wave (verified by a captured run-table), AND `WAVE_CAP`'s default is single-sourced (code == doc).

**Kit-adopted repo? Record the gates** (from dwarves-kit cwd, `lane-classify` → `normal`).

## Handoff on completion

1. ROADMAP `[x]` + PR #. 2. `HANDOFF.md` → 04. 3. `DECISIONS.md`. 4. Report, EXIT.

## Scope edges

**In:** the wave dispatch/collect path in `orchestrate.sh`, the `WAVE_CAP` default.
**Out:** the sequential path's token capture (already works), the ledger format.
**Not:** changing WAVE_CAP's value, adding new token metrics, reworking the ledger.

## Where to look

The wave/parallel dispatch in `lib/queue/orchestrate.sh`, the token-extraction helper, `commands/mega.md`'s WAVE_CAP mention.

## PR body

Captures per-sub-goal TOKENS on the wave path + reconciles the WAVE_CAP default (ID-094). Verify: the 2-sub-goal-wave token run-table. Stacked on #<02 PR>; review after it. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes
