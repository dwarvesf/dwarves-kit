# Mega-goal: cc-token-reduction

**Destination:** Claude Code per-session token consumption is audited with $-impact, the cc-harvest quota claim is empirically settled, cc-observe's cost/cache views are verified faithful, and the top recurring sink (the global CLAUDE.md) is trimmed, all without losing capability.
**Quality bar:** Every lever is backed by a number from real session data, not a vibe. After this, Han knows exactly where his tokens go and the biggest recurring sink is measurably smaller, with nothing useful lost.
**Stacking tool:** gh (stacked PRs, default)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-06-20

## Sub-goals

- [x] 01-token-sink-audit, dated research snapshot ranks sinks by $-impact + cheap/research split, `gate`, PR #439 (merged)
- [x] 02-cc-observe-cost-faithful, proof-of-done confirms subagent + cache math match token-dashboard, `auto`, PR #441 (merged)
- [x] 03-harvest-quota-verify, before/after quota run-table + keep/disable/down-rate decision, `gate`, PR #447 (merged)
- [x] 04-slim-global-claude-md, global CLAUDE.md trimmed, line/token delta captured, capability preserved, `gate` (cross-repo dotfiles), PR #142 (merged)

**COMPLETE 2026-06-20: all 4 sub-goals merged (Han released the gates: "merge all 3 now"). Headline finding: global CLAUDE.md is the cheapest token win, not the biggest; 64% of Opus cost is per-turn cache-read of accumulated context (parked research-first).**

## Dependencies

- 01 is the keystone (its ranked list scopes 04). 04 depends on 01.
- 02 and 03 are independent of 01 and of each other; base `main`, run in parallel.
- 04 lands in the `dotfiles` repo (chezmoi template), NOT ops-toolkit. It cannot use `/kit:*` (those bind to the ops-toolkit cwd) and must stage+commit in one shell call (the dotfiles watcher reverts uncommitted tracked changes; see memory `project_dotfiles_watcher_atomic_commit`). Its PR opens in `dotfiles`.

## Dropped

- 05-subagent-model-routing, dropped 2026-06-20: the data showed every custom read-only agent is already on Sonnet/Haiku, leaving only built-in Explore/general-purpose. general-purpose can't be safely cheapened (it does real work), Explore-to-Sonnet is a dispatch habit not a shippable artifact, and any CLAUDE.md routing rule grows the very prefix SG-04 shrinks. Captured as the Tier-2 "built-in subagent routing" row in `research/2026-06-20-cc-token-reduction-audit.md` instead of a sub-goal.

## Already shipped (scope is lighter than the backlog rows imply)

- ID-117's cost + subagents + cache-economics views landed in cc-observe (PRs #337, #330, 2026-06-15). SG-02 is a faithfulness verify-and-close, not net-new build.
- ID-152's throttle (<=1 run/hour) landed (PR #432, 2026-06-19). SG-03 is only the quota-measurement half.
- SG-01's audit is PRE-DRAFTED at `research/2026-06-20-cc-token-reduction-audit.md` (live cc-observe 7-day pull). SG-01 verifies + opens its PR rather than starting blank. Key finding: 64% of Opus load is cache-READ of the static prefix every turn, so the prefix-slim levers (SG-04 + global/repo dedup) carry the most leverage; the custom read-only agents are already routed to Sonnet/Haiku, which is why subagent routing stays a Tier-2 audit row rather than a sub-goal (SG-05 dropped 2026-06-20).

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read _ pr; do
      gh pr view "$pr" --json state,reviewDecision,statusCheckRollup
    done

## Notes on tagging

01 and 03 are `gate` because prioritization (01) and a cost/benefit keep-or-disable call (03) are human judgment, not a binary test. 04 is `gate` because it is a capability-loss judgment on a cross-repo file. 02 is the clean `auto`: verifying already-shipped code, test-suite-gated.
