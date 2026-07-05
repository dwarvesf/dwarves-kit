# Sub-goal 05: tool-tax

**Merge policy:** auto
**Time budget:** 2-3 hours of loop work
**Proof:** run-table (cooldown check: two consecutive invocations, second skips with log line) + the captured notion error text (or fix evidence) + the codified rule line
**Depends on:** none
Effort: low
**Branch:** fix/cc-hyg-05-tool-tax (repo: tieubao/ops-toolkit)
**PR base:** main

## Outcome

Two per-call taxes are killed (closes ID-152 + ID-243):

1. **cc-harvest throttle**: fires at most once per hour (timestamp/lockfile in the staging dir, skip-with-log inside the window), independent of how many sessions close. Then verify the header's "adds no new cost" claim: does each `claude -p --model haiku` count against Max-plan quota? Measure or reason from the usage data; correct the header if wrong.
2. **notion-query-data-sources verdict** (94% error, 15/16 calls): reproduce ONE failing call and read the actual error. Likely outcome per the ntn-first rule: codify "never reach for this tool; use the ntn CLI or notion-query-database-view" as a rule line (repo memory or CLAUDE.md Tool selection), and note whether to drop it from the loadout. A usage fix is equally acceptable if the error says so. Resolve at execution: if the claude.ai Notion MCP is absent in the loop session, derive the verdict from the transcript errors and ship the rule line.

## Quality bar

Ponytail-sized: a lockfile and a rule line, not a framework. The verdict states what the error actually was, not a guess.

## How to close the loop

- cc-harvest: edit `tools/cc-harvest/bin/cc-harvest`; test = invoke twice back-to-back (or unit-test the cooldown branch), capture both outputs in the run-table (first runs, second skips with the log line).
- Notion: one reproduced call (or transcript-derived error), captured verbatim; the rule line landed where Tool selection rules live.
- Same-repo: kit lane from this cwd (spec + spec-validate + gate-ledger). cc-harvest is a behavioral tool change: its co-located proof-of-done at `tools/cc-harvest/docs/` gets the run-table.

**Done =** second-invocation-skips proven in the run-table AND the notion verdict (rule line or fix) is committed with the captured error.

## Handoff on completion

1. Flip the ROADMAP box + PR #. 2. Overwrite HANDOFF.md (next: 06, gate). 3. Append to DECISIONS.md. 4. Exit immediately.

## Scope edges

**In:** cc-harvest cooldown + header claim, the notion tool verdict + rule line.
**Out:** other MCP health (playwright/ExitWorktree error rates are NOTES-proposed, not this sub-goal), cc-observe changes.
**Not:** no harvest redesign, no Notion API client work, no auditing other connectors.

## Where to look

`tools/cc-harvest/` (bin + docs); the ntn-first rule in repo memory / global CLAUDE.md Tool selection; cc-observe tools view for the error counts; research/2026-07-02-process-benchmark.md section 5.

## PR body

One-line outcome; the run-table + captured error; link to ROADMAP.md; closes ID-152 + ID-243.

## Notes

