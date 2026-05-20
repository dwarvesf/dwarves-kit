#!/bin/bash
# context-readiness.sh — SessionStart hook
# Checks project readiness and injects context into Claude's awareness.
# stdout from SessionStart becomes Claude's context.
# Source: Novel (dwarves-kit). Bridges context tools into a single readiness check.
#
# v1.1: Reduced context noise. Only outputs WARNINGS and critical state.
# v1.2: Added command suggestions based on project state ("detect, don't dictate").
#       Source: CCGS /start router pattern adapted to SessionStart hook.

set -euo pipefail

WARNINGS=""
STATE=""
SUGGEST=""

# Debug logging
if [ "${DWARVES_KIT_DEBUG:-0}" = "1" ]; then
  echo "[dwarves-kit:context] running readiness check in $(pwd)" >&2
fi

# Only warn about missing essentials, don't confirm present ones
[ ! -f "CLAUDE.md" ] && WARNINGS+="No CLAUDE.md in project root. "

# Spec status + command suggestion
# Resolve the active spec: docs/specs/SPEC-NNN (highest non-SHIPPED/PARKED) first,
# then the legacy .planning/ convention (deprecated; removed next minor). The
# highest-NNN heuristic is an interim selector; SPEC-005 dual-detect replaces it
# with branch-based selection. See docs/specs/SPEC-010.
SPEC_FILE=""
for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do
  grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" || { SPEC_FILE="$F"; break; }
done
if [ -z "$SPEC_FILE" ] && [ -d ".planning" ]; then
  for F in .planning/SPEC.md .planning/ROADMAP.md .planning/REQUIREMENTS.md; do
    [ -f "$F" ] && SPEC_FILE="$F" && break
  done
  [ -n "$SPEC_FILE" ] && WARNINGS+=".planning/ is deprecated; move specs to docs/specs/SPEC-NNN. "
fi

if [ -z "$SPEC_FILE" ]; then
  SUGGEST="no spec found, consider /user:think then /user:spec"
else
  # Read spec status
  SPEC_STATUS=$(grep -m1 '^Status:' "$SPEC_FILE" 2>/dev/null | sed 's/Status:\s*//' | tr -d '[:space:]' || echo "unknown")
  STATE+="spec:${SPEC_STATUS} "

  case "$SPEC_STATUS" in
    DRAFT)
      SUGGEST="spec is DRAFT, consider /user:spec-validate" ;;
    APPROVED|VALIDATED)
      # Count tasks
      TOTAL=$(grep -c '^\- \[.\]' "$SPEC_FILE" 2>/dev/null || echo 0)
      DONE=$(grep -c '^\- \[x\]' "$SPEC_FILE" 2>/dev/null || echo 0)
      STATE+="tasks:${DONE}/${TOTAL} "
      if [ "$DONE" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        if [ -f "REVIEW.md" ]; then
          SUGGEST="all tasks done and reviewed, consider /user:ship"
        else
          SUGGEST="all tasks done, consider /user:review"
        fi
      else
        SUGGEST="tasks in progress, /user:execute or /user:next"
      fi
      ;;
  esac
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

# L3.5 context: codebase-memory-mcp integration
SRC_COUNT=$(find . -name "*.ts" -o -name "*.go" -o -name "*.py" -o -name "*.rs" 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ')
if [ "$SRC_COUNT" -gt 50 ]; then
  # Check for codebase-memory-mcp index (v2 uses ~/.cache, older uses local dir)
  CBM_FOUND=false
  CBM_DB="$HOME/.cache/codebase-memory-mcp"
  [ -d ".codebase-memory" ] && CBM_FOUND=true
  [ -f ".codebase-memory.db" ] && CBM_FOUND=true
  [ -d "$CBM_DB" ] && CBM_FOUND=true

  if [ "$CBM_FOUND" = true ]; then
    STATE+="cbm:indexed "
  else
    WARNINGS+="50+ source files, no codebase index. Install codebase-memory-mcp for 120x fewer orientation tokens. "
  fi
fi

# Build output
OUTPUT=""
[ -n "$STATE" ] && OUTPUT+="${STATE}"
[ -n "$SUGGEST" ] && OUTPUT+="| next: ${SUGGEST} "
[ -n "$WARNINGS" ] && OUTPUT+="| warn: ${WARNINGS}"

if [ -n "$OUTPUT" ]; then
  echo "{\"additionalContext\": \"[dwarves-kit] ${OUTPUT}\"}"
else
  echo "{}"
fi
