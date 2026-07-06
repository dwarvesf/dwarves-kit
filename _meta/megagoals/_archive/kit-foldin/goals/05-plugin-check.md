# Sub-goal 05: plugin-check

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table , the tool runs against a committed fixture plugin dir and prints a correct freshness verdict, PLUS a stale-plugin NC (a fixture plugin with an old marker is flagged stale). Rung 2 (named NC; small generic CLI, no mutation surface).
**Design:** obvious (a straight port of a 268-LOC generic freshness-check CLI, no new logic)
**Depends on:** none (self-contained `tools/` subtree)
Model: sonnet
**Branch:** feat/kit-foldin-05-plugin-check
**PR base:** master

## Outcome

The plugin freshness checker (was cc-plugin-check, 268 LOC) lives at `dwarves-kit/tools/plugin-check/` , function-named, agent-generic. It checks a plugin dir for staleness (whatever "stale" meant in the source tool) and reports, cron- or ad-hoc-invoked, no LLM judgment. Any personal path becomes opt-in.

## Quality bar

A small, boring, correct CLI. It does exactly what the source tool did, now from the kit with no ops-toolkit assumption. A consumer points it at their plugin dir and gets the same verdict the source gave.

## How to close the loop

- Move `ops-toolkit/tools/cc-plugin-check/` to `dwarves-kit/tools/plugin-check/` (drop `cc-`).
- Replace any hardcoded plugin-dir path with an arg/env default (opt-in; the kit does not assume ops-toolkit layout).
- Commit a tiny fixture plugin dir under `tests/fixtures/` (fresh + stale variants).
- Run-table: run against the fresh fixture (verdict: fresh), run against the stale fixture (verdict: stale).

Kit-adopted: record build + review via `bash lib/gate-ledger.sh`; `lane-classify` likely `small`.

**Done =** the tool prints the correct verdict for both fixture variants (fresh + stale), captured in `docs/proof/kit-foldin-plugin-check.md`; no hardcoded ops path remains.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-07 retires `ops-toolkit/tools/cc-plugin-check`.
3. DECISIONS.md: only if a non-obvious default choice was made.
4. Report in records, EXIT.

## Scope edges

**In:** `dwarves-kit/tools/plugin-check/`, its fixture + test.
**Out:** everything else; the ops retire (SG-07).
**Not:** extending what "stale" means; adding a daemon/schedule (it stays ad-hoc/cron-invoked, the schedule is the consumer's); renaming its verdict output format.

## Where to look

`ops-toolkit/tools/cc-plugin-check/`, `dwarves-kit/tools/` (the one-subtree-per-tool shape).

## PR body

Move cc-plugin-check to `tools/plugin-check` (drop `cc-`); path becomes opt-in.

Verify: run-table over fresh + stale fixture plugin dirs. Proof: `docs/proof/kit-foldin-plugin-check.md`.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
