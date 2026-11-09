#!/usr/bin/env bash
# box.sh -- the one reader of the mega ROADMAP box and id grammar declared in lib/mega/box.tsv.
# Source it for the functions, or run it for the verbs below. Pure on load: no side effects but
# the function and variable definitions. bash 3.2 compatible.
#
#   box_chars NAME...      the characters of those boxes, token and aliases ("done" -> xX); a dash sorts last
#   box_class NAME...      the same as a bracket expression ("open" "done" -> [ xX])
#   box_re [NAME...]       the bullet and box as an ERE, anchored by the caller ("- \[[ xX]\]"); no names = every box
#   box_token NAME         the canonical token a writer stamps ("done" -> [x])
#   box_name CHAR          the box a character belongs to (x -> done); empty for an undeclared character
#   box_line_is NAME LINE  exit 0 when LINE starts `- [c]` and c belongs to NAME
#   box_id_re [NAME...]    the sub-goal id ERE, every id row ORed, or only the named rows (sg, slug)
#   BOX_ID_RE, BOX_SG_RE   box_id_re and box_id_re sg, computed once on load for the hot loops
#   box.sh machine         the declared table with a header row
#   box.sh chars|class|re|token|name|id ...   the same as the functions, for tests and the shell
#
# Readers derive their patterns from these; none spells the grammar itself
# (tests/test-mega-box.sh fails on a re-introduced copy).

BOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_TSV="$BOX_DIR/box.tsv"

_box_rows() { awk -F'\t' '!/^#/ && NF >= 3' "$BOX_TSV"; }

if [ ! -r "$BOX_TSV" ] || [ -z "$(_box_rows)" ]; then
  echo "FATAL: $BOX_TSV missing, unreadable or empty" >&2
  return 1 2>/dev/null || exit 1
fi

box_chars() {
  _box_rows | awk -F'\t' -v want=" $* " '
    $1 == "box" && index(want, " " $2 " ") {
      s = s substr($3, 2, 1)
      if ($5 != "" && $5 != "-") { n = split($5, a, " "); for (i = 1; i <= n; i++) s = s substr(a[i], 2, 1) }
    }
    END {
      for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == "-") dash = "-"; else out = out c }
      printf "%s%s", out, dash
    }'
}

box_class() { printf '[%s]' "$(box_chars "$@")"; }

box_re() {
  if [ $# -eq 0 ]; then set -- $(_box_rows | awk -F'\t' '$1 == "box" { printf "%s ", $2 }'); fi
  printf -- '- \\[%s\\]' "$(box_class "$@")"
}

box_token() { _box_rows | awk -F'\t' -v n="$1" '$1 == "box" && $2 == n { printf "%s", $3; exit }'; }

box_name() {
  _box_rows | awk -F'\t' -v c="$1" '
    $1 == "box" {
      hit = (substr($3, 2, 1) == c)
      if (!hit && $5 != "" && $5 != "-") { n = split($5, a, " "); for (i = 1; i <= n; i++) if (substr(a[i], 2, 1) == c) hit = 1 }
      if (hit) { printf "%s", $2; exit }
    }'
}

box_line_is() {
  local name="$1" line="$2" c
  case "$line" in '- ['?']'*) c="${line:3:1}" ;; *) return 1 ;; esac
  [ "$(box_name "$c")" = "$name" ]
}

box_id_re() {
  _box_rows | awk -F'\t' -v want=" $* " '
    $1 == "id" && (want == "  " || index(want, " " $2 " ")) { s = s (s == "" ? "" : "|") $3 }
    END { printf "(%s)", s }'
}

BOX_ID_RE="$(box_id_re)"
BOX_SG_RE="$(box_id_re sg)"

_box_main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    machine) printf 'kind\tname\ttoken\tclass\taliases\n'; _box_rows ;;
    chars)   box_chars "$@" ;;
    class)   box_class "$@" ;;
    re)      box_re "$@" ;;
    token)   box_token "$@" ;;
    name)    box_name "$@" ;;
    id)      box_id_re "$@" ;;
    *) echo "usage: box.sh {machine|chars NAME...|class NAME...|re [NAME...]|token NAME|name CHAR|id [NAME...]}" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _box_main "$@"
fi
