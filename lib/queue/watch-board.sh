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
# Rule 4 is the idempotency rule and it deliberately differs from `queue run`'s own
# `done`-only skip: gated-final merge is the DEFAULT posture, so `gated` is the COMMON
# terminal state, and a done-only rule would re-plan every gated row on every run forever
# (SPEC-217 DEC-002). `error`/`stalled`/`skipped` stay re-planned: those are retryable.
#
# Usage:
#   watch-board.sh [--apply] [--max N] [--board <path>] [--repo-root <path>]
#                  [--repo-name <name>] [--journal <path>]
#     --apply            actually enqueue (default is dry-run: print the plan and write it to
#                        <log-dir>/watch-board-plan.tsv for inspection, but open no window)
#     --max N            per-run budget cap, forwarded to `queue run --max-megas N` (default 1)
#     --board PATH       board file (default <repo-root>/_meta/BACKLOG.md)
#     --repo-root PATH   repo the pointers resolve against (default: the cwd's git toplevel)
#     --repo-name NAME   the identity parse-board checks `repo=` against, and the slug prefix
#                        (default: the git COMMON dir's basename, so a worktree run produces the
#                        same slug as a main-checkout run and dedups against the same journal)
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

# The journal path resolver is the queue's, not a second copy (SPEC-097's ONE durable root).
# shellcheck source=lib/telemetry/kit-log-dir.sh
. "$LIB_ROOT/telemetry/kit-log-dir.sh" || true
if ! declare -f kit_resolve_log_dir >/dev/null 2>&1; then
  echo "watch-board: lib/telemetry/kit-log-dir.sh did not load; refusing to guess a journal path" >&2
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
  [ -n "$journal" ]   || journal="$(kit_resolve_log_dir)/queue-journal.tsv"

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
  local plan_file; plan_file="$(kit_resolve_log_dir)/watch-board-plan.tsv"
  mkdir -p "$(dirname "$plan_file")" 2>/dev/null || true
  : > "$plan_file"

  while IFS=$'\t' read -r id repo pointer; do
    [ -n "$id" ] || continue
    case " $auto_ids " in *" $id "*) ;; *) continue ;; esac  # not marked #auto
    seen="$seen $id"
    slug="${repo_name}__${id}"
    verdict="$(_journal_last_verdict "$journal" "$slug")"
    case "$verdict" in
      done|gated)
        _say "[watch] skip $id: already $verdict in the queue journal (slug $slug)"
        skipped=$((skipped + 1))
        continue ;;
    esac
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
