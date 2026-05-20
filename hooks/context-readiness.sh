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
# Resolve the active spec (SPEC-005 dual-detect, reconciled to ADR-0010):
# docs/specs/ is primary (kit + downstream). Among non-SHIPPED/PARKED specs:
# exactly one -> use it; more than one -> the one whose slug matches the git
# branch; zero/multiple branch matches -> emit spec:ambiguous and pick none
# (never silently guess). Legacy .planning/ is a bounded deprecation fallback
# (removed next minor). See docs/specs/SPEC-005, SPEC-010.
SPEC_FILE=""
SPEC_AMBIG=""
CANDIDATES=$(
  for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort || true); do
    grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' "$F" && continue
    grep -qiE '^Status:' "$F" || continue   # skip files with no parseable Status
    printf '%s\n' "$F"
  done
)
N=$(printf '%s\n' "$CANDIDATES" | grep -c . || true)
if [ "$N" -eq 1 ]; then
  SPEC_FILE="$CANDIDATES"
elif [ "$N" -gt 1 ]; then
  # Disambiguate by branch: a spec whose slug tokens appear in the branch name.
  BRANCH_NAME=$(git branch --show-current 2>/dev/null || true)
  MATCHED=""
  if [ -n "$BRANCH_NAME" ]; then
    while IFS= read -r F; do
      [ -z "$F" ] && continue
      SLUG=$(basename "$F" .md | sed -E 's/^SPEC-[0-9]+-//')
      HIT=0
      OLDIFS=$IFS; IFS='-'
      for T in $SLUG; do
        if [ -n "$T" ]; then
          case "$BRANCH_NAME" in *"$T"*) HIT=1 ;; esac
        fi
      done
      IFS=$OLDIFS
      if [ "$HIT" -eq 1 ]; then MATCHED="${MATCHED}${F}"$'\n'; fi
    done <<< "$CANDIDATES"
  fi
  MN=$(printf '%s\n' "$MATCHED" | grep -c . || true)
  if [ "$MN" -eq 1 ]; then
    SPEC_FILE=$(printf '%s\n' "$MATCHED" | grep -m1 .)
  else
    SPEC_AMBIG=$(printf '%s\n' "$CANDIDATES" | sed -E 's#.*(SPEC-[0-9]+)-.*#\1#' | paste -sd, -)
  fi
fi
if [ -z "$SPEC_FILE" ] && [ -z "$SPEC_AMBIG" ] && [ -d ".planning" ]; then
  for F in .planning/SPEC.md .planning/ROADMAP.md .planning/REQUIREMENTS.md; do
    [ -f "$F" ] && SPEC_FILE="$F" && break
  done
  [ -n "$SPEC_FILE" ] && WARNINGS+=".planning/ is deprecated; move specs to docs/specs/SPEC-NNN. "
fi

if [ -n "$SPEC_AMBIG" ]; then
  STATE+="spec:ambiguous(${SPEC_AMBIG}) "
  SUGGEST="multiple live specs, no branch match; disambiguate (check out a spec's branch, or ship/park the others)"
elif [ -z "$SPEC_FILE" ]; then
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
      TOTAL=$(grep -c '^\- \[.\]' "$SPEC_FILE" 2>/dev/null || true)
      DONE=$(grep -c '^\- \[x\]' "$SPEC_FILE" 2>/dev/null || true)
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
SRC_COUNT=$(find . -name "*.ts" -o -name "*.go" -o -name "*.py" -o -name "*.rs" 2>/dev/null | { grep -v node_modules || true; } | wc -l | tr -d ' ')
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
