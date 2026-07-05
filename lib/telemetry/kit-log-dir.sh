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

# The durable default and precedence (SPEC-182, kit-modularity SG-02): the ledger root is
# ONE root shared by both planes (the write-side append substrate and the read-side `stats`
# projection). Precedence:
#   1. $KIT_LEDGER_DIR   -- the canonical knob (essential-tier config, per-consumer root).
#   2. $DWARVES_KIT_LOG_DIR -- back-compat alias (the pre-SPEC-182 name; every existing
#      test pin + the live corpus still resolve through it unchanged).
#   3. ${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs -- host-generic default,
#      outside ~/.claude entirely, so no ~/.claude/dwarves-kit* reinstall can touch it.
# A set-but-EMPTY $KIT_LEDGER_DIR is a FATAL clean error, never a silent fall-through: an
# empty root would make every writer append to a relative `runs/...` path in the caller's cwd
# (the "silent-wrong-path" footgun SG-02's NC guards). Returns 1 so a caller using
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
  # An explicit root (either knob) means the caller owns the path -- do not migrate the
  # machine corpus into a test's mktemp dir (SPEC-182: KIT_LEDGER_DIR joins the guard).
  [ "${KIT_LEDGER_DIR+set}" = "set" ] && return 0
  [ -n "${DWARVES_KIT_LOG_DIR:-}" ] && return 0
  local durable legacy
  durable="$(kit_resolve_log_dir)"
  legacy="$(kit_legacy_log_dir)"
  [ "$durable" = "$legacy" ] && return 0
  [ -f "$durable/.migrated" ] && return 0
  mkdir -p "$durable" 2>/dev/null || return 0
  if [ -d "$legacy" ] && [ ! -L "$legacy" ]; then
    # -R recursive, -n no-clobber (never overwrite a file already durable). The trailing
    # /. copies contents, not the dir itself. Legacy is never touched.
    # Sentinel is dropped ONLY on cp success (security review S3): a partial/failed copy
    # (perm, disk) leaves NO sentinel so the next access retries and completes.
    if cp -Rn "$legacy/." "$durable/" 2>/dev/null; then
      : > "$durable/.migrated" 2>/dev/null || true
    fi
  elif [ -L "$legacy" ]; then
    # Refuse to migrate THROUGH a symlink (security review B2): cp would dereference it and
    # fan an attacker-planted target's contents into the corpus /kit:retro + the eval read.
    # Warn, and sentinel so we do not re-scan a hostile link every command.
    echo "kit-log-dir: legacy log dir is a symlink; refusing to migrate through it ($legacy)" >&2
    : > "$durable/.migrated" 2>/dev/null || true
  else
    # Fresh install: no legacy dir ever existed. Nothing to migrate; mark done.
    : > "$durable/.migrated" 2>/dev/null || true
  fi
  return 0
}
