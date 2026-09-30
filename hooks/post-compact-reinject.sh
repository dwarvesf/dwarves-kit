#!/bin/bash
# post-compact-reinject.sh — SessionStart hook, matcher: compact (source=compact)
# Re-injects critical project rules after compaction strips them from context.
# CLAUDE.md gets summarized during compaction and loses precision.
# This is the surgical 10-50 line "before you ship" checklist, not the full handbook.
# Wired on SessionStart(compact): no tool is named compact, so PostToolUse never fired it.

set -euo pipefail

# Build context essentials (short, surgical, high-signal)
ESSENTIALS=""

# Project identity
if [ -f "CLAUDE.md" ]; then
  # Extract just the ## Project section (first paragraph)
  PROJECT=$(sed -n '/^## Project/,/^##/p' CLAUDE.md | head -5 | tail -4)
  [ -n "$PROJECT" ] && ESSENTIALS+="PROJECT: ${PROJECT}"$'\n'
fi

# Current branch and spec
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ESSENTIALS+="BRANCH: ${BRANCH}"$'\n'

# Active spec: docs/specs/SPEC-NNN (highest non-SHIPPED/PARKED).
SPEC=""
for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do
  grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" || { SPEC="$F"; break; }
done
if [ -n "$SPEC" ]; then
  ESSENTIALS+="SPEC: ${SPEC} (read before implementing)"$'\n'
  # Refocus: first paragraph under ## Problem (else ## Intent, ## Goal), one line, 400 chars.
  INTENT=$(python3 - "$SPEC" <<'PY' 2>/dev/null || true
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for head in ("Problem", "Intent", "Goal"):
    m = re.search(r"^##[ \t]+" + head + r"[ \t]*$(.*?)(?=^#{1,2}[ \t]|\Z)", text, re.M | re.S)
    if not m:
        continue
    para = re.search(r"\S.*?(?=\n[ \t]*\n|\Z)", m.group(1), re.S)
    if para:
        print(" ".join(para.group(0).split())[:400])
        break
PY
)
  [ -n "$INTENT" ] && ESSENTIALS+="INTENT: ${INTENT}"$'\n'
fi

# Latest backup location
LATEST_BACKUP=$(find .claude/backups -name "*.md" 2>/dev/null | sort | tail -1 || true)
[ -n "$LATEST_BACKUP" ] && ESSENTIALS+="BACKUP: ${LATEST_BACKUP} (full pre-compaction state)"$'\n'

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

# SessionStart(compact) output: hookSpecificOutput.additionalContext, built by json.dumps (safe for quotes, backslashes, newlines).
ESSENTIALS="$ESSENTIALS" python3 -c '
import json, os
ctx = "[dwarves-kit post-compaction] Context was compacted. Critical rules re-injected:\n" + os.environ["ESSENTIALS"]
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
'
