#!/usr/bin/env bash
# queue.sh -- the overnight queue LAUNCHER (runner-fastpath sub-goal 03K, SPEC-148).
#
# For each queued+tokened backlog mega, it opens a REAL interactive Claude Code `/goal` session
# in a fresh terminal-mux window and DRIVES it via scripting-control (types `/goal ` + the pointer
# prompt + Enter), monitors that window's output to completion, then launches the next. It runs on
# the operator's LIVE logged-in session, NOT a headless `claude -p` -- this sidesteps the
# AUTH/KILL-CLASS risk of a headless worker's token expiring / being killed independently
# (field-proven twice; ops-toolkit _meta/megagoals/OPERATE.md).
#
# It is a dumb (non-LLM) scheduler. Completion is detected by READING the launched session's
# output marker (`RUNNER_DONE` / `RUNNER_GATED:`), line-anchored AND blank-line-guarded (a marker
# line must be the first captured line or preceded by a blank line, so a soft-wrapped echo of the
# typed prompt -- which is DESIGNED to contain the marker text -- cannot false-trigger), never a
# fixed sleep. Every launch + exit lands a journal row. Two consecutive `error` OR `stalled` megas
# STOP THE NIGHT (both indicate the launch mechanism itself is dysfunctional, not a per-mega
# outcome).
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
#   TERMINAL_MUX=tmux       which mux to drive (default AND only supported value; see below)
#   MUX_CMD                  the mux binary (default = $TERMINAL_MUX); the mock seam for tests
#   QUEUE_MUX_SESSION        the mux session windows live in (default dk-queue)
#   QUEUE_CLAUDE_CMD         interactive Claude Code binary launched in the window (default claude)
#   QUEUE_CLAUDE_FLAGS       flags for that session (default --dangerously-skip-permissions)
#   QUEUE_JOURNAL            append-only journal (default $DWARVES_KIT_LOG_DIR/queue-journal.tsv)
#   QUEUE_POLL_SECS          capture-pane poll interval (default 15)
#   QUEUE_TIMEOUT_SECS       per-mega stall ceiling -> `stalled` (default 7200 = 2h)
#   QUEUE_RETRY_SLEEP_SECS   sleep before the single launch-failure retry (default 1800 = 30m)
#   QUEUE_BOARD_CMD          the --from-boards source command (default board)
#   QUEUE_ALLOWED_POINTER_GLOB  defense-in-depth path confinement for --from-boards ONLY (default
#                            below); a hand-authored tsv is allow-list-exempt by design (operator
#                            authorship IS the trust boundary for that path)
#
# Mechanism ladder (macos-action-selection L0-L4): PRIMARY is terminal-mux send-keys (L0/L1,
# deterministic, no GUI). Computer-Use (mcp__computer-use__*, L4) is the DOCUMENTED fallback for a
# mux-uncontrollable interface; it is NOT built into this bash launcher (manual escape hatch).
#
# cmux is NOT supported (review finding, 2026-07-05): this repo's OWN prior CLI verification
# (docs/specs/SPEC-119 DEC-001, SPEC-121 DEC-004) found cmux has no `new-window -- cmd args...`
# argv-safe launch primitive (`new-surface` takes no command; the only verified command-launch
# path is the STRING-context `new-workspace --command '<string>'`, a different sanitization
# problem). Rather than ship an unverified, likely-wrong cmux code path, TERMINAL_MUX=tmux is the
# only supported value for now; a cmux driver is a documented follow-up once that primitive is
# CLI-verified the way SPEC-121 verified its own.
set -uo pipefail

TERMINAL_MUX="${TERMINAL_MUX:-tmux}"
MUX_CMD="${MUX_CMD:-$TERMINAL_MUX}"
QUEUE_MUX_SESSION="${QUEUE_MUX_SESSION:-dk-queue}"
QUEUE_CLAUDE_CMD="${QUEUE_CLAUDE_CMD:-claude}"
QUEUE_CLAUDE_FLAGS="${QUEUE_CLAUDE_FLAGS:---dangerously-skip-permissions}"
QUEUE_POLL_SECS="${QUEUE_POLL_SECS:-15}"
QUEUE_TIMEOUT_SECS="${QUEUE_TIMEOUT_SECS:-7200}"
QUEUE_RETRY_SLEEP_SECS="${QUEUE_RETRY_SLEEP_SECS:-1800}"
# The interactive TUI takes several seconds to become input-ready; typing/submitting before it is
# drops the Enter (the text lands but stays unsent -- caught by the live smoke). Wait for a
# readiness signal (or this cap) BEFORE typing, and re-issue Enter until the prompt actually
# submits. Both configurable; tests set them to 0.
QUEUE_STARTUP_SECS="${QUEUE_STARTUP_SECS:-20}"
QUEUE_SUBMIT_SETTLE_SECS="${QUEUE_SUBMIT_SETTLE_SECS:-2}"
QUEUE_BOARD_CMD="${QUEUE_BOARD_CMD:-board}"
QUEUE_JOURNAL="${QUEUE_JOURNAL:-${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/queue-journal.tsv}"
# Defense-in-depth path confinement (review finding, CRITICAL #1): sub-goal 04's board emit is
# SUPPOSED to confine board-sourced pointers to these globs before ever emitting a row, but this
# launcher does not get to assume an upstream tool has no bugs when the destination is an
# unattended, `--dangerously-skip-permissions` session. Applied ONLY to `--from-boards` rows (a
# hand-authored tsv is exempt by design: the OPERATOR authored it, which IS the trust boundary).
QUEUE_ALLOWED_POINTER_GLOB="${QUEUE_ALLOWED_POINTER_GLOB:-_meta/megagoals/* .claude/goals/*}"

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
  # `reason` (esp. a `gated:` reason) is pane text, not operator-authored -- strip tabs/newlines/
  # control chars so an embedded tab can never shift the row's field count (review finding,
  # MEDIUM: an unescaped reason could otherwise corrupt any tool parsing the journal by column).
  local reason; reason=$(printf '%s' "${3:-}" | tr -d '\t\r' | tr '\n' ' ')
  printf '%s\t%s\t%s\t%s\n' "$(_now)" "$1" "$2" "$reason" >> "$QUEUE_JOURNAL"
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

# ---- mux abstraction (tmux only; see the cmux note in the header comment) ---------------------
# Every verb goes through "$MUX_CMD" so the whole mechanism is mockable (tests point MUX_CMD at a
# fake) and the mux binary is CONSUMER-swappable.

# A slug is used verbatim in tmux's `session:window` target syntax (`$QUEUE_MUX_SESSION:$slug`).
# tmux itself uses `:` and `.` as target separators, so a slug containing either could resolve to
# an UNINTENDED session/window (target confusion -> misdirected keystrokes or kill-window; review
# finding, LOW). Reject before any mux verb runs; a slug is meant to be a simple identifier.
_slug_ok() {  # slug
  case "$1" in
    *[:.]*|"") return 1 ;;
    *) return 0 ;;
  esac
}

_mux_ensure_session() {
  [ "$TERMINAL_MUX" = tmux ] || { _warn "queue: unsupported TERMINAL_MUX '$TERMINAL_MUX' (only 'tmux' is supported; see the cmux note in lib/queue.sh)"; return 2; }
  "$MUX_CMD" has-session -t "$QUEUE_MUX_SESSION" 2>/dev/null \
    || "$MUX_CMD" new-session -d -s "$QUEUE_MUX_SESSION" -n _init 2>/dev/null
}

# Open a fresh window named <slug> in <repo>, running interactive claude. The launched command is
# passed as SEPARATE argv tokens after `--` (tmux execs it directly; no `$SHELL -c` re-parse), and
# QUEUE_CLAUDE_FLAGS is word-split as operator config (not user data).
_mux_open() {  # slug repo
  local slug="$1" repo="$2"
  _slug_ok "$slug" || { _warn "queue: refusing slug '$slug' (contains ':' or '.', a tmux target separator)"; return 2; }
  _mux_ensure_session || return $?
  "$MUX_CMD" kill-window -t "$QUEUE_MUX_SESSION:$slug" 2>/dev/null || true
  # shellcheck disable=SC2086 # QUEUE_CLAUDE_FLAGS is operator config; word-splitting intended.
  "$MUX_CMD" new-window -d -t "$QUEUE_MUX_SESSION" -n "$slug" -c "$repo" -- \
    "$QUEUE_CLAUDE_CMD" $QUEUE_CLAUDE_FLAGS
}

# Type <text> as LITERAL keystrokes (no Enter). `-l -- "$text"` treats the argument as literal
# UTF-8 and stops option parsing, so a pointer starting with `-` or carrying shell metachars is
# inert data, never re-parsed by any shell (the NC5 argv-safe property).
_mux_type() {  # slug text
  "$MUX_CMD" send-keys -t "$QUEUE_MUX_SESSION:$1" -l -- "$2"
}

# Send a single Enter (submit) into the window.
_mux_enter() {  # slug
  "$MUX_CMD" send-keys -t "$QUEUE_MUX_SESSION:$1" -- Enter
}

# Wait for the launched interactive session to be input-ready before typing. Readiness signal: the
# TUI footer ("bypass permissions") or an input prompt (`>`/`❯`) has drawn. Best-effort: proceeds
# after QUEUE_STARTUP_SECS regardless (the re-submit loop + monitor timeout are the real backstops).
_mux_wait_ready() {  # slug
  local slug="$1" waited=0
  while [ "$waited" -lt "$QUEUE_STARTUP_SECS" ]; do
    _mux_capture "$slug" 2>/dev/null | grep -qE 'bypass permissions|^[[:space:]]*[>❯]' && return 0
    sleep 2; waited=$((waited + 2))
  done
  return 0
}

# Submit the typed goal, then VERIFY it actually submitted and re-issue Enter if not. The live
# smoke proved a single early Enter can be dropped while the text stays sitting on the `/goal`
# input line; re-issuing until the prompt no longer shows the pending `/goal` command makes the
# submit deterministic. Bounded (5 tries); an extra Enter on an empty prompt is a harmless no-op.
_mux_submit() {  # slug
  local slug="$1" tries=0
  while [ "$tries" -lt 5 ]; do
    _mux_enter "$slug"
    sleep "$QUEUE_SUBMIT_SETTLE_SECS"
    # unsent iff the input prompt line still carries the pending `/goal` command
    _mux_capture "$slug" 2>/dev/null | grep -qE '[>❯][[:space:]]*/goal' || return 0
    tries=$((tries + 1))
  done
  return 0
}

# Print the window's visible output on stdout. NONZERO exit = window gone (the launched claude
# exited) -- the "window died" signal the monitor treats as a launch failure.
_mux_capture() {  # slug
  "$MUX_CMD" capture-pane -p -t "$QUEUE_MUX_SESSION:$1" 2>/dev/null
}

_mux_kill() {  # slug
  "$MUX_CMD" kill-window -t "$QUEUE_MUX_SESSION:$1" 2>/dev/null || true
}

# ---- completion marker ------------------------------------------------------------------------
# LINE-ANCHORED so prose (or the typed /goal command echo) quoting the marker text mid-line cannot
# false-trigger. The marker must be the ONLY non-space token on its line: leading whitespace is
# allowed because the real Claude Code TUI renders the assistant's final line INDENTED inside its
# message block (confirmed by the live smoke -- a strict `^RUNNER_DONE$` misses the real pane).
#
# SECOND anchor, added after a security review found a real false-positive path (CRITICAL): the
# pointer's OWN content is designed to instruct printing "RUNNER_DONE", and `_goal_line` flattens
# that whole pointer into ONE long typed line. A wide-enough pane can soft-wrap that echoed line so
# the marker substring lands ALONE on its own rendered row -- indistinguishable from a real
# completion by the first anchor alone. The fix: require the marker line to be preceded by a BLANK
# line (or be the very first captured line). This is not a guess -- the live smoke's real
# completion output confirmed the TUI always surrounds the assistant's final marker line with
# blank lines (paragraph spacing), whereas a soft-wrapped CONTINUATION of one long echoed sentence
# is never preceded by a blank line (it directly follows the previous wrapped segment of the same
# sentence). So requiring "blank-line-or-first" rejects the wrap-induced false positive while
# still matching the real rendering. Returns: prints "done" / "gated:<reason>" / "" (no marker).
_scan_marker() {  # transcript-on-stdin
  awk '
    /^[[:space:]]*RUNNER_DONE[[:space:]]*$/ && (NR==1 || prevblank) { print "done"; exit }
    /^[[:space:]]*RUNNER_GATED:/ && (NR==1 || prevblank) {
      r=$0; sub(/^[[:space:]]*RUNNER_GATED:[[:space:]]*/,"",r); print "gated:" r; exit
    }
    { prevblank = ($0 ~ /^[[:space:]]*$/) }
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
  _mux_wait_ready "$slug"
  _mux_type "$slug" "$(_goal_line "$pointer")" || { _mux_kill "$slug"; return 2; }
  _mux_submit "$slug"

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

# Defense-in-depth pointer confinement for --from-boards rows ONLY (security review, CRITICAL #1).
# Sub-goal 04's board emit is SUPPOSED to confine pointers to _meta/megagoals/** or
# .claude/goals/** before ever emitting a row -- but this launcher, driving an unattended
# `--dangerously-skip-permissions` session, must not simply trust an upstream tool has no bugs. A
# hand-authored tsv is EXEMPT (the operator authored it; that authorship IS the trust boundary for
# that path, per SPEC-148). Checked against the pointer path RELATIVE TO ITS REPO (a pointer
# outside the repo, or one that resolves via `..` OR a SYMLINK outside it, fails closed). Uses
# `realpath` (present on both macOS/BSD and Linux/coreutils; verified on this host) so a symlink
# planted INSIDE the allow-listed directory but pointing OUTSIDE the repo is caught too -- a
# rung-4 red-team probe found `cd $(dirname) && pwd -P` alone resolves only the directory, not a
# symlink AT the final path component, which would have let such a symlink read arbitrary file
# content into the /goal prompt while still LOOKING allow-listed. Prints nothing (ok) or a reason.
_pointer_allowlist_reason() {  # repo pointer
  local repo="$1" pointer="$2" repo_abs ptr_abs rel glob
  repo_abs=$(cd "$repo" 2>/dev/null && pwd -P) || { printf 'repo unresolvable for pointer allow-list'; return; }
  if command -v realpath >/dev/null 2>&1; then
    ptr_abs=$(realpath "$pointer" 2>/dev/null) || { printf 'pointer unresolvable (not allow-listed)'; return; }
  else
    ptr_abs=$(cd "$(dirname "$pointer")" 2>/dev/null && pwd -P)/$(basename "$pointer") || true
  fi
  case "$ptr_abs" in
    "$repo_abs"/*) rel="${ptr_abs#"$repo_abs"/}" ;;
    *) printf 'pointer outside its repo (not allow-listed)'; return ;;
  esac
  for glob in $QUEUE_ALLOWED_POINTER_GLOB; do
    # shellcheck disable=SC2254 # QUEUE_ALLOWED_POINTER_GLOB is operator config; glob match intended.
    case "$rel" in $glob) return ;; esac
  done
  printf 'pointer "%s" not allow-listed (want one of: %s)' "$rel" "$QUEUE_ALLOWED_POINTER_GLOB"
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

  local consec_fail=0 attempts=0 slug repo pointer reason verdict
  while IFS=$'\t' read -r slug repo pointer _rest; do
    [ -n "$slug" ] || continue

    # idempotent nights: a slug already `done` is skipped (no window)
    if _journal_has_done "$slug"; then
      _say "[queue] $slug: already done (journal); skipping."
      continue
    fi

    # preflight (all before any window opens)
    reason=$(_repo_skip_reason "$repo")
    if [ -z "$reason" ] && [ "$from_boards" = 1 ]; then
      reason=$(_pointer_allowlist_reason "$repo" "$pointer")
    fi
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

    # error-twice-stops-night, EXTENDED to stalled (review finding, MEDIUM): `error` (launch
    # failed twice) and `stalled` (no progress for the full timeout) BOTH indicate the launch
    # mechanism/session itself is dysfunctional (auth, rate-limit, a hung interface), so both
    # accrue toward the same 2-consecutive stop. `done`/`gated` are legitimate PER-MEGA terminal
    # states signaled BY a healthy running session, so they reset the counter; `skipped` is a
    # deterministic pass-through (handled above, never reaches here) that neither increments nor
    # resets -- an attacker cannot dodge the stop by interleaving a skippable row (proven by the
    # rung-4 red-team).
    case "$verdict" in
      error|stalled)
        consec_fail=$((consec_fail + 1))
        if [ "$consec_fail" -ge 2 ]; then
          _warn "[queue] STOP THE NIGHT: two consecutive $verdict megas (assume account rate limit / a systemic hang). Later rows untouched."
          return 0
        fi
        ;;
      *) consec_fail=0 ;;
    esac

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
