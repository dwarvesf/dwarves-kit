#!/bin/bash
# context-budget.sh -- UserPromptSubmit hook that warns once per threshold once live context passes a percentage of the model's window.
#
# Why: every turn re-reads the whole context from cache. A session sitting at 65%+
# of its window burns a large share of an hour's spend, and the statusline number is
# easy to stop watching mid-session. This hook speaks up once per threshold instead
# of relying on the operator to notice.
#
# Context size = input + cache_creation + cache_read of the LAST main-chain (isSidechain
# != true) assistant turn in the transcript tail. That is the payload the next turn
# re-reads from cache. The window is the context window of that same turn's model
# (KIT_CTX_WINDOW overrides everything; default 200000; auto-bumped to 1000000 for a
# "1m" marker, case-insensitive, on any of: .message.model (usually the bare model
# id, e.g. claude-opus-5-5, so rarely a hit), the configured model (ANTHROPIC_MODEL
# or settings `.model`), or the transcript's model-identity attachment
# (.attachment.identity.modelId, which can sit far earlier in the file than the
# tail -c window below reads); also bumped when live context already exceeds
# 200000, since it cannot then be a 200k-window model).
#
# Thresholds: KIT_CTX_WARN_PCT (default 65) is advisory (hand off at the next
# boundary). KIT_CTX_STRONG_PCT (default 70) is a directive: finish the step in
# flight, write the handoff, stop starting new work. Each fires once per session
# until context drops back under KIT_CTX_WARN_PCT (e.g. after /compact or /clear),
# which clears the state so the next crossing warns again.
#
# State: ~/.cache/claude-context-budget/<session_id>, one line: last-fired threshold
# (0 = warn, 1 = strong).
#
# Source: percentage rewrite of the operator's personal dotfiles context-budget hook
# (tested, absolute-token-band suite); this is the kit's opt-in `session` module copy.
# Fail-open, exit 0 always; module install: `install.sh --with session`.
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$SESSION_ID" ] && [ -r "$TRANSCRIPT" ] || exit 0

WARN_PCT=${KIT_CTX_WARN_PCT:-65}
STRONG_PCT=${KIT_CTX_STRONG_PCT:-70}
case "$WARN_PCT$STRONG_PCT" in *[!0-9]*) exit 0 ;; esac
[ "$WARN_PCT" -gt 0 ] && [ "$WARN_PCT" -lt "$STRONG_PCT" ] && [ "$STRONG_PCT" -le 100 ] || exit 0

# The last usage sits near the end; tool results make lines long, so read a generous
# tail. fromjson? drops the partial first line.
LAST_TURN=$(tail -c 2000000 "$TRANSCRIPT" 2>/dev/null \
    | jq -Rc 'fromjson? | select(.type == "assistant" and (.isSidechain != true) and .message.usage != null)
        | {ctx: (.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
           model: (.message.model // "")}' 2>/dev/null \
    | tail -n 1)
[ -n "$LAST_TURN" ] || exit 0
CTX=$(printf '%s' "$LAST_TURN" | jq -r '.ctx' 2>/dev/null)
MODEL=$(printf '%s' "$LAST_TURN" | jq -r '.model' 2>/dev/null)
case "$CTX" in ''|*[!0-9]*) exit 0 ;; esac

if [ -n "${KIT_CTX_WINDOW:-}" ]; then
    WINDOW="$KIT_CTX_WINDOW"
else
    # The transcript records the API model id, which drops the `[1m]` suffix Claude Code
    # uses to select the 1M window (`opus[1m]` logs as `claude-opus-5-5`). Also check the
    # configured model: ANTHROPIC_MODEL, then project-local, project, and user settings.
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    CONFIGURED="${ANTHROPIC_MODEL:-}"
    for f in ${CWD:+"$CWD/.claude/settings.local.json" "$CWD/.claude/settings.json"} "$HOME/.claude/settings.json"; do
        [ -n "$CONFIGURED" ] && break
        [ -r "$f" ] && CONFIGURED=$(jq -r '.model // empty' "$f" 2>/dev/null)
    done
    # The [1m] marker can also live on the transcript's model-identity attachment
    # (.attachment.identity.modelId), earlier in the file than the tail -c window
    # above reads -- scan the whole file for the latest one.
    IDENTITY_MODEL=$(grep -o '"modelId"[[:space:]]*:[[:space:]]*"[^"]*"' "$TRANSCRIPT" 2>/dev/null | tail -n 1)
    WINDOW=200000
    case "$(printf '%s %s %s' "$MODEL" "$CONFIGURED" "$IDENTITY_MODEL" | tr '[:upper:]' '[:lower:]')" in
        *1m*) WINDOW=1000000 ;;
    esac
    # Usage past 200k proves the window is bigger, whatever the model id says.
    [ "$CTX" -gt 200000 ] && WINDOW=1000000
fi
case "$WINDOW" in *[!0-9]*) exit 0 ;; esac
[ "$WINDOW" -gt 0 ] || exit 0

STATE_DIR="${HOME}/.cache/claude-context-budget"
STATE="$STATE_DIR/$SESSION_ID"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Threshold compares as CTX*100 >= PCT*WINDOW, no floating point.
CTX100=$(( CTX * 100 ))
if [ "$CTX100" -lt "$(( WARN_PCT * WINDOW ))" ]; then
    rm -f "$STATE" 2>/dev/null
    exit 0
fi

if [ "$CTX100" -ge "$(( STRONG_PCT * WINDOW ))" ]; then
    THRESH=1
else
    THRESH=0
fi

LAST=-1
[ -r "$STATE" ] && read -r LAST < "$STATE" 2>/dev/null
case "$LAST" in ''|*[!0-9-]*) LAST=-1 ;; esac
[ "$THRESH" -gt "$LAST" ] || exit 0
printf '%s\n' "$THRESH" > "$STATE" 2>/dev/null

PCT=$(( CTX100 / WINDOW ))
K=$(( CTX / 1000 ))
# Other sessions active in the last 5 minutes (main transcripts only, stat-only scan).
OTHERS=$(find "${HOME}/.claude/projects" -maxdepth 2 -name '*.jsonl' -mmin -5 2>/dev/null \
    | grep -vF "$SESSION_ID" | wc -l | tr -d ' ')
FLEET=""
[ "${OTHERS:-0}" -gt 0 ] && FLEET=" ${OTHERS} other sessions are active too."

if [ "$THRESH" -ge 1 ]; then
    USER_MSG="Context ceiling: this session is at ${PCT}% of its window (${K}k tokens).${FLEET} Finish the step in flight, write the handoff, then /clear."
    MODEL_MSG="CONTEXT CEILING: this session's live context is ${PCT}% of its window (${K}k tokens), and each turn re-reads it from cache. Finish the step in flight, then stop starting new work: do not open a new sub-task and do not dispatch new subagents from this context. Write the handoff (the handoff skill) and tell the operator in one line to /clear."
else
    USER_MSG="Context budget: this session is at ${PCT}% of its window (${K}k tokens), and every turn re-reads all of it.${FLEET} Write the handoff now (the handoff skill), then /clear."
    MODEL_MSG="CONTEXT BUDGET: this session's live context is ${PCT}% of its window (${K}k tokens); each turn re-reads it from cache. Write the handoff now (the handoff skill) and recommend /clear to the operator in one line at the next natural boundary (a commit, a merged PR, a finished sub-task). Until then: read file slices instead of whole files, dispatch fresh-context subagents for fan-out, and do not re-read what is already in context."
fi

jq -cn --arg u "$USER_MSG" --arg m "$MODEL_MSG" \
    '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
exit 0
