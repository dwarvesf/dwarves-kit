# Sub-goal 02: session-shape signals

**Time budget:** ~3h · **Depends on:** 01 (same file) · **Branch:** feat/cc-elev-r3-02-session-shape · **PR base:** feat/cc-elev-r3-01-friction

## Outcome

cc-observe gains a `sessions` view surfacing three deterministic shape signals per session/day:

1. **session archetype** , classify each session as quick / standard / deep / marathon / automation from duration + turn count + tool mix (AgentsView uses the same taxonomy; reuse the thresholds, do not reinvent).
2. **circadian** , spawns/turns/rework bucketed by hour-of-day, so the low-rework, high-merge windows are visible vs late-night thrash.
3. **interruption rate** , `[Request interrupted]` markers per session, where I go off-track or get too verbose.

## Quality bar

Same as 01 (read-only, stdlib, `--json`, in `report`, graceful on missing fields). Archetype
thresholds are explicit + documented (not magic numbers buried in code). Timezone: use the
transcript timestamps as-is (UTC); note it, do not silently localize.

## How to close the loop

- Implement in `tools/cc-observe/bin/cc-observe` on top of 01's branch.
- Fixtures: a short session + a marathon session + an interrupted turn; smoke asserts the archetype split + an interruption count, each with a negative control (a normal turn is not counted as an interruption).
- Verify: smoke green; `cc-observe sessions --days 14` on real data shows a believable archetype distribution + an hour-of-day table.
- Update proof + README/SPEC view list.

**Done =** cc-observe surfaces archetype + circadian + interruption-rate (table + `--json` + in `report`), proven on fixtures + negative controls, smoke green, docs/proof updated; on PR #NN, based on 01's branch.

## Scope edges

**In:** the three signals, fixtures, smoke, proof, docs.
**Out:** acting on them (human); delivery (SG-05); cost/model (SG-03); LLM signals (SG-04).
**Not:** localizing timestamps; a daemon; durable-home writes.

## Where to look

01's branch + `tools/cc-observe/bin/cc-observe`, AgentsView archetype taxonomy (`tools/agentsview-deploy/` README references `agentsview stats`), transcript `timestamp`, turn counting (the prompt-turn heuristic added in #330), interruption markers in user entries.

## PR body

Outcome: cc-observe session-shape signals (archetype / circadian / interruption-rate).
Verify: smoke green with negative controls; real-run archetype distribution in the proof.
Roadmap: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` (sub-goal 02). Stacked on 01.
