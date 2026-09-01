#!/bin/bash
# notification.sh — Notification hook
# Sends a desktop notification when Claude finishes work or needs input.
# Lets you switch to other tasks without watching the terminal.
# Source: Anthropic hooks guide + disler/hooks-mastery

INPUT=$(cat)
TYPE=$(echo "$INPUT" | jq -r '.type // empty' 2>/dev/null)

# Determine message based on notification type
case "$TYPE" in
  "permission_prompt")
    MSG="Claude needs permission to proceed"
    ;;
  "idle_prompt")
    MSG="Claude is waiting for your input"
    ;;
  *)
    MSG="Claude needs your attention"
    ;;
esac

# macOS
if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$MSG\" with title \"dwarves-kit\" sound name \"Tink\"" 2>/dev/null &
# Linux
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "dwarves-kit" "$MSG" 2>/dev/null &
fi

exit 0
