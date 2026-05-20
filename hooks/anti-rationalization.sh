#!/bin/bash
# anti-rationalization.sh — Stop hook
# Catches Claude declaring work complete while rationalizing incomplete work.
# Source: Trail of Bits anti-rationalization pattern (command-based v1)
# Exit 2 = force Claude to continue. Guard against infinite loop via stop_hook_active.
#
# v1.1: Trimmed from 13 to 5 patterns. Removed "out of scope", "pre-existing",
# "we can revisit", "a future improvement", "for now, this should", "beyond the scope",
# "outside the current task", "I'll leave that for" -- all legitimate phrases Claude
# uses correctly. Remaining patterns are unambiguous rationalization signals.

set -euo pipefail
INPUT=$(cat)

# Guard: prevent infinite Stop hook loop
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Get Claude's final response text
RESPONSE=$(echo "$INPUT" | jq -r '.assistant_response // empty')
[ -z "$RESPONSE" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:anti-rat] checking response (${#RESPONSE} chars)" >&2
fi

# Pattern match for rationalization cop-outs
# ONLY unambiguous patterns that indicate Claude is quitting early.
# If you're tempted to add more, check the log first for false positive rates.
PATTERNS=(
  "left as an exercise"
  "follow-up PR"
  "too many issues to address"
  "that's a separate concern"
  "follow-up task"
)

for PATTERN in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -qi "$PATTERN"; then
    # Log for future eval corpus
    LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | $PATTERN | $(pwd)" >> "$LOG_DIR/anti-rationalization.log"

    [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:anti-rat] BLOCKED on pattern: $PATTERN" >&2

    echo "{\"decision\":\"block\",\"reason\":\"Rationalization detected: your response contains '${PATTERN}'. If this work is genuinely out of scope, state why explicitly. Otherwise, finish what you started before stopping.\"}"
    exit 2
  fi
done

exit 0
