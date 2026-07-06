# Sub-goal 05: sessions-digest (numeric-only sessions adapter + safety counters + `ledger digest`)

**Merge policy:** gate
**Time budget:** 2-3 hours of loop work
**Proof:** full reviewable proof: run-table over the real transcript corpus; the PRIVACY NC (load-bearing); north-star scorecard capture from `ledger digest`; coverage-delta row.
**Design:** bearing
**Depends on:** 01
Model: sonnet
**Branch:** `feat/lo-sessions-digest`
**PR base:** `feat/lo-anomaly-advisor`
**Over-test: yes** (privacy NC is the hardest requirement in the whole run)

## Outcome

The session telemetry plane exists: a `sessions` adapter over `~/.claude/projects/*/` transcript jsonl extracting NUMBERS ONLY (tokens in/out/cache-read, tool-call count, error/retry count, compaction count, canary-drop count, duration, project slug), a `safety` table from secret-guard audit counts (bypasses, blocks), and `ledger digest`: the weekly north-star scorecard (token efficiency incl. cost-per-verified-outcome via sessions x kit_gates JOIN; time-to-done; coverage) + `anomalies --propose` in one command. Token-runaway (04) arms itself against the new table.

Covers: ID-255.

## Quality bar

NO transcript CONTENT ever lands in the lens: no message text, no tool inputs/outputs, no file paths from inside conversations. Numbers, timestamps, and the project-dir slug only. The lens must stay safe to query casually.

## How to close the loop

- PRIVACY NC (load-bearing, asserted): a committed fixture transcript containing a fake secret string (e.g. `FAKE-SECRET-a1b2c3`) is adapted; test asserts that string appears NOWHERE in the materialized db (`ledger query` full-text scan) while its numeric row exists.
- Golden fixture: transcript with known counts -> exact row assertion.
- Real run: `uv run ledger rebuild` + `ledger digest --table` over the live corpus; captured scorecard = the run-table.
- Safety: fixture secret-guard log -> counts row asserted; real capture included.
- Over-test: malformed jsonl lines, truncated files, empty sessions, multi-compaction sessions; coverage-delta row.
- Kit lane + gate-ledger records before push.

**Done =** privacy NC + golden fixture asserted green AND the first real `ledger digest` scorecard captured in the proof. Gate: Han reviews the field list + scorecard before merge.

## Handoff on completion

1. Flip ROADMAP box + PR #, emit the gate banner (this PR is held for Han). 2. HOT `HANDOFF.md`: next is 06-memory-lens. 3. `DECISIONS.md`: the extracted-field whitelist (the privacy boundary) verbatim. 4. EXIT.

## Scope edges

**In:** sessions + safety adapters, digest command, tests, proof docs; `tools/ledger-observatory/`.
**Out:** memory stores (06); any transcript WRITE or cleanup.
**Not:** content extraction of any kind (titles, prompts, paths inside messages); OTel; daemons/cron.

## Where to look

`research/2026-07-04-scaling-the-harness-audit.md` §5 (planes, principles, north-star queries); `~/.claude/projects/` jsonl shape (probe a few lines for the usage fields); secret-guard status script for the count source; `schemas.py` pattern.

## PR body

Numeric-only sessions + safety planes + the `ledger digest` north-star scorecard. HELD FOR REVIEW (privacy boundary): field whitelist in DECISIONS.md, privacy NC in proof. Stacked; review after anomalies-advisor. Covers ID-255.

## Notes

