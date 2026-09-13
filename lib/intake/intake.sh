#!/usr/bin/env bash
# intake.sh -- the scripted dedup gate for knowledge intake.
#
# Five intake skills carried five hand-written prose copies of the same gate ("check the URL
# ledger, then the board, then the verdict ledger, then prior notes"), and the copies had
# already drifted: two grew an open-pull-request check the others never got. A prose gate
# cannot be run, so an item that was already decided came back in through a different source
# and was processed twice. This verb is the one engine those copies describe.
#
# Each store is read through one operator-config key, because every one of them belongs to
# the operator, not to this kit and not to a project. A key left empty, a command not on
# PATH, or a path that does not exist is SKIPPED with a stderr line and a `skipped` row in
# the output: a missing store never fails the gate, it only narrows it.
#
# Usage:
#   intake.sh gate <url | "subject">
#       -> one JSON object on stdout: the subject, every hit, every skipped source.
#          Exit 0 on any hit, 1 on none. A hit fills the caller's MATCHES line and stops
#          the item.
#   intake.sh -h | --help | help
#
# Hit kinds: url (the URL ledger), board (a row on any registered board), verdict (a decided
# eval), owned (this kit's own inventory, via `precedent find`), note (prior writing), pr (an
# open pull request). A board hit also carries row_kind: `eval` when the row was a measured
# evaluation, `skim` when it was only a skim, `other` otherwise, because a skim row must not
# close an eval.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"
KIT_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
# shellcheck source=lib/config/kit-config.sh
source "$LIB_ROOT/config/kit-config.sh" || { echo "FATAL: lib/config/kit-config.sh missing or unreadable" >&2; exit 1; }

# Semantic recall returns k rows for any input, so a floor is what makes it a gate rather
# than a search. 0.65 keeps the measured hits (a decided subject scored 0.68) and drops the
# noise floor (an unrelated query scored 0.34).
NOTE_FLOOR="0.65"
# Rows per store in the output. A gate answers "decided already", so the caller needs the
# first few citations, never the whole match list.
MAX_ROWS=3

HITS=""      # newline-separated JSON objects
SKIPPED=""   # newline-separated JSON objects

_usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

_add_hit() {
  local json; json="$(jq -cn --arg k "$1" --arg w "$2" --arg l "$3" --arg r "${4:-}" \
    '{kind:$k, where:$w, label:$l} + (if $r == "" then {} else {row_kind:$r} end)')"
  HITS="${HITS}${json}
"
}

_skip() {
  echo "intake gate: skipped $1 ($2)" >&2
  local json; json="$(jq -cn --arg k "$1" --arg w "$2" '{kind:$k, why:$w}')"
  SKIPPED="${SKIPPED}${json}
"
}

# _expand <path> -- a leading ~ means $HOME; everything else is returned as given.
_expand() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}" ;; *) printf '%s' "$1" ;; esac; }

# _terms <subject> -- the grep terms a line must ALL contain to count as a hit. A URL is one
# fixed term (scheme and trailing slash stripped, so a http/https or trailing-slash variant
# of the same link still matches). A subject is its words of four characters or more, which
# drops the connectives that would match every row.
_terms() {
  case "$1" in
    http://*|https://*)
      local u="${1#http://}"; u="${u#https://}"; printf '%s\n' "${u%/}" ;;
    *)
      printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '\n' \
        | awk 'length($0) >= 4' | sort -u || true ;;
  esac
}

# _match <file> -- print up to MAX_ROWS lines of <file> that contain every term. Fixed-string
# and case-insensitive: a subject is words, never a regex the operator has to escape.
_match() {
  local file="$1" out t
  out="$(cat "$file")" || return 1
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    out="$(printf '%s\n' "$out" | grep -i -F -- "$t")" || return 1
  done <<< "$TERMS"
  printf '%s\n' "$out" | head -"$MAX_ROWS"
}

# _row_kind <row> -- whether a board row records a measured evaluation or only a skim. The
# distinction is load-bearing: a skim row closed an eval once, and the eval had to be reopened.
_row_kind() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *"[eval]"*|*eval*) printf 'eval' ;;
    *skim*)            printf 'skim' ;;
    *)                 printf 'other' ;;
  esac
}

# _label <text> -- one output line: whitespace collapsed, trimmed to a citation length.
_label() { printf '%s' "$1" | tr -s '[:space:]' ' ' | cut -c1-160; }

# --- the six stores ---------------------------------------------------------------------

_src_url() {
  local cmd out
  case "$SUBJECT" in http://*|https://*) : ;; *) _skip url "the subject is not a URL"; return ;; esac
  cmd="$(kit_config_get_root intake.url_ledger "")"
  [ -n "$cmd" ] || { _skip url "intake.url_ledger is not set"; return; }
  command -v "$cmd" >/dev/null 2>&1 || { _skip url "$cmd is not on PATH"; return; }
  if out="$("$cmd" check "$SUBJECT" 2>/dev/null)"; then
    _add_hit url "$cmd" "$(_label "$(printf '%s' "$out" | jq -r '"seen \(.date // "?") verdict \(.verdict // "?"): \(.conclusion // .reason // "")"' 2>/dev/null || printf '%s' "$out")")"
  fi
}

_src_board() {
  local reg name path file rows row
  reg="$(kit_config_get_root intake.boards "")"
  [ -n "$reg" ] || { _skip board "intake.boards is not set"; return; }
  reg="$(_expand "$reg")"
  [ -f "$reg" ] || { _skip board "$reg does not exist"; return; }
  [ -n "$TERMS" ] || { _skip board "no searchable words in the subject"; return; }
  while read -r name path _rest; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -n "${path:-}" ] || continue
    file="$(_expand "$path")"
    [ -f "$file" ] || continue
    rows="$(_match "$file")" || continue
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      _add_hit board "$name" "$(_label "$row")" "$(_row_kind "$row")"
    done <<< "$rows"
  done < "$reg"
}

_src_verdict() {
  local file rows row
  file="$(kit_config_get_root intake.verdicts "")"
  [ -n "$file" ] || { _skip verdict "intake.verdicts is not set"; return; }
  file="$(_expand "$file")"
  [ -f "$file" ] || { _skip verdict "$file does not exist"; return; }
  [ -n "$TERMS" ] || { _skip verdict "no searchable words in the subject"; return; }
  rows="$(_match "$file")" || return 0
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    _add_hit verdict "${file##*/}" "$(_label "$row")"
  done <<< "$rows"
}

_src_owned() {
  local out
  out="$(bash "$KIT_ROOT/bin/precedent" find "$SUBJECT" --surface inventory --quiet --json 2>/dev/null)" \
    || { _skip owned "precedent find failed"; return; }
  printf '%s' "$out" | jq -e '.total_hits > 0' >/dev/null 2>&1 || return 0
  local label
  label="$(printf '%s' "$out" | jq -r '[to_entries[] | select(.value.hits? and (.value.hits | length > 0)) | "\(.key): \(.value.hits[0])"] | .[0] // ""')"
  _add_hit owned "precedent inventory" "$(_label "$label")"
}

_src_note() {
  local cmd out
  cmd="$(kit_config_get_root intake.notes "")"
  [ -n "$cmd" ] || { _skip note "intake.notes is not set"; return; }
  command -v "$cmd" >/dev/null 2>&1 || { _skip note "$cmd is not on PATH"; return; }
  out="$("$cmd" query "$SUBJECT" --k "$MAX_ROWS" --floor "$NOTE_FLOOR" --json 2>/dev/null)" \
    || { _skip note "$cmd query failed"; return; }
  printf '%s' "$out" | jq -e 'length > 0' >/dev/null 2>&1 || return 0
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _add_hit note "$cmd" "$(_label "$line")"
  done <<< "$(printf '%s' "$out" | jq -r '.[] | "\(.source) :: \(.heading // "")"' 2>/dev/null)"
}

# The stores above only see LANDED work. An item already being worked on lives in an open
# pull request, which is why two of the five prose copies had grown this check by hand.
_src_pr() {
  local out line
  command -v gh >/dev/null 2>&1 || { _skip pr "gh is not on PATH"; return; }
  [ -n "$TERMS" ] || { _skip pr "no searchable words in the subject"; return; }
  out="$(gh search prs "$SUBJECT" --state=open --involves=@me --limit "$MAX_ROWS" \
        --json title,url 2>/dev/null)" || { _skip pr "gh search prs failed (auth or rate limit)"; return; }
  printf '%s' "$out" | jq -e 'length > 0' >/dev/null 2>&1 || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _add_hit pr "open pull request" "$(_label "$line")"
  done <<< "$(printf '%s' "$out" | jq -r '.[] | "\(.title) \(.url)"' 2>/dev/null)"
}

cmd_gate() {
  [ $# -ge 1 ] && [ -n "${1:-}" ] || { echo 'usage: intake gate <url | "subject">' >&2; return 64; }
  SUBJECT="$1"
  TERMS="$(_terms "$SUBJECT")"

  _src_url
  _src_board
  _src_verdict
  _src_owned
  _src_note
  _src_pr

  jq -n --arg s "$SUBJECT" \
     --argjson hits "$(printf '%s' "$HITS" | jq -cs '.')" \
     --argjson skipped "$(printf '%s' "$SKIPPED" | jq -cs '.')" \
     '{subject:$s, hits:$hits, skipped:$skipped}'

  [ -n "$HITS" ]
}

main() {
  local sub="${1:-}"
  case "$sub" in
    -h|--help|help) _usage; return 0 ;;
    gate) shift; cmd_gate "$@" ;;
    *) echo 'usage: intake.sh gate <url | "subject">' >&2; return 64 ;;
  esac
}

main "$@"
