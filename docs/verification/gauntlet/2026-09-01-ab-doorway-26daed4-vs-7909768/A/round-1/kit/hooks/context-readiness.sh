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

# Board awareness (SPEC-083 / ID-033): the SessionStart injection is the entry
# surface, so it must see the board, or queued work is invisible at session
# start. Twin of lib/board/backlog.sh _rows: status = second-to-last pipe cell,
# leading keyword before space/bracket/paren (keep the two parsers in sync).
BOARD_Q=""
if [ -f "_meta/BACKLOG.md" ]; then
  BOARD_Q=$(awk -F'|' '/^\| *ID-[0-9]+ *\|/ {
    s=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", s); split(s, a, /[ \[(]/)
    if (a[1] == "queued") n++
  } END { print n+0 }' "_meta/BACKLOG.md" 2>/dev/null || echo "")
  [ -n "$BOARD_Q" ] && STATE+="board:${BOARD_Q}q "
fi

# Spec status + command suggestion
# Resolve the active spec (SPEC-005 dual-detect, reconciled to ADR-0010):
# docs/specs/ is primary (kit + downstream). Among non-SHIPPED/PARKED specs:
# exactly one -> use it; more than one -> the one whose slug matches the git
# branch; zero/multiple branch matches -> emit spec:ambiguous and pick none
# (never silently guess). See docs/specs/SPEC-005, SPEC-010.
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
      # whole-token match: a slug token must appear as a COMPLETE token in the
      # branch (split on / _ . -), so short tokens (a, db, gate) don't
      # substring-match an unrelated branch (e.g. "gate" in "gateway") and
      # silently mis-select. BTOK is space-padded so the case glob is boundaried.
      BTOK=" $(printf '%s' "$BRANCH_NAME" | tr '/_.-' '    ') "
      HIT=0
      OLDIFS=$IFS; IFS='-'
      for T in $SLUG; do
        if [ -n "$T" ]; then
          case "$BTOK" in *" $T "*) HIT=1 ;; esac
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
if [ -n "$SPEC_AMBIG" ]; then
  STATE+="spec:ambiguous(${SPEC_AMBIG}) "
  SUGGEST="multiple live specs, no branch match; disambiguate (check out a spec's branch, or ship/park the others)"
elif [ -z "$SPEC_FILE" ]; then
  # Intent-first (SPEC-083): the operator states intent; commands are named in
  # parentheses for reference. A non-empty queue routes to the board pull.
  if [ -n "$BOARD_Q" ] && [ "$BOARD_Q" -gt 0 ]; then
    SUGGEST="${BOARD_Q} queued on the board; state the task, or /kit:assign --next"
  else
    SUGGEST="no spec found; state the task (the kit routes it), or /kit:think then /kit:spec"
  fi
else
  # Read spec status
  SPEC_STATUS=$(grep -m1 '^Status:' "$SPEC_FILE" 2>/dev/null | sed 's/Status:\s*//' | tr -d '[:space:]' || echo "unknown")
  STATE+="spec:${SPEC_STATUS} "

  case "$SPEC_STATUS" in
    DRAFT)
      SUGGEST="spec is DRAFT; say 'validate it' (or /kit:spec-validate)" ;;
    APPROVED|VALIDATED)
      # Count tasks
      TOTAL=$(grep -c '^\- \[.\]' "$SPEC_FILE" 2>/dev/null || true)
      DONE=$(grep -c '^\- \[x\]' "$SPEC_FILE" 2>/dev/null || true)
      STATE+="tasks:${DONE}/${TOTAL} "
      # A live spec's cycle suggestion beats the board pull (SPEC-083:
      # mid-cycle, finishing beats starting); the board: token stays either way.
      if [ "$DONE" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        if grep -q '^## Review' "$SPEC_FILE" 2>/dev/null; then
          SUGGEST="all tasks done and reviewed; say 'ship it' (or /kit:ship)"
        else
          SUGGEST="all tasks done; say 'review it' (or /kit:review)"
        fi
      else
        SUGGEST="tasks in progress; say 'continue' (or /kit:execute, /kit:next)"
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
# Only need to know whether there are >50 source files, so prune the heavy dirs
# DURING traversal (not grep -v after, which still descends into them and cost
# ~4s cold on a big repo) and stop at 51. The `|| true` neutralizes pipefail:
# head closing the pipe early sends find a SIGPIPE (141) that set -e would abort on.
SRC_COUNT=$(find . \( -name node_modules -o -name .git -o -name .venv -o -name .cache \) -prune -o \
  \( -name "*.ts" -o -name "*.go" -o -name "*.py" -o -name "*.rs" \) -print 2>/dev/null \
  | head -51 | wc -l | tr -d ' ' || true)
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
