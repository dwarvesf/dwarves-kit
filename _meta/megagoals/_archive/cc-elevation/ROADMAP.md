# Mega-goal: cc-elevation

**Destination:** Every Claude Code session is more self-aware and useful: it pulls my own prior notes into context, measures its own tool/skill/hook usage, auto-harvests learnings before compaction loses them, verifies the file:line refs it cites, and runs scheduled read-only cross-repo health sweeps.
**Quality bar:** Each addition earns its latency. Hooks stay in the millisecond range, no private prose leaves the Air, and every new tool ships a proof-of-done. The harness should feel like it knows me, not like a pile of bolt-ons.
**Stacking tool:** gh (01-05 parallel off main, 06 stacked on 05)
**Started:** 2026-06-14

## Sub-goals

- [x] 01-observability, hook-latency log + skill/tool usage report, proven on a real session + a slow-hook negative control, PR #261
- [x] 02-citation-guard, Stop hook flags a bad file:line ref and passes a good one, log-only by default, PR #263
- [x] 03-prose-rag, local fastembed index over til+research+ledger; UserPromptSubmit injects top-k relevant notes (hook opt-in, ~250ms not <100ms), PR #265
- [x] 04-precompact-harvest, PreCompact+SessionEnd hook uses Claude Haiku to stage deduped queued ledger rows, zero durable-home writes, PR #267
- [x] 05-repo-sweeps, read-only cross-repo harness + 6 deterministic sweeps emit one digest, each proven on a seeded finding, PR #268
- [x] 06-reasoning-sweeps, backlog-triage digest + learning-flush/synthesis, built on the 05 harness + the ledger, PR #269 (stacked on #268)

## Dependencies

- 06 depends on 05 (built on the sweep harness; learning-flush reuses the existing `_meta/learned-ledger.md` that 04 also feeds). 01-05 are independent and open in parallel off `main`.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done

## Source

Analysis + designs: `research/2026-06-14-claude-code-events-tools-elevation.md`. Backlog rows: `_meta/BACKLOG.md` ID-075..080 (build) + ID-081..084 (parked borrows).
