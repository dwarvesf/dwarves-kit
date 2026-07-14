#!/usr/bin/env bash
# session.sh -- thin standalone entry for the session subsystem (kit-modularity
# SG-03, board.sh/orchestrate.sh shape; the five prefixed `bin/session-*` CLIs
# collapsed into this one dispatcher, ADR-0034 decision 7, SG-04). Forwards
# `session <verb> <args...>` to the sibling tool that already owns that verb
# (kit-foldin's session-observe/session-recall/session-intel/session-report/
# session-semantic, folded into lib/session/{observe,recall,intel}/). Adds NO new
# logic; deep lib paths unchanged. Additive: every existing
# `bash lib/session/<x>/bin/session-*` call-site keeps working.
#
# Usage:
#   session.sh observe <args...>   -> lib/session/observe/bin/session-observe (own usage)
#   session.sh recall <args...>    -> lib/session/recall/bin/session-recall (own usage)
#   session.sh intel <args...>     -> lib/session/intel/bin/session-intel (own usage)
#   session.sh report <args...>    -> lib/session/observe/bin/session-report (own usage)
#   session.sh semantic <args...>  -> lib/session/observe/bin/session-semantic (own usage)
#   session.sh audit <args...>     -> lib/session/audit/bin/session-audit (own usage)
#   session.sh -h|--help|help      -> this usage
set -euo pipefail

SESSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    observe)  exec "$SESSION_DIR/observe/bin/session-observe" "$@" ;;
    recall)   exec "$SESSION_DIR/recall/bin/session-recall" "$@" ;;
    intel)    exec "$SESSION_DIR/intel/bin/session-intel" "$@" ;;
    report)   exec "$SESSION_DIR/observe/bin/session-report" "$@" ;;
    semantic) exec "$SESSION_DIR/observe/bin/session-semantic" "$@" ;;
    audit)    exec "$SESSION_DIR/audit/bin/session-audit" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "session: unknown verb '$verb' (try: session --help)" >&2; exit 1 ;;
  esac
}

main "$@"
