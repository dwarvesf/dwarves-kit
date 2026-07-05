# Mega-goal: token-hygiene

> STATUS: COMPLETE (2026-06-29). All 5 sub-goals merged (PR #581, #582, #80, #81, #584).
> Each got a fresh-context review this session. Successor wave: `_meta/megagoals/token-optim-v2/`.

## Destination
Make Claude Code token spend in the mega-goal/kit workflow observable AND structurally
lower. Non-deployable (tooling + docs + framework change); terminus = all sub-goals merged
(no deploy/UAT gate, intentional).

## Theory of change (expected token reduction)
Today a mega-goal run = one un-cleared session whose context grows monotonically across
6-10h, plus 5-9 subagents per sub-goal returning full output into the lead; cost is
dominated by cache_read (the whole context re-read every turn). These sub-goals attack that
directly:
- SG-04 summarized returns: subagent results come back distilled, so the lead grows slowly
  instead of absorbing 16-25K-token dumps per return.
- SG-04 checkpoint signal + SG-02 operator habit: each sub-goal becomes a clear-able unit;
  `/clear` + resume via POINTER_PROMPT between sub-goals kills the monotonic growth (the #1
  cost driver).
- SG-05 tail meta-agent: unspecified work gets an ephemeral tool-scoped subagent instead of
  the all-tools general-purpose agent (smaller per-turn footprint).
- SG-01 forensic `--loops`: the measurement instrument.

Success metric: a `token-forensic --loops` comparison of a mega-goal run before vs after,
showing lower cache_read per turn and lower total for an equivalent run. The win is
structural (each sub-goal packaged as a lean, handed-off, near-fresh-context unit), not
incremental trimming.

## Assumptions (from the 2026-06-28 session)
- Dominant waste = long un-cleared sessions (cache_read 58.5%); mega-goal runs are one
  continuous session + 5-9 subagents/sub-goal with full returns (kit audit, `WORKFLOW.md:651-652, 707-712`).
- Evidence: `research/2026-06-28-{token-spend-forensic,claude-token-cost-attribution}.md`.
- dwarves-kit is a shared repo (dwarvesf/dwarves-kit); kit changes are `gate` (team review),
  never auto-merge.
- Stacking: `gh` stacked PRs. Merge: auto-bottom-up + gated-final.

## Sub-goals
- [x] SG-01 token-forensic `--loops` view (ops-toolkit) , auto , PR #581 (merged) , SPEC-120
- [x] SG-02 mega-goal token-hygiene runbook (ops-toolkit) , auto , PR #582 (merged)
- [x] SG-03 dwarves-kit context-hygiene SPEC + ADR (design) , gate , PR #80 (merged, dwarvesf/dwarves-kit)
- [x] SG-04 dwarves-kit impl (non-LLM orchestrator + feed-forward handoff) , gate , PR #81 (merged, dwarvesf/dwarves-kit) , depends SG-03
- [x] SG-05 meta-agent tail prototype (experiments/) , gate , PR #584 (merged, ops-toolkit) , depends SG-01

## Dependencies
SG-01, SG-02, SG-03 independent (branch off main). SG-04 depends on SG-03 (design before
impl). SG-05 depends on SG-01 (needs `--loops` to measure).

## Before close
Run `/kit:review-team` (+ a focused review lens) across the merged set before marking the
mega-goal complete. Then append the LAB_LOG arc entry on the last sub-goal's branch.
