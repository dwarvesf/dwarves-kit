#!/usr/bin/env bash
# kit-migrate.sh -- the ONE install-time migration of legacy kit logs into the durable ledger root.
#
# WHY: a hook must never run migration code. The ledger resolver and the hook-log resolver used to
# copy old logs (cp -Rn, cp -n) on first use, and hooks reach both. The copy now lives here and
# runs once, from install.sh and lib/adopt.sh. Every runtime path only resolves a directory.
#
# Two additive, no-clobber moves, both guarded by a .migrated sentinel and neither deleting a source:
#   1. the run corpus: ~/.claude/dwarves-kit/logs/.  ->  <ledger root>/
#   2. the hook logs (the files in _KIT_HOOK_LOG_NAMES) -> <ledger root>/hooks/
#
# Contract:
#   kit_migrate            -> run both moves; always returns 0 (a hiccup must never break an install)
#   bash kit-migrate.sh    -> the same, as a command
#
# Guards: a pinned root ($KIT_LEDGER_DIR, $DWARVES_KIT_LOG_DIR) never ingests the machine corpus or
# the old default dir (a test's temp dir must not); it still adopts hook logs that sat directly in
# it. A fixture $CLAUDE_DIR and [ledger].location = "isolated" skip everything.
[ -n "${_KIT_MIGRATE_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_MIGRATE_SOURCED=1

_KIT_MIGRATE_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$_KIT_MIGRATE_SELF/kit-log-dir.sh" || { echo "kit-migrate: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; return 1 2>/dev/null || exit 1; }

# The files a hook appends to. Only these move; nothing else in the old dir is touched.
_KIT_HOOK_LOG_NAMES="anti-rationalization board-row-gate citation-guard commit-format safety-gate secrets-guard ship-gate slop-cleaner spec-drift-guard"

# A knob pins the root: the caller owns that path.
_kit_root_pinned() { [ "${KIT_LEDGER_DIR+set}" = "set" ] || [ -n "${DWARVES_KIT_LOG_DIR:-}" ]; }

# _kit_migrate_corpus <durable>: copy the legacy run corpus in. The sentinel lands only on cp
# success, so a partial copy (permissions, disk) retries on the next install.
_kit_migrate_corpus() {
  local durable="$1" legacy
  legacy="$(kit_legacy_log_dir)"
  [ "$durable" = "$legacy" ] && return 0
  [ -f "$durable/.migrated" ] && return 0
  mkdir -p "$durable" 2>/dev/null || return 0
  if [ -d "$legacy" ] && [ ! -L "$legacy" ]; then
    # -R recursive, -n no-clobber; the trailing /. copies contents, not the dir itself.
    if cp -Rn "$legacy/." "$durable/" 2>/dev/null; then
      : > "$durable/.migrated" 2>/dev/null || true
    fi
  elif [ -L "$legacy" ]; then
    # Never migrate THROUGH a symlink: cp would dereference it and fan an attacker-planted
    # target's contents into the corpus /kit:retro and the eval read. Warn, and sentinel.
    echo "kit-migrate: legacy log dir is a symlink; refusing to migrate through it ($legacy)" >&2
    : > "$durable/.migrated" 2>/dev/null || true
  else
    # Fresh install: no legacy dir ever existed. Mark done.
    : > "$durable/.migrated" 2>/dev/null || true
  fi
  return 0
}

# _kit_migrate_hook_logs <root>: copy old hook logs into <root>/hooks. Sources, in order: the root
# itself (hook logs sat directly in it when a knob pinned it) and the old default dir. cp -n never
# overwrites, old files are never deleted, a symlinked source is refused. The sentinel lands only
# when every copy succeeded, so a partial copy retries.
_kit_migrate_hook_logs() {
  local root="$1" dir="$1/hooks" src name ok=1 srcs=("$1")
  [ -f "$dir/.migrated" ] && return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  _kit_root_pinned || srcs+=("$(kit_legacy_log_dir)")
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

kit_migrate() {
  [ -z "${CLAUDE_DIR:-}" ] || [ "$CLAUDE_DIR" = "$HOME/.claude" ] || return 0
  local root; root="$(kit_resolve_log_dir 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0
  [ "$root" = "$PWD/.kit/logs" ] && return 0
  _kit_root_pinned || _kit_migrate_corpus "$root"
  _kit_migrate_hook_logs "$root"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  kit_migrate
fi
