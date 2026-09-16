#!/usr/bin/env bash
# attempt-state.sh -- the dispatch Attempt state machine.
#
# A dead or disconnected subagent is an UNKNOWN OUTCOME, not a failure. The kit
# used to read worker silence as FAILED and re-dispatch, which is how a resumed
# agent and its replacement could both land the same work on the same branch
# (memory note: resume-a-dead-subagent-never-respawn-on-its-branch).
#
# The fix is structural, one state per grain:
#
#   TaskState    -- what the TASK is doing. One per task.
#   AttemptState -- what one TRY is doing. Many per task.
#
# A disconnect moves the ATTEMPT to `disconnected` and starts a grace window.
# The TASK stays `dispatched` the whole time, so nothing re-dispatches it. If
# the worker comes back inside the window (SendMessage resume), the attempt
# returns to `running` and no second dispatch ever happened. Only when the
# window expires does `lose-attempt` mark the attempt `lost`, exclude that
# worker, and free the task back to `queued`.
#
# Commit semantics: at-least-once execution, exactly-once result commit.
# `commit-result` is idempotent on the TASK id, not the attempt id: the first
# attempt to commit wins, every later one reports the winner and is recorded
# `superseded`. That is what makes a resume and a replacement safe to race.
#
# Store: $(git rev-parse --git-common-dir)/kit-attempts/<task>.task -- the same
# .git-backed convention goal-registry.sh uses, so a lead reads both in one
# place. Override with ATTEMPT_REGISTRY_DIR for tests.
#
# Subcommands:
#   dispatch <task> <worker> [attempt-id]     create the next attempt
#   mark-disconnected <task> [attempt] [--grace N]   start the grace window
#   resume <task> [attempt]                   the worker came back inside the window
#   lose-attempt <task> [attempt]             only after the window expires
#   commit-result <task> <attempt> <ref>      idempotent on <task>
#   abandon <task> <reason>                   no worker left to try; task -> lost
#   status <task>                             state, attempts, grace remaining
#   list                                      one line per tracked task
#   release <task>                            drop the task's record
#   dir                                       print the resolved store root

set -euo pipefail

# The grace window a disconnected attempt gets before it may be declared lost.
# One default, one flag (--grace), never a constant repeated at a call site.
ATTEMPT_GRACE_DEFAULT_SECONDS=120

# --- clock ------------------------------------------------------------------

# ATTEMPT_NOW pins the clock so grace expiry is testable without sleeping.
_now() { printf '%s\n' "${ATTEMPT_NOW:-$(date +%s)}"; }

# --- legal transitions ------------------------------------------------------
#
# Anything absent is refused. An unexpected transition means two code paths
# disagree about who owns the task, which is the duplicate-work bug itself.

_TASK_TRANSITIONS='queued>dispatched
dispatched>queued
dispatched>done
dispatched>lost
queued>lost'

_ATTEMPT_TRANSITIONS='running>disconnected
running>committed
running>superseded
disconnected>running
disconnected>committed
disconnected>lost
disconnected>superseded'

_legal() {  # <table> <from> <to>
  printf '%s\n' "$1" | grep -qx "$2>$3"
}

_task_goto() {  # <to> -- mutates T_STATE, refuses an illegal move
  if [ "$T_STATE" = "$1" ]; then return 0; fi
  if ! _legal "$_TASK_TRANSITIONS" "$T_STATE" "$1"; then
    echo "attempt-state: illegal task transition $T_STATE -> $1" >&2
    return 1
  fi
  T_STATE="$1"
}

_attempt_goto() {  # <index> <to> -- mutates ATTEMPTS[i], refuses an illegal move
  local i="$1" to="$2" from
  from="$(_field "${ATTEMPTS[$i]}" 3)"
  if [ "$from" = "$to" ]; then return 0; fi
  if ! _legal "$_ATTEMPT_TRANSITIONS" "$from" "$to"; then
    echo "attempt-state: illegal attempt transition $from -> $to" >&2
    return 1
  fi
  ATTEMPTS[$i]="$(_field "${ATTEMPTS[$i]}" 1)|$(_field "${ATTEMPTS[$i]}" 2)|$to|$(_field "${ATTEMPTS[$i]}" 4)"
}

# --- store ------------------------------------------------------------------

registry_dir() {
  if [ -n "${ATTEMPT_REGISTRY_DIR:-}" ]; then
    printf '%s\n' "$ATTEMPT_REGISTRY_DIR"
    return 0
  fi
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
    echo "attempt-state: not a git repository (the store lives under .git)" >&2
    return 3
  }
  case "$common" in
    /*) : ;;
    *)  common="$(cd "$common" && pwd)" ;;
  esac
  printf '%s/kit-attempts\n' "$common"
}

# A task id names a single file; a slash would split the store.
_check_id() {  # <id> <what>
  case "$1" in
    ""|*/*|*..*|*'|'*|*[[:space:]]*)
      echo "attempt-state: invalid $2 '$1' (no slashes, traversal, pipes, or whitespace)" >&2
      return 64;;
  esac
  return 0
}

_field() {  # <pipe-record> <n>
  printf '%s\n' "$1" | cut -d'|' -f"$2"
}

# Load <task> into T_STATE / T_RESULT / T_WINNER / T_EXCLUDED / ATTEMPTS[].
# Returns 1 when the task is unknown, so callers choose create-or-refuse.
_load() {  # <task>
  local file line
  file="$(registry_dir)/$1.task"
  T_TASK="$1"; T_STATE=queued; T_RESULT=""; T_WINNER=""; T_EXCLUDED=""
  ATTEMPTS=()
  [ -f "$file" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      state=*)     T_STATE="${line#state=}" ;;
      result_ref=*) T_RESULT="${line#result_ref=}" ;;
      winner=*)    T_WINNER="${line#winner=}" ;;
      excluded=*)  T_EXCLUDED="${line#excluded=}" ;;
      attempt\|*)  ATTEMPTS+=("${line#attempt|}") ;;
    esac
  done < "$file"
  return 0
}

_save() {
  local dir file tmp a
  dir="$(registry_dir)"; mkdir -p "$dir"
  file="$dir/$T_TASK.task"; tmp="$file.tmp.$$"
  {
    printf 'task=%s\n' "$T_TASK"
    printf 'state=%s\n' "$T_STATE"
    printf 'result_ref=%s\n' "$T_RESULT"
    printf 'winner=%s\n' "$T_WINNER"
    printf 'excluded=%s\n' "$T_EXCLUDED"
    if [ "${#ATTEMPTS[@]}" -gt 0 ]; then
      for a in "${ATTEMPTS[@]}"; do printf 'attempt|%s\n' "$a"; done
    fi
  } > "$tmp"
  mv "$tmp" "$file"
}

# Index of the attempt whose id is $1, or empty.
_index_of() {  # <attempt-id>
  local i
  [ "${#ATTEMPTS[@]}" -gt 0 ] || return 0
  for i in "${!ATTEMPTS[@]}"; do
    if [ "$(_field "${ATTEMPTS[$i]}" 1)" = "$1" ]; then printf '%s\n' "$i"; return 0; fi
  done
  return 0
}

# Index of the one live attempt (running or disconnected), or empty. Only one
# attempt may be live at a time, so this is what lets the verbs default.
_index_live() {
  local i s
  [ "${#ATTEMPTS[@]}" -gt 0 ] || return 0
  for i in "${!ATTEMPTS[@]}"; do
    s="$(_field "${ATTEMPTS[$i]}" 3)"
    if [ "$s" = running ] || [ "$s" = disconnected ]; then printf '%s\n' "$i"; return 0; fi
  done
  return 0
}

# Resolve the target attempt: the named one, else the live one. Sets IDX.
_target() {  # <task> [attempt-id]
  if [ -n "${2:-}" ]; then
    IDX="$(_index_of "$2")"
    [ -n "$IDX" ] || { echo "attempt-state: unknown attempt '$2' on task '$1'" >&2; return 1; }
  else
    IDX="$(_index_live)"
    [ -n "$IDX" ] || { echo "attempt-state: task '$1' has no live attempt; name one explicitly" >&2; return 1; }
  fi
  return 0
}

_excluded() {  # <worker>
  case " $T_EXCLUDED " in *" $1 "*) return 0;; esac
  return 1
}

# --- subcommands ------------------------------------------------------------

as_dispatch() {  # <task> <worker> [attempt-id]
  local task="${1:-}" worker="${2:-}" aid="${3:-}"
  [ -n "$task" ] && [ -n "$worker" ] || { echo "usage: attempt-state dispatch <task> <worker> [attempt-id]" >&2; return 64; }
  _check_id "$task" "task id" || return $?
  _check_id "$worker" "worker id" || return $?
  _load "$task" || true
  if _excluded "$worker"; then
    echo "REFUSED: worker '$worker' is excluded from task '$task' (a prior attempt was lost on it)" >&2
    return 1
  fi
  local live; live="$(_index_live)"
  if [ -n "$live" ]; then
    echo "REFUSED: task '$task' already has a live attempt '$(_field "${ATTEMPTS[$live]}" 1)' ($(_field "${ATTEMPTS[$live]}" 3)). Resume or lose it first; never dispatch a second." >&2
    return 1
  fi
  [ -n "$aid" ] || aid="a$(( ${#ATTEMPTS[@]} + 1 ))"
  _check_id "$aid" "attempt id" || return $?
  [ -z "$(_index_of "$aid")" ] || { echo "attempt-state: attempt '$aid' already exists on task '$task'" >&2; return 1; }
  _task_goto dispatched || return 1
  ATTEMPTS+=("$aid|$worker|running|")
  _save
  echo "DISPATCHED $task attempt=$aid worker=$worker"
}

as_mark_disconnected() {  # <task> [attempt] [--grace N]
  local task="" aid="" grace="$ATTEMPT_GRACE_DEFAULT_SECONDS"
  while [ $# -gt 0 ]; do
    case "$1" in
      --grace) grace="${2:-}"; shift 2 || true ;;
      --grace=*) grace="${1#--grace=}"; shift ;;
      *) if [ -z "$task" ]; then task="$1"; else aid="$1"; fi; shift ;;
    esac
  done
  [ -n "$task" ] || { echo "usage: attempt-state mark-disconnected <task> [attempt] [--grace N]" >&2; return 64; }
  case "$grace" in ''|*[!0-9]*) echo "attempt-state: --grace wants whole seconds, got '$grace'" >&2; return 64;; esac
  _load "$task" || { echo "attempt-state: unknown task '$task'" >&2; return 1; }
  _target "$task" "$aid" || return 1
  _attempt_goto "$IDX" disconnected || return 1
  local until; until=$(( $(_now) + grace ))
  ATTEMPTS[$IDX]="$(_field "${ATTEMPTS[$IDX]}" 1)|$(_field "${ATTEMPTS[$IDX]}" 2)|disconnected|$until"
  _save
  echo "DISCONNECTED $task attempt=$(_field "${ATTEMPTS[$IDX]}" 1) grace=${grace}s until=$until (task stays $T_STATE; do NOT dispatch a replacement)"
}

as_resume() {  # <task> [attempt]
  local task="${1:-}" aid="${2:-}"
  [ -n "$task" ] || { echo "usage: attempt-state resume <task> [attempt]" >&2; return 64; }
  _load "$task" || { echo "attempt-state: unknown task '$task'" >&2; return 1; }
  _target "$task" "$aid" || return 1
  _attempt_goto "$IDX" running || return 1
  # Clear the window: the worker proved it is alive.
  ATTEMPTS[$IDX]="$(_field "${ATTEMPTS[$IDX]}" 1)|$(_field "${ATTEMPTS[$IDX]}" 2)|running|"
  _save
  echo "RESUMED $task attempt=$(_field "${ATTEMPTS[$IDX]}" 1)"
}

as_lose_attempt() {  # <task> [attempt]
  local task="${1:-}" aid="${2:-}"
  [ -n "$task" ] || { echo "usage: attempt-state lose-attempt <task> [attempt]" >&2; return 64; }
  _load "$task" || { echo "attempt-state: unknown task '$task'" >&2; return 1; }
  _target "$task" "$aid" || return 1
  local state until now
  state="$(_field "${ATTEMPTS[$IDX]}" 3)"
  until="$(_field "${ATTEMPTS[$IDX]}" 4)"
  if [ "$state" != disconnected ]; then
    echo "REFUSED: attempt '$(_field "${ATTEMPTS[$IDX]}" 1)' is $state, not disconnected. Only a disconnected attempt can be lost." >&2
    return 1
  fi
  now="$(_now)"
  if [ -n "$until" ] && [ "$now" -le "$until" ]; then
    echo "REFUSED: grace window has $(( until - now ))s left on attempt '$(_field "${ATTEMPTS[$IDX]}" 1)'. Resume it, or wait." >&2
    return 1
  fi
  local worker; worker="$(_field "${ATTEMPTS[$IDX]}" 2)"
  _attempt_goto "$IDX" lost || return 1
  _excluded "$worker" || T_EXCLUDED="${T_EXCLUDED:+$T_EXCLUDED }$worker"
  _task_goto queued || return 1
  _save
  echo "LOST $task attempt=$(_field "${ATTEMPTS[$IDX]}" 1) worker=$worker excluded; task freed to queued"
}

as_commit_result() {  # <task> <attempt> <result-ref>
  local task="${1:-}" aid="${2:-}" ref="${3:-}"
  [ -n "$task" ] && [ -n "$aid" ] || { echo "usage: attempt-state commit-result <task> <attempt> <result-ref>" >&2; return 64; }
  _load "$task" || { echo "attempt-state: unknown task '$task'" >&2; return 1; }
  local idx; idx="$(_index_of "$aid")"
  [ -n "$idx" ] || { echo "attempt-state: unknown attempt '$aid' on task '$task'" >&2; return 1; }

  # Idempotent on the TASK: the first commit wins, every later one is a no-op
  # that names the winner. This is what lets a resumed agent and a replacement
  # both report without both landing.
  if [ "$T_STATE" = done ]; then
    if [ "$(_field "${ATTEMPTS[$idx]}" 3)" != committed ]; then
      _attempt_goto "$idx" superseded || return 1
      _save
    fi
    echo "NOOP $task already committed by attempt=$T_WINNER (ref=$T_RESULT); attempt=$aid superseded"
    return 0
  fi

  _attempt_goto "$idx" committed || return 1
  T_WINNER="$aid"; T_RESULT="$ref"
  _task_goto done || return 1
  # Any sibling still live lost the race.
  local i s
  for i in "${!ATTEMPTS[@]}"; do
    if [ "$i" = "$idx" ]; then continue; fi
    s="$(_field "${ATTEMPTS[$i]}" 3)"
    if [ "$s" = running ] || [ "$s" = disconnected ]; then _attempt_goto "$i" superseded || return 1; fi
  done
  _save
  echo "COMMITTED $task attempt=$aid ref=$ref"
}

as_abandon() {  # <task> <reason>
  local task="${1:-}"; shift 2>/dev/null || true
  local reason="$*"
  [ -n "$task" ] && [ -n "$reason" ] || { echo "usage: attempt-state abandon <task> <reason>" >&2; return 64; }
  _load "$task" || { echo "attempt-state: unknown task '$task'" >&2; return 1; }
  _task_goto lost || return 1
  _save
  echo "ABANDONED $task ($reason)"
}

as_status() {  # <task>
  local task="${1:-}"
  [ -n "$task" ] || { echo "usage: attempt-state status <task>" >&2; return 64; }
  _load "$task" || { echo "attempt-state: unknown task '$task'" >&2; return 1; }
  printf 'task=%s state=%s\n' "$T_TASK" "$T_STATE"
  if [ -n "$T_WINNER" ]; then printf 'winner=%s ref=%s\n' "$T_WINNER" "$T_RESULT"; fi
  if [ -n "$T_EXCLUDED" ]; then printf 'excluded=%s\n' "$T_EXCLUDED"; fi
  local a now left; now="$(_now)"
  [ "${#ATTEMPTS[@]}" -gt 0 ] || return 0
  for a in "${ATTEMPTS[@]}"; do
    left=""
    if [ "$(_field "$a" 3)" = disconnected ] && [ -n "$(_field "$a" 4)" ]; then
      left=$(( $(_field "$a" 4) - now ))
      if [ "$left" -le 0 ]; then left=" grace=expired"; else left=" grace=${left}s"; fi
    fi
    printf 'attempt=%s worker=%s state=%s%s\n' "$(_field "$a" 1)" "$(_field "$a" 2)" "$(_field "$a" 3)" "$left"
  done
}

as_list() {
  local dir f; dir="$(registry_dir)" || return $?
  shopt -s nullglob
  local files=("$dir"/*.task)
  if [ "${#files[@]}" -eq 0 ]; then echo "(no tracked tasks)"; return 0; fi
  printf '%-24s %-11s %s\n' TASK STATE ATTEMPTS
  for f in "${files[@]}"; do
    _load "$(basename "$f" .task)" || continue
    printf '%-24s %-11s %s\n' "$T_TASK" "$T_STATE" "${#ATTEMPTS[@]}"
  done
}

as_release() {  # <task>
  local task="${1:-}"
  [ -n "$task" ] || { echo "usage: attempt-state release <task>" >&2; return 64; }
  _check_id "$task" "task id" || return $?
  rm -f "$(registry_dir)/$task.task"
  echo "RELEASED $task"
}

# --- dispatch ---------------------------------------------------------------

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    dispatch)                             as_dispatch "$@";;
    mark-disconnected|mark_disconnected)  as_mark_disconnected "$@";;
    resume)                               as_resume "$@";;
    lose-attempt|lose_attempt)            as_lose_attempt "$@";;
    commit-result|commit_result)          as_commit_result "$@";;
    abandon)                              as_abandon "$@";;
    status)                               as_status "$@";;
    list)                                 as_list "$@";;
    release)                              as_release "$@";;
    dir)                                  registry_dir;;
    *) echo "usage: attempt-state.sh {dispatch|mark-disconnected|resume|lose-attempt|commit-result|abandon|status|list|release|dir} ..." >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
