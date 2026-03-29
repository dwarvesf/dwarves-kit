#!/bin/bash
# permission-auto-approve.sh — PermissionRequest hook
# Auto-approves read-only and safe operations.
# Eliminates "click approve 20 times" friction for ls, cat, git status, etc.
# Source: disler/hooks-mastery + Trail of Bits auto-allow pattern

set -euo pipefail
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Always auto-approve read-only tools
case "$TOOL" in
  Read|Glob|Grep|WebSearch|WebFetch)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
    ;;
esac

# Auto-approve safe Bash commands (read-only, non-destructive)
if [ "$TOOL" = "Bash" ] && [ -n "$CMD" ]; then
  # Whitelist of safe command prefixes
  SAFE_PATTERNS=(
    "^ls\b"
    "^cat\b"
    "^head\b"
    "^tail\b"
    "^wc\b"
    "^echo\b"
    "^pwd$"
    "^find\b.*-name\b"
    "^grep\b"
    "^git\s+(status|log|diff|branch|show|remote|tag)"
    "^git\s+ls-files"
    "^which\b"
    "^type\b"
    "^file\b"
    "^stat\b"
    "^du\b"
    "^df\b"
    "^env$"
    "^printenv\b"
    "^node\s+--version"
    "^npm\s+(list|ls|outdated|view)"
    "^npx\s+prettier\b.*--check"
    "^go\s+(version|env|list)"
    "^python3?\s+--version"
    "^ruff\s+check\b"
    "^cargo\s+(--version|check\b)"
  )

  for PATTERN in "${SAFE_PATTERNS[@]}"; do
    if echo "$CMD" | grep -qE "$PATTERN"; then
      echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      exit 0
    fi
  done
fi

# Everything else: let the normal permission dialog show
exit 0
