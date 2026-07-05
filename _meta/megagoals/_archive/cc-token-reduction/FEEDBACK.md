# FEEDBACK, cc-token-reduction

Append-only. Categories below are suggestions; use whichever fits. Audience: Han (skill/tooling/codebase maintainer).

## Skill friction

2026-06-20 · skill friction · The cluster turned out half-shipped (ID-117 views + ID-152 throttle already merged) once mapped, so two of the three backlog rows shrank to verify-and-close. plan-for-mega-goal has no explicit "re-verify each backlog item's real remaining work before decomposing" step; the decompose was only correct because a recall sweep ran first. Worth a one-line nudge in the skill's step 3.

## Tooling gaps

(none yet)

## Codebase issues

2026-06-20 · codebase · Sub-goal 04's lever lives in the `dotfiles` repo, not ops-toolkit, so it cannot use the kit SDD slash commands and rides a separate PR + the watcher atomic-commit gotcha. Most high-value CC-token levers (global CLAUDE.md, hooks, MCP schemas) live under `~/.claude/` = dotfiles/harness config, outside this repo. A future "harness-config token budget" tool may want to live where those configs do, or the mega-goal framework may want first-class cross-repo sub-goal support.

## Pointer prompt churn

(none yet)
