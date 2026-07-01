#!/bin/bash
# slop-cleaner.sh — Stop hook
# After long sessions, Claude produces increasingly bloated code.
# This hook checks recently modified source files for bloat signals
# and nudges (does NOT block) with a context message.
# Source: oh-my-claudecode code-simplifier (adapted: nudge, not auto-fix)
#
# Exit 0 always. This is a suggestion, not a gate.
# anti-rationalization blocks (exit 2); this one suggests (exit 0 + additionalContext).

set -euo pipefail
INPUT=$(cat)

# Guard: prevent infinite Stop hook loop
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:slop-cleaner] checking recently modified files" >&2
fi

# Session-start marker. Path is overridable for tests; prod default unchanged.
MARKER="${DWARVES_KIT_SESSION_MARKER:-/tmp/.dwarves-kit-session-start}"

# If no session marker exists, create one and skip this run
# (first Stop of the session -- no baseline to compare against)
if [ ! -f "$MARKER" ]; then
  touch "$MARKER"
  exit 0
fi

# Bounded blast radius: only scan inside a git work tree. Outside a repo (a
# session at $HOME or a multi-repo workspace root) "find ." would walk an
# unbounded tree, and there is nothing meaningful to bloat-check anyway.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Find source files modified since session start.
# Prune heavy dirs DURING traversal (not via post-filter grep): from a large
# tree (monorepo, Obsidian vault, nested repos) the old "find . | grep -v"
# walked node_modules/.git/vector-dbs first, pegging CPU on every Stop event.
RECENT_FILES=$(find . \
  \( -type d \( -name node_modules -o -name vendor -o -name dist -o -name .git \
       -o -name target -o -name build -o -name .venv -o -name __pycache__ \
       -o -name .obsidian -o -name .claude -o -name '.smtcmp_*' \) -prune \) -o \
  \( -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
       -o -name "*.go" -o -name "*.py" -o -name "*.rs" \) \
     -newer "$MARKER" -print \) 2>/dev/null \
  | head -20 || true)

[ -z "$RECENT_FILES" ] && exit 0

BLOAT_FILES=""

while IFS= read -r FILE; do
  [ ! -f "$FILE" ] && continue
  ISSUES=""

  # Check 1: Functions over 50 lines (strong bloat signal)
  # Rough heuristic: count lines between function-like patterns
  LONG_FUNCS=$(awk '
    /^(export )?(async )?(function |const .* = |def |func |fn )/ { start=NR }
    start && /^}$|^})|^end$/ {
      if (NR - start > 50) count++
      start=0
    }
    END { print count+0 }
  ' "$FILE" 2>/dev/null)
  [ "$LONG_FUNCS" -gt 0 ] && ISSUES+="$LONG_FUNCS long functions (>50 lines), "

  # Check 2: Deep nesting (>4 levels of indentation)
  DEEP_NESTING=$(grep -cE '^\s{16,}\S' "$FILE" 2>/dev/null || echo 0)
  [ "$DEEP_NESTING" -gt 3 ] && ISSUES+="deep nesting ($DEEP_NESTING lines >4 levels), "

  # Check 3: File over 300 lines (size bloat)
  LINE_COUNT=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')
  [ "$LINE_COUNT" -gt 300 ] && ISSUES+="$LINE_COUNT lines (consider splitting), "

  # Check 4: Duplicate code blocks (3+ consecutive identical lines appearing twice)
  # Light heuristic -- just check for exact duplicate chunks
  DUPES=$(awk '
    { lines[NR] = $0 }
    END {
      for (i=1; i<=NR-2; i++) {
        chunk = lines[i] "\n" lines[i+1] "\n" lines[i+2]
        if (seen[chunk]++) dupes++
      }
      print dupes+0
    }
  ' "$FILE" 2>/dev/null)
  [ "$DUPES" -gt 0 ] && ISSUES+="$DUPES duplicate code blocks, "

  if [ -n "$ISSUES" ]; then
    BLOAT_FILES+="  $FILE: ${ISSUES%, }\n"
  fi
done <<< "$RECENT_FILES"

if [ -n "$BLOAT_FILES" ]; then
  # Log for eval corpus
  LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$LOG_DIR"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | SLOP | $(echo -e "$BLOAT_FILES" | wc -l | tr -d ' ') files | $(pwd)" >> "$LOG_DIR/slop-cleaner.log"

  [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo -e "[dwarves-kit:slop-cleaner] DETECTED:\n$BLOAT_FILES" >&2

  # Nudge via additionalContext (does NOT block)
  ESCAPED=$(echo -e "$BLOAT_FILES" | tr '\n' ' ' | sed 's/"/\\"/g')
  echo "{\"additionalContext\": \"[dwarves-kit:slop-check] These recently modified files may have unnecessary complexity: ${ESCAPED}Consider simplifying before continuing.\"}"
fi

exit 0
