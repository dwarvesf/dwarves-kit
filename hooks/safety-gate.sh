#!/bin/bash
# safety-gate.sh — PreToolUse hook, matcher: Bash
# Blocks destructive deletes and direct pushes to main/master.
# Source: Trail of Bits claude-code-config (adapted for dwarves-kit)
# Exit 2 = block action, stderr = reason shown to Claude

set -euo pipefail
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Block rm -rf / rm -fr patterns
if echo "$CMD" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive\s+--force|-[a-zA-Z]*f[a-zA-Z]*r)\b'; then
  echo "BLOCKED: Destructive delete detected. Use 'trash' or 'mv' to a temp directory instead of rm -rf." >&2
  exit 2
fi

# Block direct push to main/master
if echo "$CMD" | grep -qE 'git\s+push\s+.*\b(main|master)\b'; then
  echo "BLOCKED: Do not push directly to main/master. Create a feature branch and open a PR." >&2
  exit 2
fi

# Block force push anywhere
if echo "$CMD" | grep -qE 'git\s+push\s+.*--force'; then
  echo "BLOCKED: Force push is dangerous. Use --force-with-lease if you must overwrite remote history." >&2
  exit 2
fi

exit 0
