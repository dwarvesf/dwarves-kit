#!/bin/bash
# context-budget.sh -- UserPromptSubmit hook that warns once per threshold once live context passes an absolute token budget.
#
# Why: every turn re-reads the whole context from cache, so cost grows with absolute
# context size, whatever the window. The statusline number is easy to stop watching
# mid-session. This hook speaks up once per threshold instead of relying on the
# operator to notice.
#
# Context size = input + cache_creation + cache_read of the LAST main-chain (isSidechain
# != true) assistant turn in the transcript tail. That is the payload the next turn
# re-reads from cache.
#
# Thresholds (default, absolute tokens): KIT_CTX_WARN_TOKENS (default 200000) is
# advisory (hand off at the next boundary). KIT_CTX_STRONG_TOKENS (default 250000) is a
# directive: finish the step in flight, write the handoff, stop starting new work. No
# window guess is involved: the transcript often logs a bare model id, so a window
# guessed from it can be wrong by 5x.
#
# Legacy percentage mode, for backward compatibility only: setting KIT_CTX_WARN_PCT or
# KIT_CTX_STRONG_PCT (either one; the other defaults to 65 / 70) switches to thresholds
# as a percentage of the window, and the *_TOKENS variables are then ignored. The window
# is KIT_CTX_WINDOW if set, else the statusline's window file, else 200000, bumped to
# 1000000 for a "1m" marker (case-insensitive) on .message.model, the configured model
# (ANTHROPIC_MODEL or settings `.model`) or the transcript's model-identity attachment
# (.attachment.identity.modelId), or when live context already exceeds 200000.
# KIT_CTX_WINDOW alone does not switch modes.
#
# Either way, each threshold fires once per session until context drops back under the
# warn threshold (e.g. after /compact or /clear), which clears the state so the next
# crossing warns again.
#
# State: <config data path cache context-budget>/<session_id>, one line: last-fired threshold
# (0 = warn, 1 = strong).
#
# Source: the operator's personal dotfiles context-budget hook (absolute-token bands),
# retired there once the kit's opt-in `session` module took it over.
# Fail-open, exit 0 always; module install: `install.sh --with session`.
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$SESSION_ID" ] && [ -r "$TRANSCRIPT" ] || exit 0

if [ -n "${KIT_CTX_WARN_PCT:-}${KIT_CTX_STRONG_PCT:-}" ]; then
    PCT_MODE=1
    WARN_PCT=${KIT_CTX_WARN_PCT:-65}
    STRONG_PCT=${KIT_CTX_STRONG_PCT:-70}
    case "$WARN_PCT$STRONG_PCT" in *[!0-9]*) exit 0 ;; esac
    [ "$WARN_PCT" -gt 0 ] && [ "$WARN_PCT" -lt "$STRONG_PCT" ] && [ "$STRONG_PCT" -le 100 ] || exit 0
else
    PCT_MODE=0
    WARN_AT=${KIT_CTX_WARN_TOKENS:-200000}
    STRONG_AT=${KIT_CTX_STRONG_TOKENS:-250000}
    case "$WARN_AT$STRONG_AT" in *[!0-9]*) exit 0 ;; esac
    [ "$WARN_AT" -gt 0 ] && [ "$WARN_AT" -lt "$STRONG_AT" ] || exit 0
fi

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

# shellcheck source=../lib/config/data-path.sh
. "${BASH_SOURCE[0]%/*}/../lib/config/data-path.sh" 2>/dev/null || exit 0
STATE_DIR="$(kit_data_path cache context-budget)"
if [ "$PCT_MODE" -eq 1 ]; then
    # A statusline that sees Claude Code's context_window_size may drop it here; it is the
    # real window, so it beats every guess below (a 1M model often logs a bare model id).
    WINDOW_FILE_VAL=""
    [ -r "$STATE_DIR/$SESSION_ID.window" ] && read -r WINDOW_FILE_VAL < "$STATE_DIR/$SESSION_ID.window" 2>/dev/null
    case "$WINDOW_FILE_VAL" in ''|*[!0-9]*) WINDOW_FILE_VAL="" ;; esac

    if [ -n "${KIT_CTX_WINDOW:-}" ]; then
        WINDOW="$KIT_CTX_WINDOW"
    elif [ -n "$WINDOW_FILE_VAL" ]; then
        WINDOW="$WINDOW_FILE_VAL"
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
    # Percent thresholds become token thresholds (rounded up, so CTX >= AT matches
    # CTX*100 >= PCT*WINDOW exactly); the rest of the hook is mode-blind.
    WARN_AT=$(( (WARN_PCT * WINDOW + 99) / 100 ))
    STRONG_AT=$(( (STRONG_PCT * WINDOW + 99) / 100 ))
fi

STATE="$STATE_DIR/$SESSION_ID"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

if [ "$CTX" -lt "$WARN_AT" ]; then
    rm -f "$STATE" 2>/dev/null
    exit 0
fi

if [ "$CTX" -ge "$STRONG_AT" ]; then
    THRESH=1
else
    THRESH=0
fi

LAST=-1
[ -r "$STATE" ] && read -r LAST < "$STATE" 2>/dev/null
case "$LAST" in ''|*[!0-9-]*) LAST=-1 ;; esac
[ "$THRESH" -gt "$LAST" ] || exit 0
printf '%s\n' "$THRESH" > "$STATE" 2>/dev/null

K=$(( CTX / 1000 ))
WARN_K=$(( WARN_AT / 1000 ))
STRONG_K=$(( STRONG_AT / 1000 ))
# Other sessions active in the last 5 minutes (main transcripts only, stat-only scan).
OTHERS=$(find "${HOME}/.claude/projects" -maxdepth 2 -name '*.jsonl' -mmin -5 2>/dev/null \
    | grep -vF "$SESSION_ID" | wc -l | tr -d ' ')
FLEET=""
[ "${OTHERS:-0}" -gt 0 ] && FLEET=" ${OTHERS} other sessions are active too."

if [ "$THRESH" -ge 1 ]; then
    USER_MSG="Context ceiling: this session holds ${K}k tokens of live context, at or past the ${STRONG_K}k ceiling.${FLEET} Finish the step in flight, write the handoff, then /clear."
    MODEL_MSG="CONTEXT CEILING: this session's live context is ${K}k tokens, at or past the ${STRONG_K}k ceiling, and each turn re-reads it from cache. Finish the step in flight, then stop starting new work: do not open a new sub-task and do not dispatch new subagents from this context. Write the handoff (the handoff skill) and tell the operator in one line to /clear."
else
    USER_MSG="Context budget: this session holds ${K}k tokens of live context, at or past the ${WARN_K}k budget, and every turn re-reads all of it.${FLEET} Write the handoff now (the handoff skill), then /clear."
    MODEL_MSG="CONTEXT BUDGET: this session's live context is ${K}k tokens, at or past the ${WARN_K}k budget; each turn re-reads it from cache. Write the handoff now (the handoff skill) and recommend /clear to the operator in one line at the next natural boundary (a commit, a merged PR, a finished sub-task). Until then: read file slices instead of whole files, dispatch fresh-context subagents for fan-out, and do not re-read what is already in context."
fi

jq -cn --arg u "$USER_MSG" --arg m "$MODEL_MSG" \
    '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
exit 0
