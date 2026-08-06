#!/usr/bin/env bash
# output-offload.sh -- PostToolUse. When a tool returns more than ~OFFLOAD_MAX_TOKENS tokens,
# write the FULL payload to a recoverable file and inject a TERSE pointer into context, nudging
# the agent to read the file / narrow scope instead of re-requesting the whole output.
#
# IMPORTANT (honest contract): a PostToolUse hook runs AFTER the tool result is captured, so it
# cannot strip the current turn's output. The real per-turn saver for shell output is the native
# BASH_MAX_OUTPUT_LENGTH (caps at the source); see WORKFLOW.md. This hook is the safety net for
# NON-Bash tools (no source cap): it makes the bloat visible, persists a reversible full copy,
# and trains scope-narrowing. SPEC: token-optim-v2 SG-06.
#
# Token estimate = chars / 4 (rough; no tokenizer in a shell hook). Threshold via OFFLOAD_MAX_TOKENS.
set -uo pipefail

INPUT=$(cat)

MAX_TOKENS="${OFFLOAD_MAX_TOKENS:-2000}"
CHAR_BUDGET=$(( MAX_TOKENS * 4 ))

# Fast path: if the entire payload is within budget there is nothing oversized to offload. This
# keeps the common case to a string-length check (no jq) so the hook is cheap on every tool call.
[ "${#INPUT}" -le "$CHAR_BUDGET" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)

# Coerce tool_response (string | {content..} | {stdout,stderr} | array) to a flat string.
# (Extraction reused from the dotfiles secret-guard-post hook; battle-tested across tool shapes.)
RESPONSE=$(printf '%s' "$INPUT" | jq -r '
    .tool_response
    | if type == "string" then .
      elif type == "object" then
        [
            (.content // empty
             | if type == "array"
               then (map(select(.type == "text") | .text) | join("\n"))
               else tostring
               end),
            (.stdout // ""),
            (.stderr // ""),
            (.text // ""),
            (.output // "")
        ] | join("\n")
      elif type == "array" then
        map(if type == "object" and .text then .text else tostring end) | join("\n")
      else tostring
      end
' 2>/dev/null)

# The response itself must be over budget (the input also carries tool_input, which can inflate
# the raw payload size); only offload when the OUTPUT is the large part.
[ -n "$RESPONSE" ] || exit 0
[ "${#RESPONSE}" -le "$CHAR_BUDGET" ] && exit 0

EST_TOKENS=$(( ${#RESPONSE} / 4 ))

OFFLOAD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dwarves-kit/offload"
mkdir -p "$OFFLOAD_DIR" 2>/dev/null || exit 0

# Filename: timestamp + tool + a short content hash, so repeated identical outputs do not pile up.
TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo now)
HASH=$(printf '%s' "$RESPONSE" | (shasum 2>/dev/null || md5 2>/dev/null) | cut -c1-8)
SAFE_TOOL=$(printf '%s' "$TOOL_NAME" | tr -c 'A-Za-z0-9_-' '_')
FILE="$OFFLOAD_DIR/${TS}-${SAFE_TOOL}-${HASH}.txt"

printf '%s\n' "$RESPONSE" > "$FILE" 2>/dev/null || exit 0

# Terse pointer (one line, ~30 tokens) -- do NOT echo the payload back (that would re-bloat).
MSG="[dwarves-kit] ${TOOL_NAME} output was large (~${EST_TOKENS} tokens, over the ${MAX_TOKENS}-token offload threshold). Full payload saved to ${FILE}. Read that file (or a slice of it) for detail; next time narrow the tool's scope (offset/limit, head, grep) instead of re-requesting the whole output. For Bash specifically, set BASH_MAX_OUTPUT_LENGTH to cap at the source."

jq -cn --arg ctx "$MSG" '{additionalContext: $ctx}' 2>/dev/null || printf '{"additionalContext":%s}\n' "$(printf '%s' "$MSG" | jq -Rs . 2>/dev/null)"
exit 0
