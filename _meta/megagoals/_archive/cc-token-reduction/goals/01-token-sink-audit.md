# Sub-goal 01: token-sink-audit

**Merge policy:** gate (the ranked prioritization is Han's judgment call; the doc PR is mergeable but the priority order needs sign-off)
**Time budget:** 1-2 hours of loop work
**Depends on:** none (keystone; scopes 04)
**Branch:** feat/cctoken-01-sink-audit
**PR base:** main

## Outcome

A dated research snapshot tells Han exactly where his Claude Code tokens go, ranked by per-session dollar impact from real cc-observe data, with each sink paired to a concrete reduction tactic and split into cheap-wins (do now) vs research-first (measure before deciding).

## Quality bar

Numbers, not vibes. Every sink in the table carries a $-estimate sourced from cc-observe (or explicit math when not directly measurable), and the cheap-vs-research split is honest about capability risk. The table is the input that scopes sub-goal 04 and any future r2.

## How to close the loop

Route through the kit: `lane-classify classify "audit and rank Claude Code token sinks from cc-observe data"` (likely a docs/research lane), run its gates. Use cc-observe as the data source: `tools/cc-observe/bin/cc-observe report --json` and `cc-observe cost` over a recent multi-day window.

Sub-goal-specific verification:
- Write `research/2026-06-DD-cc-token-reduction-audit.md` (frontmatter per `research/README.md`).
- It must contain a ranked sink table: one row per sink across global+repo CLAUDE.md, MCP tool-schema bloat, hook re-injection per turn, file re-reads, subagent fan-out, recalled-memory blocks, each with a per-session $-or-token estimate, the source of that number, a reduction tactic, and an effort tag.
- It must contain a prioritized action list splitting cheap-wins from research-first.
- Self-check: `rg -c '^\|' research/2026-06-DD-cc-token-reduction-audit.md` confirms the table exists; eyeball that every named sink has its own row (structural, not an OR-count).

**Done =** `research/2026-06-DD-cc-token-reduction-audit.md` exists with a ranked one-row-per-sink table (each row: $/token estimate + source + tactic + effort) and a cheap-wins-vs-research-first action list, the numbers traceable to cc-observe output cited in the doc.

## Scope edges

**In:** the research snapshot only.
**Out:** shipping any win (that is 04 and future rows), cc-observe code (02), cc-harvest (03).
**Not:** do not start trimming CLAUDE.md or disabling MCP servers in this sub-goal, do not build a new measurement tool (use cc-observe as-is), do not benchmark models.

## Where to look

`tools/cc-observe/` (the data source + its existing cost/subagents views), `research/README.md` (frontmatter shape), `research/2026-06-15-claude-code-usage-metrics-and-tooling.md` (prior cc-elevation research to build on), and the recalled-memory / hook surfaces the audit must account for.

## PR body

Adds a dated token-sink audit: ranks where Claude Code tokens go by per-session $-impact from cc-observe data, with a cheap-wins vs research-first action list. Scopes sub-goal 04 (global CLAUDE.md slim) and any follow-on.

Verify: open `research/2026-06-DD-cc-token-reduction-audit.md`, confirm the ranked sink table (one row per sink, $-estimate + source + tactic) and the prioritized action list.

Roadmap: `_meta/megagoals/cc-token-reduction/ROADMAP.md`.

## Notes
