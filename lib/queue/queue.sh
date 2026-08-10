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
#     --ready         open a NORMAL PR instead of the unattended draft default (SPEC-224); the
#                     escape hatch mirroring OpenHands' model-overridable draft=False.
#     --sanitize-prompt  treat the pointer body as UNTRUSTED (SPEC-223): run it through
#                     `sanitize_cell`, prepend the XPIA preamble, and gate the row if the run
#                     wrote a protected path. Implied by `--from-boards`; the watcher passes it
#                     explicitly for its own generated plan. A hand-authored tsv without the flag
#                     is unchanged, because the OPERATOR authored it (the SPEC-148 trust boundary).
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
# RUNAWAY GUARDS (SPEC-221). Three per-slug sidecar files under <log-dir>/queue-runs/, each with
# exactly ONE writer: `<slug>.beat` (this conductor touches it every poll; its mtime IS the
# liveness signal and its PRESENCE is the in-flight claim), `<slug>.status` (the RUN writes it;
# carries the explicit EXIT_SIGNAL line), `<slug>.guard` (counters + timers, key=value). The
# REAPER that consumes a stale beat lives in watch-board.sh: it runs on the tick the operator
# already runs, so these guards add no daemon. Their env knobs:
#   QUEUE_BEAT_STALE_SECS    beat age past which the conductor is presumed gone (default 600)
#   QUEUE_BEAT_DEAD_SECS     beat age past which the reaper writes a verdict   (default 3600)
#   QUEUE_MAX_STALLS         stalls before quarantine (empty retry_after)      (default 3)
#   QUEUE_COOLDOWN_SECS      breaker cooldown before an `error` row re-picks   (default 1800)
#   QUEUE_NOPROGRESS_TRIP    consecutive no-progress runs that trip the breaker (default 3)
#   QUEUE_SAMEERROR_TRIP     consecutive `error` runs that trip the breaker     (default 5)
#
# CHEAP GUARDRAILS (SPEC-224, board row ID-461). Draft-PR-by-default on this unattended path, plus a
# self-reported per-row spend ceiling composed OR-style with the wall-clock timeout above:
#   QUEUE_PR_READY               1 = open a normal PR (--ready); 0 = draft default (default 0)
#   QUEUE_MAX_TOOL_CALLS         per-row ceiling on the run's self-reported TOOL_CALLS (0 = off)
#   QUEUE_MAX_TOTAL_TOOL_CALLS   queue-wide ceiling across rows this run           (0 = off)
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
# SPEC-200 I3 / SPEC-097: the journal lives under the ONE durable root, resolved by the ONE
# resolver (KIT_LEDGER_DIR -> DWARVES_KIT_LOG_DIR -> kit.toml [ledger].location -> XDG state).
# Before this, it defaulted straight into ~/.claude/dwarves-kit/logs, the exact path a plugin
# reinstall wipes and that SPEC-097 exists to escape: the queue's history was the one telemetry
# corpus not protected by it.
# The resolver soft-`return 1`s when lib/config/kit-config.sh is missing (a degraded or partial
# checkout), leaving kit_resolve_log_dir UNDEFINED. queue.sh has no `set -e`, so an unguarded
# call would substitute empty and put the journal at `/queue-journal.tsv`: a silent footgun in
# the one launcher that runs unattended overnight. Fail loudly instead (review finding, advisor).
# shellcheck source=lib/telemetry/kit-log-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../telemetry" && pwd)/kit-log-dir.sh" || true
if ! declare -f kit_resolve_log_dir >/dev/null 2>&1; then
  echo "queue: kit-log-dir.sh did not load (lib/config/kit-config.sh missing?); refusing to guess a journal path" >&2
  exit 1
fi
QUEUE_JOURNAL="${QUEUE_JOURNAL:-$(kit_resolve_log_dir)/queue-journal.tsv}"
case "$QUEUE_JOURNAL" in /queue-journal.tsv|queue-journal.tsv)
  echo "queue: refusing a filesystem-root journal path ($QUEUE_JOURNAL)" >&2; exit 1 ;;
esac
# Defense-in-depth path confinement (review finding, CRITICAL #1): sub-goal 04's board emit is
# SUPPOSED to confine board-sourced pointers to these globs before ever emitting a row, but this
# launcher does not get to assume an upstream tool has no bugs when the destination is an
# unattended, `--dangerously-skip-permissions` session. Applied ONLY to `--from-boards` rows (a
# hand-authored tsv is exempt by design: the OPERATOR authored it, which IS the trust boundary).
QUEUE_ALLOWED_POINTER_GLOB="${QUEUE_ALLOWED_POINTER_GLOB:-_meta/megagoals/* .claude/goals/*}"

# The untrusted-input pass (SPEC-223). Sourced, not re-implemented, so `watch-board.sh` (which
# sources this file) gets the same one. Fail loudly if it is missing: this launcher drives an
# unattended `--dangerously-skip-permissions` session, and a silently absent sanitizer would look
# exactly like a sanitized run.
# shellcheck source=lib/queue/sanitize.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sanitize.sh" || true
if ! declare -f sanitize_cell >/dev/null 2>&1; then
  echo "queue: lib/queue/sanitize.sh did not load; refusing to run without the untrusted-input pass" >&2
  exit 1
fi
# 0 = the shipped operator-authored path (pointer body typed verbatim). 1 = board-sourced.
QUEUE_SANITIZE_PROMPT="${QUEUE_SANITIZE_PROMPT:-0}"

# ---- runaway-guard thresholds (SPEC-221) -------------------------------------------------------
# Re-derived for THIS kit's clocks, not copied from the donor: the beat interval here is
# QUEUE_POLL_SECS (15s, vs the donor's 30s) and the per-row ceiling is QUEUE_TIMEOUT_SECS (2h, vs
# their hours-long stage budget). So the short threshold is tighter in beat-multiples and the long
# one is SHORTER in absolute terms. Full derivation: docs/specs/SPEC-221-runaway-guards.md.
QUEUE_BEAT_STALE_SECS="${QUEUE_BEAT_STALE_SECS:-600}"
QUEUE_BEAT_DEAD_SECS="${QUEUE_BEAT_DEAD_SECS:-3600}"
QUEUE_MAX_STALLS="${QUEUE_MAX_STALLS:-3}"
# 30 min matches QUEUE_RETRY_SLEEP_SECS: this launcher's existing instinct for "back off and try
# later" is half an hour, and a second different number would be arbitrary.
QUEUE_COOLDOWN_SECS="${QUEUE_COOLDOWN_SECS:-1800}"
QUEUE_NOPROGRESS_TRIP="${QUEUE_NOPROGRESS_TRIP:-3}"
QUEUE_SAMEERROR_TRIP="${QUEUE_SAMEERROR_TRIP:-5}"
# Jittered retry window after a stall, in minutes. The jitter is load-bearing: one sleeping host
# stalls several rows at once, and without it every one of them becomes re-pickable on the same tick.
QUEUE_RETRY_JITTER_MIN="${QUEUE_RETRY_JITTER_MIN:-5}"
QUEUE_RETRY_JITTER_SPAN="${QUEUE_RETRY_JITTER_SPAN:-11}"

# ---- cheap guardrails (SPEC-224) ---------------------------------------------------------------
# Two wins that ride channels SPEC-221 already built. Both default OFF-or-safe, so the shipped
# overnight behavior is byte-identical until an operator opts in.
#   QUEUE_PR_READY             0 = draft-PR-by-default on this unattended path (the queue is always
#                              autonomous); 1 = the --ready escape hatch, open a normal PR (OpenHands
#                              model-overridable draft=False).
#   QUEUE_MAX_TOOL_CALLS       per-row soft ceiling on the run's SELF-REPORTED TOOL_CALLS count
#                              (0 = unlimited, SWE-agent per_instance_call_limit default). Self-report
#                              is a GUARDRAIL not a boundary; the wall-clock QUEUE_TIMEOUT_SECS is the
#                              non-gameable backstop, composed OR-style (first-to-trip wins).
#   QUEUE_MAX_TOTAL_TOOL_CALLS queue-wide ceiling across rows this run (0 = unlimited). The current
#                              row finishes + ships first, then remaining rows are skipped.
QUEUE_PR_READY="${QUEUE_PR_READY:-0}"
QUEUE_MAX_TOOL_CALLS="${QUEUE_MAX_TOOL_CALLS:-0}"
QUEUE_MAX_TOTAL_TOOL_CALLS="${QUEUE_MAX_TOTAL_TOOL_CALLS:-0}"
# Coerce to a safe integer so a junk config value never errors a later `-gt`/`-ge` comparison in the
# overnight run; junk means disabled, not a crash.
case "$QUEUE_MAX_TOOL_CALLS" in ''|*[!0-9]*) QUEUE_MAX_TOOL_CALLS=0 ;; esac
case "$QUEUE_MAX_TOTAL_TOOL_CALLS" in ''|*[!0-9]*) QUEUE_MAX_TOTAL_TOOL_CALLS=0 ;; esac

_say()  { printf '%s\n' "$*"; }
_warn() { printf '%s\n' "$*" >&2; }
_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- per-slug sidecars (SPEC-221) --------------------------------------------------------------
# Portable file mtime in epoch seconds. GNU `stat -c` is tried FIRST because it errors cleanly on
# BSD/macOS so the `stat -f` fallback runs there; the reverse order is unsafe (GNU `stat -f`
# SUCCEEDS with filesystem text, starving the fallback and poisoning the arithmetic). Same shape
# lib/queue/orchestrate.sh already uses. Empty when the file is absent or stat prints non-digits.
_mtime() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
  case "$m" in ''|*[!0-9]*) return 0 ;; *) printf '%s' "$m" ;; esac
}

_run_dir() { printf '%s/queue-runs' "$(kit_resolve_log_dir)"; }

# The sidecar path for <slug>.<ext>. Refuses a slug that is not `_slug_ok`, which now includes `/`:
# the slug names a FILE here, so a separator would be a traversal out of the sidecar directory.
_run_file() {  # slug ext
  _slug_ok "$1" || return 1
  printf '%s/%s.%s' "$(_run_dir)" "$1" "$2"
}

# Age of a file in seconds, clamped at 0. The clamp is the clock-skew guard: an NTP correction that
# moves the clock BACKWARD must delay a reap, never fire one early.
_age() {  # path
  local m now
  m=$(_mtime "$1"); [ -n "$m" ] || return 1
  now=$(date +%s)
  if [ "$now" -lt "$m" ]; then printf '0'; else printf '%s' $((now - m)); fi
}

# The heartbeat. Touching is the whole write: mtime carries the liveness, presence carries the
# in-flight claim, so there is nothing to serialize and nothing to corrupt on a kill mid-write.
_beat() {  # slug
  local f; f=$(_run_file "$1" beat) || return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  : > "$f"
}
_beat_clear() { local f; f=$(_run_file "$1" beat) || return 0; rm -f "$f" 2>/dev/null || true; }

# `<slug>.guard` is `key=value` lines. Read prints the LAST value for the key (empty if unset);
# write rewrites the file with that key replaced. Small enough that rewrite-whole beats an in-place
# edit, and a torn write loses counters rather than corrupting a verdict.
_guard_get() {  # slug key
  local f; f=$(_run_file "$1" guard) || return 0
  [ -f "$f" ] || return 0
  awk -F= -v k="$2" '$1==k {v=substr($0, length(k)+2)} END{if(v!="") print v}' "$f"
}
_guard_set() {  # slug key value
  local f tmp; f=$(_run_file "$1" guard) || return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  tmp="$f.tmp.$$"
  { [ -f "$f" ] && grep -v "^$2=" "$f"; printf '%s=%s\n' "$2" "$3"; } > "$tmp" 2>/dev/null
  mv -f "$tmp" "$f" 2>/dev/null || true
}
_guard_clear() { local f; f=$(_run_file "$1" guard) || return 0; rm -f "$f" 2>/dev/null || true; }

# A guard counter as an integer, defaulting to 0 so arithmetic is always safe.
_guard_num() {  # slug key
  local v; v=$(_guard_get "$1" "$2")
  case "$v" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac
}

# ---- the explicit exit signal (SPEC-221) -------------------------------------------------------
# `<slug>.status` is written BY THE RUN. Read one key's value, first occurrence wins.
_status_get() {  # slug key
  local f; f=$(_run_file "$1" status) || return 0
  [ -f "$f" ] || return 0
  grep -m1 "^[[:space:]]*$2:" "$f" 2>/dev/null \
    | sed -e "s/^[[:space:]]*$2:[[:space:]]*//" -e 's/[[:space:]]*$//'
}

# Prints exactly one of: "true" | "false" | "bad" | "" (no status file at all).
#
# "bad" is the load-bearing case and it is NOT the same as "": a status file that exists but
# carries no parsable EXIT_SIGNAL is a run that TRIED to speak and failed, so it must never fall
# back to reading prose off the pane. "" means the run never opted into the contract, and that path
# stays byte-identical to the shipped pane scan.
_exit_signal() {  # slug
  local f v; f=$(_run_file "$1" status) || return 0
  [ -f "$f" ] || return 0
  v=$(_status_get "$1" EXIT_SIGNAL)
  case "$v" in
    true|TRUE|True)    printf 'true' ;;
    false|FALSE|False) printf 'false' ;;
    *)                 printf 'bad' ;;
  esac
}

# SPEC-224: the largest numeric value of KEY across ALL its lines in <slug>.status (0 if none). A
# self-reported monotonic counter like TOOL_CALLS may be rewritten or appended by the run; MAX is
# its latest value either way, so this never reads a stale earlier number. Distinct from
# `_status_get` (first-wins), whose first-occurrence rule is load-bearing for EXIT_SIGNAL only.
_status_num() {  # slug key
  local f; f=$(_run_file "$1" status) || { printf '0'; return 0; }
  [ -f "$f" ] || { printf '0'; return 0; }
  # CLAMP to 9 digits (<=999999999) before any compare (security review, MEDIUM). This value is
  # SELF-REPORTED by an untrusted run: an oversized number (30 digits) would otherwise (a) error the
  # `-ge` in the per-row ceiling with "integer expected" and silently DISABLE it, and (b) overflow
  # the 64-bit queue-wide accumulator and spuriously abort the whole batch. A 9-digit cap keeps every
  # comparison and the summed accumulator inside safe integer range while staying far above any sane
  # ceiling. Clamping the STRING LENGTH (not the numeric value) is what avoids the overflow at parse.
  awk -v k="$2" '
    { key=$0; sub(/:.*$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",key) }
    key==k { v=$0; sub(/^[^:]*:/,"",v); gsub(/[^0-9]/,"",v)
             if (length(v) > 9) v="999999999"
             if (v!="" && v+0>m) m=v+0 }
    END { print m+0 }' "$f"
}

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
  # Length cap (security review, LOW): a `REASON:` value now reaches here from `<slug>.status`,
  # which the RUN writes, so its length is agent-controlled. Unbounded, it bloats an append-only
  # file that every dedup read scans linearly. Truncation cannot corrupt a column.
  [ "${#reason}" -gt 500 ] && reason="${reason:0:500}..."
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
#
# `/` joined the reject set with SPEC-221: the slug now also names a FILE under the sidecar
# directory (`<log-dir>/queue-runs/<slug>.beat`), so a separator would be a traversal out of it.
# Sanitizing instead of refusing was rejected: two different slugs would collide on one sidecar.
_slug_ok() {  # slug
  case "$1" in
    *[:./]*|"") return 1 ;;
    *) return 0 ;;
  esac
}

_mux_ensure_session() {
  [ "$TERMINAL_MUX" = tmux ] || { _warn "queue: unsupported TERMINAL_MUX '$TERMINAL_MUX' (only 'tmux' is supported; see the cmux note in lib/queue/queue.sh)"; return 2; }
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
# smoke proved a single early Enter can be dropped while the text stays sitting on the input
# line; re-issuing until the input line is BARE makes the submit deterministic. Bounded (5
# tries); an extra Enter on an empty prompt is a harmless no-op.
#
# Detection is "prompt char followed by ANY content", not the literal `/goal`: a long paste
# renders TAIL-first in the input box (the pane shows `❯ (or "EXIT_SIGNAL...`, never `❯ /goal`),
# so the old `/goal` match reported submitted after one dropped Enter and stranded the row with
# no journal entry. Three consecutive live runs reproduced it; one manual Enter unstuck each.
# False "still pending" only costs harmless extra Enters, false "submitted" strands the row,
# so the check errs pending.
_mux_submit() {  # slug
  local slug="$1" tries=0
  while [ "$tries" -lt 5 ]; do
    _mux_enter "$slug"
    sleep "$QUEUE_SUBMIT_SETTLE_SECS"
    # submitted iff no line renders a prompt char with content still after it
    _mux_capture "$slug" 2>/dev/null | grep -qE '^[[:space:]]*[>❯][[:space:]]*[^[:space:]]' || return 0
    tries=$((tries + 1))
  done
  _warn "queue: $slug submit unconfirmed after $tries tries; the goal may still be sitting unsubmitted in the window."
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
#
# SPEC-221 appends ONE clause naming the run's status file. That is how the run learns where to
# write its explicit EXIT_SIGNAL: the typed prompt is the same channel the RUNNER_DONE contract
# already travels on, so it needs no `tmux new-window -e` (tmux 3.0 floor) and no environment
# inheritance assumption. A run that ignores the clause behaves exactly as before.
#
# SPEC-223: on the board-sourced path the pointer body is UNTRUSTED. It is run through
# `sanitize_cell`, framed by the XPIA preamble, and fenced by explicit begin/end markers so the
# model can see where the data starts and stops. Returns 1 (no output) when the sanitizer cannot
# run, which the caller turns into a refusal to launch rather than an unsanitized prompt.
_goal_line() {  # pointer-path slug
  local pointer="$1" slug="${2:-}" content status
  if [ "$QUEUE_SANITIZE_PROMPT" = 1 ]; then
    content=$(sanitize_cell "$pointer") || return 1
    content="$(xpia_preamble) An unattended run must NOT write any of these paths: ${QUEUE_PROTECTED_GLOBS}; writing one stops the row for a human instead of shipping it. BEGIN UNTRUSTED TASK TEXT >>> ${content} <<< END UNTRUSTED TASK TEXT."
  else
    content=$(tr '\n' ' ' < "$pointer" 2>/dev/null)
  fi
  local line="/goal $content"
  status=$(_run_file "$slug" status 2>/dev/null) || status=""
  if [ -n "$status" ]; then
    line="$line When you finish, write $status containing the line \"EXIT_SIGNAL: true\" (or \"EXIT_SIGNAL: false\" if you are not done), plus \"REASON: <why>\" if a human must review, \"FILES_CHANGED: <n>\", and \"QUESTION: true\" if you stopped to ask something."
    # SPEC-224: when a spend ceiling is active, ask the run to self-report a cumulative tool-call
    # count into the SAME status file, so the conductor can read it on the poll it already does.
    if [ "$QUEUE_MAX_TOOL_CALLS" -gt 0 ] || [ "$QUEUE_MAX_TOTAL_TOOL_CALLS" -gt 0 ]; then
      line="$line Also update $status every few tool calls with a line \"TOOL_CALLS: <your cumulative tool-call count>\"."
    fi
  fi
  # SPEC-224: draft-PR-by-default on this unattended path (OpenHands posture). This builder is only
  # ever called by the autonomous queue, so appending here IS "autonomous path only"; interactive
  # /kit:ship never reaches it. QUEUE_PR_READY=1 is the --ready escape hatch (their draft=False).
  if [ "$QUEUE_PR_READY" != 1 ]; then
    # Footer the journal BASENAME, not the resolved path (security review, LOW): the full path
    # defaults under the operator's home and would leak a local path + username into a public PR
    # body. The basename + slug still identify the run in the journal, which is all the footer is for.
    local jbase; jbase=$(basename "$QUEUE_JOURNAL")
    line="$line When you open a pull request, make it a DRAFT (gh pr create --draft) and append this provenance footer on its own line in the PR body: \"[unattended orchestrator run; journal ${jbase}; slug ${slug}]\"."
  fi
  printf '%s' "$line"
}

# Open + type + poll ONE window to a terminal state.
# Prints a verdict token on stdout: "done" | "gated:<reason>" | "stalled".
# Returns 0 for any of those; returns 2 for "window died" (launch failure -> caller retries).
_launch_once() {  # slug repo pointer
  local slug="$1" repo="$2" pointer="$3"
  # A stale status file from a PREVIOUS attempt would answer for this one. Clear before launching.
  local sf; sf=$(_run_file "$slug" status 2>/dev/null) && [ -n "$sf" ] && rm -f "$sf" 2>/dev/null
  _beat "$slug"
  _mux_open "$slug" "$repo" || return 2
  _mux_wait_ready "$slug"
  # Captured before typing, so a sanitizer that cannot run refuses the launch instead of typing an
  # empty prompt (a `$( )` failure is invisible to the command it feeds).
  local goal
  goal=$(_goal_line "$pointer" "$slug") || {
    _warn "queue: $slug refusing to launch (the untrusted-input pass could not run)"
    _mux_kill "$slug"; return 2; }
  _mux_type "$slug" "$goal" || { _mux_kill "$slug"; return 2; }
  _mux_submit "$slug"

  local start now elapsed out verdict cap_rc sig malformed=0 reason
  start=$(date +%s)
  while :; do
    sleep "$QUEUE_POLL_SECS"
    _beat "$slug"
    out=$(_mux_capture "$slug"); cap_rc=$?
    if [ "$cap_rc" -ne 0 ]; then
      # window gone = launched claude exited without a marker -> launch failure
      return 2
    fi

    # SPEC-221 exit gate. Read the run's OWN explicit signal BEFORE the pane, every poll. The
    # ordering is the anti-false-completion rule: an explicit `false` outranks whatever prose the
    # pane happens to render, and an unparsable file is never a completion.
    sig=$(_exit_signal "$slug")
    case "$sig" in
      true)
        _mux_kill "$slug"
        reason=$(_status_get "$slug" REASON)
        # A REASON alongside an explicit completion means a human still has to look: that is the
        # journal's existing `gated` verdict, not a second vocabulary.
        if [ -n "$reason" ]; then printf 'gated:%s' "$reason"; else printf 'done'; fi
        return 0 ;;
      false)
        # Explicit "keep working". Skip the pane scan entirely this poll.
        ;;
      bad)
        # The run tried to speak and produced something unparsable. Never guess from prose;
        # remember it so the eventual timeout names the real reason.
        malformed=1 ;;
      *)
        # No status file: the shipped pane path, byte-identical.
        verdict=$(printf '%s\n' "$out" | _scan_marker)
        if [ -n "$verdict" ]; then
          _mux_kill "$slug"
          printf '%s' "$verdict"
          return 0
        fi ;;
    esac

    # SPEC-224 per-row spend ceiling, composed OR-style with the wall-clock below (first-to-trip
    # wins). Checked AFTER the exit gate so a finished run is never spend-capped, and BEFORE the
    # timeout so the more specific reason wins when both cross on one poll. The run self-reports its
    # count; the check reads only completed turns between polls, so "stop this row after the observed
    # turn" is the graceful, autosubmit-equivalent stop, whatever draft PR it opened persists.
    if [ "$QUEUE_MAX_TOOL_CALLS" -gt 0 ] && [ "$(_status_num "$slug" TOOL_CALLS)" -ge "$QUEUE_MAX_TOOL_CALLS" ]; then
      _mux_kill "$slug"
      printf 'stalled:spend_ceiling'
      return 0
    fi

    now=$(date +%s); elapsed=$((now - start))
    if [ "$elapsed" -ge "$QUEUE_TIMEOUT_SECS" ]; then
      _mux_kill "$slug"
      if [ "$malformed" = 1 ]; then printf 'stalled:malformed_exit_signal'; else printf 'stalled'; fi
      return 0
    fi
  done
}

# Sleep in beat-sized chunks so the heartbeat keeps ticking through a LEGITIMATE pause. Without
# this the 30-minute launch-retry sleep would look exactly like a dead conductor to the reaper.
_beat_sleep() {  # slug secs
  local slug="$1" left="$2" chunk
  chunk="$QUEUE_POLL_SECS"; [ "$chunk" -gt 0 ] 2>/dev/null || chunk=15
  while [ "$left" -gt 0 ]; do
    _beat "$slug"
    if [ "$left" -le "$chunk" ]; then sleep "$left"; left=0; else sleep "$chunk"; left=$((left - chunk)); fi
  done
  _beat "$slug"
}

# Launch a row with the single-retry launch-failure policy. Prints the FINAL verdict
# (done|gated|stalled|error) on stdout.
_run_row() {  # slug repo pointer
  local slug="$1" repo="$2" pointer="$3" v rc
  v=$(_launch_once "$slug" "$repo" "$pointer"); rc=$?
  if [ "$rc" -eq 2 ]; then
    _warn "queue: $slug launch failed; sleeping ${QUEUE_RETRY_SLEEP_SECS}s then retrying once."
    _beat_sleep "$slug" "$QUEUE_RETRY_SLEEP_SECS"
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
  # `read -ra` splits on whitespace WITHOUT pathname expansion. A bare `for glob in
  # $QUEUE_ALLOWED_POINTER_GLOB` globs the patterns against the CWD first, so running from a
  # directory that happens to contain `_meta/megagoals/` replaced the literal pattern with real
  # subdirectory paths and made every legitimate pointer fail the check (found while wiring the
  # SPEC-217 watcher, which calls this function from the repo root). The `case` match below is the
  # glob that was ever intended.
  local globs=()
  IFS=' ' read -ra globs <<< "$QUEUE_ALLOWED_POINTER_GLOB"
  for glob in "${globs[@]}"; do
    # shellcheck disable=SC2254 # QUEUE_ALLOWED_POINTER_GLOB is operator config; glob match intended.
    case "$rel" in $glob) return ;; esac
  done
  printf 'pointer "%s" not allow-listed (want one of: %s)' "$rel" "$QUEUE_ALLOWED_POINTER_GLOB"
}

# ---- circuit breaker (SPEC-221) ----------------------------------------------------------------
# The FOUR no-progress escape hatches, ported because git-diff-only stall detection produces false
# stalls and that is precisely the failure this guard must not have.
#
# Prints one of:
#   "verified" -- the REPO actually moved. Independently checked, so it may reset every counter.
#   "reported" -- the RUN says it made progress. Self-attested and unverifiable.
#   "freeze"   -- the run stopped to ask something: neither progress nor stagnation.
#   ""         -- nothing.
#
# The verified/reported split is load-bearing (security + architecture review, HIGH). Hatches 2-4
# read `<slug>.status`, which the RUN itself writes. If a self-report could reset the STALL
# counter, any run that emits `FILES_CHANGED: 1` (or `QUESTION: true`) on every attempt would never
# accrue a stall, never back off, and never quarantine: the guard's central promise, opted out of
# by the exact population most likely to need it, whether through a hostile Notes cell (ID-459) or
# an agent that merely over-reports itself. So self-report may calm the BREAKER, and only a real
# repo delta may clear the STALL ladder.
_progress_evidence() {  # slug repo head-before
  local slug="$1" repo="$2" before="$3" after files

  # Hatch 1 FIRST, because it is the only independently verifiable one. Guarded on a real
  # directory because `git -C ""` silently falls back to the CURRENT directory: unguarded, the
  # reaper (which does not know a slug's repo) would read the operator's cwd and call its dirty
  # tree this row's progress. Caught by the A4 stall-counter assertion.
  if [ -n "$repo" ] && [ -d "$repo" ]; then
    after=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
    { [ -n "$after" ] && [ -n "$before" ] && [ "$after" != "$before" ]; } && { printf 'verified'; return; }
    [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ] && { printf 'verified'; return; }
  fi

  # Hatch 4: a question freezes the counters. Counting it as stagnation would quarantine exactly
  # the rows most worth a human's attention.
  [ "$(_status_get "$slug" QUESTION)" = "true" ] && { printf 'freeze'; return; }

  # Hatch 3: an explicit completion the run claims for itself.
  [ "$(_exit_signal "$slug")" = "true" ] && { printf 'reported'; return; }

  # Hatch 2: the run's own file count. Parallel evidence to the git view, never a replacement.
  files=$(_status_get "$slug" FILES_CHANGED)
  case "$files" in ''|*[!0-9]*) ;; *) [ "$files" -gt 0 ] && { printf 'reported'; return; } ;; esac
}

# Update the counters for one finished run and print the verdict to journal, which is the input
# verdict UNLESS the breaker trips. Terminal verdicts (`done`/`gated`) are never rewritten: a
# legitimate investigate-and-report row changes no files and must not be called stagnation for it.
# The stall ladder. Only a `stalled` verdict climbs it, and every climb schedules the next alarm
# from the SAME freshly-read count, so `stalls` and `retry_after` can never disagree.
_stall_bump() {  # slug verdict
  local st
  [ "$2" = stalled ] || return 0
  st=$(( $(_guard_num "$1" stalls) + 1 ))
  _guard_set "$1" stalls "$st"
  _schedule_retry "$1" "$st"
}

_breaker_apply() {  # slug repo head-before verdict -> "verdict<TAB>reason"
  local slug="$1" repo="$2" before="$3" verdict="$4" ev np se now

  case "$verdict" in
    done|gated)
      _guard_clear "$slug"
      printf '%s\t' "$verdict"; return ;;
  esac

  ev=$(_progress_evidence "$slug" "$repo" "$before")

  if [ "$ev" = verified ]; then
    # A REAL repo delta zeroes every counter INCLUDING the stall ladder. This is what keeps a
    # productive-but-slow row (real commits, then the 2h cap) out of quarantine.
    _guard_set "$slug" noprogress 0
    _guard_set "$slug" sameerror 0
    _guard_set "$slug" stalls 0
    _guard_set "$slug" retry_after ""
    printf '%s\t' "$verdict"; return
  fi

  # `reported` (self-attested) calms the BREAKER only; `freeze` (a question) calms neither but
  # accuses of nothing. NEITHER may clear the stall ladder, so a run that claims progress, or keeps
  # stopping to ask, still climbs toward quarantine and eventually reaches a human.
  if [ "$ev" = reported ]; then
    _guard_set "$slug" noprogress 0
    _guard_set "$slug" sameerror 0
  fi
  if [ "$ev" = reported ] || [ "$ev" = freeze ]; then
    _stall_bump "$slug" "$verdict"
    printf '%s\t' "$verdict"; return
  fi

  np=$(( $(_guard_num "$slug" noprogress) + 1 )); _guard_set "$slug" noprogress "$np"
  se=$(_guard_num "$slug" sameerror)
  if [ "$verdict" = error ]; then se=$((se + 1)); _guard_set "$slug" sameerror "$se"; fi
  _stall_bump "$slug" "$verdict"

  if [ "$np" -ge "$QUEUE_NOPROGRESS_TRIP" ] || [ "$se" -ge "$QUEUE_SAMEERROR_TRIP" ]; then
    now=$(date +%s)
    _guard_set "$slug" cooldown_until $((now + QUEUE_COOLDOWN_SECS))
    printf 'error\tstagnation_detected'; return
  fi
  printf '%s\t' "$verdict"
}

# Write the jittered re-pick alarm after a stall. On the Nth stall the alarm is written EMPTY,
# which no comparison can satisfy: that empty field IS the quarantine, not a new state.
_schedule_retry() {  # slug stall-count
  local slug="$1" stalls="$2" now mins
  if [ "$stalls" -ge "$QUEUE_MAX_STALLS" ]; then
    _guard_set "$slug" retry_after ""
    return
  fi
  now=$(date +%s)
  mins=$(( (RANDOM % QUEUE_RETRY_JITTER_SPAN) + QUEUE_RETRY_JITTER_MIN ))
  _guard_set "$slug" retry_after $((now + mins * 60))
}

# ---- protected paths (SPEC-223) ----------------------------------------------------------------
# Print a reason if the run touched a path an unattended run may not write, else nothing.
#
# DETECTION, NOT PREVENTION, and the distinction is the whole honest claim: the launched session
# runs `--dangerously-skip-permissions`, so no bash wrapper can intercept a write. What this does is
# make such a write TERMINAL and visible, `gated` rather than a silent ship. Both surfaces are read
# because a run may commit (diff against the pre-launch HEAD) or leave the tree dirty (status).
#
# `_progress_evidence` above reads the SAME two git surfaces for a different question (did the repo
# move at all). Kept separate on purpose: one asks "was there progress", this asks "was a protected
# path touched", and merging them would couple the breaker's evidence rules to the deny-glob's.
# If a third caller ever needs the changed-path set, snapshot it once and pass it to both
# (architecture review, LOW: two derivations of one fact can drift).
_protected_touched() {  # repo head-before
  local repo="$1" before="$2" p r
  { [ -n "$repo" ] && [ -d "$repo" ]; } || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    r=$(protected_path_reason "$p")
    [ -n "$r" ] && { printf '%s' "$r"; return; }
  done < <(
    { [ -n "$before" ] && git -C "$repo" diff --name-only "$before" HEAD 2>/dev/null
      # `status --porcelain` prefixes two status columns and a space. A rename prints `old -> new`,
      # and a failed glob match on THAT string is a false negative in a deny-list, not a safe
      # default: `git mv scratch.md CLAUDE.md`, left staged, would ship ungated (security review,
      # HIGH). So emit both sides of a rename as separate paths.
      git -C "$repo" status --porcelain 2>/dev/null | cut -c4- \
        | sed -e 's/ -> /\'$'\n''/'
    } | sort -u
  )
}

# ---- run --------------------------------------------------------------------------------------
cmd_run() {
  local src="" dry=0 max=0 from_boards=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)    dry=1; shift ;;
      --sanitize-prompt) QUEUE_SANITIZE_PROMPT=1; shift ;;
      # A board emit is untrusted by the same reasoning that gave it a pointer allow-list: it was
      # not authored by the operator.
      --from-boards) from_boards=1; QUEUE_SANITIZE_PROMPT=1; shift ;;
      --max-megas)  max="${2:-0}"; shift 2 ;;
      --journal)    QUEUE_JOURNAL="${2:-$QUEUE_JOURNAL}"; shift 2 ;;
      # SPEC-224: open a NORMAL PR instead of the unattended draft default (OpenHands draft=False).
      --ready)      QUEUE_PR_READY=1; shift ;;
      --*)          _warn "queue: unknown flag '$1'"; return 64 ;;
      *)            src="$1"; shift ;;
    esac
  done
  if [ "$from_boards" != 1 ] && { [ -z "$src" ] || [ ! -f "$src" ]; }; then
    _warn "queue: no queue source (want a tsv path or --from-boards)"; return 64
  fi

  local consec_fail=0 attempts=0 total_calls=0 slug repo pointer reason verdict head_before brk_verdict brk_reason
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
    # Fail closed BEFORE a window opens: on the untrusted path, no sanitizer means no launch.
    if [ -z "$reason" ] && [ "$QUEUE_SANITIZE_PROMPT" = 1 ] && ! command -v "$QUEUE_PERL_CMD" >/dev/null 2>&1; then
      reason="the untrusted-input pass cannot run (perl not found)"
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
    # Snapshot HEAD before the window opens: hatch 1 of the breaker's progress evidence.
    head_before=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
    verdict=$(_run_row "$slug" "$repo" "$pointer")

    case "$verdict" in
      gated:*)   reason="${verdict#gated:}"; verdict=gated ;;
      stalled:*) reason="${verdict#stalled:}"; verdict=stalled ;;
      *)         reason="" ;;
    esac
    # SPEC-221: counters + the trip decision. May rewrite a NON-terminal verdict to `error`.
    # _breaker_apply always prints exactly `verdict<TAB>reason`; an empty reason keeps the one
    # the run itself produced (a `gated:` pane reason, or `malformed_exit_signal`).
    IFS=$'\t' read -r brk_verdict brk_reason <<< "$(_breaker_apply "$slug" "$repo" "$head_before" "$verdict")"
    verdict="$brk_verdict"
    [ -n "$brk_reason" ] && reason="$brk_reason"
    # SPEC-223: a protected path written by an untrusted-path run outranks every other verdict,
    # including `done`. `gated` is terminal, so the row stops here and a human looks at it.
    if [ "$QUEUE_SANITIZE_PROMPT" = 1 ]; then
      local prot; prot=$(_protected_touched "$repo" "$head_before")
      if [ -n "$prot" ]; then verdict=gated; reason="$prot"; fi
    fi
    # The run is over: drop the in-flight claim so the watcher may consider this slug again.
    _beat_clear "$slug"
    _journal_append "$slug" "$verdict" "$reason"
    _say "[queue] $slug: $verdict${reason:+ ($reason)}."

    # SPEC-224 queue-wide spend ceiling. Accumulate the run's self-reported tool-calls; once the
    # BATCH total crosses the ceiling, the current row has already finished + shipped (SWE-agent:
    # the instance autosubmits before the batch halts), so only the REMAINING rows are skipped.
    if [ "$QUEUE_MAX_TOTAL_TOOL_CALLS" -gt 0 ]; then
      total_calls=$((total_calls + $(_status_num "$slug" TOOL_CALLS)))
      if [ "$total_calls" -ge "$QUEUE_MAX_TOTAL_TOOL_CALLS" ]; then
        _warn "[queue] SPEND CEILING: queue-wide tool-call total $total_calls >= $QUEUE_MAX_TOTAL_TOOL_CALLS; aborting remaining rows."
        return 0
      fi
    fi

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
    run)   cmd_run "$@" ;;
    # The backlog watcher (SPEC-217): a filter that turns `#auto`-marked queued board rows into
    # the same TSV `run` above consumes. It owns its own flags, so this is a forward, not a wrapper.
    watch) exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/watch-board.sh" "$@" ;;
    *)     _warn "usage: queue.sh run <src.tsv> [--dry-run] [--max-megas N] [--from-boards] [--journal <path>]"
           _warn "       queue.sh watch [--apply] [--max N] [--board <path>]"; exit 64 ;;
  esac
}

# Run main only when executed, not when sourced (tests source + call helpers directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
