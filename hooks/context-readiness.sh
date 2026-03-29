#!/bin/bash
# context-readiness.sh — SessionStart hook
# Checks project readiness and injects context into Claude's awareness.
# stdout from SessionStart becomes Claude's context.
# Source: Novel (dwarves-kit). Bridges context tools into a single readiness check.
#
# v1.1: Reduced context noise. Only outputs WARNINGS and critical state.
# Removed verbose "X found" confirmations that consumed context budget
# without adding decision-relevant information.

set -euo pipefail

WARNINGS=""
STATE=""

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:context] running readiness check in $(pwd)" >&2
fi

# Only warn about missing essentials, don't confirm present ones
[ ! -f "CLAUDE.md" ] && WARNINGS+="No CLAUDE.md in project root. "

# Spec status (only warn if missing when .planning/ exists)
if [ -d ".planning" ]; then
  if ! find .planning -maxdepth 2 \( -name "SPEC.md" -o -name "ROADMAP.md" -o -name "REQUIREMENTS.md" \) | grep -q .; then
    WARNINGS+=".planning/ exists but no SPEC.md found. "
  fi
fi

# Git info (always useful, compact)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  STATE+="branch:${BRANCH} "
  DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$DIRTY" -gt 0 ] && STATE+="dirty:${DIRTY} "
fi

# Only warn about missing test infrastructure, don't confirm it
if [ -f "package.json" ]; then
  if ! grep -q '"test"' package.json 2>/dev/null; then
    WARNINGS+="No test script in package.json. "
  fi
fi

# L3.5 context warnings (only when relevant)
if [ $(find . -name "*.ts" -o -name "*.go" -o -name "*.py" -o -name "*.rs" 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ') -gt 50 ]; then
  if [ ! -d ".codebase-memory" ] && [ ! -f ".codebase-memory.db" ]; then
    WARNINGS+="50+ source files, no codebase index. Consider codebase-memory-mcp. "
  fi
fi

# Only output if there's something worth saying
if [ -n "$WARNINGS" ] || [ -n "$STATE" ]; then
  echo "{\"additionalContext\": \"[dwarves-kit] ${STATE}${WARNINGS}\"}"
else
  # Nothing to report = healthy project, don't consume context
  echo "{}"
fi
