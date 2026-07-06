#!/usr/bin/env bash
# classify.sh -- thin standalone entry for the classify subsystem (kit-modularity
# SG-03, board.sh/orchestrate.sh shape). Forwards `classify <verb> <args...>` to the
# sibling script that already owns that verb; adds NO new logic. Additive: every
# existing `bash lib/classify/<x>.sh ...` call-site keeps working unchanged.
#
# Usage:
#   classify.sh lane <task description>          -> lane-classify.sh
#   classify.sh role <args...>                    -> role-classify.sh
#   classify.sh task-type <args...>               -> task-type-classify.sh
#   classify.sh significance <args...>             -> significance-classify.sh
#   classify.sh route-suggest <args...>            -> route-suggest.sh
#   classify.sh -h|--help|help                     -> this usage
set -euo pipefail

CLASSIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    lane)           exec bash "$CLASSIFY_DIR/lane-classify.sh" "$@" ;;
    role)           exec bash "$CLASSIFY_DIR/role-classify.sh" "$@" ;;
    task-type)      exec bash "$CLASSIFY_DIR/task-type-classify.sh" "$@" ;;
    significance)   exec bash "$CLASSIFY_DIR/significance-classify.sh" "$@" ;;
    route-suggest)  exec bash "$CLASSIFY_DIR/route-suggest.sh" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "classify: unknown verb '$verb' (try: classify --help)" >&2; exit 1 ;;
  esac
}

main "$@"
