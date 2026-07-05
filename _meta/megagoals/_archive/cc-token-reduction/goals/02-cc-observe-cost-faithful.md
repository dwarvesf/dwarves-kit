# Sub-goal 02: cc-observe-cost-faithful

**Merge policy:** auto (verifying already-shipped code, test-suite-gated; refine only if drift is found)
**Time budget:** 1-2 hours of loop work
**Depends on:** none
**Branch:** feat/cctoken-02-observe-faithful
**PR base:** main

## Outcome

cc-observe's subagent-attribution and cache-hit math are confirmed faithful to token-dashboard's formulas (sidechain-aware, per-task denominator; cache-hit = read / (read + create)). If any drift exists it is fixed; either way the proof-of-done records the check so ID-117 closes with confidence.

## Quality bar

ID-117 said "capture the metric deltas, do not adopt the tool." This proves the deltas were captured correctly. A reader of the proof-of-done can see the exact formula cc-observe uses and that it matches the reference, no hand-waving.

## How to close the loop

Route through the kit: `lane-classify classify "verify cc-observe cost/cache/subagent math matches token-dashboard formulas"`, run its gates.

Sub-goal-specific verification:
- `tools/cc-observe/bin/cc-observe report --json` emits a `subagents` key with per-day + per-type + per-100-prompts breakdown.
- `cc-observe cost --file <recent>` cache-hit % equals read / (read + create) on the same input (hand-check one window).
- Confirm subagent attribution is sidechain-aware with a per-task denominator (read the `subagent_*_rows` logic against `research/2026-06-15-claude-code-usage-metrics-and-tooling.md`'s token-dashboard notes). If it diverges, fix it and add a test.
- `bash tools/cc-observe/tests/smoke.sh` stays green; capture the run-table into the cc-observe proof-of-done with a new "ID-117 faithfulness" assertion row.

**Done =** `tools/cc-observe/docs/proof-of-done.md` gains an ID-117 faithfulness section whose run-table shows `cc-observe report --json` emitting the subagent breakdown and the cache-hit formula matching read/(read+create), with `tests/smoke.sh` green (and any drift fixed by a committed change + test).

## Scope edges

**In:** `tools/cc-observe/bin/cc-observe` (cost/subagents/report views + tests), its proof-of-done.
**Out:** the audit (01), cc-harvest (03), the global CLAUDE.md (04).
**Not:** do not adopt or vendor token-dashboard, do not add a web UI, do not add new metrics beyond what ID-117 named (cost-$, cache, subagent attribution).

## Where to look

`tools/cc-observe/` (the cost + subagents views, the smoke suite, the proof-of-done) and the token-dashboard formula notes in `research/2026-06-15-claude-code-usage-metrics-and-tooling.md`.

## PR body

Verifies (and closes ID-117) that cc-observe's subagent-attribution + cache-hit math are faithful to token-dashboard's formulas. Adds an "ID-117 faithfulness" section to the cc-observe proof-of-done; fixes drift if any.

Verify:
- `tools/cc-observe/bin/cc-observe report --json` has a `subagents` key (per-day + per-type + per-100)
- `cc-observe cost` cache-hit % = read/(read+create)
- `bash tools/cc-observe/tests/smoke.sh` green

Roadmap: `_meta/megagoals/cc-token-reduction/ROADMAP.md`.

## Notes
