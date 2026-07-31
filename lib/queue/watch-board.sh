#!/usr/bin/env bash
# watch-board.sh -- the backlog watcher (SPEC-217, board row ID-457 gap B).
#
# Scans ONE board (`<repo-root>/_meta/BACKLOG.md`) for `queued` rows the OPERATOR marked
# `#auto`, and hands them to the shipped queue launcher in the TSV contract it already
# consumes (`slug<TAB>repo<TAB>pointer`). It is a FILTER in front of `queue run`, never a
# second queue: pointer confinement, launch policy, retry, and the journal all stay in
# lib/board/parse-board.sh and lib/queue/queue.sh.
#
# NOT a daemon. Run it by hand, or from an external cron the operator owns. Dry-run is the
# DEFAULT; `--apply` is required before any window opens.
#
# A row reaches the plan only if ALL of these hold:
#   1. status leading-keyword is `queued`      (parse-board rows)
#   2. the row text carries `#auto`            (word-bounded: `#automation` does not match)
#   3. it passes parse-board's `queue-rows` allow-list (a `#queue{repo=,pointer=}` token whose
#      charset, repo self-consistency, containment, and existence all check out)
#   4. its slug's LAST queue-journal verdict is not terminal (`done` or `gated`)
#
#   5. no runaway guard is holding it back (SPEC-221: no live heartbeat, not quarantined,
#      past its stall backoff, past its breaker cooldown)
#
# Rule 4 is the idempotency rule and it deliberately differs from `queue run`'s own
# `done`-only skip: gated-final merge is the DEFAULT posture, so `gated` is the COMMON
# terminal state, and a done-only rule would re-plan every gated row on every run forever
# (SPEC-217 DEC-002). `error`/`stalled`/`skipped` stay re-planned: those are retryable.
#
# Rule 5 is what makes rule 4's "retryable" bounded (SPEC-221). Retryable used to mean
# re-planned on EVERY tick with no backoff and no ceiling, so a row that fails identically
# every time opened a fresh `--dangerously-skip-permissions` session every hour, forever.
# This run also REAPS before it plans: a slug whose conductor process died left no journal
# row at all, and `_reap_stale_runs` writes one so the row stops looking un-run.
#
# Usage:
#   watch-board.sh [--apply] [--max N] [--board <path>] [--repo-root <path>]
#                  [--repo-name <name>] [--journal <path>]
#     --apply            actually enqueue (default is dry-run: print the plan and write it to a
#                        fresh <log-dir>/watch-board-plans/plan.XXXXXX, but open no window)
#     --max N            per-run budget cap, forwarded to `queue run --max-megas N` (default 1)
#     --board PATH       board file (default <repo-root>/_meta/BACKLOG.md)
#     --repo-root PATH   repo the pointers resolve against (default: the cwd's git toplevel)
#     --repo-name NAME   the identity parse-board checks `repo=` against, and the slug prefix
#                        (default: the git COMMON dir's basename, so a worktree run produces the
#                        same slug as a main-checkout run and dedups against the same journal).
#                        PIN THIS EXPLICITLY in any cron wiring: the slug is the dedup key, so a
#                        name that changes between runs re-plans an already-terminal row.
#     --journal PATH     queue journal to dedup against (default: the queue's own resolved path)
#
# Exit is 0 for an empty plan: honest-empty is a result, not a failure (same posture as
# `board queue`). A missing board file is also exit 0 with a stderr reason, so a cron never
# pages on a repo that simply has no board.
#
# WATCH_QUEUE_CMD is the mock seam for `--apply` (mirrors queue.sh's MUX_CMD/CLAUDE_CMD
# convention); default is this subsystem's own `queue.sh run`.

set -uo pipefail

WATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$WATCH_DIR/.." && pwd)"
PARSE_BOARD_SH="$LIB_ROOT/board/parse-board.sh"
QUEUE_SH="$WATCH_DIR/queue.sh"

# Source the queue itself (its own header sanctions this: `main` runs only when EXECUTED). Two
# things come from it, neither re-implemented here: the resolved `$QUEUE_JOURNAL` (so an operator
# who moved the journal moves this watcher's dedup with it, SPEC-097's ONE durable root), and
# `_pointer_allowlist_reason`, the realpath/symlink-aware containment check.
#
# That second one matters. `queue run` applies it only to `--from-boards` rows, and the watcher
# hands it a generated TSV, which `queue run` treats as operator-authored and therefore exempt.
# A watcher-planned row is NOT operator-authored: it came from a free-text Notes cell. So the
# watcher applies the hardened pass to its OWN plan, before any window can open. parse-board's
# containment is lexical and does not follow symlinks; this one does (architecture review).
# shellcheck source=lib/queue/queue.sh
. "$QUEUE_SH" || { echo "watch-board: lib/queue/queue.sh did not load" >&2; exit 1; }
if ! declare -f _pointer_allowlist_reason >/dev/null 2>&1 || ! declare -f kit_resolve_log_dir >/dev/null 2>&1; then
  echo "watch-board: lib/queue/queue.sh loaded without its helpers; refusing to run unhardened" >&2
  exit 1
fi

WATCH_QUEUE_CMD="${WATCH_QUEUE_CMD:-bash $QUEUE_SH run}"

_say()  { printf '%s\n' "$*"; }
_warn() { printf '%s\n' "$*" >&2; }

# _repo_name <repo-root> -- the repo's stable identity. `git rev-parse --git-common-dir` points
# at the MAIN checkout's .git even from a linked worktree, so `f457` (a worktree dir) and the
# main checkout both resolve to the same name. Falls back to the root's basename outside git.
_repo_name() {
  local root="$1" common
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)" || { basename "$root"; return; }
  case "$common" in
    /*) ;;
    *) common="$root/$common" ;;
  esac
  basename "$(cd "$common/.." 2>/dev/null && pwd)"
}

# _has_auto <row-text> -- 0 iff the row carries the `#auto` marker as a whole tag. The
# surrounding-character check is what keeps `#automation` / `#auto-merge` out.
_has_auto() {
  printf '%s' "$1" | grep -qE '(^|[^A-Za-z0-9_-])#auto([^A-Za-z0-9_-]|$)'
}

# _journal_last_verdict <journal> <slug> -- the slug's most recent verdict, or "" if it has
# never run. Field-exact (col2=slug, col3=verdict), the same read shape queue.sh's
# _journal_has_done uses, so a slug named inside another row's free-text reason never matches.
_journal_last_verdict() {
  local journal="$1" slug="$2"
  [ -f "$journal" ] || return 0
  awk -F'\t' -v s="$slug" '$2==s {v=$3} END{if(v!="") print v}' "$journal"
}

# ---- the stale-window reaper (SPEC-221) --------------------------------------------------------
# The tick IS the reaper. No daemon: this runs inside the watcher run the operator already invokes,
# BEFORE any planning, so a slug whose conductor died gets its verdict before it is reconsidered.
#
# Three ages, one beat file:
#   fresh (< STALE)        a conductor is alive and driving this slug. Leave it entirely alone.
#   stale (STALE .. DEAD)  the conductor is presumed gone but not confirmed. WARN, write nothing.
#                          The donor frees a claim here; this kit has no claim registry to free,
#                          and killing the window at 10 minutes would destroy a run whose conductor
#                          is merely paused (SPEC-221 DEC-002).
#   dead  (>= DEAD)        confirmed gone. Write the verdict, schedule the retry, clear the beat.
_reap_stale_runs() {  # journal
  local journal="$1" rundir beat slug age sig reason verdict stalls
  rundir="$(_run_dir)"
  [ -d "$rundir" ] || return 0
  for beat in "$rundir"/*.beat; do
    [ -f "$beat" ] || continue
    slug="$(basename "$beat" .beat)"
    age="$(_age "$beat")" || continue

    if [ "$age" -lt "$QUEUE_BEAT_STALE_SECS" ]; then
      continue
    fi
    if [ "$age" -lt "$QUEUE_BEAT_DEAD_SECS" ]; then
      _warn "[watch] orphan: $slug has no conductor heartbeat for ${age}s (not yet dead at ${QUEUE_BEAT_DEAD_SECS}s); not planning it."
      continue
    fi

    # Honor a finished run. A run can write its explicit completion and THEN lose its conductor;
    # relabelling that `stalled` would throw away real, finished work.
    sig="$(_exit_signal "$slug")"
    reason=""
    if [ "$sig" = true ]; then
      reason="$(_status_get "$slug" REASON)"
      if [ -n "$reason" ]; then verdict="gated"; else verdict="done"; fi
      _guard_clear "$slug"
    else
      verdict=stalled
      reason="conductor heartbeat dead for ${age}s"
      # The stall ladder ALWAYS climbs here. The reaper does not know which repo this slug ran
      # against, so it can never obtain `verified` evidence, and a self-report is not allowed to
      # clear the ladder (security review, HIGH): a run that writes `FILES_CHANGED: 1` on every
      # attempt would otherwise be permanently exempt from quarantine, which is the one promise
      # this guard exists to keep.
      stalls=$(( $(_guard_num "$slug" stalls) + 1 ))
      _guard_set "$slug" stalls "$stalls"
      _schedule_retry "$slug" "$stalls"
      [ "$stalls" -ge "$QUEUE_MAX_STALLS" ] && reason="$reason; quarantined after $stalls stalls"
    fi

    _journal_append "$slug" "$verdict" "$reason"
    _mux_kill "$slug"          # the orphan window, if tmux still holds one
    _beat_clear "$slug"
    _say "[watch] reaped $slug: $verdict ($reason)"
  done
}

# _guard_skip_reason <slug> -- why this slug must not be planned right now, or "" to allow it.
# The single re-pick gate. Every runaway guard converges here, which is why SPEC-221 DEC-005
# declined a separate transition table: a second copy of these rules could disagree with this one.
_guard_skip_reason() {  # slug
  local slug="$1" beat retry cooldown now stalls
  now=$(date +%s)

  # An in-flight claim. Presence, not age: the reaper above already converted every dead beat, so
  # a beat still here means a conductor that is alive or only recently silent. Either way a second
  # window for the same slug is the thing to prevent.
  beat=$(_run_file "$slug" beat 2>/dev/null) || { printf 'slug is not a legal identifier'; return; }
  if [ -f "$beat" ]; then printf 'a run is in flight (heartbeat present)'; return; fi

  stalls=$(_guard_num "$slug" stalls)
  retry=$(_guard_get "$slug" retry_after)
  if [ "$stalls" -ge "$QUEUE_MAX_STALLS" ] && [ -z "$retry" ]; then
    printf 'quarantined after %s stalls (clear %s to re-enable)' "$stalls" "$(_run_dir)/$slug.guard"
    return
  fi
  case "$retry" in
    ''|*[!0-9]*) ;;
    *) [ "$now" -lt "$retry" ] && { printf 'backing off until %s' "$retry"; return; } ;;
  esac
  cooldown=$(_guard_get "$slug" cooldown_until)
  case "$cooldown" in
    ''|*[!0-9]*) ;;
    *) [ "$now" -lt "$cooldown" ] && { printf 'breaker cooldown until %s' "$cooldown"; return; } ;;
  esac
}

cmd_watch() {
  local apply=0 max=1 board="" repo_root="" repo_name="" journal=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)     apply=1; shift ;;
      --max)       max="${2:-1}"; shift 2 ;;
      --board)     board="${2:-}"; shift 2 ;;
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --repo-name) repo_name="${2:-}"; shift 2 ;;
      --journal)   journal="${2:-}"; shift 2 ;;
      -h|--help)   usage; return 0 ;;
      *)           _warn "watch-board: unknown flag '$1'"; return 64 ;;
    esac
  done

  [ -n "$repo_root" ] || repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  [ -n "$board" ]     || board="$repo_root/_meta/BACKLOG.md"
  [ -n "$repo_name" ] || repo_name="$(_repo_name "$repo_root")"
  # QUEUE_JOURNAL is queue.sh's own resolved value (sourced above), so an operator who moved the
  # journal moves this watcher's dedup with it instead of silently splitting the two.
  [ -n "$journal" ]   || journal="$QUEUE_JOURNAL"
  # queue.sh's helpers (_journal_append, _reap_stale_runs) all write through the GLOBAL, so point
  # it at the resolved journal once rather than threading it through every call site.
  QUEUE_JOURNAL="$journal"

  # SPEC-221: reap dead runs BEFORE planning, so a slug whose conductor died gets its verdict in
  # the same tick that reconsiders it. Runs even when the board is missing: the runs that need
  # reaping are already launched, and a repo losing its board must not strand them.
  _reap_stale_runs "$journal"

  if [ ! -f "$board" ]; then
    _warn "watch-board: no board at $board (nothing to watch)"
    _say "[watch] 0 rows to enqueue."
    return 0
  fi

  # Leg 1: which queued rows carry the marker. Leg 2: which queued rows have an allow-listed,
  # existing pointer. A row is planned only where the two legs agree, so the marker can never
  # widen what parse-board is willing to emit.
  local auto_ids=""
  while IFS=$'\t' read -r id status line; do
    [ -n "$id" ] || continue
    [ "$status" = "queued" ] || continue
    _has_auto "$line" || continue
    auto_ids="$auto_ids $id"
  done < <(bash "$PARSE_BOARD_SH" rows "$board" 2>/dev/null)

  local planned=0 skipped=0 id repo pointer slug verdict seen=""
  # Per-run plan file, never a fixed path: two overlapping runs would otherwise interleave
  # truncate-and-write on the same file (the queue waits up to QUEUE_TIMEOUT_SECS per row, so
  # overlap is realistic). mktemp is the pattern the rest of this repo already uses for scratch
  # (security review). The path is printed so the operator can inspect what would be enqueued.
  local plan_dir; plan_dir="$(kit_resolve_log_dir)/watch-board-plans"
  mkdir -p "$plan_dir" 2>/dev/null || true
  local plan_file; plan_file="$(mktemp "$plan_dir/plan.XXXXXX")" || {
    _warn "watch-board: could not create a plan file under $plan_dir"; return 1; }

  while IFS=$'\t' read -r id repo pointer; do
    [ -n "$id" ] || continue
    case " $auto_ids " in *" $id "*) ;; *) continue ;; esac  # not marked #auto
    seen="$seen $id"
    # The hardened, symlink-aware containment pass (see the sourcing note at the top). A symlink
    # planted INSIDE an allow-listed dir but pointing outside the repo passes parse-board's lexical
    # check and fails here.
    local hard; hard="$(_pointer_allowlist_reason "$repo" "$pointer")"
    if [ -n "$hard" ]; then
      _say "[watch] skip $id: $hard"
      skipped=$((skipped + 1))
      continue
    fi
    slug="${repo_name}__${id}"
    verdict="$(_journal_last_verdict "$journal" "$slug")"
    case "$verdict" in
      done|gated)
        _say "[watch] skip $id: already $verdict in the queue journal (slug $slug)"
        skipped=$((skipped + 1))
        continue ;;
    esac
    # SPEC-221's re-pick gate: in-flight claim, quarantine, stall backoff, breaker cooldown. Runs
    # AFTER the terminal-verdict rule above, so a `done` row is still skipped for the shipped
    # reason rather than for a timer.
    local gr; gr="$(_guard_skip_reason "$slug")"
    if [ -n "$gr" ]; then
      _say "[watch] skip $id: $gr (slug $slug)"
      skipped=$((skipped + 1))
      continue
    fi
    printf '%s\t%s\t%s\n' "$slug" "$repo" "$pointer" >> "$plan_file"
    _say "[watch] $id -> ${pointer#"$repo"/} (slug $slug)"
    planned=$((planned + 1))
  done < <(bash "$PARSE_BOARD_SH" queue-rows "$board" "$repo_name" "$repo_root" 2>/dev/null)

  # An #auto row parse-board refused (no pointer token, bad charset, dangling pointer) is
  # reported here rather than silently dropped: the operator marked it, so its absence from
  # the plan is news.
  local aid
  for aid in $auto_ids; do
    case " $seen " in *" $aid "*) continue ;; esac
    _say "[watch] skip $aid: marked #auto but not queue-eligible (no allow-listed #queue{} pointer)"
    skipped=$((skipped + 1))
  done

  if [ "$planned" -eq 0 ]; then
    _say "[watch] 0 rows to enqueue ($skipped skipped)."
    return 0
  fi

  if [ "$apply" -eq 0 ]; then
    _say "[watch] plan written to $plan_file"
    _say "[watch] $planned row(s) to enqueue, $skipped skipped. Dry-run: re-run with --apply (cap --max $max)."
    return 0
  fi

  _say "[watch] applying: $planned row(s), cap $max."
  # shellcheck disable=SC2086 # WATCH_QUEUE_CMD is operator config (the mock seam); split intended.
  $WATCH_QUEUE_CMD "$plan_file" --max-megas "$max"
}

usage() { sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  case "${1:-}" in
    ""|--*|-h) cmd_watch "$@" ;;
    watch)     shift; cmd_watch "$@" ;;
    *)         _warn "watch-board: unknown subcommand '$1'"; usage >&2; return 64 ;;
  esac
}

# Run main only when executed, not when sourced (tests source + call helpers directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
