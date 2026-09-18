#!/usr/bin/env bash
# gate-policy.sh -- is a quality gate switched on for this project?
#
# The one reader of the `[gate]` block (kit-root kit.toml, then the operator overlay,
# then the project's .kit.toml, which wins). Hooks call THIS script instead of reading
# config themselves, so the standing lint "no hook reads kit.toml at runtime" stays
# true and there is one place the default lives.
#
# Quality gates are OPT-IN: a gate is on only when its key resolves to a literal `true`.
# The kit root says false for every key but one: board_row_gate defaults ON (DEFAULT_ON),
# because a board-row check nobody switched on would cover no board. For the rest, an operator turns them on machine-wide in
# ~/.config/dwarves-kit/kit.toml, a repo turns one on with `<key> = true` in its .kit.toml
# (never commit-gated: turning a gate on is not a bypass). A project-level `false` over an
# operator `true` counts only once .kit.toml is committed and clean: the hooks read the
# working tree, so an uncommitted file would let the gated agent switch its own gate off
# with no trace in the PR. An unknown key, a missing resolver, or a reader error means ON,
# so a broken kit never silently drops a gate an operator turned on.
#
# Exit-code contract for callers: 0 = on, 1 = off by config. Callers treat EVERY other exit
# (a broken or unreadable copy of this script, 2/126/127) as on.
#
# Safety gates (safety-gate.sh, secrets-guard.sh) have no key here on purpose. They stop
# destructive git and credential leaks, not quality drift, and cannot be switched off.
#
# Usage:
#   gate-policy.sh enabled <key> [project-root]   exit 0 = on, exit 1 = off by config (only 1)
#   gate-policy.sh keys                            the known keys, one per line
#
# <key>: proof_of_done | lane_gates | understanding_gate | commit_format | board_row_gate
set -uo pipefail
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS="proof_of_done lane_gates understanding_gate commit_format board_row_gate"
DEFAULT_ON="board_row_gate"   # the code default when no config file names the key

enabled() {
  local key="${1:-}" root="${2:-$PWD}" v
  case " $KEYS " in *" $key "*) ;; *) return 0 ;; esac
  # shellcheck source=lib/config/kit-config.sh
  source "$GATE_DIR/../config/kit-config.sh" 2>/dev/null || return 0
  # What the operator overlay and the kit root say, with the project file out of the picture.
  local def=false; case " $DEFAULT_ON " in *" $key "*) def=true ;; esac
  local rest; rest="$(KIT_PROJECT_ROOT=/nonexistent kit_config_get "gate.$key" "$def" 2>/dev/null)" || return 0
  case "$(_kit_toml_get "$root/.kit.toml" gate "$key")" in
    true) return 0 ;;
    false)
      # A project-level off over an operator on: only when the file is tracked and unmodified.
      if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
         && git -C "$root" ls-files --error-unmatch .kit.toml >/dev/null 2>&1 \
         && git -C "$root" diff --quiet HEAD -- .kit.toml 2>/dev/null; then
        return 1
      fi
      [ "$rest" = "true" ] && echo "gate-policy: [gate] $key = false in $root/.kit.toml is not applied until the file is committed and clean" >&2
      ;;
  esac
  [ "$rest" = "true" ]
}

case "${1:-}" in
  enabled) shift; enabled "$@" ;;
  keys)    printf '%s\n' $KEYS ;;
  *) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
