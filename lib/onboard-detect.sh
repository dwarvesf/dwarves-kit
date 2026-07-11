#!/usr/bin/env bash
# onboard-detect.sh -- detect how the dwarves-kit is installed on THIS machine, for /kit:onboard.
#
# READ-ONLY by contract: it inspects install state under $CLAUDE_DIR and prints a mode word (and,
# on `explain`, a one-line explanation). It never writes anything. The interactive first-run flow
# (commands/onboard.md) is the orchestrator; this is the one deterministic seam worth testing as
# bash rather than proving by transcript (SPEC-199).
#
# The detection signals mirror install.sh's own plugin-detect block (install.sh:315-353) exactly,
# so onboard and install agree on what "installed as a plugin" means:
#   plugin cache present : a lib dir exists under
#       $CLAUDE_DIR/plugins/cache/dwarves-marketplace/kit/*/lib   (install.sh:328's glob),
#       OR $CLAUDE_DIR/plugins/installed_plugins.json names the dwarves marketplace/kit.
#   bash hooks live      : $CLAUDE_DIR/settings.json registers >=1 dwarves-kit/hooks/*.sh command
#       (the full bash install path; the plugin COMPAT symlink deliberately writes no
#       settings.json hooks, install.sh:331, so a compat-only machine reads as `plugin`, correctly).
#
# Modes:
#   plugin : plugin cache present, no bash hooks. Runtime loads from the plugin.
#   bash   : bash hooks live, no plugin cache. settings.json drives the hooks directly.
#   both   : both present. Hooks are DOUBLE-registered and fire twice -- the hazard case.
#   none   : neither. The kit is not installed on this machine yet.
#
# Usage: onboard-detect.sh [mode|explain]
#   mode     (default) : print just the mode word.
#   explain            : print "<mode>\t<one-line explanation>".
#
# Test seam: $CLAUDE_DIR is env-overridable (default $HOME/.claude), the same override install.sh
# uses, so the four modes are fixture-tested without a real install.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# plugin_present -- true if a dwarves-kit plugin install is present on this machine.
plugin_present() {
  # Primary: the exact cache-lib glob install.sh:328 keys on. A glob with no match under `set -e`
  # must not abort the function, so guard it inside an `if`.
  if ls -d "$CLAUDE_DIR"/plugins/cache/dwarves-marketplace/kit/*/lib >/dev/null 2>&1; then
    return 0
  fi
  # Fallback: the CC-owned roster names the kit's marketplace. Grep (not jq) so there is no hard
  # jq dependency in a first-run probe; the marketplace slug is specific enough to not false-match.
  local ip="$CLAUDE_DIR/plugins/installed_plugins.json"
  if [ -f "$ip" ] && grep -q 'dwarves-marketplace' "$ip" 2>/dev/null; then
    return 0
  fi
  return 1
}

# bash_hooks_present -- true if the FULL bash install registered kit hooks in settings.json.
# The compat symlink path writes no settings.json hooks, so this is false on a compat-only machine.
bash_hooks_present() {
  local settings="$CLAUDE_DIR/settings.json"
  [ -f "$settings" ] || return 1
  grep -q 'dwarves-kit/hooks/' "$settings" 2>/dev/null
}

detect_mode() {
  local p=0 b=0
  plugin_present && p=1
  bash_hooks_present && b=1
  if [ "$p" -eq 1 ] && [ "$b" -eq 1 ]; then echo "both"
  elif [ "$p" -eq 1 ]; then echo "plugin"
  elif [ "$b" -eq 1 ]; then echo "bash"
  else echo "none"; fi
}

explain_mode() {
  case "$1" in
    plugin) echo "installed as a Claude Code plugin; runtime loads from the plugin (\${CLAUDE_PLUGIN_ROOT}). No kit hooks are registered in settings.json, so nothing double-fires." ;;
    bash)   echo "installed via bash install.sh; \$CLAUDE_DIR/settings.json registers the kit hooks directly, and \$CLAUDE_DIR/dwarves-kit holds the engine copies." ;;
    both)   echo "BOTH a plugin AND a bash install are present -- the kit hooks are DOUBLE-registered and will fire twice. Keep exactly one path (see the disclosure in /kit:onboard)." ;;
    none)   echo "the kit is not installed on this machine yet (no plugin cache, no kit hooks in settings.json). Install it first, then re-run /kit:onboard." ;;
    *)      echo "unknown install mode" ;;
  esac
}

main() {
  local verb="${1:-mode}" mode
  mode="$(detect_mode)"
  case "$verb" in
    mode) printf '%s\n' "$mode" ;;
    explain) printf '%s\t%s\n' "$mode" "$(explain_mode "$mode")" ;;
    -h|--help|help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "onboard-detect: unknown verb '$verb' (use: mode | explain)" >&2; return 64 ;;
  esac
}

main "$@"
