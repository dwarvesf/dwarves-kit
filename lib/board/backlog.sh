#!/usr/bin/env bash
# backlog.sh -- the Active queue as a kanban board (PHILOSOPHY §6 N2).
#
# The BACKLOG stays a markdown file (one source of truth; no parallel database). This
# helper makes its Status column MECHANICAL: render the board, pick the next queued
# item, flip a row's state, so a pull (`/kit:assign --next`) is scriptable and testable
# instead of a hand-edit. Status vocabulary is the, plus `claimed` (a pulled
# item between `queued` and `speccing`; the cross-session claim itself lives in
# lib/goal/goal-registry.sh, this only records the board state).
#
# Rows are `| <ID> | ... | <status...> |` in the Active queue table, where <ID> is a
# prefixed id like ID-NNN (ops-toolkit), DS-NNN, DF-NNN, BK-NNN, FO-NNN. The status cell
# may carry prose after the keyword (e.g. "queued [re-eval ...]"); only the LEADING
# keyword is the state. Section-header rows (no id cell) are ignored.
#
# BACKLOG_ID_RE overrides the id pattern (default `[A-Z]+-[0-9]+`, matches any prefix).
#
# Usage:
#   backlog.sh board               -> kanban columns (state -> ID + title), exit 0
#   backlog.sh next                -> the first queued row's ID (file order = priority), exit 1 if none
#   backlog.sh set <ID-NNN> <state> [note]  -> flip the row's leading status keyword.
#                                    Refuses (exit 1, writes nothing) when <ID-NNN> matches more
#                                    than one row -- a union-merge duplicate would otherwise have
#                                    both rows flipped silently. Run `dedupe` first.
#   backlog.sh dedupe <ID-NNN>     -> collapse duplicate rows sharing one id down to one: keeps
#                                    the shipped/dropped/parked copy (in that order), else the
#                                    last occurrence; a unique id is a no-op
#   backlog.sh dedupe-all [file]   -> sweep every id in the file (default BACKLOG_FILE), not just
#                                    one: for each id with more than one row, keep the first
#                                    non-queued copy (the one a merge flipped), or the first row
#                                    when every copy is still queued. Prints the deduped ids,
#                                    space-separated, empty when nothing changed. Driven by
#                                    `wrap.sh`'s union re-merge after a GitHub conflict, where the
#                                    rows to fix are unknown up front and every one wants the same
#                                    rule; a known single id still goes through plain `dedupe`.
#   backlog.sh states              -> the legal state names
#
# BACKLOG_FILE overrides the file path (tests point it at a fixture copy).

set -euo pipefail

BACKLOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKLOG_FILE="${BACKLOG_FILE:-$BACKLOG_DIR/../../_meta/BACKLOG.md}"  # _meta/ is at repo root (above lib/)
# shellcheck source=lib/gate/default-branch-warn.sh
source "$BACKLOG_DIR/../gate/default-branch-warn.sh" \
  || { echo "FATAL: lib/gate/default-branch-warn.sh missing or unreadable" >&2; exit 1; }

STATES="queued claimed speccing validated executing shipped parked dropped"
BACKLOG_ID_RE="${BACKLOG_ID_RE:-[A-Z]+-[0-9]+}"

_rows() {  # emit: ID<TAB>title<TAB>leading-status
  awk -F'|' -v idre="$BACKLOG_ID_RE" '
    $0 ~ ("^\\| *" idre " *\\|") {
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

# _match_lines <id> -> that id's row line numbers (1-based), one per line, file order
_match_lines() {
  grep -nE "^\| *${1} *\|" "$BACKLOG_FILE" | cut -d: -f1
}

set_state() {
  local id="${1:-}" state="${2:-}"; shift 2 2>/dev/null || { echo "usage: backlog.sh set <ID-NNN> <state> [note]" >&2; return 64; }
  # The note is everything left in argv joined by spaces (a legitimate multi-word note is
  # quoted by the caller and arrives as one $1). A caller that appends a flag this script
  # does not parse (e.g. a wrapper forwarding --backlog-file straight through) used to have
  # it silently folded into the note text, corrupting the row; refuse instead.
  for arg in "$@"; do
    case "$arg" in
      --*) echo "backlog.sh set: stray argument after the note: '$arg' (set takes <ID-NNN> <state> [note] only)" >&2; return 64 ;;
    esac
  done
  if [ "$#" -gt 1 ]; then
    echo "backlog.sh set: stray argument after the note: '$2' (set takes <ID-NNN> <state> [note] only)" >&2
    return 64
  fi
  local note="${*:-}"
  echo "$STATES" | tr ' ' '\n' | grep -qx "$state" || { echo "unknown state '$state' (states: $STATES)" >&2; return 64; }
  grep -qE "^\| *${id} *\|" "$BACKLOG_FILE" || { echo "no Active-queue row for $id" >&2; return 1; }
  # A union merge on _meta/BACKLOG.md can re-add a duplicate row for the same id; the awk write
  # below matches every row whose first cell is $id, so writing through a duplicate flips both
  # silently. Refuse instead of guessing which copy is current.
  local match_lines match_count
  match_lines="$(_match_lines "$id")"
  match_count="$(printf '%s\n' "$match_lines" | grep -c .)"
  if [ "$match_count" -gt 1 ]; then
    local joined; joined="$(printf '%s\n' "$match_lines" | paste -sd ',' - | sed 's/,/, /g')"
    echo "board set: ${id} matches ${match_count} rows (lines ${joined}); dedupe first" >&2
    return 1
  fi
  # Replace only the LEADING keyword of the last cell; keep the row's annotation prose.
  awk -F'|' -v OFS='|' -v id="$id" -v st="$state" -v note="$note" '
    $0 ~ "^\\| *" id " *\\|" {
      cell=$(NF-1); sub(/^[ \t]+/, "", cell)
      rest=cell; sub(/^[A-Za-z-]+/, "", rest)
      # A terminal state ends the row, so its note SUPERSEDES the in-flight ones rather than
      # stacking in front of them. Stacking let a shipped row keep an older note that still
      # described the work as open, and a reader cannot tell which note is current.
      # Only when a note is given: flipping to terminal with no note would otherwise erase
      # the only record the row has and leave nothing in its place.
      if (note != "") {
        if (st == "shipped" || st == "dropped") rest = " [" note "]"
        else rest = " [" note "]" rest
      }
      $(NF-1) = " " st rest " "
    } { print }' "$BACKLOG_FILE" > "$BACKLOG_FILE.tmp" && mv -f "$BACKLOG_FILE.tmp" "$BACKLOG_FILE"
  echo "$id -> $state"
  kit_warn_default_branch "$BACKLOG_FILE" "board set"
}

dedupe() {
  local id="${1:-}"; [ -n "$id" ] || { echo "usage: backlog.sh dedupe <ID-NNN>" >&2; return 64; }
  # <line>\t<leading-status> per matching row, file order.
  local rows
  rows="$(awk -v id="$id" '
    $0 ~ ("^\\| *" id " *\\|") {
      n = split($0, f, "|"); status = f[n-1]; gsub(/^[ \t]+|[ \t]+$/, "", status)
      split(status, a, /[ \[(]/); printf "%d\t%s\n", NR, a[1]
    }' "$BACKLOG_FILE")"
  local count; count="$(printf '%s\n' "$rows" | grep -c .)"
  if [ "$count" -le 1 ]; then
    echo "nothing to dedupe"
    return 0
  fi
  # Keep priority: shipped, then dropped, then parked (all resolved/terminal-ish), else the
  # last occurrence in the file (the most recently written copy).
  local keep=""
  for want in shipped dropped parked; do
    keep="$(printf '%s\n' "$rows" | awk -F'\t' -v w="$want" '$2==w{print $1; exit}')"
    [ -n "$keep" ] && break
  done
  [ -n "$keep" ] || keep="$(printf '%s\n' "$rows" | awk -F'\t' 'END{print $1}')"
  local dropped; dropped="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$keep" '$1!=k{print $1}' | paste -sd ',' - | sed 's/,/, /g')"
  local drop_csv; drop_csv="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$keep" '$1!=k{printf "%s,",$1}')"
  awk -v dropset="$drop_csv" '
    BEGIN { n = split(dropset, d, ","); for (i = 1; i <= n; i++) if (d[i] != "") skip[d[i]] = 1 }
    !(NR in skip) { print }' "$BACKLOG_FILE" > "$BACKLOG_FILE.tmp" && mv -f "$BACKLOG_FILE.tmp" "$BACKLOG_FILE"
  echo "board dedupe: ${id} kept line ${keep}, dropped lines ${dropped}"
  kit_warn_default_branch "$BACKLOG_FILE" "board dedupe"
}

# dedupe_all [file] -- sweep every duplicated id in one pass (default $BACKLOG_FILE). Unlike
# `dedupe <id>`, which keeps a terminal (shipped/dropped/parked) copy over the last occurrence,
# this rule is the one a union-merge duplicate actually needs: prefer whichever copy is NOT
# queued (the row a branch flipped), file order breaks a tie. Prints the deduped ids.
dedupe_all() {
  local file="${1:-$BACKLOG_FILE}"
  [ -f "$file" ] || return 0
  local ids; ids="$(awk -F'|' -v idre="$BACKLOG_ID_RE" '
    $0 ~ ("^\\| *" idre " *\\|") { id=$2; gsub(/^[ \t]+|[ \t]+$/, "", id); print id }' "$file" \
    | sort | uniq -d)"
  [ -n "$ids" ] || return 0
  local id rows keep skip_csv="" done_ids=""
  for id in $ids; do
    rows="$(awk -v id="$id" -F'|' '
      $0 ~ ("^\\| *" id " *\\|") {
        s = $(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", s); split(s, a, /[ \[(]/)
        printf "%d\t%s\n", NR, a[1]
      }' "$file")"
    keep="$(printf '%s\n' "$rows" | awk -F'\t' '$2 != "queued" { print $1; exit }')"
    [ -n "$keep" ] || keep="$(printf '%s\n' "$rows" | head -n1 | cut -f1)"
    skip_csv="${skip_csv}$(printf '%s\n' "$rows" | awk -F'\t' -v k="$keep" '$1 != k { printf "%s,", $1 }')"
    done_ids="${done_ids}${done_ids:+ }${id}"
  done
  awk -v dropset="$skip_csv" '
    BEGIN { n = split(dropset, d, ","); for (i = 1; i <= n; i++) if (d[i] != "") skip[d[i]] = 1 }
    !(NR in skip) { print }' "$file" > "$file.tmp" && mv -f "$file.tmp" "$file"
  kit_warn_default_branch "$file" "board dedupe-all"
  echo "$done_ids"
}

main() {
  local sub="${1:-}"; shift || true
  # Every verb but `states` reads BACKLOG_FILE; a wrapper pointing it at a moved or
  # misspelled path used to fail deep inside _rows()'s awk call with a bare "can't open
  # file" and exit 2, naming neither the variable nor the wrapper as the likely cause.
  if [ "$sub" != "states" ] && [ ! -r "$BACKLOG_FILE" ]; then
    echo "backlog.sh: BACKLOG_FILE names no readable file: $BACKLOG_FILE, check the board wrapper's path" >&2
    return 1
  fi
  case "$sub" in
    board)      board ;;
    next)       next ;;
    set)        set_state "$@" ;;
    dedupe)     dedupe "$@" ;;
    dedupe-all) dedupe_all "$@" ;;
    states)     echo "$STATES" | tr ' ' '\n' ;;
    *) echo "usage: backlog.sh {board|next|set <ID-NNN> <state> [note]|dedupe <ID-NNN>|dedupe-all [file]|states}" >&2; return 64 ;;
  esac
}

main "$@"
