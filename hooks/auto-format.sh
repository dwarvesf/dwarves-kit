#!/bin/bash
# auto-format.sh — PostToolUse hook, matcher: Write|Edit
# Runs the appropriate formatter after every file write/edit.
# Source: Common pattern. Idempotent, zero risk.
# Exit 0 always (formatting failure should not block work).
#
# v1.1: Fixed formatter detection order. No more npx --yes (which downloads
# prettier from the network on first run, adding 5-10s latency per edit).
# Priority: project-local binary > global binary > skip silently.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:auto-format] formatting $FILE" >&2
fi

# Helper: find prettier in project or global, never npx --yes
find_prettier() {
  # 1. Project-local (most common in Node projects)
  if [ -x "./node_modules/.bin/prettier" ]; then
    echo "./node_modules/.bin/prettier"
    return 0
  fi
  # 2. Global install
  if command -v prettier >/dev/null 2>&1; then
    echo "prettier"
    return 0
  fi
  # 3. npx WITHOUT --yes (uses cache only, no network download)
  if command -v npx >/dev/null 2>&1; then
    # Check if prettier is in npx cache without downloading
    if npx --no prettier --version >/dev/null 2>&1; then
      echo "npx --no prettier"
      return 0
    fi
  fi
  return 1
}

# Detect formatter by file extension and run silently
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.md|*.html)
    PRETTIER=$(find_prettier)
    if [ -n "$PRETTIER" ]; then
      $PRETTIER --write "$FILE" 2>/dev/null || true
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
    # Format via the rustup toolchain, not whatever rustfmt is first on PATH: a
    # brew rustfmt can shadow the rustup proxy and format to a different toolchain
    # VERSION than CI, causing import-order / style churn. Default to `stable`
    # (matches CI); a consumer repo that pins a different channel overrides with
    # RUSTFMT_TOOLCHAIN. If the pinned toolchain is missing we SKIP formatting
    # rather than silently fall through to a PATH rustfmt (that would re-introduce
    # the very divergence this fixes). Plain rustfmt is used only when rustup is
    # absent entirely. Never blocks (|| true), consistent with the hook contract.
    if command -v rustup >/dev/null 2>&1; then
      rustup run "${RUSTFMT_TOOLCHAIN:-stable}" rustfmt "$FILE" 2>/dev/null || true
    elif command -v rustfmt >/dev/null 2>&1; then
      rustfmt "$FILE" 2>/dev/null || true
    fi
    ;;
esac

exit 0
