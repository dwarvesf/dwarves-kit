#!/bin/bash
# anti-rationalization.sh — Stop hook
# Catches Claude declaring work complete while rationalizing incomplete work.
# Source: Trail of Bits anti-rationalization pattern (command-based v1)
# Exit 2 = force Claude to continue. Guard against infinite loop via stop_hook_active.
#
# v1.1: Trimmed from 13 to 5 patterns. Removed "out of scope", "pre-existing",
# "we can revisit", "a future improvement", "for now, this should", "beyond the scope",
# "outside the current task", "I'll leave that for" -- all legitimate phrases Claude
# uses correctly. Remaining patterns are unambiguous rationalization signals.

set -euo pipefail
INPUT=$(cat)

# Guard: prevent infinite Stop hook loop
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Get Claude's final response text
RESPONSE=$(echo "$INPUT" | jq -r '.assistant_response // empty')
[ -z "$RESPONSE" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:anti-rat] checking response (${#RESPONSE} chars)" >&2
fi

# Pattern match for rationalization cop-outs
# ONLY unambiguous patterns that indicate Claude is quitting early.
# If you're tempted to add more, check the log first for false positive rates.
PATTERNS=(
  "left as an exercise"
  "follow-up PR"
  "too many issues to address"
  "that's a separate concern"
  "follow-up task"
)

for PATTERN in "${PATTERNS[@]}"; do
  if echo "$RESPONSE" | grep -qi "$PATTERN"; then
    # Log for future eval corpus
    LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | $PATTERN | $(pwd)" >> "$LOG_DIR/anti-rationalization.log"

    [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:anti-rat] BLOCKED on pattern: $PATTERN" >&2

    echo "{\"decision\":\"block\",\"reason\":\"Rationalization detected: your response contains '${PATTERN}'. If this work is genuinely out of scope, state why explicitly. Otherwise, finish what you started before stopping.\"}"
    exit 2
  fi
done

# Guess-fix guard (SPEC-013). Backstop for the debug iron law:
# "no fix without a recorded root cause". Gated so it is silent outside a
# debug session: it fires ONLY when an active ledger under .claude/debug/
# still has an empty "## Root cause" AND the response shows a guess-fix smell.
# This keeps false positives near zero in normal coding (PHILOSOPHY: detect, don't dictate).
if [ -d ".claude/debug" ]; then
  GUESS_FIX_PATTERNS=(
    "let me just try"
    "quick fix"
    "let me try changing"
    "let me try a different"
    "that should fix"
    "should be fixed now"
  )
  # A ledger is "undiagnosed" if its "## Root cause" block has no non-blank
  # content (or the heading is absent). awk exits 0 when filled, 1 when empty.
  UNDIAGNOSED=0
  while IFS= read -r LEDGER; do
    [ -f "$LEDGER" ] || continue
    if ! awk '
      /^## Root cause/ { inblock=1; next }
      /^## / { inblock=0 }
      inblock && NF { found=1 }
      END { exit found?0:1 }
    ' "$LEDGER"; then
      UNDIAGNOSED=1
      break
    fi
  done < <(find .claude/debug -maxdepth 1 -name '*.md' 2>/dev/null)

  if [ "$UNDIAGNOSED" = "1" ]; then
    for PATTERN in "${GUESS_FIX_PATTERNS[@]}"; do
      if echo "$RESPONSE" | grep -qi "$PATTERN"; then
        LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
        mkdir -p "$LOG_DIR"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED-GUESSFIX | $PATTERN | $(pwd)" >> "$LOG_DIR/anti-rationalization.log"

        [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:anti-rat] BLOCKED guess-fix: $PATTERN" >&2

        echo "{\"decision\":\"block\",\"reason\":\"Guess-fix detected during an open debug session: a .claude/debug ledger still has an empty '## Root cause'. Find and record the root cause first (debug Phase 1). No fix without a recorded root cause.\"}"
        exit 2
      fi
    done
  fi
fi

# Phantom-implementation guard (SPEC-014). On a completion claim, block if the
# uncommitted diff's ADDED lines contain a strong "not implemented" stub marker.
# Scoped tight (completion claim + added lines + strong markers only) so bare
# TODO/FIXME and mid-work states never trip it. Source: claudekit self-review.
if echo "$RESPONSE" | grep -qiE '\b(all done|done\b|complete|completed|finished|ready for review|ready to ship|all set|implemented (it|the))' \
   && command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  # Anchor to lines that ARE a stub statement, not lines that merely mention the
  # token (so code that defines/tests these markers does not self-trigger).
  PHANTOM_RE='^\+[[:space:]]*(raise[[:space:]]+NotImplementedError|unimplemented!\(|panic\(.*not implemented|throw[[:space:]]+new[[:space:]]+Error\(.*not implemented|throw[[:space:]]+new[[:space:]]+NotImplementedException)'
  PHANTOM=$(git diff --no-color 2>/dev/null | grep -iE "$PHANTOM_RE" | head -1 || true)
  if [ -n "$PHANTOM" ]; then
    LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED-PHANTOM | $(pwd)" >> "$LOG_DIR/anti-rationalization.log"

    [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:anti-rat] BLOCKED phantom-impl" >&2

    echo "{\"decision\":\"block\",\"reason\":\"Completion claimed but the diff still adds an unimplemented stub (NotImplementedError / unimplemented!() / panic or throw 'not implemented'). Implement it for real or remove the claim before stopping.\"}"
    exit 2
  fi
fi

exit 0
