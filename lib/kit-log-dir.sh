#!/usr/bin/env bash
# kit-log-dir.sh -- the single resolver for the kit's durable run-telemetry root (SPEC-097).
#
# WHY: the run corpus that feeds /kit:retro and the SPEC-073 effectiveness eval used to
# default to ~/.claude/dwarves-kit/logs -- INSIDE the plugin state dir, which a plugin
# reinstall recreates (the 2026-07-01 reinstall wiped the whole corpus). This resolver
# moves the default OUT of that blast zone to XDG state, and migrates any legacy corpus
# in additively on first access. Corpus-bearing libs source this instead of hard-coding
# the path, so there is one place the default lives.
#
# Contract (all functions, no output on load, safe under set -euo pipefail):
#   kit_resolve_log_dir   -> the durable log dir ($DWARVES_KIT_LOG_DIR wins if set)
#   kit_legacy_log_dir    -> the pre-SPEC-097 default (~/.claude/dwarves-kit/logs)
#   kit_migrate_log_dir   -> one-time, additive, sentinel-guarded copy legacy -> durable
#
# Idempotent-source guard: sourcing twice is a no-op.
[ -n "${_KIT_LOG_DIR_SOURCED:-}" ] && return 0
_KIT_LOG_DIR_SOURCED=1

# The durable default. $DWARVES_KIT_LOG_DIR always wins (tests, operators). Otherwise
# ${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs -- outside ~/.claude entirely,
# so no ~/.claude/dwarves-kit* reinstall can touch it.
kit_resolve_log_dir() {
  if [ -n "${DWARVES_KIT_LOG_DIR:-}" ]; then
    printf '%s' "$DWARVES_KIT_LOG_DIR"
  else
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs"
  fi
}

kit_legacy_log_dir() { printf '%s' "$HOME/.claude/dwarves-kit/logs"; }

# One-time additive migration. No-ops when:
#   - DWARVES_KIT_LOG_DIR is set (explicit path = caller owns it; this is what stops a
#     test pointing at a temp dir from ingesting the real machine corpus), or
#   - the durable dir == legacy dir (nothing to move), or
#   - the .migrated sentinel already exists (already done).
# Otherwise cp -Rn legacy/. durable/ (no-clobber, never deletes legacy) and drops the
# sentinel. All failures are swallowed: a migration hiccup must never break a tool call.
kit_migrate_log_dir() {
  [ -n "${DWARVES_KIT_LOG_DIR:-}" ] && return 0
  local durable legacy
  durable="$(kit_resolve_log_dir)"
  legacy="$(kit_legacy_log_dir)"
  [ "$durable" = "$legacy" ] && return 0
  [ -f "$durable/.migrated" ] && return 0
  mkdir -p "$durable" 2>/dev/null || return 0
  if [ -d "$legacy" ]; then
    # -R recursive, -n no-clobber (never overwrite a file already durable). The trailing
    # /. copies contents, not the dir itself. Legacy is never touched.
    cp -Rn "$legacy/." "$durable/" 2>/dev/null || true
  fi
  : > "$durable/.migrated" 2>/dev/null || true
  return 0
}
