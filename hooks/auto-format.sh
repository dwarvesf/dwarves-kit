#!/bin/bash
# auto-format.sh — PostToolUse hook, matcher: Write|Edit
# Runs the appropriate formatter after every file write/edit.
# Source: Common pattern. Idempotent, zero risk.
# Exit 0 always (formatting failure should not block work).

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Detect formatter by file extension and run silently
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.md|*.html)
    if command -v npx >/dev/null 2>&1; then
      npx --yes prettier --write "$FILE" 2>/dev/null || true
    fi
    ;;
  *.go)
    if command -v gofmt >/dev/null 2>&1; then
      gofmt -w "$FILE" 2>/dev/null || true
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$FILE" 2>/dev/null || true
    elif command -v black >/dev/null 2>&1; then
      black --quiet "$FILE" 2>/dev/null || true
    fi
    ;;
  *.rs)
    if command -v rustfmt >/dev/null 2>&1; then
      rustfmt "$FILE" 2>/dev/null || true
    fi
    ;;
esac

exit 0
