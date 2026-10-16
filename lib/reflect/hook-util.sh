#!/usr/bin/env bash
# hook-util.sh -- sourced helpers shared by the bash hooks that stage into the backlog funnel
# (intake-sweep, backlog-stage, harvest). Each one stands in for a Python behavior the hooks
# reproduce; tests/test-hook-util.sh pins them. Bash 3.2 safe. No hook state lives here.

# hu_mtime <file>: the file's mtime in epoch seconds, or return 1. GNU stat first: on Linux
# `stat -f %m` is a filesystem query that prints several lines and exits 1, so the BSD form
# comes second and every answer must be all digits.
hu_mtime() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null)
  case "$m" in ''|*[!0-9]*) m=$(stat -f %m "$1" 2>/dev/null) ;; esac
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$m"
}

# hu_int <value> <default>: Python's int() of a plain integer string (blanks and one sign
# allowed), else <default>. A run of more than 18 digits clamps to +/-999999999999999999 so
# bash arithmetic cannot wrap.
hu_int() {
  if [[ "$1" =~ ^[[:space:]]*([+-]?)([0-9]+)[[:space:]]*$ ]]; then
    local d=${BASH_REMATCH[2]} n
    [ "${#d}" -le 18 ] || d=999999999999999999
    n=$((10#$d)); [ "${BASH_REMATCH[1]}" = "-" ] && n=$((0 - n))
    printf '%s' "$n"
  else
    printf '%s' "$2"
  fi
}

# hu_throttled <state-dir> <stamp-name> <interval>: return 0 when the stamp exists and is younger
# than <interval> seconds (skip this run); otherwise create or refresh the stamp and return 1.
# An interval of zero or less turns the throttle off. Bookkeeping errors never throttle.
hu_throttled() {
  local dir=$1 stamp m
  [ "$3" -gt 0 ] || return 1
  stamp="${dir:+$dir/}$2"
  mkdir -p "$dir" 2>/dev/null || return 1
  if [ -f "$stamp" ]; then
    m=$(hu_mtime "$stamp") && [ $(( $(date +%s) - m )) -lt "$3" ] && return 0
  fi
  { : > "$stamp" && touch "$stamp"; } 2>/dev/null
  return 1
}

# hu_join <root> <relative>: os.path.join(root, relative) for a relative path. A trailing slash
# on the root is not doubled.
hu_join() { printf '%s/%s' "${1%/}" "$2"; }

# hu_run_capture <timeout-seconds> <out-file> <command...>: run a command with its stdout to a
# file, stdin from $HU_STDIN when set (else /dev/null), and kill it after the timeout (a
# timeout of zero or less starts it and kills it at once, as subprocess.run does). Returns the
# command's status; a killed command returns non-zero and leaves <out-file>.timedout beside its
# output, because subprocess.run throws a timed-out command's stdout away (callers that keep
# output truncate it). The watchdog and its sleep are reaped.
hu_run_capture() {
  local t=$1 out=$2 pid wd rc kids; shift 2
  [ "$t" -ge 0 ] || t=0
  command rm -f -- "$out.timedout" 2>/dev/null
  if [ -n "${HU_STDIN:-}" ]; then "$@" < "$HU_STDIN" > "$out" 2>/dev/null & else "$@" > "$out" 2>/dev/null & fi
  pid=$!
  ( sleep "$t" 2>/dev/null; kill -9 "$pid" 2>/dev/null && : > "$out.timedout" ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  # SIGKILL, not TERM: a caller that ignores TERM (lib/gate/negctl.sh does, once its restore step runs)
  # passes the disposition to every child, and a TERM the watchdog ignored left this wait running out
  # the whole timeout. The watchdog goes first so it cannot fire on a finished pid; its sleep is reaped after.
  kids=$(pgrep -P "$wd" 2>/dev/null)
  kill -9 "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  [ -z "$kids" ] || kill -9 $kids 2>/dev/null
  return $rc
}

# hu_utf8_ok <file>: return 0 when the file is valid UTF-8 and does not start with a BOM (Python's
# text read raises on invalid UTF-8, and json.loads rejects a BOM).
hu_utf8_ok() {
  [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" != efbbbf ] || return 1
  iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1
}
