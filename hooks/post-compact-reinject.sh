#!/bin/bash
# post-compact-reinject.sh -- SessionStart hook (matcher compact) that re-injects the critical project rules compaction strips from context.
# post-compact-reinject.sh — SessionStart hook, matcher: compact (source=compact)
# Re-injects critical project rules after compaction strips them from context.
# CLAUDE.md gets summarized during compaction and loses precision.
# This is the surgical 10-50 line "before you ship" checklist, not the full handbook.
# Wired on SessionStart(compact): no tool is named compact, so PostToolUse never fired it.

set -euo pipefail

# Build context essentials (short, surgical, high-signal)
ESSENTIALS=""

# Project identity
PROJECT_SRC=""
if [ -f "CLAUDE.md" ]; then PROJECT_SRC="CLAUDE.md"; elif [ -f "AGENTS.md" ]; then PROJECT_SRC="AGENTS.md"; fi
if [ -n "$PROJECT_SRC" ]; then
  # Extract just the ## Project section (first paragraph)
  PROJECT=$(sed -n '/^## Project/,/^##/p' "$PROJECT_SRC" | head -5 | tail -4)
  [ -n "$PROJECT" ] && ESSENTIALS+="PROJECT: ${PROJECT}"$'\n'
fi

# Current branch and spec
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ESSENTIALS+="BRANCH: ${BRANCH}"$'\n'

# Active spec: one lookup (lib/spec/spec-active.sh): the branch's own spec, the lone open spec, or
# ambiguous. A spec with no Status header counts as open. Without the lib no spec is resolved.
SPEC=""; AMBIG=""
SPEC_ACTIVE_SH="$(dirname "${BASH_SOURCE[0]}")/../lib/spec/spec-active.sh"
if [ -r "$SPEC_ACTIVE_SH" ] && . "$SPEC_ACTIVE_SH" 2>/dev/null; then
  OUT=$(spec_active --live --branch "$(git branch --show-current 2>/dev/null || true)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" 2>/dev/null || true)
  SPEC=$(printf '%s\n' "$OUT" | awk -F'\t' '$1 != "ambiguous" && $2 != "" { print $2; exit }')
  AMBIG=$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == "ambiguous" { n = split($2, p, "/"); f = p[n]; if (match(f, /^SPEC-[0-9]+/)) f = substr(f, 1, RLENGTH); printf "%s%s", sep, f; sep = ", " }')
  SPEC="${SPEC#"$(pwd -P)"/}"
fi
[ -z "$AMBIG" ] || ESSENTIALS+="SPEC: ambiguous (${AMBIG}); state which spec before implementing"$'\n'
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
- If unsure about architecture, check docs/reference/architecture.md and docs/decisions/.
"

# SessionStart(compact) output: hookSpecificOutput.additionalContext, built by jq (safe for quotes, backslashes,
# newlines). jq, not python3: without python3 the rules above were never re-injected.
jq -n --arg ctx "[dwarves-kit post-compaction] Context was compacted. Critical rules re-injected:"$'\n'"$ESSENTIALS" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
