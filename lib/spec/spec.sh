#!/usr/bin/env bash
# spec.sh -- thin standalone entry for the spec subsystem (kit-modularity SG-03,
# board.sh/orchestrate.sh shape). Forwards `spec <verb> <args...>` to the sibling
# script that already owns that verb; adds NO new logic. Additive: every existing
# `bash lib/spec/<x>.sh ...` call-site keeps working unchanged.
#
# Usage:
#   spec.sh index [list]        -> spec-index.sh (the grouped spec table)
#   spec.sh next <args...>      -> spec-next.sh (next|check <NNN>|reserve)
#   spec.sh -h|--help|help      -> this usage
set -euo pipefail

SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    index)              exec bash "$SPEC_DIR/spec-index.sh" "$@" ;;
    next)               exec bash "$SPEC_DIR/spec-next.sh" "$@" ;;
    -h|--help|help|"")  usage ;;
    *) echo "spec: unknown verb '$verb' (try: spec --help)" >&2; exit 1 ;;
  esac
}

main "$@"
