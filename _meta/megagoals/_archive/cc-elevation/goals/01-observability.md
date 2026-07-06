# Sub-goal 01: Observability (hook latency + skill usage)

**Time budget:** ~2-3 hours loop work
**Depends on:** none
**Branch:** feat/cc-elevation-01-observe
**PR base:** main

## Outcome

I can see my own Claude Code usage as data. A new `tools/cc-observe/` provides (a) a hook-latency timing wrapper that records `{ts,hook,event,ms}` per hook execution to a vps-mon-readable log, and (b) a report CLI that turns the session JSONL transcripts into a per-skill and per-tool frequency + error-rate table. Together they answer "which hooks are slow" and "which of my 87 skills actually fire vs rot."

## Quality bar

Measurement is near-free: the wrapper adds no perceptible time, the report runs offline against existing JSONL. No new always-on daemon; vps-mon is the sink. Borrow claude-code-otel's metric names, not its Docker stack.

## How to close the loop

- `tools/cc-observe/` exists with a runnable report CLI + tests.
- Skill/tool usage: point the report at a sample session JSONL; it prints a table with at least name, invocation count, error count. A known-fired skill shows count >= 1; an unused skill is absent or 0 (negative control).
- Hook latency: the timing wrapper, given a sample hook + payload, emits a `{ts,hook,event,ms}` line; a deliberately-slow stub hook (`sleep 0.3`) shows ms >= 300, a no-op hook shows a small ms (negative control).
- Wiring runbook at `tools/cc-observe/deploy/observe-runbook.md` covers wrapping the dotfiles hooks + the vps-mon ingest (activation is a post-merge deploy step, not this PR).
- Classify the lane (`bash ~/.claude/dwarves-kit/lib/lane-classify.sh classify ...`); as a new data tool it owes `tools/cc-observe/docs/proof-of-done.md` with a recorded run.

**Done =** `tools/cc-observe/` ships a tested report CLI (skill+tool freq/error from JSONL) AND a hook-latency wrapper proven with a slow-hook negative control AND a wiring runbook AND docs/proof-of-done.md, on PR #NN with green CI.

## Scope edges

**In:** the new `tools/cc-observe/` (report CLI, latency wrapper script, runbook, tests, proof).
**Out:** editing ~/.claude or dotfiles hooks (that is the runbook's post-merge deploy); cost/$ dashboards.
**Not:** standing up OTel/Prometheus/Grafana; a live daemon; touching peon-ping.

## Where to look

The session JSONL transcript directory (`~/.claude/projects/<slug>/...`), the existing bash hooks for the wrapper shape, `tools/vps-mon/` for the log/ingest convention, claude-code-otel's metric schema for names, `tools/tide/` for tool shape.

## PR body

Outcome: a `tools/cc-observe/` tool that records hook-execution latency to a vps-mon-readable log and reports per-skill/per-tool usage + error rates from session JSONL.
Verify: run the report against a sample JSONL (known skill shows >=1, unused shows 0); run the latency wrapper on a slow stub hook (ms >= 300).
Roadmap: `_meta/megagoals/cc-elevation/ROADMAP.md` (sub-goal 01).

## Notes
