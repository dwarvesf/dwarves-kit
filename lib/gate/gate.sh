#!/usr/bin/env bash
# gate.sh -- thin standalone entry for the gate subsystem (kit-modularity SG-03,
# board.sh/orchestrate.sh shape). Forwards `gate <verb> <args...>` to the sibling
# script that already owns that verb; adds NO new logic. Additive: every existing
# `bash lib/gate/<x>.sh ...` call-site keeps working unchanged.
#
# Usage:
#   gate.sh ledger <args...>          -> gate-ledger.sh (tokens|debt|outcome|rid|...)
#   gate.sh dispatch <args...>        -> dispatch-gate.sh (touches|disjoint|plan|drift)
#   gate.sh proof <args...>           -> proof-gate.sh (class|requirement|classes)
#   gate.sh proof-ledger <args...>    -> proof-ledger.sh
#   gate.sh proof-table <args...>     -> proof-table-gen.sh
#   gate.sh quiz <args...>            -> quiz-gate.sh (questions|tap|respond|route)
#   gate.sh coverage-delta <args...>  -> coverage-delta.sh (check|class|classes)
#   gate.sh mutation-smoke <args...>  -> mutation-smoke.sh (run|candidates|...)
#   gate.sh verif-counts               -> verif-counts.sh
#   gate.sh -h|--help|help             -> this usage
set -euo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    ledger)          exec bash "$GATE_DIR/gate-ledger.sh" "$@" ;;
    dispatch)        exec bash "$GATE_DIR/dispatch-gate.sh" "$@" ;;
    proof)           exec bash "$GATE_DIR/proof-gate.sh" "$@" ;;
    proof-ledger)    exec bash "$GATE_DIR/proof-ledger.sh" "$@" ;;
    proof-table)     exec bash "$GATE_DIR/proof-table-gen.sh" "$@" ;;
    quiz)            exec bash "$GATE_DIR/quiz-gate.sh" "$@" ;;
    coverage-delta)  exec bash "$GATE_DIR/coverage-delta.sh" "$@" ;;
    mutation-smoke)  exec bash "$GATE_DIR/mutation-smoke.sh" "$@" ;;
    verif-counts)    exec bash "$GATE_DIR/verif-counts.sh" "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "gate: unknown verb '$verb' (try: gate --help)" >&2; exit 1 ;;
  esac
}

main "$@"
