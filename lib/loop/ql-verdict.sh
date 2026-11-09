#!/bin/bash
# ql-verdict.sh: the one parser for QL-VERDICT round markers, and the resume verb for bounded loops.
#   parse  <file> [--section <heading>]   one "round clean findings" line per marker, file order
#   resume <file> [--section <heading>]   round=<next> clean_streak=<k> last_findings=<K or ->
# Read-only. A missing file or no markers means a fresh start. A line naming QL-VERDICT that does
# not match the full grammar is a loud error (exit 65). --section limits the scan to the lines
# under one markdown heading (e.g. "## Test plan critique") up to the next heading of equal or
# higher level.
set -uo pipefail

# Backticks and surrounding spaces are stripped first, so a marker may be wrapped in `code`.
MARKER='^[ ]*\[\[QL-VERDICT round=([0-9]+) clean=(true|false) findings=([0-9]+)\]\][ ]*$'

usage() { echo "usage: ql-verdict.sh {parse|resume} <file> [--section <heading>]" >&2; exit 64; }

verb="${1:-}"; file="${2:-}"; section=""
[ -n "$file" ] || usage
case "$verb" in parse|resume) ;; *) usage ;; esac
shift 2
if [ "${1:-}" = "--section" ]; then section="${2:-}"; [ -n "$section" ] || usage; shift 2; fi
[ "$#" -eq 0 ] || usage
[ -f "$file" ] || { [ "$verb" = parse ] || echo "round=1 clean_streak=0 last_findings=-"; exit 0; }

# The lines to scan: the whole file, or one section of it.
scan_lines() {
  [ -z "$section" ] && { cat -- "$file"; return; }
  awk -v want="$section" '
    /^#+[ ]/ {
      h = $0; sub(/[ ]+$/, "", h); lvl = match(h, /[^#]/) - 1
      if (on && lvl <= start) on = 0
      if (!on && h == want) { on = 1; start = lvl }
    }
    on' "$file"
}

rows=""; bad=0
while IFS= read -r line; do
  case "$line" in *QL-VERDICT*) ;; *) continue ;; esac
  if [[ "${line//\`/}" =~ $MARKER ]]; then
    rows+="${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"$'\n'
  else
    echo "malformed QL-VERDICT in $file: $line" >&2; bad=1
  fi
done < <(scan_lines)
[ "$bad" -eq 0 ] || exit 65

if [ "$verb" = parse ]; then printf '%s' "$rows"; exit 0; fi

max=0 streak=0 last="-"
while read -r rno clean findings; do
  [ $((10#$rno)) -gt "$max" ] && max=$((10#$rno))
  if [ "$clean" = true ]; then streak=$((streak + 1)); else streak=0; fi
  last=$((10#$findings))
done < <(printf '%s' "$rows")
echo "round=$((max + 1)) clean_streak=$streak last_findings=$last"
