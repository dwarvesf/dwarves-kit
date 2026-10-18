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
#   kit_hook_log_dir   -> prints the hook log dir; creates it only for the one-time migration.
#                         Never fails: an unresolvable root falls back to the XDG default.
#
# Hot path: a hook sources this file at start (a few lines, no forks) and calls
# kit_hook_log_dir only where it writes a log line, because resolving the root reads the kit
# config. Sourcing is idempotent.
[ -n "${_KIT_HOOK_LOG_DIR_SOURCED:-}" ] && return 0
_KIT_HOOK_LOG_DIR_SOURCED=1

# No forks here: a hook pays this on every run.
_KIT_HOOK_LOG_LIB="${BASH_SOURCE[0]%/*}"
case "$_KIT_HOOK_LOG_LIB" in /*) ;; *) _KIT_HOOK_LOG_LIB="$PWD/$_KIT_HOOK_LOG_LIB" ;; esac

# The files a hook appends to. Only these move; nothing else in the old dir is touched.
_KIT_HOOK_LOG_NAMES="anti-rationalization board-row-gate citation-guard commit-format safety-gate secrets-guard ship-gate slop-cleaner spec-drift-guard"

# _kit_hook_log_migrate <root> <hooks-dir>: one-time, additive copy of old hook logs into the
# new dir. Sources, in order: the ledger root itself (hook logs sat directly in it when a knob
# pinned it) and the old default ~/.claude/dwarves-kit/logs. The old default is skipped when a
# knob pins the root, so a test's temp dir never ingests the machine's logs. cp -n never
# overwrites, the old files are never deleted, and a symlinked source is refused. The sentinel
# lands only when every copy succeeded, so a partial copy retries on the next call.
_kit_hook_log_migrate() {
  local root="$1" dir="$2" src name ok=1 srcs=("$1")
  mkdir -p "$dir" 2>/dev/null || return 0
  if [ -z "${KIT_LEDGER_DIR+x}" ] && [ -z "${DWARVES_KIT_LOG_DIR:-}" ] && command -v kit_legacy_log_dir >/dev/null 2>&1; then
    srcs+=("$(kit_legacy_log_dir)")
  fi
  for src in "${srcs[@]}"; do
    [ -d "$src" ] && [ ! -L "$src" ] || continue
    for name in $_KIT_HOOK_LOG_NAMES; do
      [ -f "$src/$name.log" ] && [ ! -L "$src/$name.log" ] || continue
      cp -n "$src/$name.log" "$dir/$name.log" 2>/dev/null || [ -e "$dir/$name.log" ] || ok=0
    done
  done
  [ "$ok" = 1 ] && : > "$dir/.migrated" 2>/dev/null
  return 0
}

kit_hook_log_dir() {
  local root="" dir
  # shellcheck source=lib/telemetry/kit-log-dir.sh
  if . "$_KIT_HOOK_LOG_LIB/kit-log-dir.sh" 2>/dev/null; then
    root="$(kit_resolve_log_dir 2>/dev/null)" || root=""
  fi
  [ -n "$root" ] || root="${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs"
  dir="$root/hooks"
  [ -f "$dir/.migrated" ] || _kit_hook_log_migrate "$root" "$dir"
  printf '%s' "$dir"
}
