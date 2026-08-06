#!/usr/bin/env bash
# reviewer-run.sh (TRUSTED): the only code that writes a skill draft or a ledger line.
#
# Pipeline: payload file (transcript_path, session_id) -> last-K-turn summary -> a no-write
# `claude -p` reviewer (the MODEL has --allowedTools "" so it can write nothing) -> parse the
# returned JSON draft -> the WRAPPER writes it to ~/.claude/skill-proposals/<slug>/SKILL.md and
# appends cost to the ledger. The model never touches the filesystem; staging-by-path is a hard
# gate (SPEC-103 DEC-008). Always exits 0 (a reviewer must never break a session).
#
# Test seam: SKILL_CURATOR_REVIEWER_CMD overrides the claude call (reads the prompt on stdin, emits a
# `claude -p --output-format json` envelope on stdout), so tests run without a live model.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/common.sh"
# shellcheck source=lib/transcript.sh
. "$HERE/transcript.sh"

main() {
  local payload_file="${1:-}"
  [ -n "$payload_file" ] && [ -f "$payload_file" ] || { si_log "reviewer: no payload file"; return 0; }

  local transcript_path session_id
  transcript_path="$(jq -r '.transcript_path // empty' "$payload_file" 2>/dev/null)"
  session_id="$(jq -r '.session_id // empty' "$payload_file" 2>/dev/null)"

  local summary; summary="$(transcript_compact "$transcript_path" "$(cfg transcript_k 40)")"
  if [ -z "${summary//[[:space:]]/}" ]; then si_log "reviewer: empty transcript, nothing to review"; return 0; fi

  # Deterministic signal-marker pre-gate (opt-in via signal_gate): skip the model call for a summary
  # with zero cheap markers of a draftable signal, preserving quota. Conservative by design (broad
  # pattern biases toward KEEPING a session over dropping a real one); skips are ledgered so the
  # false-negative rate is auditable before the gate is trusted. Runs before the lock + the model.
  if [ "$(cfg signal_gate false)" = "true" ] && ! has_signal_markers "$summary"; then
    si_log "reviewer: signal-gate , no signal markers in summary, skipping (quota preserved)"
    _ledger false "" 0 0 0 "skip-no-signal"; return 0
  fi

  # Single-flight: a reviewer already in flight holds the lock; skip rather than pile up cost.
  if ! si_acquire_lock; then si_log "reviewer: single-flight , another reviewer in flight, skipping"; return 0; fi
  trap 'si_release_lock' EXIT

  # Build reviewer input = prompt + summary.
  local prompt_file="$SKILL_CURATOR_ROOT/prompts/review-skill.md" input envelope
  [ -f "$prompt_file" ] || { si_log "reviewer: missing prompt $prompt_file"; return 0; }
  input="$(cat "$prompt_file"; printf '\n\n=== SESSION SUMMARY ===\n%s\n' "$summary")"

  envelope="$(printf '%s' "$input" | run_reviewer)"
  if [ -z "${envelope//[[:space:]]/}" ]; then
    si_log "reviewer: empty claude output (missing/auth/non-zero); no draft"
    _ledger false "" 0 0 0 "no-output"; return 0
  fi

  # Outer layer: the claude -p envelope (cost + the model's result text).
  local cost itok otok result
  cost="$(jq -r '.total_cost_usd // 0' <<<"$envelope" 2>/dev/null | grep -Eo '^[0-9.]+' | head -1)"; cost="${cost:-0}"
  itok="$(jq -r '.usage.input_tokens // 0' <<<"$envelope" 2>/dev/null | grep -Eo '^[0-9]+' | head -1)"; itok="${itok:-0}"
  otok="$(jq -r '.usage.output_tokens // 0' <<<"$envelope" 2>/dev/null | grep -Eo '^[0-9]+' | head -1)"; otok="${otok:-0}"
  result="$(jq -r '.result // empty' <<<"$envelope" 2>/dev/null)"
  if [ -z "$result" ]; then
    si_log "reviewer: envelope had no .result; no draft"; _ledger false "" "$cost" "$itok" "$otok" "no-result"; return 0
  fi

  # Inner layer: the model's JSON {draft|null, reason}. Tolerate a stray code fence / canary line.
  local clean draft_present slug body
  clean="$(printf '%s' "$result" | grep -vE '^[[:space:]]*(```([a-z]*)?|🐱 Neko-san)[[:space:]]*$')"
  if ! jq -e . >/dev/null 2>&1 <<<"$clean"; then
    si_log "reviewer: model result was not valid JSON; no draft (logged, not fatal)"
    _ledger false "" "$cost" "$itok" "$otok" "bad-json"; return 0
  fi
  draft_present="$(jq -r 'if (.draft // null) == null then "no" else "yes" end' <<<"$clean" 2>/dev/null)"
  if [ "$draft_present" != "yes" ]; then
    si_log "reviewer: null draft (no reusable skill this session) , $(jq -r '.reason // ""' <<<"$clean")"
    _ledger false "" "$cost" "$itok" "$otok" "null-draft"; return 0
  fi

  slug="$(safe_slug "$(jq -r '.draft.slug // .draft.name // ""' <<<"$clean")")"
  body="$(jq -r '.draft.body // ""' <<<"$clean")"
  if [ -z "${body//[[:space:]]/}" ]; then
    si_log "reviewer: draft had empty body; no write"; _ledger false "$slug" "$cost" "$itok" "$otok" "empty-body"; return 0
  fi

  # Wrapper-side secret guard: drop a draft that still carries a credential (defense in depth on
  # top of the prompt ban + the promote-time scan). Never stage a printed secret.
  if contains_secret "$body"; then
    si_log "reviewer: draft '$slug' DROPPED , contained a secret-shaped string (not staged)"
    _ledger false "$slug" "$cost" "$itok" "$otok" "dropped-secret"; return 0
  fi

  # The only place the wrapper ever writes a draft: skill-proposals/<slug>/SKILL.md (NOT skills/).
  local dir="$SKILL_CURATOR_PROPOSALS_DIR/$slug"
  if ! mkdir -p "$dir" 2>/dev/null; then
    si_log "reviewer: could not create $dir; no write"; _ledger false "$slug" "$cost" "$itok" "$otok" "mkdir-fail"; return 0
  fi
  printf '%s\n' "$body" > "$dir/SKILL.md" 2>/dev/null || { si_log "reviewer: write failed $dir/SKILL.md"; return 0; }
  si_log "reviewer: staged draft -> $dir/SKILL.md (cost \$$cost)"
  _ledger true "$slug" "$cost" "$itok" "$otok" "staged"
  return 0
}

# run_reviewer: stdin = prompt; stdout = claude -p envelope JSON. CLAUDE_REVIEWING set for the
# reentrancy guard. SKILL_CURATOR_REVIEWER_CMD overrides the model call (tests). Model = no write.
run_reviewer() {
  if [ -n "${SKILL_CURATOR_REVIEWER_CMD:-}" ]; then
    CLAUDE_REVIEWING=1 bash -c "$SKILL_CURATOR_REVIEWER_CMD"
  else
    CLAUDE_REVIEWING=1 claude -p --bare --no-session-persistence \
      --allowedTools "" --model "$(cfg model haiku)" --max-turns "$(cfg max_turns 2)" \
      --output-format json 2>>"$SKILL_CURATOR_LOG"
  fi
}

# has_signal_markers <text>: deterministic pre-gate. Returns 0 if the summary carries any cheap
# marker of a draftable signal (user correction / frustration, a fix / technique / debug path, or a
# skill-was-wrong note , mirroring prompts/review-skill.md's signal list), 1 if none are present.
# The pattern is intentionally broad: a false positive only wastes one null-draft call, whereas a
# false negative drops a real signal, so the gate keeps by default. Override via `signal_markers`
# (config) / SKILL_CURATOR_SIGNAL_MARKERS (env).
has_signal_markers() {
  local text="$1" pat
  pat="$(cfg signal_markers '')"
  [ -n "$pat" ] || pat="actually|instead|no,|nope|stop (doing|that)|do(n't| not)|too (verbose|much)|just (give|tell|answer|the)|you (always|keep|never)|wrong|not what|that's not|should (have|not)|why did you|prefer|fix(ed|es)?|workaround|root cause|turns out|the (trick|issue|problem|fix)|gotcha|debug|figured out|missing a step|outdated|patch"
  printf '%s' "$text" | grep -qiE -- "$pat"
}

# _ledger <staged-bool> <slug> <cost> <itok> <otok> <note>
_ledger() {
  local staged="$1" slug="$2" cost="$3" itok="$4" otok="$5" note="$6" ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo '?')"
  ledger_append "$(jq -nc \
    --arg ts "$ts" --arg sid "${session_id:-}" --arg slug "$slug" --arg note "$note" \
    --argjson staged "$staged" --argjson cost "${cost:-0}" --argjson it "${itok:-0}" --argjson ot "${otok:-0}" \
    '{ts:$ts, session_id:$sid, kind:"skill-review", staged:$staged,
      slug:(if $slug=="" then null else $slug end), note:$note,
      total_cost_usd:$cost, input_tokens:$it, output_tokens:$ot}' 2>/dev/null)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  session_id=""   # set inside main() from the payload; declared here so _ledger sees it
  main "${1:-}"
fi
