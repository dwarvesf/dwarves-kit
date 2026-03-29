#!/bin/bash
# context-readiness.sh — SessionStart hook
# Checks project readiness and injects context into Claude's awareness.
# stdout from SessionStart becomes Claude's context.
# Source: Novel (dwarves-kit). Bridges context tools into a single readiness check.

set -euo pipefail

CONTEXT=""
WARNINGS=""

# Check CLAUDE.md
if [ -f "CLAUDE.md" ]; then
  CONTEXT+="CLAUDE.md found. "
else
  WARNINGS+="[!] No CLAUDE.md in project root. "
fi

# Check for spec/planning directory
if [ -d ".planning" ]; then
  SPEC_COUNT=$(find .planning -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  CONTEXT+="Spec directory found (.planning/, ${SPEC_COUNT} files). "
  
  # Check for roadmap or spec
  if find .planning -maxdepth 2 -name "SPEC.md" -o -name "ROADMAP.md" -o -name "REQUIREMENTS.md" | grep -q .; then
    CONTEXT+="Approved spec present. "
  else
    WARNINGS+="[!] .planning/ exists but no SPEC.md or ROADMAP.md found. "
  fi
elif [ -d ".gsd" ]; then
  CONTEXT+="GSD project detected (.gsd/). "
fi

# Git info
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  CONTEXT+="Git branch: ${BRANCH}. "
  
  # Uncommitted changes
  DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$DIRTY" -gt 0 ] && CONTEXT+="Uncommitted changes: ${DIRTY} files. "
fi

# Check for test infrastructure
if [ -f "package.json" ]; then
  if grep -q '"test"' package.json 2>/dev/null; then
    CONTEXT+="Test script found in package.json. "
  else
    WARNINGS+="[!] No test script in package.json. "
  fi
elif [ -f "go.mod" ]; then
  CONTEXT+="Go module detected. "
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  CONTEXT+="Python project detected. "
fi

# --- L3.5 Context Layer Checks ---

# Check codebase-memory-mcp index
if [ -d ".codebase-memory" ] || [ -f ".codebase-memory.db" ]; then
  CONTEXT+="Codebase index found (codebase-memory-mcp). "
elif [ $(find . -name "*.ts" -o -name "*.go" -o -name "*.py" -o -name "*.rs" 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ') -gt 50 ]; then
  WARNINGS+="[!] 50+ source files but no codebase index. Consider running codebase-memory-mcp to index for faster context loading. "
fi

# Check Context Hub availability
if command -v chub >/dev/null 2>&1; then
  CONTEXT+="Context Hub (chub) available. "
else
  # Only warn if project uses external APIs (has fetch/axios/http in deps)
  if [ -f "package.json" ] && grep -qE '"(axios|node-fetch|got|ky|@anthropic|openai|stripe)"' package.json 2>/dev/null; then
    WARNINGS+="[!] Project uses external APIs but Context Hub (chub) not installed. Run: npm install -g @aisuite/chub "
  fi
fi

# Check MCP config
if [ -f ".mcp.json" ]; then
  MCP_COUNT=$(jq 'keys | length' .mcp.json 2>/dev/null || echo "0")
  CONTEXT+="MCP config found (.mcp.json, ${MCP_COUNT} servers). "
fi

# Check for retro backlog (nudge if last retro was long ago)
LAST_RETRO=$(find .planning -name "RETRO-*.md" 2>/dev/null | sort | tail -1)
if [ -n "$LAST_RETRO" ]; then
  RETRO_DATE=$(basename "$LAST_RETRO" | sed 's/RETRO-//;s/\.md//')
  CONTEXT+="Last retro: ${RETRO_DATE}. "
fi

# Output as additionalContext JSON
echo "{\"additionalContext\": \"[dwarves-kit] ${CONTEXT}${WARNINGS}\"}"
