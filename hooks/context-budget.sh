#!/bin/bash
# context-budget.sh -- UserPromptSubmit hook that warns once per band once live context passes a budget.
#
# Why: every turn re-reads the whole context from cache. A session sitting at 300k+
# context burns a large share of an hour's spend, and the statusline number is easy
# to stop watching mid-session. This hook speaks up once per band instead of relying
# on the operator to notice.
#
# Context size = input + cache_creation + cache_read of the LAST main-chain (isSidechain
# != true) assistant turn in the transcript tail. That is the payload the next turn
# re-reads from cache.
#
# Bands: first warning at CC_CTX_WARN (default 200000), then one more per CC_CTX_STEP
# (default 100000). A drop below CC_CTX_WARN (e.g. after /compact) clears the state so
# the next crossing warns again.
#
# State: ~/.cache/claude-context-budget/<session_id>, one line: last warned band.
#
# Source: ported from the operator's personal dotfiles context-budget hook (tested,
# 13-case suite); this is the kit's opt-in `session` module copy. Fail-open, exit 0
# always; module install: `install.sh --with session`.
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$SESSION_ID" ] && [ -r "$TRANSCRIPT" ] || exit 0

WARN=${CC_CTX_WARN:-200000}
STEP=${CC_CTX_STEP:-100000}
case "$WARN$STEP" in *[!0-9]*) exit 0 ;; esac
[ "$STEP" -gt 0 ] || exit 0

# The last usage sits near the end; tool results make lines long, so read a generous
# tail. fromjson? drops the partial first line.
CTX=$(tail -c 2000000 "$TRANSCRIPT" 2>/dev/null \
    | jq -R 'fromjson? | select(.type == "assistant" and (.isSidechain != true) and .message.usage != null)
        | .message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null \
    | tail -n 1)
case "$CTX" in ''|*[!0-9]*) exit 0 ;; esac

STATE_DIR="${HOME}/.cache/claude-context-budget"
STATE="$STATE_DIR/$SESSION_ID"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

if [ "$CTX" -lt "$WARN" ]; then
    rm -f "$STATE" 2>/dev/null
    exit 0
fi

BAND=$(( (CTX - WARN) / STEP ))
LAST=-1
[ -r "$STATE" ] && read -r LAST < "$STATE" 2>/dev/null
case "$LAST" in ''|*[!0-9-]*) LAST=-1 ;; esac
[ "$BAND" -gt "$LAST" ] || exit 0
printf '%s\n' "$BAND" > "$STATE" 2>/dev/null

K=$(( CTX / 1000 ))
# Other sessions active in the last 5 minutes (main transcripts only, stat-only scan).
OTHERS=$(find "${HOME}/.claude/projects" -maxdepth 2 -name '*.jsonl' -mmin -5 2>/dev/null \
    | grep -vF "$SESSION_ID" | wc -l | tr -d ' ')
FLEET=""
[ "${OTHERS:-0}" -gt 0 ] && FLEET=" ${OTHERS} other sessions are active too."

USER_MSG="Context budget: this session is at ${K}k tokens, and every turn re-reads all of it.${FLEET} At the next boundary: handoff, then /clear."
MODEL_MSG="CONTEXT BUDGET: this session's live context is ${K}k tokens; each turn re-reads it from cache. Do not stop the current step. At the next natural boundary (a commit, a merged PR, a finished sub-task), recommend a handoff plus /clear to the operator in one line. Until then: read file slices instead of whole files, dispatch fresh-context subagents for fan-out, and do not re-read what is already in context."

jq -cn --arg u "$USER_MSG" --arg m "$MODEL_MSG" \
    '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
exit 0
