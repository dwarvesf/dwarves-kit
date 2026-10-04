#!/usr/bin/env bash
# ledger-key.sh -- the cache-key helpers for the two ledger-verdict caches: lane-telemetry's
# $LOG_DIR/.shipped-incomplete.cache and gate-ledger `check`'s $LOG_DIR/.gate-check.cache.
# One key format, one place. Sourced; prints nothing on load. The caller defines LIB_ROOT (the lib/ dir).
#
#   _lane_fp   -> cksum of the lane data (kit root, operator and project kit.toml, the project's
#                 tracked-and-clean state) and every gate script. A change in any of them drops every
#                 cached verdict.
#   _file_id F -> "<size><TAB><mtime><TAB><inode>" of a ledger file ("" when it cannot be stat'ed).
[ -n "${_LEDGER_KEY_SOURCED:-}" ] && return 0 2>/dev/null || true
_LEDGER_KEY_SOURCED=1

_lane_fp() {
  local pf="${KIT_PROJECT_ROOT:-$PWD}/.kit.toml"
  local op="${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml"
  local clean=0 d; d="$(dirname "$pf")"
  # lane-data.sh honours the project file only when it is tracked and clean against HEAD
  if [ -f "$pf" ] && git -C "$d" ls-files --error-unmatch .kit.toml >/dev/null 2>&1 \
     && git -C "$d" diff --quiet HEAD -- .kit.toml 2>/dev/null; then clean=1; fi
  { cat "$LIB_ROOT/../kit.toml" "$op" "$pf" "$LIB_ROOT"/gate/*.sh "$LIB_ROOT/config/kit-config.sh" 2>/dev/null || true
    echo "clean=$clean"; } | cksum | cut -d' ' -f1
}

# _file_id <file>: "<size><TAB><mtime><TAB><inode>"; GNU stat first (BSD stat rejects -c, GNU stat -f
# means filesystem). The inode catches a same-size, same-second file swapped in place.
_file_id() {
  local o; o="$(stat -c '%s %Y %i' "$1" 2>/dev/null || stat -f '%z %m %i' "$1" 2>/dev/null)" || return 0
  printf '%s' "${o// /$'\t'}"
}
