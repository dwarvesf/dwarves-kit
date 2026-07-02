#!/usr/bin/env bash
# orchestrate.sh -- drive a mega-goal as ONE fresh `claude -p` session per sub-goal, so the
# loop lives in this dumb (non-LLM) driver and no session accumulates more than one sub-goal's
# context (SPEC-087, ADR-0027). Each `claude -p` is a new session, so the `/clear` between
# sub-goals is free; the kit never self-`/clear`s. Each sub-goal session writes HANDOFF.md for
# the next, and the orchestrator injects it (re-discovery becomes a read). The driver MUST stay
# non-LLM: an LLM orchestrator spawning a subagent per sub-goal would re-accumulate every return
# and become the new marathon (DEC-004).
#
# Usage:
#   orchestrate.sh next <megagoal-dir>             print the next unchecked sub-goal + policy
#   orchestrate.sh run  <megagoal-dir> [--dry-run] [--step] [--stream]
#       --dry-run  print the plan only (no claude)
#       --step     pause for the operator after each sub-goal (resume on Enter, q to stop)
#       --stream   stream each session live (stream-json) + capture to .orchestrate/<id>.stream.jsonl
#       --board=roadmap|kanban|both  surface progress as a per-mega-goal kanban (SG-10); default
#                  detects (backlog.sh present -> both, else roadmap). Event-sourced + derived;
#                  ROADMAP.md stays canonical, the repo-wide BACKLOG cockpit is never touched.
#   --step/--stream are opt-in; default behavior is unchanged (SG-01, SPEC-087 Mechanism A).
#   Env (SG-11 robustness, advisory): WATCHDOG_STALL_SECS>0 backgrounds each session + flags it
#   `stalled` after that many seconds with no output (WATCHDOG_POLL_SECS poll interval); never
#   kills. Default 0 = off (synchronous path unchanged). A dead/incomplete session never advances
#   its box (`[guardrail]` halt); a sub-goal with no goals/ file warns before launch.
#
# <megagoal-dir> holds: ROADMAP.md (sub-goal lines `- [ ] SG-NN ... , auto|gate , ...`),
# POINTER_PROMPT.md (static resume prompt), HANDOFF.md (feed-forward, written by each sub-goal).
# Grounded completion: a sub-goal session MUST flip its ROADMAP checkbox to [x]; the
# orchestrator advances only then (no self-claim). It STOPS at the first `gate` sub-goal
# (shared-repo review needs a human).
#
# The `claude` invocation is `$CLAUDE_CMD` (default: claude), so tests mock it and operators
# tune the permission flags.
set -uo pipefail

CLAUDE_CMD="${CLAUDE_CMD:-claude}"
# Permission posture for the unattended sub-goal session (SPEC-087 "Session invocation"). Default
# is full access so the session can edit/commit/push/open-PR without a permission wall stalling
# the loop; override with a tighter `--allowedTools` allowlist or an agentkernel sandbox via
# CLAUDE_CMD. Word-split intentionally (operator config, not user data). Tests set CLAUDE_FLAGS=""
# so the mock's prompt stays the last arg.
CLAUDE_FLAGS="${CLAUDE_FLAGS:---dangerously-skip-permissions}"

# Hot-handoff size cap (SPEC-087 Mechanism B, two-tier). The HOT HANDOFF.md is injected in full,
# so it must stay small or it recreates the marathon. Over the cap -> inject head + a notice and
# point at the file. The WARM DECISIONS.md ledger is never injected in full (pointer only).
HANDOFF_MAX_LINES="${HANDOFF_MAX_LINES:-80}"

# Deterministic handoff (token-optim-v3 SG-02). Off (0) by default -> the per-session invocation
# stays byte-identical and the LLM session writes its own HANDOFF.md/DECISIONS.md (unchanged). On
# (1) -> the session is captured to stream-json and, after grounded completion, the two-tier
# handoff is REGENERATED deterministically from that transcript by lib/handoff-gen (SPEC-087 Mech
# B fields preserved; no LLM in the handoff path). Always-produced + reproducible beats
# occasionally-excellent-but-skippable.
DETERMINISTIC_HANDOFF="${DETERMINISTIC_HANDOFF:-0}"

# Kanban renderer reused by the board-view (SG-10). Resolved next to this script; override in
# tests. When absent, board mode fail-safes to roadmap-only so a kit without the tooling runs.
ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_LIB="${BACKLOG_LIB:-$ORCH_DIR/backlog.sh}"

# Loop robustness (SG-11, advisory). WATCHDOG_STALL_SECS=0 (default) keeps the synchronous run
# path UNCHANGED. >0 backgrounds each session and polls every WATCHDOG_POLL_SECS: if the session
# emits no output for WATCHDOG_STALL_SECS while its process is still alive, it is flagged
# `stalled` (event + warn) -- never killed (flag, don't kill). Liveness is a `kill -0` probe (no
# daemon, per the pi-swarm thesis).
WATCHDOG_STALL_SECS="${WATCHDOG_STALL_SECS:-0}"
WATCHDOG_POLL_SECS="${WATCHDOG_POLL_SECS:-30}"

# Flip-lock stale-reclaim threshold (SPEC-106 TASK-002 / DEC-009). The box-flip mutual-exclusion
# primitive is a `mkdir` lock (atomic on POSIX; flock is absent on macOS and unused in this repo).
# A lock whose recorded holder PID is DEAD (crashed) is reclaimed immediately; a lock with no
# readable PID (a racy just-created lock) is reclaimed only after this many seconds. Default 120.
# FLIP_LOCK_POLL_SECS is the short retry sleep while the lock is held by a live holder.
FLIP_LOCK_STALE_SECS="${FLIP_LOCK_STALE_SECS:-120}"
FLIP_LOCK_POLL_SECS="${FLIP_LOCK_POLL_SECS:-0.1}"

# Wavefront concurrency cap (SPEC-106 DEC-002/009). Default 1 = waves OFF: the run loop takes the
# serial path always, byte-identical to the pre-wavefront loop. >=2 opts into concurrent waves. A
# non-numeric or <1 value is REJECTED at cmd_run entry (see the validation there), NOT silently
# coerced, per DEC-009 / Edge case 4. Defaulted here so the top-of-loop `-ge 2` test is `set -u`-safe.
WAVE_CAP="${WAVE_CAP:-1}"

# Wave-convergence merge hook (SPEC-106 TASK-004c). After a wave lands its sub-goals on their worktree
# branches, their merges back to the mega-goal base MUST happen ONE AT A TIME under the flip lock (see
# `_wave_converge`); the actual merge goes through THIS mockable hook. Default is the real path
# (`lib/mega-merge.sh merge`, whose semantics stay untouched , convergence only SEQUENCES calls to it),
# but real gh-backed merge is DEFERRED to ID-085-followup (waves are off at the default WAVE_CAP=1, and
# a real merge needs `gh` + real PRs). Tests set WAVE_MERGE_CMD to a mock that records merge ordering.
# Word-split intentionally (operator config, not user data), mirroring CLAUDE_FLAGS.
WAVE_MERGE_CMD="${WAVE_MERGE_CMD:-$ORCH_DIR/mega-merge.sh merge}"

_say() { printf '%s\n' "$*"; }

# Portable file mtime (epoch secs). GNU `stat -c` FIRST: it errors cleanly on BSD/macOS, so the
# `stat -f` fallback runs there; the reverse order is unsafe because GNU `stat -f` SUCCEEDS with
# filesystem text (starting "File:"), starving the fallback and poisoning `$(( ))`. Digit-guarded
# so any non-numeric stat output yields empty rather than breaking arithmetic. Empty if absent.
_mtime() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)
  case "$m" in ''|*[!0-9]*) return 0 ;; *) printf '%s' "$m" ;; esac
}

# ---- Portable mkdir-based mutual exclusion (SPEC-106 TASK-002 / DEC-009) ----------------------
# `mkdir "$lockdir"` is the atomic acquire (NOT `flock`: absent on macOS, zero repo usage). The
# holder writes its PID to "$lockdir/pid"; `_lock` blocks/retries with a short sleep until it wins.
# A STALE lock is reclaimed ONLY when: [ -n "$lockdir" ] AND the recorded PID fails `kill -0` (the
# holder crashed) OR the lock age exceeds FLIP_LOCK_STALE_SECS AND that PID is dead. Reclaim is
# `rmdir` after moving the pid file aside -- NEVER `rm -rf` (rmdir refuses a non-empty/odd path).

# 0 = stale (reclaimable) / 1 = fresh. A LIVE holder PID is never stale (the holder is working);
# a DEAD recorded PID is stale (crash); an unreadable/absent PID is stale only past the timeout so
# a lock created microseconds ago (mkdir done, pid not yet written) is never yanked out of a race.
_lock_stale() {  # lockdir
  local lockdir="$1" pid age now mt
  [ -n "$lockdir" ] || return 1
  [ -d "$lockdir" ] || return 1
  pid=$( [ -f "$lockdir/pid" ] && tr -dc '0-9' < "$lockdir/pid" 2>/dev/null )  # guard the open: benign mkdir-before-pid-write race must not leak stderr
  if [ -n "$pid" ]; then
    kill -0 "$pid" 2>/dev/null && return 1   # holder alive -> not stale
    return 0                                  # recorded holder dead -> reclaim (crashed)
  fi
  now=$(date +%s); mt=$(_mtime "$lockdir"); [ -n "$mt" ] || return 1
  age=$((now - mt))
  [ "$age" -ge "$FLIP_LOCK_STALE_SECS" ] && return 0 || return 1
}

# Reclaim a stale lock: move the stale pid file aside (never `rm`), then `rmdir` the emptied dir.
_lock_reclaim() {  # lockdir
  local lockdir="$1"
  [ -n "$lockdir" ] || return 1
  [ -e "$lockdir/pid" ] && mv -f "$lockdir/pid" "${TMPDIR:-/tmp}/flip-stale-pid.$$.$RANDOM" 2>/dev/null
  rmdir "$lockdir" 2>/dev/null
}

# Acquire the lock (blocks until held), writing our PID into it; reclaims a crashed holder.
_lock() {  # lockdir
  local lockdir="$1"
  [ -n "$lockdir" ] || { echo "_lock: empty lockdir" >&2; return 64; }
  mkdir -p "$(dirname "$lockdir")" 2>/dev/null || true
  while :; do
    if mkdir "$lockdir" 2>/dev/null; then
      printf '%s\n' "$$" > "$lockdir/pid"
      return 0
    fi
    if _lock_stale "$lockdir"; then _lock_reclaim "$lockdir"; continue; fi
    sleep "$FLIP_LOCK_POLL_SECS"
  done
}

# Release a lock we hold (or an empty one); never yank a different LIVE holder's lock.
_unlock() {  # lockdir
  local lockdir="$1" pid
  [ -n "$lockdir" ] || return 0
  [ -d "$lockdir" ] || return 0
  pid=$( [ -f "$lockdir/pid" ] && tr -dc '0-9' < "$lockdir/pid" 2>/dev/null )  # guard the open: benign mkdir-before-pid-write race must not leak stderr
  if [ -z "$pid" ] || [ "$pid" = "$$" ]; then
    [ -e "$lockdir/pid" ] && mv -f "$lockdir/pid" "${TMPDIR:-/tmp}/flip-own-pid.$$.$RANDOM" 2>/dev/null
    rmdir "$lockdir" 2>/dev/null
  fi
}

# Emit "id<TAB>policy<TAB>checked(0|1)" per sub-goal line, in ROADMAP order.
# Policy is the comma-separated field that EQUALS auto|gate after trim (not a regex hit on the
# description, so "(gate review)" or "gate-aware" do not false-match). Unknown -> gate (fail-safe:
# a malformed line stops the loop for a human rather than silently auto-running). The trailing
# `|| true` keeps a no-match grep from escaping under `set -o pipefail`.
_subgoals() {
  local roadmap="$1"
  grep -E '^- \[[ xX]\] SG-[0-9]+' "$roadmap" 2>/dev/null | while IFS= read -r line; do
    local id policy checked=0
    id=$(printf '%s' "$line" | grep -oE 'SG-[0-9]+' | head -1)
    [ -n "$id" ] || continue
    policy=$(printf '%s' "$line" | awk -F',' '{for(i=1;i<=NF;i++){f=$i; gsub(/^[ \t]+|[ \t]+$/,"",f); lf=tolower(f); if(lf=="auto"||lf=="gate"){print lf; exit}}}')
    case "$line" in
      '- ['[xX]']'*) checked=1 ;;
    esac
    printf '%s\t%s\t%s\n' "$id" "${policy:-gate}" "$checked"
  done || true
}

# Next unchecked sub-goal as "id<TAB>policy", or empty.
_next() { _subgoals "$1" | awk -F'\t' '$3==0 {print $1"\t"$2; exit}'; }

# Wavefront ready set (SPEC-106 TASK-001): every sub-goal that is unchecked AND has no blocking
# deps, in ROADMAP order, as "id<TAB>policy" (the _subgoals shape minus the checked column).
# Ready = checked==0 AND `_sg_deps_blocked` empty (reuses the existing dep parser at L133; no
# reimplementation). PURE READ helper: it changes NO scheduling (nothing calls it into the run
# loop yet). Backward-compat invariant: on a no-deps ROADMAP nothing blocks, so it returns ALL
# unchecked sub-goals and its FIRST line equals `_next`'s pick (the size-1 superset invariant ,
# `_next` is `_ready_set | head -1` semantically). Process-sub (not a pipe) so the caller's shell
# owns the loop, matching _derive_board L172.
_ready_set() {
  local roadmap="$1" id policy checked line
  while IFS=$'\t' read -r id policy checked; do
    [ "$checked" = 0 ] || continue
    line=$(_sg_line "$roadmap" "$id")
    [ -z "$(_sg_deps_blocked "$roadmap" "$line")" ] && printf '%s\t%s\n' "$id" "$policy"
  done < <(_subgoals "$roadmap")
}

# ---- SG-10 board-view / event-sourced status -----------------------------------------------
# Event-sourced status (pi-swarm borrow): the loop APPENDS status events; the board is DERIVED
# by replay (last event per sub-goal wins), NEVER mutated in place -> a crashed/concurrent
# session cannot corrupt a checkbox. ROADMAP.md + the goal files stay canonical; the board is a
# regenerated view-sync. SG-11's watchdog reuses this file (mtime + last status) as its signal.
_events_file() { printf '%s/.orchestrate/events.log\n' "$1"; }

_emit_event() {  # dir id status [note]
  local dir="$1" id="$2" status="$3" note="${4:-}" ef
  ef=$(_events_file "$dir"); mkdir -p "$(dirname "$ef")"
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$status" "$note" >> "$ef"
}

# Last event for a sub-goal by replay, as "status<TAB>note" (empty if none).
_event_status() {  # dir id
  local ef; ef=$(_events_file "$1")
  [ -f "$ef" ] || return 0
  awk -F'\t' -v id="$2" '$2==id{s=$3; n=$4} END{ if(s!="") printf "%s\t%s", s, n }' "$ef"
}

# Raw ROADMAP line for a sub-goal id (or empty).
_sg_line() { grep -E "^- \[[ xX]\] $2 " "$1" 2>/dev/null | head -1; }

# Human title from a ROADMAP line: text after "SG-NN " up to the first " , " policy separator.
_sg_title() {  # raw-line id
  printf '%s' "$1" | sed -E "s/^- \[[ xX]\] $2 //; s/ , .*$//" | cut -c1-60
}

# Blocking deps: SG-NN tokens in the line's `depends ...` tail that are NOT yet checked (space-
# separated, empty if none). Non-SG deps (e.g. #81 = a prerequisite PR) are out of board scope.
_sg_deps_blocked() {  # roadmap raw-line
  local roadmap="$1" line="$2" deps d blockers=""
  deps=$(printf '%s' "$line" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' || true)
  for d in $deps; do
    _subgoals "$roadmap" | awk -F'\t' -v i="$d" '$1==i && $3==1{f=1} END{exit !f}' || blockers="$blockers $d"
  done
  printf '%s' "${blockers# }"
}

# Dependents test (SPEC-106 TASK-005): does any OTHER sub-goal's `depends` list name <id>?
# Exit 0 iff <id> HAS DEPENDENTS (something feeds forward FROM it), else nonzero. Reuses the same
# `depends SG-NN` token parse as _sg_deps_blocked (no new format). Read-only. This is the WRITE-side
# key: a sub-goal writes HANDOFF-<id>.md only when this holds; a leaf / linear-tail has none and
# keeps writing plain HANDOFF.md, so the no-deps mega-goal stays byte-identical.
_sg_dependents() {  # roadmap id
  local roadmap="$1" id="$2" other _p _c line deps d
  while IFS=$'\t' read -r other _p _c; do
    [ "$other" = "$id" ] && continue
    line=$(_sg_line "$roadmap" "$other")
    deps=$(printf '%s' "$line" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' || true)
    for d in $deps; do
      [ "$d" = "$id" ] && return 0
    done
  done < <(_subgoals "$roadmap")
  return 1
}

# Derive the per-mega-goal BOARD.md (kanban table in backlog.sh's row format, so backlog.sh
# renders it and the cockpit format stays consistent). State = shipped if the box is checked,
# else the replayed event status, else dep-analysis (queued=ready / parked=blocked). The
# ready/blocked/stalled nuance rides as status PROSE (backlog.sh supports it). Prints the path.
_derive_board() {  # dir roadmap
  local dir="$1" roadmap="$2"
  local board="$dir/BOARD.md"
  {
    printf '# Board (derived view): %s\n\n' "$(basename "$dir")"
    printf '> DERIVED by "orchestrate.sh --board" from ROADMAP.md + .orchestrate/events.log. Do NOT\n'
    printf '> hand-edit: ROADMAP.md + the goal files are canonical; this is a regenerated view-sync.\n'
    printf '> Per-mega-goal only; the repo-wide BACKLOG cockpit is never touched.\n\n'
    printf '## Active queue\n\n'
    printf '| ID | Item | Notes & source | Status |\n'
    printf '|----|------|----------------|--------|\n'
    local id policy checked line title es estatus enote status blockers
    while IFS=$'\t' read -r id policy checked; do
      line=$(_sg_line "$roadmap" "$id"); title=$(_sg_title "$line" "$id")
      es=$(_event_status "$dir" "$id")
      estatus=$(printf '%s' "$es" | cut -f1); enote=$(printf '%s' "$es" | cut -f2)
      if [ "$checked" = 1 ]; then
        status="shipped"
      elif [ "$estatus" = executing ] || [ "$estatus" = stalled ]; then
        status="executing"
        [ "$estatus" = stalled ] && status="executing [stalled${enote:+: $enote}]"
      else
        blockers=$(_sg_deps_blocked "$roadmap" "$line")
        if [ -n "$blockers" ]; then status="parked [blocked: needs $blockers]"; else status="queued [ready]"; fi
      fi
      printf '| %s | %s | %s | %s |\n' "$id" "${title:-?}" "$policy" "$status"
    done < <(_subgoals "$roadmap")
  } > "$board"
  printf '%s\n' "$board"
}

# Render the board surface to stdout for a mode. roadmap -> nothing (checkboxes ARE the view);
# kanban|both -> derive BOARD.md then render its columns via backlog.sh (fallback: cat the file).
_render_board() {  # dir roadmap mode
  local dir="$1" roadmap="$2" mode="$3" board
  case "$mode" in
    roadmap|"") return 0 ;;
    kanban|both)
      board=$(_derive_board "$dir" "$roadmap")
      _say "[board] derived per-mega-goal view -> $board (ROADMAP stays canonical)"
      if [ -f "$BACKLOG_LIB" ]; then
        BACKLOG_FILE="$board" bash "$BACKLOG_LIB" board 2>/dev/null || cat "$board"
      else
        cat "$board"
      fi ;;
    *) echo "unknown --board mode: '$mode' (want roadmap|kanban|both)" >&2; return 64 ;;
  esac
}

# Resolve the board mode: explicit wins; empty -> detect (backlog.sh present -> both, else
# roadmap so a kit without the kanban tooling still runs).
_resolve_board_mode() { if [ -n "$1" ]; then printf '%s' "$1"; elif [ -f "$BACKLOG_LIB" ]; then printf 'both'; else printf 'roadmap'; fi; }
# --------------------------------------------------------------------------------------------

# Resolve a sub-goal's goal file path (goals/<NN>-*.md), or empty.
_goalfile() {
  local dir="$1" id="$2" f
  for f in "$dir/goals/${id#SG-}-"*.md; do [ -f "$f" ] && { printf '%s\n' "$f"; return; }; done
}

# Wavefront admission gate (SPEC-106 TASK-003, DEC-007/011/012). PURE DECISION helper: it decides
# which ready sub-goals may run concurrently; it spawns NOTHING and is not yet wired into cmd_run
# (that is TASK-004). Reads the ready set (`_ready_set`), then admits GREEDILY in ROADMAP order , a
# candidate is admitted iff (a) its goal file declares its OWN `## Touches` section AND (b) it proves
# disjoint (dispatch-gate.sh, the ONE disjointness authority per DEC-001) against EVERY already-
# admitted member. Admission stops at WAVE_CAP (env, default 1 => at most one `run`, serial default).
#
# Self-Touches is REQUIRED (DEC-012b): dispatch-gate admits the FIRST member vacuously (empty admitted
# set => nothing to prove disjoint against), so without demanding the candidate's own `## Touches` a
# Touches-less sub-goal would be wrongly admitted. A goal file with no `## Touches` => always `defer`
# (the Option-B opt-in gate).
#
# dispatch-gate.sh is REUSED as a SUBPROCESS (`bash "$gate" touches|disjoint ...`), NOT sourced: it
# runs `set -euo pipefail` at load, which would leak `-e` into this driver's deliberate `set -uo`
# posture (L33) and break the sourced test harness. The subprocess boundary contains that; a fork per
# pair is negligible for a wave-launch decision over a small ready set. `disjoint` exit 0 = provably
# disjoint (admit-eligible); any nonzero (1 overlap / 2 undeclared) = not disjoint => defer.
#
# Output: one `run<TAB>id` or `defer<TAB>id` line per ready sub-goal, in ROADMAP order. Wire format
# per SPEC-106 "Helper wire formats". bash-3.2 safe: no assoc-arrays; the admitted set is a plain
# array of goal-file paths, empty-guarded `${arr[@]+"${arr[@]}"}` (DEC-005, mega-merge.sh:224).
# Process-sub (not a pipe) feeds the loop so the admitted state lives in THIS shell, not a subshell.
_wave_gate() {  # megadir roadmap
  local megadir="$1" roadmap="$2"
  local cap="${WAVE_CAP:-1}"
  # Defensive numeric guard: a non-numeric/empty cap would make the `-lt` test emit a bash integer
  # error. The parse-time rejection of `<1`/non-numeric WAVE_CAP is TASK-004b's wiring boundary; this
  # helper only ever sees a validated cap in the wired path, so falling back to 1 here is belt-and-
  # braces for a direct call, never a substitute for that rejection.
  case "$cap" in ''|*[!0-9]*) cap=1 ;; esac
  local gate="$ORCH_DIR/dispatch-gate.sh"
  local admitted_files=() admitted_n=0
  local id policy gf a decision ok
  while IFS=$'\t' read -r id policy; do
    [ -n "$id" ] || continue
    decision=defer
    gf=$(_goalfile "$megadir" "$id")
    # (a) self-Touches REQUIRED, and (b) room under the cap, and (c) disjoint vs every admitted member.
    if [ -n "$gf" ] && [ -n "$(bash "$gate" touches "$gf" 2>/dev/null)" ] && [ "$admitted_n" -lt "$cap" ]; then
      ok=1
      for a in ${admitted_files[@]+"${admitted_files[@]}"}; do
        bash "$gate" disjoint "$gf" "$a" >/dev/null 2>&1 || { ok=0; break; }
      done
      if [ "$ok" = 1 ]; then
        decision=run
        admitted_files+=("$gf")
        admitted_n=$((admitted_n + 1))
      fi
    fi
    printf '%s\t%s\n' "$decision" "$id"
  done < <(_ready_set "$roadmap")
}

# Emit "model<TAB>effort" read from a goal file's `Model:`/`Effort:` lines (empty when absent).
# Bare `Key: value` header lines, not YAML; first match each, value trimmed. Absent field or
# absent file -> empty -> the orchestrator emits no flag and the session inherits its tier
# (SPEC-087 "Model / Effort routing"). The biggest $ lever: Opus only on the hard sub-goals.
_route() {
  local gf="${1:-}" model="" effort=""
  if [ -f "$gf" ]; then
    model=$(grep -iE '^Model:[[:space:]]*' "$gf" | head -1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+$//')
    effort=$(grep -iE '^Effort:[[:space:]]*' "$gf" | head -1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+$//')
  fi
  printf '%s\t%s\n' "$model" "$effort"
}

# Emit a gate-ledger START for a dispatched sub-goal (SPEC-101 / ID-085), the automated
# mirror of the `gate-ledger.sh start` that `commands/assign.md` makes for hand-run work.
# Without it, mega-dispatched runs are untracked (`?` lane/type) in lane-telemetry, the root
# cause of the SPEC-073 eval's NULL lane/type/skip/escape rates. Advisory + non-fatal: a
# missing goal file or a goal file with no `**Branch:**` WARNs and skips (a rid that does not
# match the session's real branch would only orphan the START). The rid is derived from the
# goal file's declared `**Branch:** <type>/<slug>` (branch does not exist yet at dispatch;
# gate-ledger keys the ledger by the rid string, and `runid` is idempotent, so the driver's
# raw slug and the session's later normalized rid resolve to one ledger file). chosen ==
# classified on both axes: the automated path takes the classifier verbatim (no human
# override), which is honest and never reads as a misroute.
_emit_start() {  # dir id
  local dir="$1" id="$2"
  local gf; gf=$(_goalfile "$dir" "$id")
  [ -n "$gf" ] || return 0   # no goal file already warns loudly in cmd_run
  local branch slug
  branch=$(grep -iE '^\*\*Branch:\*\*' "$gf" | head -1 | sed -E 's/^\*\*[Bb]ranch:\*\*[[:space:]]*//; s/[[:space:]].*$//')
  if [ -z "$branch" ]; then
    echo "[orchestrate] [telemetry] WARN: $id goal file has no '**Branch:**' header; cannot derive rid, skipping START (run will be '?' in lane-telemetry)." >&2
    return 0
  fi
  slug="${branch#*/}"   # strip the type/ prefix, matching gate-ledger.sh rid
  local title lane type
  title=$(_sg_title "$(_sg_line "$dir/ROADMAP.md" "$id")" "$id")
  lane=$(bash "$ORCH_DIR/lane-classify.sh" classify "$title" 2>/dev/null | tail -1)
  type=$(bash "$ORCH_DIR/task-type-classify.sh" classify "$title" 2>/dev/null | tail -1)
  [ -n "$lane" ] || lane=normal
  [ -n "$type" ] || type=spec-feature
  bash "$ORCH_DIR/gate-ledger.sh" start "$slug" "$lane" "$lane" "$type" "$type" \
    && _say "[orchestrate] [telemetry] $id START recorded (rid=$slug lane=$lane type=$type)."
}

_build_prompt() {
  local dir="$1" id="$2"
  cat "$dir/POINTER_PROMPT.md" 2>/dev/null
  printf '\n\nNEXT SUB-GOAL: %s\n' "$id"
  # Inject the goal file's CONTENT (not just a path), so the session has the contract and
  # re-discovery is actually eliminated (SPEC-087 "Session invocation").
  local gf; gf=$(_goalfile "$dir" "$id")
  if [ -n "$gf" ]; then
    printf '\nGOAL FILE (%s, the contract for this sub-goal):\n' "$(basename "$gf")"
    cat "$gf"
  fi
  # Two-tier feed-forward (SPEC-087 Mechanism B):
  #   HOT  HANDOFF.md  -- overwritten each transition; injected in FULL but capped. Carries the
  #                      next action + read-pointers so re-discovery becomes a read.
  #   WARM DECISIONS.md -- append-only ledger of invariants + dead-ends; injected as a POINTER
  #                      only (path + size), read on demand, so it never bloats the prompt.
  # Per-edge feed-forward (SPEC-106 TASK-005): if <id> DECLARES deps, inject each dep-PARENT's
  # HANDOFF-<MM>.md (falling back to plain HANDOFF.md when the per-edge file is absent, so a chain
  # root that only wrote plain still feeds forward). A sub-goal with NO deps takes the ORIGINAL
  # plain path below UNCHANGED (byte-identical) -- do not fold the two together.
  local roadmap="$dir/ROADMAP.md" mydeps=""
  [ -f "$roadmap" ] && mydeps=$(printf '%s' "$(_sg_line "$roadmap" "$id")" | grep -oE 'depends[^,]*' | grep -oE 'SG-[0-9]+' || true)
  if [ -n "$mydeps" ]; then
    local mm hp lines
    printf '\nHOT HANDOFF from dep-parent(s) (verify before trusting):\n'
    for mm in $mydeps; do
      hp="$dir/HANDOFF-$mm.md"
      [ -s "$hp" ] || hp="$dir/HANDOFF.md"   # fallback: parent wrote plain HANDOFF.md, no per-edge file
      [ -s "$hp" ] || continue
      lines=$(wc -l < "$hp" | tr -d ' ')
      printf '\n-- from %s (%s):\n' "$mm" "$(basename "$hp")"
      if [ "$lines" -gt "$HANDOFF_MAX_LINES" ]; then
        head -n "$HANDOFF_MAX_LINES" "$hp"
        printf '[... %s truncated at %s/%s lines; read the file for the rest]\n' "$(basename "$hp")" "$HANDOFF_MAX_LINES" "$lines"
      else
        cat "$hp"
      fi
    done
  elif [ -s "$dir/HANDOFF.md" ]; then
    local lines; lines=$(wc -l < "$dir/HANDOFF.md" | tr -d ' ')
    printf '\nHOT HANDOFF from the previous sub-goal (verify before trusting):\n'
    if [ "$lines" -gt "$HANDOFF_MAX_LINES" ]; then
      head -n "$HANDOFF_MAX_LINES" "$dir/HANDOFF.md"
      printf '[... HANDOFF.md truncated at %s/%s lines; read the file for the rest]\n' "$HANDOFF_MAX_LINES" "$lines"
    else
      cat "$dir/HANDOFF.md"
    fi
  fi
  if [ -s "$dir/DECISIONS.md" ]; then
    local dlines; dlines=$(wc -l < "$dir/DECISIONS.md" | tr -d ' ')
    printf '\nWARM LEDGER: %s exists (%s lines) -- invariants + dead-ends. Read it on demand before re-deciding; it is NOT inlined here to keep this prompt lean.\n' "$dir/DECISIONS.md" "$dlines"
  fi
  # pi-swarm wording: the next session reads these records, not your transcript.
  # Per-edge WRITE target (SPEC-106 TASK-005): a sub-goal that HAS DEPENDENTS writes its own
  # HANDOFF-<id>.md so parallel siblings never clobber one hot file; a leaf / linear-tail keeps
  # writing plain HANDOFF.md, so the instruction stays byte-identical for the no-dependents case.
  local hf="HANDOFF.md"
  { [ -f "$roadmap" ] && _sg_dependents "$roadmap" "$id"; } && hf="HANDOFF-$id.md"
  printf '\nWhen you finish: report findings IN the records (overwrite %s with the next action + read-pointers as file:line; append durable invariants/dead-ends to DECISIONS.md), NOT only in your response text. The next sub-goal reads the files, not this transcript.\n' "$hf"
}

cmd_next() {
  local dir="${1:-}"
  [ -f "$dir/ROADMAP.md" ] || { echo "no ROADMAP.md in '$dir'" >&2; return 64; }
  local nx; nx=$(_next "$dir/ROADMAP.md")
  if [ -n "$nx" ]; then printf '%s\n' "$nx"; else _say "(none unchecked)"; fi
}

# cmd_flip <megadir> <id>: flip "- [ ] SG-NN" -> "- [x]" in the SHARED absolute-path
# `$megadir/ROADMAP.md` (never a per-sub-goal worktree copy: the driver only sees the shared one,
# SPEC-106 DEC-008), UNDER the flip lock, via write-temp-then-`mv` (atomic rename) so a concurrent
# reader/flip never sees a torn file. Idempotent: flipping an already-checked box is a no-op
# success. Unknown id -> nonzero + a clear message. NO scheduling is wired here (waves land later);
# this is the mutual-exclusion primitive the wave loop will call for grounded box-flips.
cmd_flip() {  # megadir id
  local megadir="${1:-}" id="${2:-}"
  [ -n "$megadir" ] && [ -n "$id" ] || { echo "usage: orchestrate.sh flip <megadir> <SG-NN>" >&2; return 64; }
  local roadmap="$megadir/ROADMAP.md"
  [ -f "$roadmap" ] || { echo "flip: no ROADMAP.md in '$megadir'" >&2; return 64; }
  [ -n "$(_sg_line "$roadmap" "$id")" ] || { echo "flip: unknown sub-goal '$id' in $roadmap" >&2; return 65; }

  local lockdir="$megadir/.orchestrate/flip.lock"
  _lock "$lockdir" || { echo "flip: could not acquire lock $lockdir" >&2; return 1; }

  # Re-read the line UNDER the lock: a sibling flip may have checked it since the pre-lock probe.
  local line rc=0
  line=$(_sg_line "$roadmap" "$id")
  case "$line" in
    '- ['[xX]']'*) _unlock "$lockdir"; return 0 ;;   # already checked -> idempotent no-op
  esac

  local tmp
  tmp=$(mktemp "$megadir/.roadmap.flip.XXXXXX" 2>/dev/null) || { _unlock "$lockdir"; echo "flip: mktemp failed" >&2; return 1; }
  if awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$roadmap" > "$tmp" && mv -f "$tmp" "$roadmap"; then
    _emit_event "$megadir" "$id" flip "box checked"
  else
    rc=1
    [ -e "$tmp" ] && mv -f "$tmp" "${TMPDIR:-/tmp}/flip-tmp.$$.$RANDOM" 2>/dev/null
    echo "flip: failed to write $roadmap" >&2
  fi
  _unlock "$lockdir"
  return "$rc"
}

# Pause after a completed sub-goal in --step mode. Reads ONE line from the driver's stdin (free:
# the prompt is fed to claude via a temp file, not here). Empty/y/c -> continue; q/n -> stop;
# EOF (no operator attached) -> stop (can't get consent, so don't march on). pi-swarm confirmAction.
_step_pause() {
  local id="$1" ans
  printf '[orchestrate] --step: %s done. [Enter]=continue  q=stop: ' "$id" >&2
  if ! IFS= read -r ans; then
    _say "[orchestrate] --step: stdin closed; stopping after $id."
    return 1
  fi
  case "$ans" in
    q|Q|n|N|quit|stop) _say "[orchestrate] --step: operator stopped after $id."; return 1 ;;
    *) return 0 ;;
  esac
}

# Run a session under the stall-watchdog (SG-11). Backgrounds claude (output -> a session log),
# polls liveness (`kill -0`, no daemon) + the log's mtime; after WATCHDOG_STALL_SECS of no new
# output while the process is still alive, emits a `stalled` event + WARN ONCE (advisory: never
# kills). Returns the session's exit code. The captured output is surfaced after completion.
_run_session_watchdog() {  # dir id pfile route_flags
  local dir="$1" id="$2" pfile="$3" rflags="$4"
  local logdir="$dir/.orchestrate"; mkdir -p "$logdir"
  local slog="$logdir/${id}.session.log"; : > "$slog"
  _say "[orchestrate] [watchdog] $id: output -> $slog (stall=${WATCHDOG_STALL_SECS}s, poll=${WATCHDOG_POLL_SECS}s; advisory, never kills)"
  # shellcheck disable=SC2086 # rflags + CLAUDE_FLAGS are operator/goal config; word-splitting is intended.
  { "$CLAUDE_CMD" -p $rflags $CLAUDE_FLAGS < "$pfile" > "$slog" 2>&1; } &
  local spid=$! warned=0 now last age
  while kill -0 "$spid" 2>/dev/null; do
    sleep "$WATCHDOG_POLL_SECS"
    kill -0 "$spid" 2>/dev/null || break
    now=$(date +%s); last=$(_mtime "$slog"); [ -n "$last" ] || last=$now; age=$((now - last))
    if [ "$age" -ge "$WATCHDOG_STALL_SECS" ] && [ "$warned" = 0 ]; then
      warned=1
      _emit_event "$dir" "$id" stalled "no output for ${age}s (pid $spid alive)"
      echo "[orchestrate] [watchdog] WARN: $id stalled -- no output for ${age}s, pid $spid still alive. Not killing (advisory); tail $slog." >&2
    fi
  done
  wait "$spid"; local rc=$?
  cat "$slog"
  return "$rc"
}

# _run_one_session: run ONE sub-goal session via the correct mutually-exclusive run-path
# (SG-11 watchdog / --stream|DETERMINISTIC_HANDOFF stream-json / plain claude -p). Keyed on
# `dir id pfile route_flags stream` (stream is a cmd_run local, so it is passed explicitly).
# Returns the session exit code; exposes the stream-log path via the global _ROS_SLOG so the
# caller can wire post-session logic (grounded completion, deterministic handoff) to it. Extracted
# from cmd_run (TASK-000) so the serial and wave paths share ONE copy and the three run-paths are
# never forked. Zero behavior change vs the former inline block.
_run_one_session() {  # dir id pfile route_flags stream
  local dir="$1" id="$2" pfile="$3" route_flags="$4" stream="$5"
  # --stream (opt-in observability): emit stream-json and tee it to a per-sub-goal capture so
  # the operator sees a live tail AND the run is recorded. Off -> the default invocation is
  # byte-identical (no pipe, no tee). pipefail (set at top) keeps the `if ! ... | tee` honest.
  local rc=0 slog=""
  if [ "$WATCHDOG_STALL_SECS" -gt 0 ]; then
    # SG-11 watchdog path (opt-in): backgrounds the session + polls for stalls/liveness.
    # (Deterministic-handoff capture is not wired through the watchdog path; the two opt-in
    # paths are independent. See docs/implementation-notes/v3-deterministic-handoff.md.)
    _run_session_watchdog "$dir" "$id" "$pfile" "$route_flags" || rc=$?
  elif [ "$stream" = 1 ] || [ "$DETERMINISTIC_HANDOFF" = 1 ]; then
    # Capture stream-json when either the operator wants a live tail (--stream) OR the
    # deterministic handoff needs the transcript (DETERMINISTIC_HANDOFF=1). The live `tee` to
    # the terminal happens only under --stream; det-handoff capture is silent.
    local logdir="$dir/.orchestrate"; mkdir -p "$logdir"
    slog="$logdir/${id}.stream.jsonl"
    # shellcheck disable=SC2086 # CLAUDE_FLAGS + route_flags are operator/goal config; word-splitting is intended.
    if [ "$stream" = 1 ]; then
      _say "[orchestrate] streaming $id -> $slog (live tail + captured)"
      "$CLAUDE_CMD" -p $route_flags --output-format stream-json --verbose $CLAUDE_FLAGS < "$pfile" | tee "$slog" || rc=$?
    else
      "$CLAUDE_CMD" -p $route_flags --output-format stream-json --verbose $CLAUDE_FLAGS < "$pfile" > "$slog" || rc=$?
    fi
  else
    # shellcheck disable=SC2086 # CLAUDE_FLAGS + route_flags are operator/goal config; word-splitting is intended.
    "$CLAUDE_CMD" -p $route_flags $CLAUDE_FLAGS < "$pfile" || rc=$?
  fi
  _ROS_SLOG="$slog"
  return "$rc"
}

# ---- Wavefront spawn/reap primitive (SPEC-106 TASK-004a, DEC-005) -----------------------------
# The concurrent-wave engine: take the admitted `run` set, run those sub-goals concurrently (each in
# its OWN worktree), reap on completion, drain safely on a sibling failure. bash-3.2 throughout: no
# assoc arrays (the reap map is index-aligned plain arrays), no `wait -n` (poll `kill -0` like
# `_run_session_watchdog`), no `flock`. Standalone-testable with a MOCK CLAUDE_CMD; wiring into
# cmd_run (size-dispatch on admitted count) is the NEXT task (TASK-004b), so `_wave_run` has ZERO
# call sites in the run loop after this task.

# A sub-goal's declared branch from its goal file's `**Branch:** <type>/<slug>` header (same parse
# as `_emit_start`), or a stable `wave/<id-lower>` fallback when absent so a worktree can still be
# stood up. One branch per sub-goal id => distinct branches => no "already checked out" clash.
_sg_branch() {  # goalfile id
  local gf="${1:-}" id="$2" branch=""
  [ -n "$gf" ] && [ -f "$gf" ] && branch=$(grep -iE '^\*\*Branch:\*\*' "$gf" | head -1 | sed -E 's/^\*\*[Bb]ranch:\*\*[[:space:]]*//; s/[[:space:]].*$//')
  [ -n "$branch" ] || branch="wave/$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$branch"
}

# Create OR reuse a per-sub-goal worktree at <repo>/.claude/worktrees/<id> on <branch> (the repo-wide
# worktree location, per the global worktree rule). REUSE only on a clean crash-resume (edge 5): the
# path is already a REGISTERED git worktree, its tree is clean, AND it is on <branch>. Otherwise
# RECREATE. NEVER a blind `git worktree add` onto an existing path: a stale/dirty/mismatched worktree
# is dropped with `git worktree remove --force` (git's own remover, which refuses paths outside its
# admin list), and a leftover NON-worktree dir is moved aside (never `rm -rf`). Prunes stale admin
# entries first so a dir removed out-of-band cannot wedge `worktree add`. Echoes the worktree path;
# nonzero on failure.
_wave_worktree() {  # repo id branch
  local repo="$1" id="$2" branch="$3"
  local wt="$repo/.claude/worktrees/$id"
  git -C "$repo" worktree prune 2>/dev/null || true

  if [ -e "$wt/.git" ]; then
    # A linked worktree carries a `.git` FILE (a gitdir pointer). Clean + on <branch> => resume.
    local dirty cur
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null)
    cur=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$dirty" ] && [ "$cur" = "$branch" ]; then
      printf '%s\n' "$wt"; return 0
    fi
    git -C "$repo" worktree remove --force "$wt" 2>/dev/null || true
  elif [ -e "$wt" ]; then
    # non-worktree collision at the path (leftover from a crash): move aside, never delete.
    mv -f "$wt" "${TMPDIR:-/tmp}/wave-wt-stale.$id.$$.$RANDOM" 2>/dev/null || true
  fi
  git -C "$repo" worktree prune 2>/dev/null || true

  mkdir -p "$repo/.claude/worktrees" 2>/dev/null || true
  # Reuse the branch if it already exists (a resume that lost only its checkout), else create it
  # off HEAD.
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo" worktree add "$wt" "$branch" >/dev/null 2>&1 || return 1
  else
    git -C "$repo" worktree add -b "$branch" "$wt" >/dev/null 2>&1 || return 1
  fi
  printf '%s\n' "$wt"
}

# Abort handler for `_wave_run`'s INT/TERM trap: kill every still-live wave PID then reap, so an
# operator ctrl-C never leaves an orphaned `claude -p` (mock) child. `_WAVE_PIDS` is a GLOBAL (not a
# `_wave_run` local) precisely so this handler can reach it while `_wave_run` is on the stack. The
# empty-guard `${arr[@]+...}` keeps `set -u` happy when the trap fires before any PID is recorded.
_wave_abort() {
  local p
  for p in ${_WAVE_PIDS[@]+"${_WAVE_PIDS[@]}"}; do
    kill "$p" 2>/dev/null
  done
  wait 2>/dev/null
  echo "[orchestrate] [wave] aborted; killed + reaped the wave PID set (no orphaned children)." >&2
  return 130
}

# _wave_run <megadir> <roadmap>: spawn the admitted wave, reap on completion, drain on sibling fail.
# Computes the admitted set via `_wave_gate` (its `run<TAB>id` lines). For each admitted sub-goal:
#   * skip an already-checked box (idempotent resume, invariant 1),
#   * stand up its worktree (`_wave_worktree`: reuse-clean-else-recreate, never blind add),
#   * build its prompt (`_build_prompt`) and BACKGROUND a session via `_run_one_session`,
#     cd'd INTO the worktree so siblings are genuinely isolated,
#   * record `pid -> sg-id` in the index-aligned reap map (`_WAVE_PIDS` / `wave_ids`).
# Then the REAP LOOP polls all live PIDs with `kill -0` (NOT `wait -n`, bash 4.3+). As each PID
# exits it is reaped with `wait` (retrieves the status bash cached for the finished job) and the
# GROUNDED completion check runs for THAT sub-goal: its box must be flipped in the SHARED
# $megadir/ROADMAP.md (read via `_subgoals`; the SESSION flips its own box, we only CHECK, never
# `cmd_flip` here).
#
# Failure semantics (invariant 5 / failure-modes table "Sibling session exits nonzero mid-wave"): a
# sub-goal that exits NONZERO or dies with its box UNFLIPPED marks the wave failed, but in-flight
# siblings are LET DRAIN to completion in their isolated worktrees (the reap loop never breaks early
# and never kills a healthy sibling); the run returns nonzero only AFTER every wave PID is reaped.
# The INT/TERM `trap` reaps+kills the whole PID set on an abort so nothing is orphaned.
#
# Returns 0 iff every admitted sub-goal completed with a flipped box; nonzero otherwise (incl. a
# worktree-setup failure). An empty admitted set (all deferred / all already checked) is a no-op 0.
_wave_run() {  # megadir roadmap
  local megadir="$1" roadmap="$2"
  local repo; repo=$(git -C "$megadir" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$repo" ] || { echo "[orchestrate] [wave] '$megadir' is not inside a git repo; cannot stand up worktrees." >&2; return 64; }

  # Reap map = index-aligned plain arrays (bash 3.2 has no assoc arrays). `_WAVE_PIDS` is global so
  # `_wave_abort` can reach it; the rest are locals.
  _WAVE_PIDS=()
  # `_WAVE_LANDED` is GLOBAL (like `_WAVE_PIDS`): the wave-success path appends each grounded-complete
  # sub-goal id here so the caller (`cmd_run`) can hand the landed set to `_wave_converge` after the
  # wave drains. Reset per run so a prior wave's ids never leak. Empty-guarded at every read site.
  _WAVE_LANDED=()
  local wave_ids=() wave_done=() wave_pfiles=()
  local wave_failed=0 spawned=0

  # Reap/kill the wave PID set on an abort so no `claude -p` (mock) child is orphaned. Cleared
  # before the normal return paths below.
  trap '_wave_abort' INT TERM

  local decision id gf branch wt route_flags rmodel reffort pfile pid checked
  while IFS=$'\t' read -r decision id; do
    [ "$decision" = run ] || continue
    # Idempotent resume: a box already checked is skipped, never re-run.
    checked=$(_subgoals "$roadmap" | awk -F'\t' -v i="$id" '$1==i {print $3}')
    [ "$checked" = 1 ] && { _say "[orchestrate] [wave] $id already checked; skipping (idempotent)."; continue; }

    gf=$(_goalfile "$megadir" "$id")
    branch=$(_sg_branch "$gf" "$id")
    if ! wt=$(_wave_worktree "$repo" "$id" "$branch"); then
      echo "[orchestrate] [wave] $id: worktree setup failed; marking wave failed." >&2
      wave_failed=1
      continue
    fi

    # Per-sub-goal model/effort routing (matches cmd_run); absent hint -> no flag -> inherit.
    route_flags=""
    IFS=$'\t' read -r rmodel reffort < <(_route "$gf")
    [ -n "$rmodel" ] && route_flags="$route_flags --model $rmodel"
    [ -n "$reffort" ] && route_flags="$route_flags --effort $reffort"

    pfile=$(mktemp)
    _build_prompt "$megadir" "$id" > "$pfile"
    _emit_event "$megadir" "$id" executing "wave (worktree $wt)"

    # Background the session INSIDE its worktree (genuine isolation). `_run_one_session` picks the
    # run-path (plain in the default/test posture); its `_ROS_SLOG` global is unused on the wave
    # path (deterministic-handoff regen is TASK-005), so losing it in the subshell is fine. The
    # session's exit code comes back via `wait` in the reap loop, NOT via the subshell here.
    ( cd "$wt" 2>/dev/null && _run_one_session "$megadir" "$id" "$pfile" "$route_flags" 0 ) &
    pid=$!
    _WAVE_PIDS+=("$pid")
    wave_ids+=("$id")
    wave_pfiles+=("$pfile")
    wave_done+=(0)
    spawned=$((spawned + 1))
    _say "[orchestrate] [wave] spawned $id (pid $pid) in $wt"
  done < <(_wave_gate "$megadir" "$roadmap")

  # Empty wave (nothing admitted, or every admitted box already checked): not a failure unless a
  # worktree setup already failed above.
  if [ "$spawned" = 0 ]; then
    trap - INT TERM
    return "$wave_failed"
  fi

  # Reap loop: poll ALL live PIDs with `kill -0` (the `_run_session_watchdog` pattern, NOT `wait -n`
  # which is bash 4.3+/absent on macOS). As each PID exits, reap it with `wait`, then run the
  # grounded box-flip check for THAT sub-goal. A nonzero exit OR an unflipped box marks the wave
  # failed but does NOT break the loop: in-flight siblings DRAIN to completion (never killed).
  local remaining="$spawned" i rc box
  while [ "$remaining" -gt 0 ]; do
    for i in $(seq 0 $((spawned - 1))); do
      [ "${wave_done[$i]}" = 1 ] && continue
      pid="${_WAVE_PIDS[$i]}"; id="${wave_ids[$i]}"
      kill -0 "$pid" 2>/dev/null && continue   # still in-flight -> leave it alone (do not kill)
      rc=0; wait "$pid" 2>/dev/null || rc=$?    # exited -> reap the cached status
      wave_done[i]=1
      remaining=$((remaining - 1))
      rm -f "${wave_pfiles[$i]}" 2>/dev/null
      box=$(_subgoals "$roadmap" | awk -F'\t' -v x="$id" '$1==x {print $3}')
      if [ "$rc" != 0 ]; then
        wave_failed=1
        _emit_event "$megadir" "$id" blocked "wave session exited nonzero ($rc)"
        echo "[orchestrate] [wave] $id session exited nonzero ($rc); draining siblings, then failing." >&2
      elif [ "$box" != 1 ]; then
        wave_failed=1
        _emit_event "$megadir" "$id" blocked "wave: box not flipped (no self-claim)"
        echo "[orchestrate] [wave] $id finished but did not flip its ROADMAP box; draining siblings, then failing." >&2
      else
        _emit_event "$megadir" "$id" shipped "wave: box checked"
        _WAVE_LANDED+=("$id")
        _say "[orchestrate] [wave] $id complete (box checked)."
      fi
    done
    [ "$remaining" -gt 0 ] && sleep "${WAVE_POLL_SECS:-0.2}"
  done

  trap - INT TERM
  return "$wave_failed"
}
# -----------------------------------------------------------------------------------------------

# ---- Wave convergence sequencer (SPEC-106 TASK-004c, DEC-008) ----------------------------------
# After a wave lands its sub-goals on their worktree branches, their merges back to the mega-goal base
# MUST happen ONE AT A TIME (never concurrently), in ROADMAP order, each under the flip lock , so two
# same-base merges never race. This is a THIN SEQUENCER: it does NOT reimplement merging. Each merge
# goes through the MOCKABLE `$WAVE_MERGE_CMD` hook (default `lib/mega-merge.sh merge`, whose merge
# SEMANTICS stay untouched per scope , we only sequence calls to it). Real gh-backed merge is DEFERRED
# to ID-085-followup (waves are off at the default WAVE_CAP=1, so this is never reached and the serial
# path stays byte-identical; a real merge also needs `gh` + real PRs).

# Files a wave branch changed vs the base: three-dot diff = changes on <branch> since its merge-base
# with <base>. Empty when the branch has no commits (e.g. a session that only flipped its box) or is
# absent (git errors, swallowed). Read-only.
_wave_branch_files() {  # repo base branch
  git -C "$1" diff --name-only "$2...$3" 2>/dev/null
}

# The PR number on a sub-goal's ROADMAP line (`... , PR #<n>`), or empty for a placeholder (`PR #__`)
# / absent. A sub-goal with no real PR cannot be merged yet, so `_wave_converge` SKIPS it (the real
# PR-open + merge wiring is ID-085-followup), never fails on it.
_sg_pr() {  # roadmap id
  _sg_line "$1" "$2" | sed -nE 's/.*PR #([0-9]+).*/\1/p' | head -1
}

# _wave_converge <megadir> [<id>...]: sequence the merges of a landed wave. With explicit ids it merges
# exactly those; with none, it reads the just-landed set from the global `_WAVE_LANDED` (populated by
# `_wave_run`). Steps:
#   1. Order the target ids by ROADMAP position (NOT argv order) , merges land in ROADMAP order.
#   2. SAME-FILE cross-wave guard (belt-and-suspenders over dispatch-gate's PRE-admission disjointness,
#      the SPEC-106 risk row): diff each landed branch vs the base; if two branches changed the SAME
#      file, FLAG (event + message + nonzero) and REFUSE to merge , never silently land a clean-but-
#      wrong merge. A file appearing from >=2 branches (union `sort | uniq -d`) is the overlap.
#   3. Merge each in ROADMAP order, ONE AT A TIME under the flip lock, through `$WAVE_MERGE_CMD`. A
#      sub-goal with no real PR (placeholder `#__`) is SKIPPED (merge wiring deferred), not failed.
# bash-3.2: no assoc arrays (membership via a space-padded string match); arrays empty-guarded
# `${arr[@]+"${arr[@]}"}` (DEC-005, mega-merge.sh:224). Returns 0 iff every mergeable sub-goal's hook
# succeeded and no same-file overlap was found; nonzero on an overlap flag or a merge-hook failure.
_wave_converge() {  # megadir [id...]
  local megadir="$1"; shift 2>/dev/null || true
  local roadmap="$megadir/ROADMAP.md"
  [ -f "$roadmap" ] || { echo "[orchestrate] [converge] no ROADMAP.md in '$megadir'" >&2; return 64; }

  # Target set: explicit args, else the just-landed set from `_wave_run`.
  local targets=()
  if [ "$#" -gt 0 ]; then
    targets=("$@")
  else
    targets=( ${_WAVE_LANDED[@]+"${_WAVE_LANDED[@]}"} )
  fi
  [ "${#targets[@]}" -gt 0 ] || { _say "[orchestrate] [converge] no landed wave sub-goals to converge (no-op)."; return 0; }

  local repo; repo=$(git -C "$megadir" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$repo" ] || { echo "[orchestrate] [converge] '$megadir' is not inside a git repo; cannot converge." >&2; return 64; }
  local base; base=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null); [ -n "$base" ] || base=HEAD

  # 1. Order the targets by ROADMAP position. Walk `_subgoals` (ROADMAP order) and keep those in the
  #    target set; membership via a space-padded string match (bash-3.2 has no assoc arrays).
  local want=" $(printf '%s ' "${targets[@]}")"
  local ordered=() sgid sgpol sgchk
  while IFS=$'\t' read -r sgid sgpol sgchk; do
    case "$want" in *" $sgid "*) ordered+=("$sgid") ;; esac
  done < <(_subgoals "$roadmap")
  [ "${#ordered[@]}" -gt 0 ] || { _say "[orchestrate] [converge] none of the requested ids are in the ROADMAP (no-op)."; return 0; }

  # 2. Same-file cross-wave guard. Each branch's file list is deduped (`sort -u`); across the union, a
  #    file that appears >=2 times (`uniq -d`) was touched by >=2 branches , the overlap.
  local id gf branch overlap
  overlap=$(
    for id in "${ordered[@]}"; do
      gf=$(_goalfile "$megadir" "$id")
      branch=$(_sg_branch "$gf" "$id")
      _wave_branch_files "$repo" "$base" "$branch" | sort -u
    done | sort | uniq -d
  )
  if [ -n "$overlap" ]; then
    _emit_event "$megadir" "wave" blocked "converge: same-file cross-wave edit"
    {
      echo "[orchestrate] [converge] SAME-FILE cross-wave edit detected across the landed wave; REFUSING to merge (a clean-but-wrong merge is the hazard dispatch-gate's disjointness guards against). Overlapping file(s):"
      printf '%s\n' "$overlap" | sed 's/^/    /'
    } >&2
    return 1
  fi

  # 3. Merge each in ROADMAP order, ONE AT A TIME under the flip lock, via the mockable hook.
  local lockdir="$megadir/.orchestrate/flip.lock"
  local pr rc
  for id in "${ordered[@]}"; do
    pr=$(_sg_pr "$roadmap" "$id")
    if [ -z "$pr" ]; then
      _say "[orchestrate] [converge] $id has no real PR yet (placeholder); skipping its merge (real PR/merge wiring is deferred)."
      continue
    fi
    _lock "$lockdir" || { echo "[orchestrate] [converge] could not acquire the flip lock to merge $id" >&2; return 1; }
    rc=0
    # shellcheck disable=SC2086 # WAVE_MERGE_CMD is operator config; word-splitting is intended (mirrors CLAUDE_FLAGS).
    $WAVE_MERGE_CMD "$pr" "$id" || rc=$?
    _unlock "$lockdir"
    if [ "$rc" != 0 ]; then
      _emit_event "$megadir" "$id" blocked "converge: merge hook failed (PR #$pr, rc $rc)"
      echo "[orchestrate] [converge] $id merge hook failed (PR #$pr, rc $rc); stopping convergence (no self-claim)." >&2
      return "$rc"
    fi
    _emit_event "$megadir" "$id" merged "converge: PR #$pr merged (one-at-a-time under the flip lock)"
    _say "[orchestrate] [converge] $id merged (PR #$pr)."
  done
  return 0
}
# -----------------------------------------------------------------------------------------------

cmd_run() {
  local dir="" dry=0 step=0 stream=0 board_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)  dry=1 ;;
      --step)     step=1 ;;
      --stream)   stream=1 ;;
      --board)    board_arg="both" ;;
      --board=*)  board_arg="${1#--board=}" ;;
      --*)        echo "unknown flag: $1" >&2; return 64 ;;
      *)          if [ -z "$dir" ]; then dir="$1"; else echo "unexpected arg: $1" >&2; return 64; fi ;;
    esac
    shift
  done
  [ -d "$dir" ] || { echo "no such megagoal dir: '$dir'" >&2; return 64; }
  local roadmap="$dir/ROADMAP.md"
  [ -f "$roadmap" ] || { echo "no ROADMAP.md in '$dir'" >&2; return 64; }
  local board_mode; board_mode=$(_resolve_board_mode "$board_arg")
  case "$board_mode" in roadmap|kanban|both) ;; *) echo "unknown --board mode: '$board_mode' (want roadmap|kanban|both)" >&2; return 64 ;; esac

  # WAVE_CAP parse-time validation (SPEC-106 TASK-004b / DEC-009 / Edge case 4). Default 1 (waves
  # off). A non-numeric or <1 value is REJECTED with a clear error + nonzero exit here, NOT silently
  # coerced to 1 elsewhere, so a typo (`WAVE_CAP=0`, `WAVE_CAP=two`) fails loudly instead of quietly
  # running serial. The digit-class check rejects empty / non-numeric / negative (the sign char is a
  # non-digit); the `-lt 1` check then rejects 0.
  case "$WAVE_CAP" in
    ''|*[!0-9]*) echo "orchestrate: WAVE_CAP must be a positive integer >=1 (got: '$WAVE_CAP')" >&2; return 64 ;;
  esac
  [ "$WAVE_CAP" -lt 1 ] && { echo "orchestrate: WAVE_CAP must be >=1 (got: '$WAVE_CAP')" >&2; return 64; }

  if [ "$dry" = 1 ]; then
    _say "[plan] mega-goal: $dir"
    [ "$step" = 1 ]   && _say "  (--step: pause for the operator after each sub-goal)"
    [ "$stream" = 1 ] && _say "  (--stream: each session streamed live + captured to .orchestrate/<id>.stream.jsonl)"
    local any=0
    while IFS=$'\t' read -r sg ppolicy; do
      any=1
      local rmodel reffort
      IFS=$'\t' read -r rmodel reffort < <(_route "$(_goalfile "$dir" "$sg")")
      _say "  -> $sg ($ppolicy)  [model: ${rmodel:-inherit}, effort: ${reffort:-inherit}]  [prompt: POINTER_PROMPT + goal-file + $([ -s "$dir/HANDOFF.md" ] && echo HANDOFF || echo no-handoff)]"
      [ "$ppolicy" = gate ] && { _say "  == STOP at $sg (gate: human review) =="; break; }
      [ "$step" = 1 ] && _say "     [--step] pause here for the operator before the next sub-goal"
    done < <(_subgoals "$roadmap" | awk -F'\t' '$3==0 {print $1"\t"$2}')
    [ "$any" = 1 ] || _say "  (no unchecked sub-goals)"
    if [ "$board_mode" != roadmap ]; then
      _say ""; _say "[board mode: $board_mode]"
      _render_board "$dir" "$roadmap" "$board_mode"
    fi
    return 0
  fi

  while :; do
    # SPEC-106 TASK-004b size-dispatch (DEC-002/006/012): serial-vs-wave decided per cycle on the
    # ADMITTED count (post-`_wave_gate`), NOT the raw ready size (a no-deps mega-goal has ready size
    # N, so raw size can't gate the serial path). WAVE_CAP defaults to 1 (waves OFF) => this guard is
    # FALSE => the loop falls straight through to the byte-identical serial body below, exactly as the
    # pre-wavefront loop ran (the sacred invariant). Only WAVE_CAP>=2 even consults `_wave_gate`; only
    # `admitted>=2` (dep-free, Touches-declaring, provably-disjoint sub-goals) routes to `_wave_run`.
    # admitted<=1 falls through to the serial body on `_next`'s pick, byte-identical for that cycle.
    # `_wave_run` serializes its own flips under the flip lock and blocks until the wave drains, so we
    # `continue` to recompute the next cycle from the freshly re-read ROADMAP: one blocking wave per
    # cycle means no double-launch and no CAP overshoot across cycles. (Gate/`--step`/`--stream`/
    # `--board` on the wave path are TASK-005/007's scope; at the default CAP=1 they are untouched.)
    if [ "$WAVE_CAP" -ge 2 ]; then
      local admitted_n
      admitted_n=$(_wave_gate "$dir" "$roadmap" | awk -F'\t' '$1=="run"{n++} END{print n+0}')
      if [ "$admitted_n" -ge 2 ]; then
        if _wave_run "$dir" "$roadmap"; then
          # Converge the landed wave (TASK-004c): merge its sub-goals ONE AT A TIME under the flip
          # lock, in ROADMAP order, via the mockable hook. A same-file cross-wave edit or a merge-hook
          # failure halts the loop (no self-claim). At the default WAVE_CAP=1 this block is unreachable,
          # so the serial path stays byte-identical.
          if ! _wave_converge "$dir" ${_WAVE_LANDED[@]+"${_WAVE_LANDED[@]}"}; then
            echo "[orchestrate] [wave] convergence flagged a same-file cross-wave conflict or a merge failure; halting (no self-claim)." >&2
            return 1
          fi
          continue
        fi
        echo "[orchestrate] [wave] a wave sub-goal did not complete (nonzero exit or unflipped box); halting (no self-claim)." >&2
        return 1
      fi
      # Wait-vs-complete termination guard (SPEC-106 TASK-006, Edge case 1). Reached only when
      # admitted<2 (no wave launched this cycle). If unchecked sub-goals REMAIN but the ready set is
      # EMPTY -- every remaining unchecked is dep-blocked, nothing is runnable, and no wave is in
      # flight (`_wave_run` blocks to drain before we get here) -- the dep-IGNORANT serial `_next`
      # below would wrongly RUN a dep-blocked sub-goal (proven: a mutual-dep cycle ran both boxes to
      # a false "done"). Halt for a human instead: a clear blocked message + NONZERO exit, never a
      # false-complete, never a spin. Guarded by `unchecked>0` so the legit all-checked completion
      # still falls through to `_next`'s empty -> "done" return-0 path. Only reachable on the wave
      # path (WAVE_CAP>=2); the serial default never enters this block, so serial stays byte-identical.
      local unchecked_n ready_n
      unchecked_n=$(_subgoals "$roadmap" | awk -F'\t' '$3==0 {n++} END{print n+0}')
      if [ "$unchecked_n" -gt 0 ]; then
        ready_n=$(_ready_set "$roadmap" | awk 'END{print NR+0}')
        if [ "$ready_n" -eq 0 ]; then
          _emit_event "$dir" "-" blocked "$unchecked_n unchecked, none runnable"
          [ "$board_mode" != roadmap ] && _render_board "$dir" "$roadmap" "$board_mode" >/dev/null
          echo "[orchestrate] [wave] blocked: $unchecked_n unchecked, none runnable (all remaining sub-goals are dep-blocked; no in-flight producer). Halting for human review (not a false-complete)." >&2
          return 1
        fi
      fi
    fi

    local nx id policy
    nx=$(_next "$roadmap")
    [ -n "$nx" ] || { _say "[orchestrate] all sub-goals checked; done."; return 0; }
    id=$(printf '%s' "$nx" | cut -f1); policy=$(printf '%s' "$nx" | cut -f2)

    if [ "$policy" = gate ]; then
      _emit_event "$dir" "$id" blocked "gate: human review"
      [ "$board_mode" != roadmap ] && _render_board "$dir" "$roadmap" "$board_mode" >/dev/null
      _say "[orchestrate] STOP: $id is a gate sub-goal; open/await its PR for review, then re-run."
      return 0
    fi

    # Per-sub-goal model/effort routing (SPEC-087): read the goal file's hints and pass them as
    # flags, so this sub-goal runs on its own tier instead of inheriting Opus-for-everything.
    # Absent hint -> no flag -> inherit.
    local rmodel reffort route_flags=""
    IFS=$'\t' read -r rmodel reffort < <(_route "$(_goalfile "$dir" "$id")")
    [ -n "$rmodel" ] && route_flags="$route_flags --model $rmodel"
    [ -n "$reffort" ] && route_flags="$route_flags --effort $reffort"
    # Guardrail (SG-11): a sub-goal with no goals/ file runs without its contract -- a re-discovery
    # hazard. Warn loudly (advisory; the loop still runs it on POINTER_PROMPT + handoff alone).
    if [ -z "$(_goalfile "$dir" "$id")" ]; then
      echo "[orchestrate] [guardrail] WARN: $id has no goals/ file; session runs without its contract (re-discovery hazard)." >&2
    fi
    _emit_event "$dir" "$id" executing "model=${rmodel:-inherit} effort=${reffort:-inherit}"
    # SPEC-101: record the run's routing facts so mega-dispatched runs are as measurable
    # as hand-run ones (assign.md makes this same START call). Before the session spawns,
    # so a run that dies mid-session is still tracked, not '?'.
    _emit_start "$dir" "$id"
    [ "$board_mode" != roadmap ] && _render_board "$dir" "$roadmap" "$board_mode" >/dev/null
    _say "[orchestrate] running $id in a fresh session ($CLAUDE_CMD -p, model: ${rmodel:-inherit}, effort: ${reffort:-inherit}) ..."
    # Inject the prompt via a TEMP FILE on stdin, not a shell-interpolated argv arg (pi-swarm
    # borrow). Removes the backtick/${}/secret-guard bug class when the handoff body carries shell
    # metachars, and dodges ARG_MAX on a large injected handoff. `claude -p` reads the prompt from
    # stdin when no positional prompt is given.
    local pfile; pfile=$(mktemp)
    _build_prompt "$dir" "$id" > "$pfile"
    # Run the session via the extracted helper (TASK-000): it picks the correct run-path
    # (watchdog / --stream|det-handoff stream-json / plain) and returns the session exit code.
    # slog (the stream-log path, "" when no capture happened) comes back via _ROS_SLOG for the
    # grounded-completion + deterministic-handoff logic below.
    local rc=0 slog=""
    _run_one_session "$dir" "$id" "$pfile" "$route_flags" "$stream" || rc=$?
    slog="$_ROS_SLOG"
    rm -f "$pfile"
    if [ "$rc" != 0 ]; then
      _emit_event "$dir" "$id" blocked "session exited nonzero ($rc)"
      [ "$board_mode" != roadmap ] && _render_board "$dir" "$roadmap" "$board_mode" >/dev/null
      echo "[orchestrate] session for $id exited nonzero; stopping." >&2
      return 1
    fi

    # grounded completion: advance only if the box actually flipped.
    local checked; checked=$(_subgoals "$roadmap" | awk -F'\t' -v i="$id" '$1==i {print $3}')
    if [ "$checked" != 1 ]; then
      _emit_event "$dir" "$id" blocked "box not flipped (no self-claim)"
      [ "$board_mode" != roadmap ] && _render_board "$dir" "$roadmap" "$board_mode" >/dev/null
      echo "[orchestrate] [guardrail] $id did not check its ROADMAP box; halting (no self-claim, no advance on a dead/incomplete session)." >&2
      return 1
    fi
    _emit_event "$dir" "$id" shipped "box checked"
    [ "$board_mode" != roadmap ] && _render_board "$dir" "$roadmap" "$board_mode" >/dev/null
    _say "[orchestrate] $id complete (box checked); advancing."

    # Deterministic handoff (SG-02): regenerate the two-tier handoff for the NEXT sub-goal from
    # this session's captured transcript, so the handoff is always produced and reproducible
    # rather than depending on the model having written a good one. Overwrites HANDOFF.md (hot)
    # and appends DECISIONS.md (warm, idempotent). Failure is non-fatal: the loop continues and
    # the session's own HANDOFF.md (if any) stands.
    if [ "$DETERMINISTIC_HANDOFF" = 1 ] && [ -s "$slog" ]; then
      local nx2 nid nraw ntitle
      nx2=$(_next "$roadmap")
      if [ -n "$nx2" ]; then
        nid=$(printf '%s' "$nx2" | cut -f1)
        nraw=$(_sg_line "$roadmap" "$nid"); ntitle=$(_sg_title "$nraw" "$nid")
        if "$ORCH_DIR/handoff-gen" "$slog" --dir "$dir" --next-id "$nid" --next-title "$ntitle" --date "$(date -u +%F)"; then
          # Per-edge WRITE (SPEC-106 TASK-005): handoff-gen always writes $dir/HANDOFF.md; if the
          # JUST-completed $id HAS DEPENDENTS, rename it to the per-edge HANDOFF-<id>.md so parallel
          # siblings (CAP>1) never clobber one hot file. No dependents -> leave plain (byte-identical).
          if _sg_dependents "$roadmap" "$id"; then
            mv -f "$dir/HANDOFF.md" "$dir/HANDOFF-$id.md" 2>/dev/null || true
          fi
          _emit_event "$dir" "$id" handoff "deterministic -> $nid"
          _say "[orchestrate] deterministic handoff written for $nid (HANDOFF.md overwritten, DECISIONS.md appended)."
        else
          echo "[orchestrate] WARN: deterministic handoff generation failed for $id; the session's own HANDOFF.md (if any) stands." >&2
        fi
      fi
    fi
    # --step: pause for the operator between sub-goals, but only when the NEXT one is auto (the
    # loop would actually run it). If next is a gate, the gate-stop below is the natural halt, so
    # don't double up with a pause first.
    if [ "$step" = 1 ]; then
      local nxt; nxt=$(_next "$roadmap")
      if [ -n "$nxt" ] && [ "$(printf '%s' "$nxt" | cut -f2)" = auto ]; then
        _step_pause "$id" || return 0
      fi
    fi
  done
}

main() {
  local cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    next) cmd_next "$@" ;;
    run)  cmd_run "$@" ;;
    flip) cmd_flip "$@" ;;
    *) echo "usage: orchestrate.sh {next|run|flip} <megagoal-dir> [<SG-NN>] [--dry-run] [--step] [--stream] [--board=roadmap|kanban|both]" >&2; exit 64 ;;
  esac
}

# Only run main when executed, not when sourced (so tests can source and call the internal
# helpers, e.g. _ready_set, directly). Same guard as lib/dispatch-gate.sh.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
