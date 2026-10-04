#!/usr/bin/env bash
# run-lock.sh -- one heavy kit test run at a time per user on this host.
#
# Several Claude sessions on one machine run the git-heavy suites at once; load average hit
# 40-57 on 14 cores and each run took 2-4x longer. Queueing the runs makes each one quiet-speed.
#
# Usage (top of a top-level runner, before it does any work):
#   source "$KIT_DIR/tests/lib/run-lock.sh"; run_lock_exec "$KIT_DIR/tests/<this>.sh" "$@"
# The helper re-runs the script as a child under the lock, then exits with the child's status.
# A re-exec (not an EXIT trap) because the runners install their own EXIT/INT/TERM traps.
#
# Env: KIT_TEST_LOCK=0         off (CI also turns it off)
#      KIT_TEST_LOCK_HELD      set by the holder; nested runners skip locking
#      KIT_TEST_LOCK_DIR       lock path (default /tmp/dwarves-kit-test-lock.<uid>)
#      KIT_TEST_LOCK_WAIT=<s>  give up after this long and run anyway (default 1800)
#      KIT_TEST_LOCK_POLL=<s>  poll interval (default 2)
# bash 3.2 compatible: mkdir is the atomic primitive, macOS has no flock.

_rl_info() { sed -n "$1p" "$_RL_DIR/info" 2>/dev/null; } # 1=pid 2=command 3=start time

_rl_release() { # only the owner removes the lock
  [ "$(_rl_info 1)" = "$$" ] && rm -rf "$_RL_DIR"
  return 0
}

run_lock_exec() { # run_lock_exec <script> [args...]; returns 0 to run inline, else exits
  [ "${KIT_TEST_LOCK:-1}" = "0" ] && return 0
  [ -n "${CI:-}" ] && return 0
  [ -n "${KIT_TEST_LOCK_HELD:-}" ] && return 0
  local script="$1"; shift
  local max="${KIT_TEST_LOCK_WAIT:-1800}" poll="${KIT_TEST_LOCK_POLL:-2}"
  local waited=0 next_note=0 pid
  _RL_DIR="${KIT_TEST_LOCK_DIR:-/tmp/dwarves-kit-test-lock.$(id -u)}"
  while ! mkdir "$_RL_DIR" 2>/dev/null; do
    pid="$(_rl_info 1)"
    # ponytail: a pid recycled by an unrelated process reads as alive, and the mv takeover
    # can race a third taker; both end at the give-up timeout, never a failed run.
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null \
       && mv "$_RL_DIR" "$_RL_DIR.stale.$$" 2>/dev/null; then
      rm -rf "$_RL_DIR.stale.$$"; continue
    fi
    if [ "$waited" -ge "$max" ]; then
      echo "run-lock: waited ${waited}s for the test lock, running anyway" >&2; return 0
    fi
    if [ "$waited" -ge "$next_note" ]; then
      echo "waiting for test lock held by pid ${pid:-?}: $(_rl_info 2) (since $(_rl_info 3))" >&2
      next_note=$((waited + 60))
    fi
    sleep "$poll"; waited=$((waited + poll))
  done
  printf '%s\n%s\n%s\n' "$$" "$script $*" "$(date '+%F %T')" >"$_RL_DIR/info"
  export KIT_TEST_LOCK_HELD=1
  local child
  trap '_rl_release' EXIT
  bash "$script" "$@" <&0 &
  child=$!
  trap 'kill -TERM "$child" 2>/dev/null' INT TERM
  local rc
  wait "$child"; rc=$?
  if kill -0 "$child" 2>/dev/null; then wait "$child"; rc=$?; fi # a trapped signal cut the first wait short
  exit "$rc"
}
