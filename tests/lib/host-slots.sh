#!/usr/bin/env bash
# host-slots.sh -- a host-wide counting semaphore for test suites. Sourced by the --run-one worker of
# tests/run-all.sh and bin/test-affected, so every suite on the host takes a slot before it runs.
#
#   source tests/lib/host-slots.sh
#   host_slot_acquire [<logfile>]   block until a slot is free, then hold it (pid recorded = $$)
#   host_slot_release               give back the slot THIS shell holds (safe to call twice)
#
# WHY: each runner caps itself at 4 suites (tests/lib/job-count.sh) and cannot see other runners.
# Five sessions started a run each in their own worktree while the load was low: 20 suites ran at
# once, each spawning 100-800 subprocesses, and a 14-core Mac Mini hit load 150. A per-run cap
# cannot bound that; a slot count shared by every run on the host can.
#
# Env:   KIT_TEST_HOST_SLOTS=<n>     slots for the whole host. Default: cores / 2, minimum 2.
#                                    0 disables the gate (acquire returns at once, nothing is created).
#        KIT_TEST_SLOT_DIR=<dir>     where the slots live (default: ${TMPDIR:-/tmp}/dwarves-kit-test-slots).
#                                    Runs share a gate only when they share this dir.
#        KIT_TEST_HOST_SLOT_HELD     set (exported) by acquire. A suite that starts a nested runner
#                                    inherits it, and that nested acquire returns at once: waiting for
#                                    a second slot while holding one could deadlock the whole host.
#
# A slot is the directory <dir>/slot-<i>, taken with an atomic mkdir; the holder writes its pid to
# slot-<i>/pid. A slot whose pid is dead, or that has no pid file and is over 60 s old, is reclaimed
# (under a short per-slot lock, so two reclaimers cannot remove a slot a third just took). A slot
# whose pid is alive is never reclaimed. Waiting polls every 0.5 s with no timeout: the suite's own
# time limit starts only once it runs. Nothing prints while waiting except one line, appended to the
# logfile argument the first time the caller has to wait, so a slow run is explainable.

_hs_cores() {
  if command -v _cores >/dev/null 2>&1; then _cores
  elif command -v nproc >/dev/null 2>&1; then nproc
  elif command -v sysctl >/dev/null 2>&1; then sysctl -n hw.ncpu
  else echo 2
  fi
}

# host_slot_count: the slot count; 0 means the gate is off.
host_slot_count() {
  local n
  case "${KIT_TEST_HOST_SLOTS:-}" in
    ''|*[!0-9]*)
      n=$(( $(_hs_cores) / 2 ))
      [ "$n" -lt 2 ] && n=2
      ;;
    *) n="$KIT_TEST_HOST_SLOTS" ;;
  esac
  printf '%s\n' "$n"
}

# _hs_pid_dead <pid>: 0 when the process is gone. kill -0 alone also fails for another user's live
# process (EPERM), so ps must agree before a slot counts as dead.
_hs_pid_dead() {
  kill -0 "$1" 2>/dev/null && return 1
  ps -p "$1" >/dev/null 2>&1 && return 1
  return 0
}

# _hs_stale <slotdir>: 0 when the slot's holder is gone.
_hs_stale() {
  local pid=""
  [ -f "$1/pid" ] && pid="$(cat "$1/pid" 2>/dev/null)"
  case "$pid" in
    ''|*[!0-9]*)
      # No usable pid: a fresh slot is between mkdir and the pid write. Only an old one is stale.
      [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
      return ;;
  esac
  _hs_pid_dead "$pid"
}

# _hs_reclaim <slotdir>: remove the slot if it is stale. 0 when it was removed (retry the mkdir).
_hs_reclaim() {
  local slot="$1" lock="$1.lock" rc=1
  _hs_stale "$slot" || return 1
  if ! mkdir "$lock" 2>/dev/null; then
    # A reclaimer that died would leave its lock; one over a minute old is that.
    [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
    return 1
  fi
  if _hs_stale "$slot"; then
    rm -f "$slot/pid" 2>/dev/null
    rmdir "$slot" 2>/dev/null && rc=0
  fi
  rmdir "$lock" 2>/dev/null
  return "$rc"
}

HOST_SLOT_HELD=""

host_slot_acquire() {
  local logfile="${1:-}" n dir i noted=0
  [ -n "${KIT_TEST_HOST_SLOT_HELD:-}" ] && return 0
  n="$(host_slot_count)"
  [ "$n" -eq 0 ] && return 0
  dir="${KIT_TEST_SLOT_DIR:-${TMPDIR:-/tmp}/dwarves-kit-test-slots}"
  # A dir that cannot be made means no gate, never a stuck run.
  mkdir -p "$dir" 2>/dev/null || return 0
  while :; do
    i=0
    while [ "$i" -lt "$n" ]; do
      if mkdir "$dir/slot-$i" 2>/dev/null; then
        echo "$$" >"$dir/slot-$i/pid"
        HOST_SLOT_HELD="$dir/slot-$i"
        export KIT_TEST_HOST_SLOT_HELD=1
        return 0
      fi
      # Reclaimed: try the same slot again. Otherwise move on.
      _hs_reclaim "$dir/slot-$i" || i=$((i + 1))
    done
    if [ "$noted" -eq 0 ] && [ -n "$logfile" ]; then
      echo "host-slots: waiting for a free slot (limit $n, dir $dir)" >>"$logfile" 2>/dev/null
    fi
    noted=1
    sleep 0.5
  done
}

# host_slot_release: remove only the slot this shell holds, and only while it still names this pid.
host_slot_release() {
  local slot="$HOST_SLOT_HELD"
  [ -n "$slot" ] || return 0
  HOST_SLOT_HELD=""
  if [ "$(cat "$slot/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "$slot/pid" 2>/dev/null
    rmdir "$slot" 2>/dev/null
  fi
  return 0
}
