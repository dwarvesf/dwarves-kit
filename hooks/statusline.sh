#!/bin/bash
# statusline.sh — StatusLine script
# Shows model, git branch, context usage %, session cost, thinking mode in terminal.
# Source: oh-my-claudecode HUD + Trail of Bits statusline.sh
#
# Registered in settings.json as statusLine command.
# Runs per-turn. Must be fast (<200ms).
# Uses bash+jq only (no Node.js needed for this version).

set -euo pipefail

# Read the status data from Claude Code (passed as JSON on stdin)
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract fields with defaults
MODEL=$(echo "$INPUT" | jq -r '.model // "unknown"' 2>/dev/null || echo "unknown")
# Shorten model name for display
case "$MODEL" in
  *opus*) MODEL_SHORT="opus" ;;
  *sonnet*) MODEL_SHORT="sonnet" ;;
  *haiku*) MODEL_SHORT="haiku" ;;
  *) MODEL_SHORT=$(echo "$MODEL" | cut -c1-12) ;;
esac

CONTEXT_USED=$(echo "$INPUT" | jq -r '.context_used // 0' 2>/dev/null || echo "0")
CONTEXT_MAX=$(echo "$INPUT" | jq -r '.context_max // 200000' 2>/dev/null || echo "200000")
SESSION_COST=$(echo "$INPUT" | jq -r '.session_cost // "0.00"' 2>/dev/null || echo "0.00")
THINKING=$(echo "$INPUT" | jq -r '.thinking_enabled // false' 2>/dev/null || echo "false")

# Calculate context percentage
if [ "$CONTEXT_MAX" -gt 0 ] 2>/dev/null; then
  CONTEXT_PCT=$(( (CONTEXT_USED * 100) / CONTEXT_MAX ))
else
  CONTEXT_PCT=0
fi

# Context warning indicator
if [ "$CONTEXT_PCT" -ge 80 ]; then
  CTX_INDICATOR="!!"
elif [ "$CONTEXT_PCT" -ge 60 ]; then
  CTX_INDICATOR="!"
else
  CTX_INDICATOR=""
fi

# Git branch (fast, cached per-turn)
BRANCH=$(git branch --show-current 2>/dev/null || echo "-")

# Thinking mode indicator
if [ "$THINKING" = "true" ]; then
  THINK_IND="think:on"
else
  THINK_IND="think:off"
fi

# Output the statusline (single line, compact)
echo "[${MODEL_SHORT}] ${BRANCH} | ctx:${CONTEXT_PCT}%${CTX_INDICATOR} | \$${SESSION_COST} | ${THINK_IND}"
