#!/bin/bash
# anti-rationalization.sh — Stop hook
# Catches Claude declaring work complete while rationalizing incomplete work.
# Source: Trail of Bits anti-rationalization pattern (command-based v1)
# Exit 2 = force Claude to continue. Guard against infinite loop via stop_hook_active.

set -euo pipefail
INPUT=$(cat)

# Guard: prevent infinite Stop hook loop
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Get Claude's final response text
RESPONSE=$(echo "$INPUT" | jq -r '.assistant_response // empty')
[ -z "$RESPONSE" ] && exit 0

# Pattern match for rationalization cop-outs
# These are phrases Claude uses when it wants to stop but hasn't finished
PATTERNS=(
  "pre-existing"
  "out of scope"
  "beyond the scope"
  "follow-up task"
  "follow-up PR"
  "too many issues to address"
  "left as an exercise"
  "for now, this should"
  "a future improvement"
  "we can revisit"
  "I'll leave that for"
  "that's a separate concern"
  "outside the current task"
)

for PATTERN in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -qi "$PATTERN"; then
    # Log for future eval corpus (don't remove this -- it builds the AutoResearch dataset)
    LOG_DIR="$HOME/.claude/dwarves-kit/logs"
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | $PATTERN | $(pwd)" >> "$LOG_DIR/anti-rationalization.log"
    
    echo "{\"decision\":\"block\",\"reason\":\"Rationalization detected: your response contains '${PATTERN}'. If this work is genuinely out of scope, state why explicitly. Otherwise, finish what you started before stopping.\"}"
    exit 2
  fi
done

exit 0
