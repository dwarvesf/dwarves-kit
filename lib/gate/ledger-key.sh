#!/usr/bin/env bash
# ledger-key.sh -- the cache-key helpers for the two ledger-verdict caches: lane-telemetry's
# $LOG_DIR/.shipped-incomplete.cache and gate-ledger `check`'s $LOG_DIR/.gate-check.cache.
# One key format, one place. Sourced; prints nothing on load. The caller defines LIB_ROOT (the lib/ dir).
#
#   _lane_fp   -> cksum of the lane data (kit root, operator and project kit.toml, the project's
#                 tracked-and-clean state) and every gate script. Each file is hashed on its own and
#                 labelled by role, so bytes moved between layers change the result. A change in any
#                 of them drops every cached verdict.
#   _file_id F -> "<size><TAB><mtime><TAB><inode><TAB><ctime>" of a ledger file ("" when it cannot be
#                 stat'ed). ctime is the one timestamp a user cannot set, so a rewrite that restores
#                 size and mtime still moves it.
[ -n "${_LEDGER_KEY_SOURCED:-}" ] && return 0 2>/dev/null || true
_LEDGER_KEY_SOURCED=1

# shellcheck source=lib/config/kit-config.sh
source "${BASH_SOURCE[0]%/*}/../config/kit-config.sh"

_lane_fp() {
  local pf op clean=0 sums at
  pf="$(kit_config_project)"; op="$(kit_config_operator)"
  # lane-data.sh honours the project file only when it is tracked and clean against HEAD
  if [ -f "$pf" ] && kit_config_tracked_clean "$pf"; then clean=1; fi
  # one cksum process, one line per file (crc size path); a missing file has no line
  sums="$(cksum "$LIB_ROOT/../kit.toml" "$op" "$pf" "$LIB_ROOT"/gate/*.sh "$LIB_ROOT/config/kit-config.sh" 2>/dev/null || true)"
  sums="${sums//"$LIB_ROOT/"/}"; sums="${sums//"$op"/operator}"; sums="${sums//"$pf"/project}"
  # A project layer read at a rev (KIT_LANE_PROJECT_AT) is keyed on the committed blob, not the working tree.
  at=""
  if [ -n "${KIT_LANE_PROJECT_AT:-}" ]; then at="$(kit_config_show_at "$(dirname "$pf")" "$KIT_LANE_PROJECT_AT" | cksum)"; fi
  printf '%s\nclean=%s\nat=%s\n' "$sums" "$clean" "$at" | cksum | cut -d' ' -f1
}

# _file_id <file>: "<size><TAB><mtime><TAB><inode><TAB><ctime>"; GNU stat first (BSD stat rejects -c, GNU
# stat -f means filesystem). The inode catches a same-size, same-second file swapped in place.
_file_id() {
  local o; o="$(stat -c '%s %Y %i %Z' "$1" 2>/dev/null || stat -f '%z %m %i %c' "$1" 2>/dev/null)" || return 0
  printf '%s' "${o// /$'\t'}"
}
