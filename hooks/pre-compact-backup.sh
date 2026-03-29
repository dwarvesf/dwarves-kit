#!/bin/bash
# pre-compact-backup.sh — PreCompact hook
# Saves a structured snapshot of the current session before auto-compaction.
# Source: claudefa.st context-recovery-hook pattern (simplified for dwarves-kit)
# Compaction summarizes conversation and loses precision. This preserves it.

set -euo pipefail

BACKUP_DIR=".claude/backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
SESSION_ID=$(echo "$(cat)" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
BACKUP_FILE="${BACKUP_DIR}/backup-${TIMESTAMP}.md"

# Count existing backups for numbering
COUNT=$(find "$BACKUP_DIR" -name "backup-*.md" 2>/dev/null | wc -l | tr -d ' ')
NEXT=$((COUNT + 1))
BACKUP_FILE="${BACKUP_DIR}/${NEXT}-backup-${TIMESTAMP}.md"

cat > "$BACKUP_FILE" << BACKUP
# Session Backup #${NEXT}
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Trigger: pre-compaction
Session: ${SESSION_ID}

## Current state

### Git
$(git branch --show-current 2>/dev/null || echo "not a git repo")
$(git log --oneline -5 2>/dev/null || echo "no commits")

### Uncommitted changes
$(git diff --stat 2>/dev/null || echo "none")

### Active spec
$(if [ -d ".planning" ]; then
  SPEC=$(find .planning -name "SPEC.md" -o -name "ROADMAP.md" | head -1)
  if [ -n "$SPEC" ]; then
    echo "Spec: $SPEC"
    # Extract just the task breakdown section
    sed -n '/## Task Breakdown/,/## /p' "$SPEC" 2>/dev/null | head -30 || echo "(could not extract tasks)"
  else
    echo "No spec found in .planning/"
  fi
else
  echo "No .planning/ directory"
fi)

### Recent file changes (last 10 modified)
$(find . -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.go" -o -name "*.py" -o -name "*.rs" 2>/dev/null \
  | grep -v node_modules | grep -v vendor | grep -v dist \
  | xargs ls -t 2>/dev/null | head -10 || echo "none found")

## Context essentials (re-inject after compaction)

Read CLAUDE.md for full project rules. Key reminders:
- Check .planning/SPEC.md before implementing anything
- Do not push to main/master directly
- Write tests before or alongside implementation
- No phantom features, no premature abstraction
- Finish the job: handle edge cases, clean up what you touched
BACKUP

echo "Backup saved: $BACKUP_FILE" >&2
exit 0
