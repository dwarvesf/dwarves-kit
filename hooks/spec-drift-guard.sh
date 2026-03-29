#!/bin/bash
# spec-drift-guard.sh — PreToolUse hook, matcher: Write
# When Claude creates a new file, checks if it's referenced in the spec.
# Soft warning (allow + additionalContext), not a block.
# Source: Novel (dwarves-kit). Prevents spec drift without slowing down work.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

# Skip non-source files (config, docs, lockfiles, etc.)
case "$FILE" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|*.txt|*.env*|*.gitignore|*.cfg|*.ini)
    exit 0 ;;
  *node_modules/*|*vendor/*|*dist/*|*build/*|*.git/*)
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

# File not found in spec: allow but inject a warning as context
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  },
  "additionalContext": "[dwarves-kit] NOTE: '${FILE}' is not referenced in the spec (${PLAN_DIR}/). This may indicate spec drift. Verify this file is needed for the current task before proceeding."
}
EOF

exit 0
