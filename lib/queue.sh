#!/usr/bin/env bash
# queue.sh -- the overnight queue LAUNCHER (runner-fastpath sub-goal 03K, SPEC-146).
#
# For each queued+tokened backlog mega, it opens a REAL interactive Claude Code `/goal` session
# in a fresh terminal-mux window and DRIVES it via scripting-control (types `/goal ` + the pointer
# prompt + Enter), monitors that window's output to completion, then launches the next. It runs on
# the operator's LIVE logged-in session, NOT a headless `claude -p` -- this sidesteps the
# AUTH/KILL-CLASS risk of a headless worker's token expiring / being killed independently
# (field-proven twice; ops-toolkit _meta/megagoals/OPERATE.md).
#
# It is a dumb (non-LLM) scheduler. Completion is detected by READING the launched session's
# output marker (`^RUNNER_DONE$` / `^RUNNER_GATED:`), line-anchored, never a fixed sleep. Every
# launch + exit lands a journal row. Two consecutive `error` megas STOP THE NIGHT.
#
# Usage:
#   queue.sh run <src.tsv> [--dry-run] [--max-megas N] [--from-boards] [--journal <path>]
#     <src.tsv>       rows: slug<TAB>repo-path<TAB>pointer-path (# comments + blanks skipped)
#     --from-boards   read rows from `$QUEUE_BOARD_CMD queue` stdout instead of <src.tsv>
#                     (sub-goal 04's emit; same row contract; <src.tsv> then optional/ignored)
#     --dry-run       list which megas WOULD launch (preflight only; NO send-keys, no journal run)
#     --max-megas N   stop after N launch attempts this run
#     --journal PATH  override the journal file
#
# The mux + the interactive claude are CONSUMER config (nothing personal is hardcoded):
#   TERMINAL_MUX=tmux|cmux   which mux to drive (default tmux)
#   MUX_CMD                  the mux binary (default = $TERMINAL_MUX); the mock seam for tests
#   QUEUE_MUX_SESSION        the mux session windows live in (default dk-queue)
#   QUEUE_CLAUDE_CMD         interactive Claude Code binary launched in the window (default claude)
#   QUEUE_CLAUDE_FLAGS       flags for that session (default --dangerously-skip-permissions)
#   QUEUE_JOURNAL            append-only journal (default $DWARVES_KIT_LOG_DIR/queue-journal.tsv)
#   QUEUE_POLL_SECS          capture-pane poll interval (default 15)
#   QUEUE_TIMEOUT_SECS       per-mega stall ceiling -> `stalled` (default 7200 = 2h)
#   QUEUE_RETRY_SLEEP_SECS   sleep before the single launch-failure retry (default 1800 = 30m)
#   QUEUE_BOARD_CMD          the --from-boards source command (default board)
#
# Mechanism ladder (macos-action-selection L0-L4): PRIMARY is terminal-mux send-keys (L0/L1,
# deterministic, no GUI). Computer-Use (mcp__computer-use__*, L4) is the DOCUMENTED fallback for a
# mux-uncontrollable interface; it is NOT built into this bash launcher (manual escape hatch).
set -uo pipefail

TERMINAL_MUX="${TERMINAL_MUX:-tmux}"
MUX_CMD="${MUX_CMD:-$TERMINAL_MUX}"
QUEUE_MUX_SESSION="${QUEUE_MUX_SESSION:-dk-queue}"
QUEUE_CLAUDE_CMD="${QUEUE_CLAUDE_CMD:-claude}"
QUEUE_CLAUDE_FLAGS="${QUEUE_CLAUDE_FLAGS:---dangerously-skip-permissions}"
QUEUE_POLL_SECS="${QUEUE_POLL_SECS:-15}"
QUEUE_TIMEOUT_SECS="${QUEUE_TIMEOUT_SECS:-7200}"
QUEUE_RETRY_SLEEP_SECS="${QUEUE_RETRY_SLEEP_SECS:-1800}"
QUEUE_BOARD_CMD="${QUEUE_BOARD_CMD:-board}"
QUEUE_JOURNAL="${QUEUE_JOURNAL:-${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/queue-journal.tsv}"

_say()  { printf '%s\n' "$*"; }
_warn() { printf '%s\n' "$*" >&2; }
_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- journal ----------------------------------------------------------------------------------
# The journal IS the state: append-only TSV `ts<TAB>slug<TAB>verdict<TAB>reason`. A slug with a
# `done` row is skipped on re-run (idempotent nights).
_journal_init() { mkdir -p "$(dirname "$QUEUE_JOURNAL")" 2>/dev/null || true; }

# 0 iff <slug> already has a `done` row. Field-exact (col1=slug, col2=verdict), so a slug that
# merely APPEARS in another row's reason text never false-matches.
_journal_has_done() {  # slug
  [ -f "$QUEUE_JOURNAL" ] || return 1
  awk -F'\t' -v s="$1" '$2==s && $3=="done"{f=1} END{exit !f}' "$QUEUE_JOURNAL"
}

_journal_append() {  # slug verdict reason
  _journal_init
  printf '%s\t%s\t%s\t%s\n' "$(_now)" "$1" "$2" "${3:-}" >> "$QUEUE_JOURNAL"
}

# ---- git preflight ----------------------------------------------------------------------------
_default_branch() {  # repo
  local repo="$1" b
  b=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  b=${b#origin/}
  if [ -z "$b" ]; then
    if   git -C "$repo" show-ref --verify --quiet refs/heads/main;   then b=main
    elif git -C "$repo" show-ref --verify --quiet refs/heads/master; then b=master
    else b=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null); fi
  fi
  printf '%s' "$b"
}

# Echo a SKIP REASON if the repo is not launch-eligible, else nothing (eligible). Never opens a
# window; this is the guard NC1 depends on (dirty tree must skip with no window).
_repo_skip_reason() {  # repo
  local repo="$1" cur def
  { [ -n "$repo" ] && [ -d "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; } \
    || { printf 'repo missing'; return; }
  [ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ] || { printf 'dirty tree'; return; }
  cur=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  def=$(_default_branch "$repo")
  [ -n "$def" ] && [ "$cur" = "$def" ] || { printf 'not on default branch (%s)' "$cur"; return; }
}

# ---- mux abstraction (tmux primary, cmux mapped) ----------------------------------------------
# Every verb goes through "$MUX_CMD" so the whole mechanism is mockable (tests point MUX_CMD at a
# fake) and the mux binary is CONSUMER-swappable. TERMINAL_MUX picks the CLI dialect.

_mux_ensure_session() {
  case "$TERMINAL_MUX" in
    tmux)
      "$MUX_CMD" has-session -t "$QUEUE_MUX_SESSION" 2>/dev/null \
        || "$MUX_CMD" new-session -d -s "$QUEUE_MUX_SESSION" -n _init 2>/dev/null ;;
    cmux) : ;;  # cmux workspaces are ambient; no session bootstrap verb
    *) _warn "queue: unknown TERMINAL_MUX '$TERMINAL_MUX'"; return 2 ;;
  esac
}

# Open a fresh window named <slug> in <repo>, running interactive claude. The launched command is
# passed as SEPARATE argv tokens after `--` (tmux execs it directly; no `$SHELL -c` re-parse), and
# QUEUE_CLAUDE_FLAGS is word-split as operator config (not user data).
_mux_open() {  # slug repo
  local slug="$1" repo="$2"
  _mux_ensure_session || return $?
  case "$TERMINAL_MUX" in
    tmux)
      "$MUX_CMD" kill-window -t "$QUEUE_MUX_SESSION:$slug" 2>/dev/null || true
      # shellcheck disable=SC2086 # QUEUE_CLAUDE_FLAGS is operator config; word-splitting intended.
      "$MUX_CMD" new-window -d -t "$QUEUE_MUX_SESSION" -n "$slug" -c "$repo" -- \
        "$QUEUE_CLAUDE_CMD" $QUEUE_CLAUDE_FLAGS ;;
    cmux)
      # shellcheck disable=SC2086
      "$MUX_CMD" new-window --name "$slug" --cwd "$repo" -- "$QUEUE_CLAUDE_CMD" $QUEUE_CLAUDE_FLAGS ;;
  esac
}

# Type <text> as LITERAL keystrokes, then a separate Enter. `-l -- "$text"` (tmux) treats the
# argument as literal UTF-8 and stops option parsing, so a pointer starting with `-` or carrying
# shell metachars is inert data, never re-parsed by any shell (the NC5 argv-safe property).
_mux_type() {  # slug text
  local slug="$1" text="$2"
  case "$TERMINAL_MUX" in
    tmux)
      "$MUX_CMD" send-keys -t "$QUEUE_MUX_SESSION:$slug" -l -- "$text" || return 1
      "$MUX_CMD" send-keys -t "$QUEUE_MUX_SESSION:$slug" -- Enter ;;
    cmux)
      "$MUX_CMD" send-keys --window "$slug" --literal -- "$text" || return 1
      "$MUX_CMD" send-keys --window "$slug" -- Enter ;;
  esac
}

# Print the window's visible output on stdout. NONZERO exit = window gone (the launched claude
# exited) -- the "window died" signal the monitor treats as a launch failure.
_mux_capture() {  # slug
  local slug="$1"
  case "$TERMINAL_MUX" in
    tmux) "$MUX_CMD" capture-pane -p -t "$QUEUE_MUX_SESSION:$slug" 2>/dev/null ;;
    cmux) "$MUX_CMD" capture-pane --window "$slug" 2>/dev/null ;;
  esac
}

_mux_kill() {  # slug
  local slug="$1"
  case "$TERMINAL_MUX" in
    tmux) "$MUX_CMD" kill-window -t "$QUEUE_MUX_SESSION:$slug" 2>/dev/null || true ;;
    cmux) "$MUX_CMD" kill-window --window "$slug" 2>/dev/null || true ;;
  esac
}

# ---- completion marker ------------------------------------------------------------------------
# LINE-ANCHORED so prose (or the typed /goal command echo) quoting the marker text mid-line cannot
# false-trigger. Returns: prints "done" / "gated:<reason>" / "" (no marker yet).
_scan_marker() {  # transcript-on-stdin
  awk '
    /^RUNNER_DONE$/           { print "done"; found=1; exit }
    /^RUNNER_GATED:/          { r=$0; sub(/^RUNNER_GATED:[[:space:]]*/,"",r); print "gated:" r; found=1; exit }
  '
}

# ---- launch + monitor -------------------------------------------------------------------------
# Build the typed goal line: `/goal ` + the pointer file content, interior newlines collapsed to
# spaces so the TUI receives exactly ONE submission (a multi-line paste would submit early). v0
# behavior: prompts are treated as one logical paragraph. Metachars in the content stay literal.
_goal_line() {  # pointer-path
  local pointer="$1" content
  content=$(tr '\n' ' ' < "$pointer" 2>/dev/null)
  printf '/goal %s' "$content"
}

# Open + type + poll ONE window to a terminal state.
# Prints a verdict token on stdout: "done" | "gated:<reason>" | "stalled".
# Returns 0 for any of those; returns 2 for "window died" (launch failure -> caller retries).
_launch_once() {  # slug repo pointer
  local slug="$1" repo="$2" pointer="$3"
  _mux_open "$slug" "$repo" || return 2
  _mux_type "$slug" "$(_goal_line "$pointer")" || { _mux_kill "$slug"; return 2; }

  local start now elapsed out verdict cap_rc
  start=$(date +%s)
  while :; do
    sleep "$QUEUE_POLL_SECS"
    out=$(_mux_capture "$slug"); cap_rc=$?
    if [ "$cap_rc" -ne 0 ]; then
      # window gone = launched claude exited without a marker -> launch failure
      return 2
    fi
    verdict=$(printf '%s\n' "$out" | _scan_marker)
    if [ -n "$verdict" ]; then
      _mux_kill "$slug"
      printf '%s' "$verdict"
      return 0
    fi
    now=$(date +%s); elapsed=$((now - start))
    if [ "$elapsed" -ge "$QUEUE_TIMEOUT_SECS" ]; then
      _mux_kill "$slug"
      printf 'stalled'
      return 0
    fi
  done
}

# Launch a row with the single-retry launch-failure policy. Prints the FINAL verdict
# (done|gated|stalled|error) on stdout.
_run_row() {  # slug repo pointer
  local slug="$1" repo="$2" pointer="$3" v rc
  v=$(_launch_once "$slug" "$repo" "$pointer"); rc=$?
  if [ "$rc" -eq 2 ]; then
    _warn "queue: $slug launch failed; sleeping ${QUEUE_RETRY_SLEEP_SECS}s then retrying once."
    sleep "$QUEUE_RETRY_SLEEP_SECS"
    v=$(_launch_once "$slug" "$repo" "$pointer"); rc=$?
    [ "$rc" -eq 2 ] && { printf 'error'; return; }
  fi
  # v is "done" / "gated:<reason>" / "stalled"
  printf '%s' "$v"
}

# ---- source rows ------------------------------------------------------------------------------
# Emit `slug<TAB>repo<TAB>pointer` rows on stdout, from --from-boards or the tsv. `#`/blank lines
# dropped. NO eval, NO word-splitting of fields -- the argv-safe parse the consumers rely on.
_emit_rows() {  # src from_boards
  local src="$1" from_boards="$2"
  if [ "$from_boards" = 1 ]; then
    # shellcheck disable=SC2086 # QUEUE_BOARD_CMD may carry sub-args (operator config).
    $QUEUE_BOARD_CMD queue
  else
    grep -vE '^[[:space:]]*(#|$)' "$src" 2>/dev/null || true
  fi
}

# ---- run --------------------------------------------------------------------------------------
cmd_run() {
  local src="" dry=0 max=0 from_boards=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)    dry=1; shift ;;
      --from-boards) from_boards=1; shift ;;
      --max-megas)  max="${2:-0}"; shift 2 ;;
      --journal)    QUEUE_JOURNAL="${2:-$QUEUE_JOURNAL}"; shift 2 ;;
      --*)          _warn "queue: unknown flag '$1'"; return 64 ;;
      *)            src="$1"; shift ;;
    esac
  done
  if [ "$from_boards" != 1 ] && { [ -z "$src" ] || [ ! -f "$src" ]; }; then
    _warn "queue: no queue source (want a tsv path or --from-boards)"; return 64
  fi

  local consec_err=0 attempts=0 slug repo pointer reason verdict
  while IFS=$'\t' read -r slug repo pointer _rest; do
    [ -n "$slug" ] || continue

    # idempotent nights: a slug already `done` is skipped (no window)
    if _journal_has_done "$slug"; then
      _say "[queue] $slug: already done (journal); skipping."
      continue
    fi

    # preflight (all before any window opens)
    reason=$(_repo_skip_reason "$repo")
    if [ -n "$reason" ]; then
      if [ "$dry" = 1 ]; then
        _say "[dry-run] $slug: WOULD SKIP ($reason)"
      else
        _journal_append "$slug" skipped "$reason"
        _say "[queue] $slug: skipped ($reason)."
      fi
      continue
    fi

    if [ "$dry" = 1 ]; then
      _say "[dry-run] $slug: WOULD LAUNCH (repo=$repo pointer=$pointer)"
      continue
    fi

    attempts=$((attempts + 1))
    _say "[queue] $slug: launching /goal in a $TERMINAL_MUX window (repo=$repo)."
    verdict=$(_run_row "$slug" "$repo" "$pointer")

    case "$verdict" in
      gated:*) reason="${verdict#gated:}"; verdict=gated ;;
      *)       reason="" ;;
    esac
    _journal_append "$slug" "$verdict" "$reason"
    _say "[queue] $slug: $verdict${reason:+ ($reason)}."

    # error-twice-stops-night: only `error` accrues; done/gated/stalled reset; skipped is a
    # pass-through handled above (never reaches here).
    if [ "$verdict" = error ]; then
      consec_err=$((consec_err + 1))
      if [ "$consec_err" -ge 2 ]; then
        _warn "[queue] STOP THE NIGHT: two consecutive errors (assume account rate limit). Later rows untouched."
        return 0
      fi
    else
      consec_err=0
    fi

    if [ "$max" -gt 0 ] && [ "$attempts" -ge "$max" ]; then
      _say "[queue] reached --max-megas $max; stopping."
      return 0
    fi
  done < <(_emit_rows "$src" "$from_boards")
}

main() {
  local cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    run) cmd_run "$@" ;;
    *)   _warn "usage: queue.sh run <src.tsv> [--dry-run] [--max-megas N] [--from-boards] [--journal <path>]"; exit 64 ;;
  esac
}

# Run main only when executed, not when sourced (tests source + call helpers directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
