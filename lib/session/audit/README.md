# session-audit

An LLM deep-audit over Claude Code session transcripts: renders the co-located
`prompt.md` and hands it to an agent runtime that explores the JSONL itself
(schema-first, jq aggregates, at most K deep-reads). One dated report per run;
the previous report is auto-passed back so every run opens with a metric diff
against the last. Propose-don't-dispose: it writes the report and nothing else.

The prompt's shape is the point (borrowed from forensic log-audit practice):

| Discipline | What it buys |
|---|---|
| Learn the schema first | no false negatives from guessed field names |
| Evidence tiers (HIGH/MEDIUM/LOW) | HIGH rows are re-runnable counts, verified to reproduce exactly |
| No dark buckets | any error bucket >10% must be decomposed (a generic "Exit code 1" pile is a hole, not a finding) |
| Per-hook block attribution | a hook block names its gate: different owners, different fixes |
| Owner tags (kit / user-habit / harness / instrumentation) | the report answers "who changes what" directly |
| Metric contract per recommendation | metric + current value + re-run command, so the NEXT audit verifies the fix moved it |
| {PREV} diff | audits chain into an improve-measure-improve loop |

Division of labor in `lib/session/`: `session-observe` = deterministic parsing,
`session-semantic` = cheap LLM topic signal (cron), **`session-audit` = expensive
agentic evidence for change decisions** (weekly / on demand). Measured on a
3-day window: ~$3.5 and ~10 min on Sonnet.

## Use

```bash
session-audit run                          # 7-day window, sonnet, ~/.claude/intel/audit-YYYY-MM-DD.md
session-audit run --days 3 --model opus    # heavier judgment pass
session-audit run --out ./reports --json   # machine-readable status
```

`--pricing-file` overrides the built-in per-model price table when list prices
drift.

## Test

```bash
bash tests/smoke.sh    # -> smoke: all passed
```

## Notes

- **Model floor is Sonnet.** A 3-way tier run (2026-07-14, same prompt/corpus)
  showed Haiku fails the schema-discovery step outright: it reported token
  usage, tool errors, and sidechain markers as absent from the transcripts (all
  three exist) and then recommended instrumentation for data already there. The
  discipline in the prompt does not compensate below Sonnet. Opus buys sharper
  judgment and self-corrected measurements at similar cost.
- Runtime overridable via `SESSION_AUDIT_CMD` (prompt piped to stdin; must emit
  `--output-format json`); tests inject fixtures, no live model needed.
- Degrades to `_unavailable_` on any runtime failure; never fabricates a report.
- Provenance: ops-toolkit `experiments/log-intel-prompt-v2/` (2026-07-14), where
  the prompt beat the thin clustering prompt head-to-head and its HIGH-tier
  claims reproduced exactly on independent re-run.
