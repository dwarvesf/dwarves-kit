#!/usr/bin/env bash
# reflect.sh -- thin standalone entry for the reflect subsystem (renamed from `learn`:
# the system changes from its own telemetry, nobody
# learns). Forwards `reflect <verb> <args...>` to the sibling script that owns that verb.
# Adds NO new logic.
#
# All three verbs are LIVE: `debt` (weekend-batch, relocated from lib/queue/,
# byte-identical behavior), `propose` (the cross-run distiller),
# `drain` (the staging-review render).
#
# Usage:
#   reflect.sh debt <list|collect|mark-paid> <args...>  -> weekend-batch.sh (own usage)
#   reflect.sh propose <args...>                         -> propose.py (own usage)
#   reflect.sh drain [--days N]                          -> drain.sh (own usage)
#   reflect.sh -h|--help|help                             -> this usage
set -euo pipefail

REFLECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    debt)    exec bash "$REFLECT_DIR/weekend-batch.sh" "$@" ;;
    propose) exec python3 "$REFLECT_DIR/propose.py" "$@" ;;
    drain)   exec bash "$REFLECT_DIR/drain.sh" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "reflect: unknown verb '$verb' (try: reflect --help)" >&2; exit 1 ;;
  esac
}

main "$@"
