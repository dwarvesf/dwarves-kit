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

# Resolve what to check the new file against: the active spec in docs/specs/
# (highest non-SHIPPED/PARKED SPEC-NNN), else legacy .planning/SPEC.md, else .gsd/.
# docs/specs/ holds many specs, so grep ONLY the active one (grepping all specs
# would make drift detection meaningless). Interim selector; SPEC-005 refines it.
SPEC_SRC=""
for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do
  grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" || { SPEC_SRC="$F"; break; }
done
[ -z "$SPEC_SRC" ] && [ -f ".planning/SPEC.md" ] && SPEC_SRC=".planning/SPEC.md"
[ -z "$SPEC_SRC" ] && [ -d ".gsd" ] && SPEC_SRC=".gsd"
[ -z "$SPEC_SRC" ] && exit 0

# Check if file or its parent directory is mentioned in the active spec
BASENAME=$(basename "$FILE")
DIRNAME=$(dirname "$FILE")

if grep -rq "$FILE\|$BASENAME\|$DIRNAME" "$SPEC_SRC" 2>/dev/null; then
  # File is in the spec, all good
  exit 0
fi

# Log the drift detection
LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
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
  "additionalContext": "[dwarves-kit] '${FILE}' is not in the spec (${SPEC_SRC}). Verify this file is needed."
}
EOF

exit 0
