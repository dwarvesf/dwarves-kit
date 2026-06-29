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
#   orchestrate.sh run  <megagoal-dir> [--dry-run] drive the loop (dry-run prints the plan only)
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

_say() { printf '%s\n' "$*"; }

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

# Resolve a sub-goal's goal file path (goals/<NN>-*.md), or empty.
_goalfile() {
  local dir="$1" id="$2" f
  for f in "$dir/goals/${id#SG-}-"*.md; do [ -f "$f" ] && { printf '%s\n' "$f"; return; }; done
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
  if [ -s "$dir/HANDOFF.md" ]; then
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
  printf '\nWhen you finish: report findings IN the records (overwrite HANDOFF.md with the next action + read-pointers as file:line; append durable invariants/dead-ends to DECISIONS.md), NOT only in your response text. The next sub-goal reads the files, not this transcript.\n'
}

cmd_next() {
  local dir="${1:-}"
  [ -f "$dir/ROADMAP.md" ] || { echo "no ROADMAP.md in '$dir'" >&2; return 64; }
  local nx; nx=$(_next "$dir/ROADMAP.md")
  if [ -n "$nx" ]; then printf '%s\n' "$nx"; else _say "(none unchecked)"; fi
}

cmd_run() {
  local dir="${1:-}" dry=0
  [ "${2:-}" = "--dry-run" ] && dry=1
  [ -d "$dir" ] || { echo "no such megagoal dir: '$dir'" >&2; return 64; }
  local roadmap="$dir/ROADMAP.md"
  [ -f "$roadmap" ] || { echo "no ROADMAP.md in '$dir'" >&2; return 64; }

  if [ "$dry" = 1 ]; then
    _say "[plan] mega-goal: $dir"
    local any=0
    while IFS=$'\t' read -r sg ppolicy; do
      any=1
      local rmodel reffort
      IFS=$'\t' read -r rmodel reffort < <(_route "$(_goalfile "$dir" "$sg")")
      _say "  -> $sg ($ppolicy)  [model: ${rmodel:-inherit}, effort: ${reffort:-inherit}]  [prompt: POINTER_PROMPT + goal-file + $([ -s "$dir/HANDOFF.md" ] && echo HANDOFF || echo no-handoff)]"
      [ "$ppolicy" = gate ] && { _say "  == STOP at $sg (gate: human review) =="; break; }
    done < <(_subgoals "$roadmap" | awk -F'\t' '$3==0 {print $1"\t"$2}')
    [ "$any" = 1 ] || _say "  (no unchecked sub-goals)"
    return 0
  fi

  while :; do
    local nx id policy
    nx=$(_next "$roadmap")
    [ -n "$nx" ] || { _say "[orchestrate] all sub-goals checked; done."; return 0; }
    id=$(printf '%s' "$nx" | cut -f1); policy=$(printf '%s' "$nx" | cut -f2)

    if [ "$policy" = gate ]; then
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
    _say "[orchestrate] running $id in a fresh session ($CLAUDE_CMD -p, model: ${rmodel:-inherit}, effort: ${reffort:-inherit}) ..."
    # Inject the prompt via a TEMP FILE on stdin, not a shell-interpolated argv arg (pi-swarm
    # borrow). Removes the backtick/${}/secret-guard bug class when the handoff body carries shell
    # metachars, and dodges ARG_MAX on a large injected handoff. `claude -p` reads the prompt from
    # stdin when no positional prompt is given.
    local pfile; pfile=$(mktemp)
    _build_prompt "$dir" "$id" > "$pfile"
    # shellcheck disable=SC2086 # CLAUDE_FLAGS + route_flags are operator/goal config; word-splitting is intended.
    if ! "$CLAUDE_CMD" -p $route_flags $CLAUDE_FLAGS < "$pfile"; then
      rm -f "$pfile"
      echo "[orchestrate] session for $id exited nonzero; stopping." >&2
      return 1
    fi
    rm -f "$pfile"

    # grounded completion: advance only if the box actually flipped.
    local checked; checked=$(_subgoals "$roadmap" | awk -F'\t' -v i="$id" '$1==i {print $3}')
    if [ "$checked" != 1 ]; then
      echo "[orchestrate] $id did not check its ROADMAP box; halting (no self-claim)." >&2
      return 1
    fi
    _say "[orchestrate] $id complete (box checked); advancing."
  done
}

main() {
  local cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    next) cmd_next "$@" ;;
    run)  cmd_run "$@" ;;
    *) echo "usage: orchestrate.sh {next|run} <megagoal-dir> [--dry-run]" >&2; exit 64 ;;
  esac
}

main "$@"
