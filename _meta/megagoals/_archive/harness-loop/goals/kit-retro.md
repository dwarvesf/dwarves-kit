# kit-retro (recurring goal TEMPLATE)

> The weekly Learn-leg ritual. This file is a TEMPLATE. The consumer's weekly LaunchAgent
> (SG-10) instantiates it as `kit-retro-YYYY-WW` (the date-suffix IS the recurrence; zero
> queue-engine changes, PHILOSOPHY §3). ADR-0034 decision 2/6: this proper-noun name is the
> one recorded exception to the `retro`=per-run vocabulary; the ritual reads per-run retros
> and ENDS in a `propose`. Moved here from ops-toolkit kit-wiring ID-273.

**Merge policy:** auto
**Time budget:** minutes (one `learn propose` run + a state-line bump)
**Design:** obvious
**Depends on:** SPEC-195 shipped (`bin/learn propose`); the stats lenses it reads live.
Model: sonnet

**State:** last retro: never   <!-- the runner bumps this to the run date on RUNNER_DONE -->

## Outcome

Close the harness feedback loop across MANY runs (a layer up from `/kit:retro`, which reads
ONE run). Each weekly instance runs the three-stage distiller and stages cited backlog
candidates a human triages. It NEVER edits the kit, CLAUDE.md, or skills, and NEVER promotes:
`board promote` stays the human gate.

1. READ. The window is bounded by the `last retro` state line above (days since it, floor 7,
   default 30 on `never`). `bin/learn propose` internally aggregates the stats lenses over
   that window (gate-yield, anomalies, deviation/review/defect lenses) plus the surfaced
   starvation counters (`learn debt`, learned-ledger queue) and the `memory-sweep`
   staleness/dead-path tripwire.
2. DISTILL + STAGE. Run the distiller:
   `bin/learn propose --days <N>` (N from step 1).
   It interprets the aggregate into hypotheses, each grounded in ONE cited signal; drops the
   ungrounded and the adversarially-refuted; dedups HARD against open + staged + `[expired]` +
   `[rejected]` rows; and appends survivors to `_meta/backlog-staging.md` as `## [staged]`
   blocks whose `- Source:` line cites lens + figure + rids. Its two LLM passes emit `TOKENS`
   markers, so the weekly spend is observable in `stats`.
3. BUMP. Update the `last retro` state line to today's date and commit the close-out (the
   staging file is gitignored; the state bump + this run's note are the tracked artifact).

## Quality bar

- Honest-empty: an empty window stages 0 and prints a "0 candidates" line, never a fabricated
  insight; the staging file is left untouched.
- Cite-the-number: every staged candidate names its lens + figure + rids (rebuilt from the
  aggregate, never from the model).
- Idempotent: re-running the same week stages nothing already staged, promoted, expired, or
  rejected.
- Propose-only: the ONLY write is the gitignored staging file + this goal's `last retro` bump.

## How to close the loop (per weekly instance)

1. Compute N from the `last retro` line; run `bin/learn propose --days <N>`.
2. Read back the staged diff; confirm each new block cites evidence (honest-empty if none).
3. Bump the `last retro` state line; commit the close-out.
4. On full success (close-out committed) emit the runner success marker as the final line,
   alone; on a pause (nothing to commit, or a blocker) emit the runner gated marker with a
   one-line reason instead. (Markers: `RUNNER_DONE` / `RUNNER_GATED: <reason>` -- line-anchored,
   so they appear ONLY as that final standalone line, never inside this prose.)

**Done =** `learn propose` ran for the window, survivors (>=0) staged with cited Sources, the
`last retro` line bumped, close-out committed.

## Scope edges

**In:** one `learn propose` run over the since-last-retro window, the staged appends it
produces, the `last retro` bump.
**Out:** promoting candidates (`board promote`, the human gate); any kit/skill/CLAUDE.md edit;
memory repair (ID-100 owns it); the LaunchAgent plist (SG-10 owns the scheduler).
**Not:** a daemon, a cron, auto-opened PRs against the kit, auto-promotion in any form.
