#!/usr/bin/env bash
# spec-status.sh -- the one reader of a spec's `Status:` header.
#
# The machine is declared once, in states.tsv (state, class, next, aliases). Every reader of a spec's
# status goes through here, so `**Status:**`, `status:` and `Status: VALIDATED (round 4 ...)` mean
# the same thing everywhere (docs/briefs/DECISION-BRIEF-declared-state-machines.md).
#
# The one writer is `set`; every other script that changes a spec's status calls it, never sed.
#
# Header grammar: the FIRST line that starts with `Status:` or `**Status:**` (any case, no
# indentation). Its value is read as the first word; anything after it is decoration. The word is
# looked up in states.tsv, aliases included.
#
# Usage:
#   spec-status.sh get <spec-file>
#       the canonical state: DRAFT APPROVED VALIDATED SHIPPED PARKED, or
#       NONE     no header, empty, missing or unreadable file
#       UNKNOWN  a header whose first word is not declared
#   spec-status.sh live [--none live|dead] <spec-file>...
#       the files whose spec is open, one per line, in argument order, in one pass. Open = class
#       active, or UNKNOWN. --none says what a header-less file is (default dead). Missing or
#       unreadable paths are skipped.
#   spec-status.sh set <spec-file> <STATE>
#       rewrite the first header line to STATE (a canonical state, any case; aliases and unknown words
#       exit 64). Plain stays plain, `**Status:**` stays bold, and the old word plus any decoration
#       after it is replaced by STATE. Atomic (tmp + mv). The same state is a no-op. Leaving a
#       terminal state works and prints a reopen notice on stderr. A file with no header, or a
#       missing one, exits 1 and is not touched.
#   spec-status.sh states [--class active|terminal]    the vocabulary, one per line
#   spec-status.sh machine                             the declared table with a header row
set -uo pipefail
export LC_ALL=C

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TSV="$DIR/states.tsv"
[ -r "$TSV" ] || { echo "FATAL: $TSV missing or unreadable" >&2; exit 1; }

_machine() { awk -F'\t' '!/^#/ && NF >= 2' "$TSV"; }
[ -n "$(_machine)" ] || { echo "FATAL: $TSV has no states" >&2; exit 1; }

# _read <get|live> <none-is-live 0|1> <file>...: one awk pass over the table, then each file's header.
_read() {
  local mode="$1" none_live="$2"; shift 2
  awk -v tsv="$TSV" -v mode="$mode" -v none_live="$none_live" '
    BEGIN {
      while ((getline row < tsv) > 0) {
        if (row ~ /^#/ || row == "") continue
        n = split(row, c, "\t")
        word[c[1]] = c[1]; class[c[1]] = c[2]
        if (n >= 4 && c[4] != "-") { k = split(c[4], a, " "); for (j = 1; j <= k; j++) word[a[j]] = c[1] }
      }
      close(tsv)
      for (i = 1; i < ARGC; i++) {
        f = ARGV[i]; state = "NONE"
        while ((getline line < f) > 0) {
          if (match(tolower(line), /^[*]*status[*]*:[*]*[ \t\r]*/)) {
            state = "UNKNOWN"
            v = substr(line, RLENGTH + 1)
            if (match(v, /^[A-Za-z][A-Za-z-]*/)) { w = toupper(substr(v, 1, RLENGTH)); if (w in word) state = word[w] }
            break
          }
        }
        close(f)
        if (mode == "get") print state
        else if (state == "NONE" ? none_live : (state == "UNKNOWN" || class[state] != "terminal")) print f
      }
    }' "$@"
}

# _set <file> <state>: the one writer. Replaces the first header line's value; nothing else moves.
_set() {
  local f="$1" want="$2" cur tmp
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then echo "spec-status: set: $f is missing or unreadable" >&2; return 1; fi
  cur="$(_read get 0 "$f")"
  if [ "$cur" = NONE ]; then echo "spec-status: set: $f has no Status: header; add one by hand" >&2; return 1; fi
  [ "$cur" = "$want" ] && return 0
  if _machine | awk -F'\t' -v s="$cur" '$1 == s && $2 == "terminal" { f = 1 } END { exit !f }'; then
    echo "spec-status: $f reopens from terminal '$cur' to '$want'" >&2
  fi
  tmp="$(mktemp "$f.XXXXXX")" || return 1
  cp -p "$f" "$tmp" 2>/dev/null
  if awk -v st="$want" '
    function emit(line) { print line (cr ? "\r" : "") }
    !done && match(tolower($0), /^[*]*status[*]*:[*]*[ \t\r]*/) {
      done = 1
      line = $0; cr = (line ~ /\r$/); sub(/\r$/, "", line)
      head = substr(line, 1, RLENGTH); sub(/\r$/, "", head)
      rest = substr(line, length(head) + 1)
      if (head !~ /[ \t]$/) head = head " "
      tail = ""
      if (tolower(head) ~ /^[*]+status:[ \t]*$/ && rest ~ /[*][*][ \t]*$/) tail = "**"
      emit(head st tail)
      next
    }
    { print }' "$f" > "$tmp" && mv -f "$tmp" "$f"; then
    return 0
  fi
  rm -f "$tmp"
  echo "spec-status: set: could not rewrite $f" >&2
  return 1
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  get)
    [ "$#" -eq 1 ] || { echo "usage: spec-status.sh get <spec-file>" >&2; exit 64; }
    if [ -f "$1" ] && [ -r "$1" ]; then _read get 0 "$1"; else echo NONE; fi
    ;;
  live)
    none_live=0
    if [ "${1:-}" = "--none" ]; then
      case "${2:-}" in
        live) none_live=1 ;;
        dead) none_live=0 ;;
        *) echo "usage: spec-status.sh live [--none live|dead] <spec-file>..." >&2; exit 64 ;;
      esac
      shift 2
    fi
    files=()
    for f in "$@"; do [ -f "$f" ] && [ -r "$f" ] && files+=("$f"); done
    [ "${#files[@]}" -gt 0 ] || exit 0
    _read live "$none_live" "${files[@]}"
    ;;
  set)
    [ "$#" -eq 2 ] || { echo "usage: spec-status.sh set <spec-file> <STATE>" >&2; exit 64; }
    want="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
    if ! _machine | cut -f1 | grep -qx -- "$want"; then
      echo "spec-status: set: '$2' is not a canonical state ($(_machine | cut -f1 | paste -sd ' ' -)); aliases are read, never written" >&2
      exit 64
    fi
    _set "$1" "$want"
    ;;
  states)
    if [ "${1:-}" != "--class" ]; then _machine | cut -f1; exit 0; fi
    case "${2:-}" in
      active|hold|terminal) _machine | awk -F'\t' -v c="$2" '$2 == c { print $1 }' ;;
      *) echo "usage: spec-status.sh states [--class active|terminal]" >&2; exit 64 ;;
    esac
    ;;
  machine)
    printf 'state\tclass\tnext\taliases\n'
    _machine
    ;;
  *)
    echo "usage: spec-status.sh {get <spec-file>|set <spec-file> <STATE>|live [--none live|dead] <spec-file>...|states [--class C]|machine}" >&2
    exit 64
    ;;
esac
