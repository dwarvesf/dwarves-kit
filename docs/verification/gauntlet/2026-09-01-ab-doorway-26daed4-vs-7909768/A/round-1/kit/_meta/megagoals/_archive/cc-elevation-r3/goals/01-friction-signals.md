# Sub-goal 01: deterministic friction signals

**Time budget:** ~3-4h · **Depends on:** none · **Branch:** feat/cc-elev-r3-01-friction · **PR base:** main

## Outcome

cc-observe gains a `friction` view (or extends an existing one) surfacing four deterministic
signals derived from the transcripts, no LLM:

1. **thrash/rework** , same file edited N+ times in a session, or Edit->Edit->Edit churn on one path; flags debugging-spiral sessions.
2. **permission-friction** , which Bash/tool commands triggered permission prompts most (candidates for an allowlist; pairs with the `fewer-permission-prompts` skill).
3. **context-pressure** , compaction events per session + (where available) context-utilization at compaction; which task types blow the window.
4. **skill-activation-precision** , skill fired but the very next action ignored its output (mis-trigger), sharper than count-0 rot.

## Quality bar

Read-only over existing transcripts, stdlib-only (cc-observe's bar), no new deps, no daemon. Each
signal degrades gracefully when its source field is absent. Sidechain-aware where it matters
(reuse the r3 SG... no: the existing `subagents` sidechain handling). Match cc-observe's table-first
output + `--json` shape; fold each into `report`.

## How to close the loop

- Implement the four signals in `tools/cc-observe/bin/cc-observe` (`collect()` + view rows).
- Extend `tests/fixtures/sample.jsonl` with: a thrice-edited file, a permission-prompt event, a compaction entry, a skill-fired-then-ignored pair. Add smoke assertions, **each with a negative control** (e.g. a once-edited file does NOT show as thrash; a skill-fired-then-used does NOT show as mis-trigger).
- Verify: `bash tools/cc-observe/tests/smoke.sh` green; run each new view on real data (`cc-observe friction --days 7`) and eyeball one real finding.
- Update the co-located proof `tools/cc-observe/docs/proof-of-done.md` (new acceptance rows + run-table + negative controls) and the README/SPEC view list.

**Done =** cc-observe surfaces the four friction signals (table + `--json` + in `report`), each proven on a seeded fixture + a negative control, smoke green, proof + README/SPEC updated; on PR #NN.

## Scope edges

**In:** the four signals, fixtures, smoke, proof, doc updates.
**Out:** acting on the findings (human); pushing them anywhere (SG-05); LLM-derived signals (SG-04).
**Not:** a daemon; a rewrite of cc-observe's existing views; any write to durable homes.

## Where to look

`tools/cc-observe/bin/cc-observe` (the `subagents` view added in #330 is the closest template), `tests/smoke.sh` + `fixtures/sample.jsonl`, `docs/proof-of-done.md`, the `fewer-permission-prompts` skill, transcript fields: `tool_use`/`tool_result`, Edit `file_path`, permission-prompt markers, `isCompactSummary`/compaction entries, Skill `input.skill`.

## PR body

Outcome: cc-observe deterministic friction signals (thrash / permission-friction / context-pressure / skill-precision).
Verify: smoke green with per-signal negative controls; real-run sample in the proof.
Roadmap: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` (sub-goal 01).

## Notes (deviation, 2026-06-15)

skill-activation-precision shipped as **inert = errored** (skill fired, tool_result is_error), ranked by inert-rate, NOT the literal "next action ignored its output" in the Outcome above. Transcripts carry no reliable marker for "output ignored", and a positional no-follow-through proxy is noisy (a skill at session end is normal). The richer proxy is logged under NOTES.md `## Proposed additions`. The other three signals match the Outcome verbatim. Permission-friction uses verified real markers (capital-P `"Permission to use "` + denial/fence strings); the lowercase substring was a false positive (skill-description text). See impl-notes `01-observability.md` 2026-06-15.
