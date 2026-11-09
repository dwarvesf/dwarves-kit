#!/bin/bash
# spec-drift-guard.sh -- PreToolUse hook that warns, never blocks, when a newly written file is not referenced by the active spec.
# spec-drift-guard.sh — PreToolUse hook, matcher: Write
# When Claude creates a new file, checks if it's referenced in the spec.
# Soft warning (allow + additionalContext), not a block.
# Source: Novel (dwarves-kit). Prevents spec drift without slowing down work.
#
# Known limitation: uses grep, so "UserService" in spec won't match
# "user_service.ts" in code. Document this, don't pretend it catches everything.

# Hook logs live under the ledger root (lib/telemetry/hook-log-dir.sh); the fallback keeps a hook running without lib/.
. "${BASH_SOURCE[0]%/*}/../lib/telemetry/hook-log-dir.sh" 2>/dev/null || kit_hook_log_dir() { printf '%s' "${KIT_LEDGER_DIR:-${DWARVES_KIT_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs}}/hooks"; }
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

# Resolve what to check the new file against (the union rule, reconciled with the unified spec-location
# decision): the UNION of all open specs in docs/specs/ (lib/spec/states.tsv, class not terminal; a
# spec with no Status header counts as open), a file in ANY active design is "known"; else .gsd/.
# Grepping the union (not a single spec) avoids a false-positive storm while more
# than one spec is open. Without lib/ every spec counts as open.
SPEC_STATUS_SH="${BASH_SOURCE[0]%/*}/../lib/spec/spec-status.sh"
SPEC_LIST=$(ls docs/specs/SPEC-*.md 2>/dev/null | sort || true)
if [ -f "$SPEC_STATUS_SH" ]; then
  # shellcheck disable=SC2086 # spec paths never contain spaces
  SPEC_SRCS=$(bash "$SPEC_STATUS_SH" live --none live $SPEC_LIST 2>/dev/null | paste -sd ' ' - || true)
else
  SPEC_SRCS=$(printf '%s\n' "$SPEC_LIST" | paste -sd ' ' - || true)
fi
[ -z "$SPEC_SRCS" ] && [ -d ".gsd" ] && SPEC_SRCS=".gsd"
[ -z "$SPEC_SRCS" ] && exit 0

# Check if file or its parent directory is mentioned in any active spec
BASENAME=$(basename -- "$FILE")
DIRNAME=$(dirname -- "$FILE")

# Fixed-string match (-F via -e): paths carry regex metacharacters ('.', '-'),
# so a raw pattern would let "config.ts" match "configXts", and a repo-root
# dirname "." would match every spec line (suppressing drift for ALL root-level
# files). Skip the dirname term when it is "." (repo root). SPEC_SRCS is
# space-separated and intentionally unquoted so grep gets multiple file args
# (spec paths never contain spaces).
if [ "$DIRNAME" = "." ]; then
  grep -rqF -e "$FILE" -e "$BASENAME" $SPEC_SRCS 2>/dev/null && exit 0
else
  grep -rqF -e "$FILE" -e "$BASENAME" -e "$DIRNAME" $SPEC_SRCS 2>/dev/null && exit 0
fi

# Log the drift detection
LOG_DIR="$(kit_hook_log_dir)"
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
  "additionalContext": "[dwarves-kit] '${FILE}' is not in any active spec (${SPEC_SRCS}). Verify this file is needed."
}
EOF

exit 0
