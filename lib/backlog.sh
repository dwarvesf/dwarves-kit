#!/usr/bin/env bash
# backlog.sh -- the Active queue as a kanban board (SPEC-055, PHILOSOPHY §6 N2).
#
# The BACKLOG stays a markdown file (one source of truth; no parallel database). This
# helper makes its Status column MECHANICAL: render the board, pick the next queued
# item, flip a row's state, so a pull (`/kit:assign --next`) is scriptable and testable
# instead of a hand-edit. Status vocabulary is SPEC-005's, plus `claimed` (a pulled
# item between `queued` and `speccing`; the cross-session claim itself lives in
# lib/goal-registry.sh, this only records the board state).
#
# Rows are `| ID-NNN | ... | <status...> |` in the Active queue table; the status cell
# may carry prose after the keyword (e.g. "queued [re-eval ...]"); only the LEADING
# keyword is the state. Section-header rows (no ID-NNN) are ignored.
#
# Usage:
#   backlog.sh board               -> kanban columns (state -> ID + title), exit 0
#   backlog.sh next                -> the first queued row's ID (file order = priority), exit 1 if none
#   backlog.sh set <ID-NNN> <state> [note]  -> flip the row's leading status keyword
#   backlog.sh states              -> the legal state names
#
# BACKLOG_FILE overrides the file path (tests point it at a fixture copy).

set -euo pipefail

BACKLOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_FILE="${BACKLOG_FILE:-$BACKLOG_DIR/../_meta/BACKLOG.md}"

STATES="queued claimed speccing validated executing shipped parked dropped"

_rows() {  # emit: ID<TAB>title<TAB>leading-status
  awk -F'|' '
    /^\| *ID-[0-9]+ *\|/ {
      id=$2;    gsub(/^[ \t]+|[ \t]+$/, "", id)
      title=$3; gsub(/^[ \t]+|[ \t]+$/, "", title); gsub(/\*\*/, "", title)
      status=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", status)
      split(status, a, /[ \[(]/); lead=a[1]
      if (length(title) > 72) title = substr(title, 1, 69) "..."
      printf "%s\t%s\t%s\n", id, title, lead
    }' "$BACKLOG_FILE"
}

board() {
  local state found any=0
  for state in $STATES; do
    found="$(_rows | awk -F'\t' -v s="$state" '$3 == s { printf "  %s  %s\n", $1, $2 }')"
    [ -n "$found" ] || continue
    any=1
    printf '%s:\n%s\n' "$state" "$found"
  done
  # states outside the vocabulary surface loudly instead of vanishing
  found="$(_rows | awk -F'\t' -v all="$STATES" 'BEGIN{split(all,t," "); for(i in t) ok[t[i]]=1} !ok[$3] { printf "  %s  %s  (status: %s)\n", $1, $2, $3 }')"
  [ -n "$found" ] && printf 'UNRECOGNIZED:\n%s\n' "$found"
  [ "$any" -eq 1 ] || echo "(no Active-queue rows found)"
  return 0
}

next() {
  local id
  id="$(_rows | awk -F'\t' '$3 == "queued" { print $1; exit }')"
  [ -n "$id" ] || { echo "(no queued items)" >&2; return 1; }
  echo "$id"
}

set_state() {
  local id="${1:-}" state="${2:-}"; shift 2 2>/dev/null || { echo "usage: backlog.sh set <ID-NNN> <state> [note]" >&2; return 64; }
  local note="${*:-}"
  echo "$STATES" | tr ' ' '\n' | grep -qx "$state" || { echo "unknown state '$state' (states: $STATES)" >&2; return 64; }
  grep -qE "^\| *${id} *\|" "$BACKLOG_FILE" || { echo "no Active-queue row for $id" >&2; return 1; }
  # Replace only the LEADING keyword of the last cell; keep the row's annotation prose.
  awk -F'|' -v OFS='|' -v id="$id" -v st="$state" -v note="$note" '
    $0 ~ "^\\| *" id " *\\|" {
      cell=$(NF-1); sub(/^[ \t]+/, "", cell)
      rest=cell; sub(/^[A-Za-z-]+/, "", rest)
      if (note != "") rest = " [" note "]" rest
      $(NF-1) = " " st rest " "
    } { print }' "$BACKLOG_FILE" > "$BACKLOG_FILE.tmp" && mv -f "$BACKLOG_FILE.tmp" "$BACKLOG_FILE"
  echo "$id -> $state"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    board)  board ;;
    next)   next ;;
    set)    set_state "$@" ;;
    states) echo "$STATES" | tr ' ' '\n' ;;
    *) echo "usage: backlog.sh {board|next|set <ID-NNN> <state> [note]|states}" >&2; return 64 ;;
  esac
}

main "$@"
