#!/usr/bin/env bash
# gate-policy.sh -- is a quality gate switched on for this project?
#
# The one reader of the `[gate]` block (kit-root kit.toml, then the operator overlay,
# then the project's .kit.toml, which wins). Hooks call THIS script instead of reading
# config themselves, so the standing lint "no hook reads kit.toml at runtime" stays
# true and there is one place the default lives. Fail-open in the ON direction: an
# unknown key, a missing resolver, or any error means the gate is on. Switching a gate
# off has to be an explicit `<key> = false`.
#
# Safety gates (safety-gate.sh, secrets-guard.sh) have no key here on purpose. They stop
# destructive git and credential leaks, not quality drift, and cannot be switched off.
#
# Usage:
#   gate-policy.sh enabled <key> [project-root]   exit 0 = on, exit 1 = off by config
#   gate-policy.sh keys                            the known keys, one per line
#
# <key>: proof_of_done | lane_gates | understanding_gate | commit_format
set -uo pipefail
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS="proof_of_done lane_gates understanding_gate commit_format"

enabled() {
  local key="${1:-}" root="${2:-$PWD}" v
  case " $KEYS " in *" $key "*) ;; *) return 0 ;; esac
  # shellcheck source=lib/config/kit-config.sh
  source "$GATE_DIR/../config/kit-config.sh" 2>/dev/null || return 0
  v="$(KIT_PROJECT_ROOT="$root" kit_config_get "gate.$key" true 2>/dev/null)" || return 0
  [ "$v" != "false" ]
}

case "${1:-}" in
  enabled) shift; enabled "$@" ;;
  keys)    printf '%s\n' $KEYS ;;
  *) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
