#!/bin/bash
# post-compact-reinject.sh — PostToolUse hook, matcher: compact
# Re-injects critical project rules after compaction strips them from context.
# CLAUDE.md gets summarized during compaction and loses precision.
# This is the surgical 10-50 line "before you ship" checklist, not the full handbook.
# Source: Nick Porter's PostToolUse(compact) pattern (adapted for dwarves-kit)

set -euo pipefail

# Build context essentials (short, surgical, high-signal)
ESSENTIALS=""

# Project identity
if [ -f "CLAUDE.md" ]; then
  # Extract just the ## Project section (first paragraph)
  PROJECT=$(sed -n '/^## Project/,/^##/p' CLAUDE.md | head -5 | tail -4)
  [ -n "$PROJECT" ] && ESSENTIALS+="PROJECT: ${PROJECT}\n"
fi

# Current branch and spec
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ESSENTIALS+="BRANCH: ${BRANCH}\n"

# Active spec: docs/specs/SPEC-NNN (highest non-SHIPPED/PARKED).
SPEC=""
for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do
  grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" || { SPEC="$F"; break; }
done
[ -n "$SPEC" ] && ESSENTIALS+="SPEC: ${SPEC} (read before implementing)\n"

# Latest backup location
LATEST_BACKUP=$(find .claude/backups -name "*.md" 2>/dev/null | sort | tail -1)
[ -n "$LATEST_BACKUP" ] && ESSENTIALS+="BACKUP: ${LATEST_BACKUP} (full pre-compaction state)\n"

# Hard rules (these are the ones compaction drops)
ESSENTIALS+="
RULES (compaction may have dropped these):
- Do NOT push to main/master. Use feature branches.
- Do NOT use rm -rf. Use trash.
- Read the active spec (docs/specs/SPEC-NNN) before implementing any task.
- Write tests alongside implementation.
- No phantom features. No premature abstraction.
- Finish what you started before declaring done.
- If unsure about architecture, check docs/architecture.md and docs/decisions/.
"

# Output as additionalContext (injected into Claude's awareness)
printf '{"additionalContext": "[dwarves-kit post-compaction] Context was compacted. Critical rules re-injected:\\n%s"}' "$(echo -e "$ESSENTIALS" | tr '\n' ' ' | sed 's/"/\\"/g')"
