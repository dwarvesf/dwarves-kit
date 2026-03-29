#!/bin/bash
# spec-drift-guard.sh — PreToolUse hook, matcher: Write
# When Claude creates a new file, checks if it's referenced in the spec.
# Soft warning (allow + additionalContext), not a block.
# Source: Novel (dwarves-kit). Prevents spec drift without slowing down work.
#
# Known limitation: uses grep, so "UserService" in spec won't match
# "user_service.ts" in code. Document this, don't pretend it catches everything.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:spec-drift] checking file: $FILE" >&2
fi

# Skip non-source files (config, docs, lockfiles, etc.)
case "$FILE" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.txt|*.env*|*.gitignore|*.cfg|*.ini)
    exit 0 ;;
  *node_modules/*|*vendor/*|*dist/*|*build/*|*.git/*|*.claude/*)
    exit 0 ;;
esac

# Only check if a planning directory exists
PLAN_DIR=""
[ -d ".planning" ] && PLAN_DIR=".planning"
[ -d ".gsd" ] && PLAN_DIR=".gsd"
[ -z "$PLAN_DIR" ] && exit 0

# Check if file or its parent directory is mentioned anywhere in the spec
BASENAME=$(basename "$FILE")
DIRNAME=$(dirname "$FILE")

if grep -rq "$FILE\|$BASENAME\|$DIRNAME" "$PLAN_DIR/" 2>/dev/null; then
  # File is in the spec, all good
  exit 0
fi

# Log the drift detection
LOG_DIR="$HOME/.claude/dwarves-kit/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | DRIFT | $FILE | $(pwd)" >> "$LOG_DIR/spec-drift-guard.log"

[ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:spec-drift] DRIFT detected: $FILE not in spec" >&2

# File not found in spec: allow but inject a warning as context
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  },
  "additionalContext": "[dwarves-kit] '${FILE}' is not in the spec (${PLAN_DIR}/). Verify this file is needed."
}
EOF

exit 0
