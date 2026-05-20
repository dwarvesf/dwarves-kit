#!/bin/bash
# safety-gate.sh — PreToolUse hook, matcher: Bash
# Blocks destructive deletes and direct pushes to main/master.
# Source: Trail of Bits claude-code-config (adapted for dwarves-kit)
# Exit 2 = block action, stderr = reason shown to Claude

set -euo pipefail
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:safety] checking: $(echo "$CMD" | head -c 80)" >&2
fi

LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"

log_block() {
  mkdir -p "$LOG_DIR"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | $1 | $(pwd) | $(echo "$CMD" | head -c 120)" >> "$LOG_DIR/safety-gate.log"
}

# Block rm -rf / rm -fr patterns
if echo "$CMD" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive\s+--force|-[a-zA-Z]*f[a-zA-Z]*r)\b'; then
  log_block "rm-rf"
  echo "BLOCKED: Destructive delete detected. Use 'trash' or 'mv' to a temp directory instead of rm -rf." >&2
  exit 2
fi

# Block direct push to main/master
if echo "$CMD" | grep -qE 'git\s+push\s+.*\b(main|master)\b'; then
  log_block "push-to-main"
  echo "BLOCKED: Do not push directly to main/master. Create a feature branch and open a PR." >&2
  exit 2
fi

# Block force push anywhere
if echo "$CMD" | grep -qE 'git\s+push\s+.*--force'; then
  log_block "force-push"
  echo "BLOCKED: Force push is dangerous. Use --force-with-lease if you must overwrite remote history." >&2
  exit 2
fi

exit 0
