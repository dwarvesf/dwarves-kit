#!/bin/bash
# context-readiness.sh -- SessionStart hook that checks project readiness and injects spec, board state and the next step into context.
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
# An adopted repo with no CLAUDE.md (the adopt.agents_only layout) keeps its instructions in
# AGENTS.md, which Claude Code v2.1.277+ reads directly. A hook never reads the kit config
# (the standing lint), so the kit's own marker or pointer in AGENTS.md is the signal; a stray
# AGENTS.md with neither still warns.
if [ ! -f "CLAUDE.md" ]; then
  if [ -f "AGENTS.md" ] && { grep -qxF '<!-- kit:adopt -->' AGENTS.md 2>/dev/null \
       || head -n 1 AGENTS.md 2>/dev/null | grep -q '^<!-- kit:agents-pointer'; }; then :
  else WARNINGS+="No CLAUDE.md in project root. "; fi
fi

# Board awareness: the SessionStart injection is the entry
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
# Resolve the active spec with the one shared lookup (lib/spec/spec-active.sh, --live): docs/specs/
# at the repo root, open specs only (lib/spec/states.tsv, class not terminal; a spec with no Status
# header is open). The branch's own spec, else the lone open spec, else the open spec whose slug
# tokens appear in the branch; no single answer -> spec:ambiguous and pick none (never silently
# guess). One helper pass, no tree walk: SessionStart blocks on this. Without the lib no spec is
# resolved.
SPEC_FILE=""
SPEC_AMBIG=""
SPEC_STATUS_SH="${BASH_SOURCE[0]%/*}/../lib/spec/spec-status.sh"
SPEC_ACTIVE_SH="${BASH_SOURCE[0]%/*}/../lib/spec/spec-active.sh"
if [ -r "$SPEC_ACTIVE_SH" ] && . "$SPEC_ACTIVE_SH" 2>/dev/null; then
  SPEC_OUT=$(spec_active --live --branch "$(git branch --show-current 2>/dev/null || true)" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" 2>/dev/null || true)
  SPEC_FILE=$(printf '%s\n' "$SPEC_OUT" | awk -F'\t' '$1 != "ambiguous" && $2 != "" { print $2; exit }')
  SPEC_AMBIG=$(printf '%s\n' "$SPEC_OUT" | awk -F'\t' '$1 == "ambiguous" { n = split($2, p, "/"); f = p[n]; if (match(f, /^SPEC-[0-9]+/)) f = substr(f, 1, RLENGTH); printf "%s%s", sep, f; sep = "," }')
fi
if [ -n "$SPEC_AMBIG" ]; then
  STATE+="spec:ambiguous(${SPEC_AMBIG}) "
  SUGGEST="multiple live specs, no branch match; disambiguate (check out a spec's branch, or ship/park the others)"
elif [ -z "$SPEC_FILE" ]; then
  # Intent-first: the operator states intent; commands are named in
  # parentheses for reference. A non-empty queue routes to the board pull.
  if [ -n "$BOARD_Q" ] && [ "$BOARD_Q" -gt 0 ]; then
    SUGGEST="${BOARD_Q} queued on the board; state the task, or /kit:assign --next"
  else
    SUGGEST="no spec found; state the task (the kit routes it), or /kit:think then /kit:spec"
  fi
else
  # Read spec status
  SPEC_STATUS=$(bash "$SPEC_STATUS_SH" get "$SPEC_FILE" 2>/dev/null || echo "UNKNOWN")
  STATE+="spec:${SPEC_STATUS} "

  case "$SPEC_STATUS" in
    DRAFT)
      SUGGEST="spec is DRAFT; say 'validate it' (or /kit:spec-validate)" ;;
    APPROVED|VALIDATED)  # spec-state-ok: the per-state suggestion, not a vocabulary copy
      # Count tasks
      TOTAL=$(grep -c '^\- \[.\]' "$SPEC_FILE" 2>/dev/null || true)
      DONE=$(grep -c '^\- \[x\]' "$SPEC_FILE" 2>/dev/null || true)
      STATE+="tasks:${DONE}/${TOTAL} "
      # A live spec's cycle suggestion beats the board pull (mid-cycle, finishing
      # beats starting); the board: token stays either way.
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
