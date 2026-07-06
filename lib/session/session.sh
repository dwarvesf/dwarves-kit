#!/usr/bin/env bash
# session.sh -- thin standalone entry for the session subsystem (kit-modularity
# SG-03, board.sh/orchestrate.sh shape). Forwards `session <verb> <args...>` to the
# sibling tool that already owns that verb (kit-foldin's cc-observe/cc-recall/
# cc-intel, folded into lib/session/{observe,recall,intel}/). Adds NO new logic.
# Additive: every existing `bash lib/session/<x>/bin/cc-*` call-site keeps working.
#
# Usage:
#   session.sh observe <args...>   -> lib/session/observe/bin/cc-observe (own usage)
#   session.sh recall <args...>    -> lib/session/recall/bin/cc-recall (own usage)
#   session.sh intel <args...>     -> lib/session/intel/bin/cc-intel (own usage)
#   session.sh -h|--help|help      -> this usage
set -euo pipefail

SESSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    observe)  exec "$SESSION_DIR/observe/bin/cc-observe" "$@" ;;
    recall)   exec "$SESSION_DIR/recall/bin/cc-recall" "$@" ;;
    intel)    exec "$SESSION_DIR/intel/bin/cc-intel" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "session: unknown verb '$verb' (try: session --help)" >&2; exit 1 ;;
  esac
}

main "$@"
