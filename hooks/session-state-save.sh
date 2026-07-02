#!/bin/bash
# session-state-save.sh — Stop hook (runs alongside anti-rationalization + slop-cleaner)
# Persists session state to disk on every Stop and SubagentStop event.
# Catches session crashes that PreCompact backup misses.
# Source: ClaudeKit session-state.cjs pattern (adapted: bash, no Node.js)
#
# Writes to .claude/session-state/last-state.md
# Rotates old states (keeps last 10).
# Fail-open: errors are logged but never block the session.

set -euo pipefail

INPUT=$(cat)

# Guard: prevent infinite Stop hook loop
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:session-state] saving state on Stop" >&2
fi

STATE_DIR=".claude/session-state"
STATE_FILE="$STATE_DIR/last-state.md"
ARCHIVE_DIR="$STATE_DIR/archive"

# Fail-open: wrap everything in a trap
trap 'exit 0' ERR

mkdir -p "$STATE_DIR" "$ARCHIVE_DIR"

# Change-gated debounce (cc-hyg-04): skip the rewrite+rotate when nothing material
# changed since the last save. The existing last-state.md is still accurate for crash
# recovery, so skipping is safe, and it cuts the every-Stop tax (measured ~38 min/mo)
# with no staleness risk. Fingerprint = branch | uncommitted-count | HEAD sha.
FP_FILE="$STATE_DIR/.last-fingerprint"
# Fingerprint the CONTENT of the working state, not a dirty-file count: hash the
# tracked diff (`git diff HEAD`) plus the untracked file list. A count would miss
# further edits to an already-dirty file (same count -> stale crash-recovery
# snapshot for the rest of a single-file editing streak). Exclude the hook's own
# untracked .claude/session-state/ output, else the fingerprint never stabilizes.
FP=$(printf '%s|%s|%s' \
  "$(git branch --show-current 2>/dev/null || echo -)" \
  "$( { git diff HEAD 2>/dev/null; git status --porcelain --untracked-files=all 2>/dev/null | { grep -vF '.claude/session-state/' || true; }; } | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | awk '{print $1}')" \
  "$(git rev-parse HEAD 2>/dev/null || echo -)")
if [ -f "$STATE_FILE" ] && [ -f "$FP_FILE" ] && [ "$FP" = "$(cat "$FP_FILE" 2>/dev/null)" ]; then
  [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:session-state] unchanged since last save, skipping" >&2
  exit 0
fi

# Rotate: archive current state before overwriting
if [ -f "$STATE_FILE" ]; then
  ARCHIVE_TS=$(date +"%Y%m%d-%H%M%S")
  mv "$STATE_FILE" "$ARCHIVE_DIR/state-${ARCHIVE_TS}.md" 2>/dev/null || true

  # Keep only last 10 archives
  ARCHIVE_COUNT=$(find "$ARCHIVE_DIR" -name "state-*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$ARCHIVE_COUNT" -gt 10 ]; then
    find "$ARCHIVE_DIR" -name "state-*.md" | sort | head -n $((ARCHIVE_COUNT - 10)) | xargs rm -f 2>/dev/null || true
  fi
fi

# Gather state
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
LAST_COMMITS=$(git log --oneline -5 2>/dev/null || echo "no commits")

# Spec state
SPEC_STATUS="none"
TASK_PROGRESS=""
# Active spec: docs/specs/SPEC-NNN (highest non-SHIPPED/PARKED).
SPEC_FILE=""
for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do
  grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" || { SPEC_FILE="$F"; break; }
done
if [ -n "$SPEC_FILE" ]; then
  SPEC_STATUS=$(grep -m1 '^Status:' "$SPEC_FILE" 2>/dev/null | sed 's/Status:\s*//' | tr -d '[:space:]' || echo "unknown")
  TOTAL=$(grep -c '^\- \[.\]' "$SPEC_FILE" 2>/dev/null || true)
  DONE=$(grep -c '^\- \[x\]' "$SPEC_FILE" 2>/dev/null || true)
  TASK_PROGRESS="${DONE}/${TOTAL} tasks complete"
fi

# Recently modified source files.
# Marker path overridable for tests; prod default unchanged.
MARKER="${DWARVES_KIT_SESSION_MARKER:-/tmp/.dwarves-kit-session-start}"
# Only scan inside a git work tree (bounded blast radius, see slop-cleaner.sh).
# Outside a repo there is nothing repo-meaningful to record; "find ." there
# would walk an unbounded tree. The rest of the state still gets written.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Prune heavy dirs during traversal (see slop-cleaner.sh rationale).
  RECENT_FILES=$(find . \
    \( -type d \( -name node_modules -o -name vendor -o -name dist -o -name .git \
         -o -name target -o -name build -o -name .venv -o -name __pycache__ \
         -o -name .obsidian -o -name .claude -o -name '.smtcmp_*' \) -prune \) -o \
    \( -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" \
         -o -name "*.go" -o -name "*.py" -o -name "*.rs" \) \
       -newer "$MARKER" -print \) 2>/dev/null \
    | head -10 || echo "none")
else
  RECENT_FILES="none"
fi

# Write state
cat > "$STATE_FILE" << STATE
# Session state
Saved: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Branch: ${BRANCH}
Uncommitted: ${DIRTY} files
Spec: ${SPEC_STATUS}
Progress: ${TASK_PROGRESS:-no spec}

## Last 5 commits
${LAST_COMMITS}

## Files modified this session
${RECENT_FILES}

## Resume instructions
Read CLAUDE.md and the active spec (docs/specs/SPEC-NNN) for full context.
Check git status for uncommitted work.
Run 'start' to detect what to do next.
STATE

# Record the fingerprint so the next unchanged Stop can debounce.
printf '%s' "$FP" > "$FP_FILE" 2>/dev/null || true

[ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && echo "[dwarves-kit:session-state] state saved to $STATE_FILE" >&2

exit 0
