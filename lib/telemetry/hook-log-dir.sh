#!/usr/bin/env bash
# hook-log-dir.sh -- the one resolver for the directory the hooks write their logs to.
#
# WHY: gate and hook logs (ship-gate.log, safety-gate.log, ...) used to default to
# ~/.claude/dwarves-kit/logs, inside the plugin state dir a reinstall recreates, while the
# ledgers moved to the durable root. A reinstall erased the BLOCKED and OFF-BY-CONFIG trail.
# Hook logs now live under the resolved ledger root, in a hooks/ subdir:
#   <kit_resolve_log_dir>/hooks/<name>.log
# so $KIT_LEDGER_DIR, $DWARVES_KIT_LOG_DIR and [ledger].location move ledgers and hook logs
# together (lib/telemetry/kit-log-dir.sh holds that precedence).
#
# Contract:
#   kit_hook_log_dir   -> prints the hook log dir. It only resolves: it creates nothing and copies
#                         nothing (the writer creates the dir; lib/telemetry/kit-migrate.sh moves old
#                         logs, once, at install). Never fails: an unresolvable root falls back to the
#                         XDG default.
#
# Hot path: a hook sources this file at start (a few lines, no forks) and calls
# kit_hook_log_dir only where it writes a log line, because resolving the root reads the kit
# config. Sourcing is idempotent.
[ -n "${_KIT_HOOK_LOG_DIR_SOURCED:-}" ] && return 0
_KIT_HOOK_LOG_DIR_SOURCED=1

# No forks here: a hook pays this on every run.
_KIT_HOOK_LOG_LIB="${BASH_SOURCE[0]%/*}"
case "$_KIT_HOOK_LOG_LIB" in /*) ;; *) _KIT_HOOK_LOG_LIB="$PWD/$_KIT_HOOK_LOG_LIB" ;; esac

kit_hook_log_dir() {
  local root=""
  # shellcheck source=lib/telemetry/kit-log-dir.sh
  if . "$_KIT_HOOK_LOG_LIB/kit-log-dir.sh" 2>/dev/null; then
    root="$(kit_resolve_log_dir 2>/dev/null)" || root=""
  fi
  [ -n "$root" ] || root="${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs"
  command -v kit_note_unmigrated >/dev/null 2>&1 && kit_note_unmigrated "$root"
  printf '%s' "$root/hooks"
}
