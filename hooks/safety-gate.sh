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

# Build-artifact allowlist: a SINGLE, simple `rm -rf` of only regenerable
# artifacts (node_modules/dist/.next/target/...) is safe and should not trip the
# destructive-delete block. Compound commands (&&, ;, |, $( ), backticks) are
# NOT allowlisted: they fall through and are blocked. (gstack `careful` allowlist.)
if echo "$CMD" | grep -qE '\brm\s+-[a-zA-Z]*[rf]' && ! echo "$CMD" | grep -qE '(&&|\|\||;|\||\$\(|`)'; then
  RM_TAIL=$(echo "$CMD" | sed -E 's/^[[:space:]]*rm[[:space:]]+-[a-zA-Z]+[[:space:]]+//')
  ALL_SAFE=1; HAVE_TARGET=0
  for t in $RM_TAIL; do
    case "$t" in
      *..*) ALL_SAFE=0; break ;;   # any parent-traversal token is never safe (C-1)
      -*) ;;
      node_modules|node_modules/|node_modules/*|./node_modules|./node_modules/|./node_modules/*|\
      dist|dist/|dist/*|./dist|./dist/|./dist/*|\
      build|build/|build/*|./build|./build/|./build/*|\
      .next|.next/|.next/*|./.next|./.next/|./.next/*|\
      .nuxt|.nuxt/|.nuxt/*|.turbo|.turbo/|.turbo/*|.cache|.cache/|.cache/*|\
      target|target/|target/*|./target|./target/|./target/*|\
      coverage|coverage/|coverage/*|out|out/|out/*)
        HAVE_TARGET=1 ;;
      *) ALL_SAFE=0; break ;;
    esac
  done
  [ "$ALL_SAFE" = "1" ] && [ "$HAVE_TARGET" = "1" ] && exit 0
fi

# Block rm -rf / rm -fr patterns
if echo "$CMD" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive\s+--force|-[a-zA-Z]*f[a-zA-Z]*r)\b'; then
  log_block "rm-rf"
  echo "BLOCKED: Destructive delete detected. Use 'trash' or 'mv' to a temp directory instead of rm -rf (build artifacts like node_modules/dist are allowlisted)." >&2
  exit 2
fi

# Block direct push to main/master
if echo "$CMD" | grep -qE 'git\s+push\s+.*\b(main|master)\b'; then
  log_block "push-to-main"
  echo "BLOCKED: Do not push directly to main/master. Create a feature branch and open a PR." >&2
  exit 2
fi

# Block bare force push anywhere. --force-with-lease (and --force-if-includes) are
# the sanctioned escape hatch this very message recommends, so they must NOT match:
# require the flag to END at --force (next char is not a hyphen). Refspec force
# (`git push origin +branch`) is also blocked: it is --force without the lease.
if echo "$CMD" | grep -qE 'git\s+push\s+.*(--force([^-]|$)|\s\+[^[:space:]]+)'; then
  log_block "force-push"
  echo "BLOCKED: Force push is dangerous. Use --force-with-lease if you must overwrite remote history." >&2
  exit 2
fi

# Block destructive SQL DROP TABLE
if echo "$CMD" | grep -qiE '\bDROP\s+TABLE\b'; then
  log_block "drop-table"
  echo "BLOCKED: DROP TABLE is destructive. Run it manually after a backup, or use a reversible migration." >&2
  exit 2
fi

# Block git reset --hard (silent loss of uncommitted work)
if echo "$CMD" | grep -qE 'git\s+reset\s+.*--hard'; then
  log_block "git-reset-hard"
  echo "BLOCKED: 'git reset --hard' discards uncommitted work. Use 'git stash' first, or 'git reset --keep'." >&2
  exit 2
fi

# Block kubectl delete (destructive cluster mutation)
if echo "$CMD" | grep -qE '\bkubectl\s+delete\b'; then
  log_block "kubectl-delete"
  echo "BLOCKED: 'kubectl delete' mutates a live cluster. Confirm the context and run it manually." >&2
  exit 2
fi

exit 0
