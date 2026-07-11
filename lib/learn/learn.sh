#!/usr/bin/env bash
# learn.sh -- thin standalone entry for the learn subsystem (ADR-0034 decision 1,
# SG-04, board.sh/goal.sh shape). Forwards `learn <verb> <args...>` to the sibling
# script that owns that verb. Adds NO new logic.
#
# `debt` and `propose` are LIVE. `debt` = weekend-batch (relocated from lib/queue/,
# byte-identical). `propose` = the cross-run distiller (SPEC-195): reads the stats-lens
# aggregate over a window, interprets it into cited hypotheses, adversarially checks each,
# and stages survivors as `## [staged]` backlog blocks. `drain` (staging review render)
# is still a RESERVED name -- it REFUSES rather than silently no-op, so a caller learns
# the real state instead of getting an empty success.
#
# Usage:
#   learn.sh debt <list|collect|mark-paid> <args...>  -> weekend-batch.sh (own usage)
#   learn.sh propose [--days N|--megas N] <args...>    -> propose.py (SPEC-195)
#   learn.sh drain <args...>                            -> refuses: ships in SPEC-196
#   learn.sh -h|--help|help                             -> this usage
set -euo pipefail

LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    debt)    exec bash "$LEARN_DIR/weekend-batch.sh" "$@" ;;
    propose) exec python3 "$LEARN_DIR/propose.py" "$@" ;;
    drain)   echo "learn drain: not yet implemented -- ships in SPEC-196" >&2; exit 1 ;;
    -h|--help|help|"") usage ;;
    *) echo "learn: unknown verb '$verb' (try: learn --help)" >&2; exit 1 ;;
  esac
}

main "$@"
