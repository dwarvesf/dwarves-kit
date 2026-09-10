#!/usr/bin/env bash
# learn.sh -- thin standalone entry for the learn subsystem (ADR-0034 decision 1,
# SG-04, board.sh/goal.sh shape). Forwards `learn <verb> <args...>` to the sibling
# script that owns that verb. Adds NO new logic.
#
# All three verbs are LIVE: `debt` (weekend-batch, relocated from lib/queue/,
# byte-identical behavior), `propose` (SPEC-195, the cross-run distiller),
# `drain` (SPEC-196, the staging-review render).
#
# Usage:
#   learn.sh debt <list|collect|mark-paid> <args...>  -> weekend-batch.sh (own usage)
#   learn.sh propose <args...>                         -> propose.py (own usage)
#   learn.sh drain [--days N]                          -> drain.sh (own usage)
#   learn.sh -h|--help|help                             -> this usage
set -euo pipefail

LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    debt)    exec bash "$LEARN_DIR/weekend-batch.sh" "$@" ;;
    propose) exec python3 "$LEARN_DIR/propose.py" "$@" ;;
    drain)   exec bash "$LEARN_DIR/drain.sh" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "learn: unknown verb '$verb' (try: learn --help)" >&2; exit 1 ;;
  esac
}

main "$@"
