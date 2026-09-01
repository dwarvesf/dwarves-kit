#!/usr/bin/env bash
# goal.sh -- thin standalone entry for the goal subsystem (kit-modularity SG-03,
# board.sh/orchestrate.sh shape). Forwards `goal <verb> <args...>` to the sibling
# script that already owns that verb; adds NO new logic. Additive: every existing
# `bash lib/goal/<x>.sh ...` call-site keeps working unchanged.
#
# Usage:
#   goal.sh draft <archive|list|dir>        -> goal-drafts.sh (design-time candidates)
#   goal.sh registry <claim|list|log|...>   -> goal-registry.sh (cross-session lock)
#   goal.sh merge <gate|merge|mark>         -> mega-merge.sh (mega-goal box merge)
#   goal.sh stack-merge <next|chain>        -> stack-merge.sh (stacked-PR merge)
#   goal.sh handoff <args...>               -> handoff-gen (two-tier handoff doc)
#   goal.sh wt <start|close> <slug> ...     -> wt.sh (one work unit's worktree start/close ritual)
#   goal.sh -h|--help|help                  -> this usage
set -euo pipefail

GOAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    draft|drafts)  exec bash "$GOAL_DIR/goal-drafts.sh" "$@" ;;
    registry)      exec bash "$GOAL_DIR/goal-registry.sh" "$@" ;;
    merge)         exec bash "$GOAL_DIR/mega-merge.sh" "$@" ;;
    stack-merge)   exec bash "$GOAL_DIR/stack-merge.sh" "$@" ;;
    handoff)       exec bash "$GOAL_DIR/handoff-gen" "$@" ;;
    wt|worktree)   exec bash "$GOAL_DIR/wt.sh" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "goal: unknown verb '$verb' (try: goal --help)" >&2; exit 1 ;;
  esac
}

main "$@"
