#!/usr/bin/env bash
# load-warn.sh -- print ONE warning line when the host is too loaded for a heavy run.
#
#   load-warn.sh [<what>]      <what> names the heavy run in the line (default: "this run")
#
# The 1-minute load average is compared with a threshold: KIT_LOAD_WARN (env), else
# kit.toml [test].load_warn, else 16. Over it, one line goes to stderr suggesting Devin or
# self-hosted CI. This only warns: it never reroutes, never blocks, and the warning mode ALWAYS
# exits 0, so a caller's exit code is never its doing. An unreadable load or a non-numeric threshold prints
# nothing.
#   load-warn.sh --over        silent: exit 0 when the load is over the threshold, 1 when it is not
#                              or cannot be read. For a caller that scales its work down on a loaded host
#                              (bin/test-affected halves its job count); the one place that reads the
#                              threshold, so no caller copies the config lookup.
# Test seam: KIT_LOAD_STUB=<number> replaces the real load average.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_load1() {
  if [ -n "${KIT_LOAD_STUB:-}" ]; then printf '%s' "$KIT_LOAD_STUB"; return; fi
  if [ -r /proc/loadavg ]; then awk '{print $1}' /proc/loadavg; return; fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}' && return
  fi
  uptime 2>/dev/null | sed -n 's/.*load averages*: *\([0-9.]*\).*/\1/p'
}

_threshold() {
  if [ -n "${KIT_LOAD_WARN:-}" ]; then printf '%s' "$KIT_LOAD_WARN"; return; fi
  if [ -r "$DIR/../config/kit-config.sh" ]; then
    # shellcheck source=/dev/null
    . "$DIR/../config/kit-config.sh" 2>/dev/null
    kit_config_get test.load_warn 16 2>/dev/null && return
  fi
  printf '16'
}

# Sets LOAD and LIMIT; returns 0 when the load is over the limit, 1 when it is not or cannot be read.
_over() {
  LOAD="$(_load1 2>/dev/null)"; LIMIT="$(_threshold 2>/dev/null)"
  case "$LOAD" in ''|*[!0-9.]*) return 1 ;; esac
  case "$LIMIT" in ''|*[!0-9.]*) return 1 ;; esac
  awk -v l="$LOAD" -v t="$LIMIT" 'BEGIN { exit !(l + 0 > t + 0) }'
}

main() {
  local what="${1:-this run}"
  _over || return 0
  printf 'load-warn: 1-min load %s is over %s; %s will be slow and flaky here, consider Devin or self-hosted CI (warning only, nothing rerouted)\n' \
    "$LOAD" "$LIMIT" "$what" >&2
  return 0
}

if [ "${1:-}" = "--over" ]; then _over; exit $?; fi
main "$@"
exit 0
