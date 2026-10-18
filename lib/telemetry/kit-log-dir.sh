#!/usr/bin/env bash
# kit-log-dir.sh -- the single resolver for the kit's durable run-telemetry root.
#
# WHY: the run corpus that feeds /kit:retro and the effectiveness eval used to
# default to ~/.claude/dwarves-kit/logs -- INSIDE the plugin state dir, which a plugin
# reinstall recreates (the 2026-07-01 reinstall wiped the whole corpus). This resolver
# moves the default OUT of that blast zone to XDG state. Corpus-bearing libs source this
# instead of hard-coding the path, so there is one place the default lives.
#
# This file only RESOLVES. It never copies: a hook reaches it, and a hook must not run
# migration code. Moving an old corpus into the durable root is lib/telemetry/kit-migrate.sh,
# run once by install.sh and lib/adopt.sh.
#
# Contract (all functions, no output on load, safe under set -euo pipefail):
#   kit_resolve_log_dir   -> the durable log dir ($DWARVES_KIT_LOG_DIR wins if set)
#   kit_legacy_log_dir    -> the original default (~/.claude/dwarves-kit/logs)
#   kit_note_unmigrated [root] -> one stderr line when a legacy dir still exists and kit-migrate never ran
#   kit_migrate_log_dir   -> kept for the corpus libs that call it at load; now only kit_note_unmigrated
#
# Idempotent-source guard: sourcing twice is a no-op.
[ -n "${_KIT_LOG_DIR_SOURCED:-}" ] && return 0
_KIT_LOG_DIR_SOURCED=1

# The config-layer resolver (lib/config/kit-config.sh), sourced best-effort. It reads TOML, so it is
# a command-time lib: hooks never source it at start. A hook reaches it only through
# lib/telemetry/hook-log-dir.sh, and only at the moment it writes a log line (hook logs live in
# <this root>/hooks).
_KIT_LOG_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config/kit-config.sh
source "$_KIT_LOG_DIR_SELF/../config/kit-config.sh" || { echo "kit-log-dir: lib/config/kit-config.sh missing or unreadable" >&2; return 1; }

# The durable default and precedence (kit-modularity ; [ledger] wiring):
# the ledger root is ONE root shared by both planes (the write-side append substrate and the
# read-side `stats` projection). Precedence:
#   1. $KIT_LEDGER_DIR      -- the canonical knob (essential-tier config, per-consumer root).
#   2. $DWARVES_KIT_LOG_DIR -- back-compat alias (the original name; every existing
#      test pin + the live corpus still resolve through it unchanged).
#   3. [ledger].location in .kit.toml (project) / kit.toml (kit-root), via kit-config.sh:
#      "isolated" -> $PWD/.kit/logs; "shared" (or unset/empty) -> the XDG default below;
#      any other value is treated as an explicit path.
#   4. ${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs -- the hardcoded default,
#      outside ~/.claude entirely, so no ~/.claude/dwarves-kit* reinstall can touch it.
# A set-but-EMPTY $KIT_LEDGER_DIR is a FATAL clean error, never a silent fall-through: an
# empty root would make every writer append to a relative `runs/...` path in the caller's cwd
# (the "silent-wrong-path" footgun 's NC guards). Returns 1 so a caller using
# `LOG_DIR="$(kit_resolve_log_dir)" || exit 1` aborts cleanly.
kit_resolve_log_dir() {
  if [ "${KIT_LEDGER_DIR+set}" = "set" ]; then
    if [ -z "$KIT_LEDGER_DIR" ]; then
      echo "kit-log-dir: KIT_LEDGER_DIR is set but empty; refusing to resolve a ledger root (would write to a relative path)" >&2
      return 1
    fi
    printf '%s' "$KIT_LEDGER_DIR"
  elif [ -n "${DWARVES_KIT_LOG_DIR:-}" ]; then
    printf '%s' "$DWARVES_KIT_LOG_DIR"
  else
    local loc; loc="$(kit_config_get ledger.location "shared")"
    case "$loc" in
      isolated) printf '%s' "$PWD/.kit/logs" ;;
      shared|"") printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs" ;;
      *) printf '%s' "$loc" ;;
    esac
  fi
}

kit_legacy_log_dir() { printf '%s' "$HOME/.claude/dwarves-kit/logs"; }

# kit_note_unmigrated: a missed install stays visible. When the legacy default dir still exists and
# the shared durable root has no .migrated sentinel (corpus or hooks/), say so once per process and
# name the fix. Silent when a knob pins the root, when the root is the legacy dir or a per-project
# one, and after kit-migrate.sh ran. It never copies and never fails.
kit_note_unmigrated() {
  [ -n "${_KIT_UNMIGRATED_NOTED:-}" ] && return 0
  [ "${KIT_LEDGER_DIR+set}" = "set" ] && return 0
  [ -n "${DWARVES_KIT_LOG_DIR:-}" ] && return 0
  local legacy durable="${1:-}"
  legacy="$(kit_legacy_log_dir)"
  [ -d "$legacy" ] && [ ! -L "$legacy" ] || return 0
  [ -n "$durable" ] || durable="$(kit_resolve_log_dir 2>/dev/null)" || return 0
  [ "$durable" = "$legacy" ] && return 0
  [ "$durable" = "$PWD/.kit/logs" ] && return 0
  [ -f "$durable/.migrated" ] && [ -f "$durable/hooks/.migrated" ] && return 0
  _KIT_UNMIGRATED_NOTED=1
  echo "kit-log-dir: legacy logs in $legacy were never migrated to $durable; run: bash <kit>/lib/telemetry/kit-migrate.sh (install.sh and adopt do it once)" >&2
  return 0
}

kit_migrate_log_dir() { kit_note_unmigrated; return 0; }
