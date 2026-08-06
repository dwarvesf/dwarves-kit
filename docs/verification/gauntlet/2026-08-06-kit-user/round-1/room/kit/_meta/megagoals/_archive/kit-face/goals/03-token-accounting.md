# Sub-goal 03: token accounting + efficiency metrics

**Merge policy:** auto
**Time budget:** 4-6 hours (the widest build).
**Proof:** run-table: a real captured run writes a TOKENS ledger line (in/out/cache_read/cache_create[/cost]) · `lane-telemetry report` shows the token section (tokens-to-done median per lane, rework share at run granularity, cache efficiency) · NEGATIVE CONTROL: a non-captured run reports `usage=?`, never fake zeros · `render` mermaid mode emits per-lane annotation · the sidechain-usage probe result recorded (one probe run, informs whether per-round rework is ever possible).
**Depends on:** none.
Model: opus
Effort: high
**Branch:** feat/kit-face-03-tokens
**PR base:** master

## Outcome

Token cost becomes ledger DATA. New `gate-ledger.sh tokens <rid> in= out= cache_read= cache_create= [cost=]` subcommand (single-writer, sanitized, additive marker , `check()`/`_rows` ignore it by design, verified). Orchestrate extracts usage from stream-json on the CAPTURE-GATED paths only (`--stream` / `DETERMINISTIC_HANDOFF`; the parser extends `lib/handoff/handoff_gen.py`; schema vocabulary from the v2 SG-09 12-col ledger). `lane-telemetry report` grows the token section; `render` gains a mermaid output mode annotated per lane/per run (NOT per-phase , usage is per-session). Thresholds: NONE pinned; a 5-run baseline note instead (SPEC-073 pattern).

## Quality bar

SPEC-087's "default invocation byte-identical" pin is SACRED , the default `claude -p` path changes zero bytes. Honest nulls everywhere (`usage=?` mirrors the lane-`?` convention). The additive-marker convention sentence is shared verbatim with 05 (one convention, two users). `test-meta.sh` greps exact case-statement literals in lane-telemetry , keep formatting intact.

## How to close the loop

`/spec` + `/spec-validate` first. Then `bash tests/test-lane-telemetry.sh` (extended: token section + `usage=?` NC + render annotation) + one real captured orchestrate run whose ledger carries the TOKENS line + the sidechain probe. Assumptions: ROADMAP 03 block (watchdog path = declared gap; manual runs -> `usage=?` + pointer to ops-toolkit token tooling).

**Done =** tests green incl. the `usage=?` negative control, a real run's TOKENS line in the durable ledger, report + annotated render committed as captures, probe result recorded.

## Scope edges

**In:** gate-ledger tokens subcommand, orchestrate capture-path extraction, handoff_gen.py extension, lane-telemetry report/render, tests, the probe.
**Out:** flipping the default path to json (SPEC-087 pin); watchdog-path capture (declared gap); transcript-joins for manual runs; threshold pinning.
**Not:** per-phase token attribution (impossible at this granularity , say so, don't fake it); a cost dashboard beyond the render annotation; pricing tables.

## Where to look

lib/orchestrate.sh:312-333 (watchdog) + :418-439 (invocation paths, the SG-01 pin comment), lib/handoff/handoff_gen.py, lib/gate-ledger.sh:133 (record's verb gate), lib/route-suggest.sh (SG-09 schema), tests/fixtures/handoff-det/seed.jsonl (usage shape), tests/fixtures/routing/thin-ledger.tsv.

## PR body

Token accounting: TOKENS ledger subcommand + capture-gated usage extraction + lane-telemetry token section (tokens-to-done/lane, rework share, cache efficiency) + per-lane annotated mermaid render; `usage=?` honest nulls; SPEC-087 default-path pin untouched; thresholds deferred to a 5-run baseline. Verify: `bash tests/test-lane-telemetry.sh` + the captured-run proof. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>
