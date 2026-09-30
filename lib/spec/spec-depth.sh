#!/usr/bin/env bash
# spec-depth.sh -- read and check the `Depth:` line in a spec header.
# The line says how deep planning goes and why; it is read from the header only
# (the lines before the first `## ` heading), so a fenced example in the body
# never counts.
#
# Usage:
#   spec-depth.sh level <spec>                 -> the level set, space-separated:
#                                                 standard | research-repo research-outside blind-spot
#   spec-depth.sh wants <spec> <level>         -> exit 0 when the header's levels include
#                                                 research-repo|research-outside|blind-spot; 1 otherwise
#                                                 (including no header line)
#   spec-depth.sh check <spec>                 -> one line per problem; exit 1 on any
#   spec-depth.sh -h|--help|help               -> this usage
#
# Header forms:
#   Depth: standard (<why nothing deeper is needed>)
#   Depth: research (repo: <unknown>) | research (outside: <unknown>) | blind-spot (failure: <mode>)
#   Levels combine with " + ".
set -uo pipefail

# A spec is new, and must carry a Depth line, when it is generated on or after this date
# or its number is at or above this one. Older specs only warn. A missing Generated line
# never grants the grace period on its own: the number decides.
DEPTH_REQUIRED_FROM="2026-09-30"
DEPTH_REQUIRED_FROM_SPEC=372

# A reason made only of these (after dropping stop words) earns nothing deeper.
IMPORTANCE_WORDS=" important critical risky core complex sensitive big "
STOP_WORDS=" a an the this that these those is are was be it its of to and or very so too really change work "

usage() { sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

LEVELS=""; PROBLEMS=""; HAS_LINE=0

problem() { PROBLEMS="${PROBLEMS}$*"$'\n'; }

# Header = lines before the first `## `. Strips CR and trailing blanks; a fenced block inside
# the header is not header text, so an example there never reads as the Depth line.
header() { awk '/^## /{exit} /^```/{f=!f; next} f{next} {gsub(/\r/, ""); sub(/[ \t]+$/, ""); print}' "$1"; }

# `Depth:`, `**Depth:**` and `**Depth**:` all parse, like the Lane line in hooks/ship-gate.sh.
DEPTH_RE='^(\*\*)?Depth(\*\*)?:'
strip_depth() { sed -E 's/^(\*\*)?Depth(\*\*)?:(\*\*)?[[:space:]]*//'; }

# Split "a (x) + b (y)" into one segment per line. A split point is ") + <name> (".
segments() {
  printf '%s\n' "$1" | awk '{
    s = $0; sub(/^ +/, "", s); sub(/ +$/, "", s)
    while (match(s, /\) \+ [a-z-]+ \(/)) { print substr(s, 1, RSTART); s = substr(s, RSTART + 4) }
    print s }'
}

add_level() {
  case " $LEVELS " in *" $1 "*) ;; *) LEVELS="${LEVELS:+$LEVELS }$1" ;; esac
}

check_reason() {
  local lvl=$1 reason=$2 words w content=0 real=0
  reason=$(printf '%s' "$reason" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ -z "$reason" ]; then problem "$lvl: empty reason"; return; fi
  words=$(printf '%s' "$reason" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' ' ')
  for w in $words; do
    case "$STOP_WORDS" in *" $w "*) continue ;; esac
    content=1
    case "$IMPORTANCE_WORDS" in *" $w "*) ;; *) real=1 ;; esac
  done
  if [ "$content" -eq 0 ]; then problem "$lvl: reason has no content words"
  elif [ "$real" -eq 0 ]; then problem "$lvl: reason only says the work matters ($reason); name the unknown or the failure"
  fi
}

# Sets LEVELS, PROBLEMS, HAS_LINE from the spec header.
parse() {
  local hdr n rest seg name body lvl reason re='^([a-z-]+) \((.*)\)$'
  LEVELS=""; PROBLEMS=""; HAS_LINE=0
  hdr=$(header "$1")
  n=$(printf '%s\n' "$hdr" | grep -ciE "$DEPTH_RE")
  [ "$n" -eq 0 ] && return 0
  HAS_LINE=1
  [ "$n" -gt 1 ] && problem "two Depth lines in the header ($n found)"
  rest=$(printf '%s\n' "$hdr" | grep -m1 -iE "$DEPTH_RE" | strip_depth)
  while IFS= read -r seg; do
    if ! [[ $seg =~ $re ]]; then
      problem "malformed Depth segment '$seg' (want: <level> (<reason>))"; continue
    fi
    name=${BASH_REMATCH[1]}; body=${BASH_REMATCH[2]}
    case $name in
      standard) lvl=standard; reason=$body ;;
      research)
        case $body in
          repo:*)    lvl=research-repo;    reason=${body#repo:} ;;
          outside:*) lvl=research-outside; reason=${body#outside:} ;;
          *) problem "research needs a 'repo:' or 'outside:' prefix"; continue ;;
        esac ;;
      blind-spot)
        case $body in
          failure:*) lvl=blind-spot; reason=${body#failure:} ;;
          *) problem "blind-spot needs a 'failure:' prefix"; continue ;;
        esac ;;
      *) problem "unknown Depth level '$name'"; continue ;;
    esac
    add_level "$lvl"
    check_reason "$lvl" "$reason"
  done <<EOF
$(segments "$rest")
EOF
  case " $LEVELS " in
    *" standard "*) [ "$LEVELS" = "standard" ] || problem "standard cannot combine with a deeper level" ;;
  esac
}

# Body of the spec's `## Open questions` section (outside fenced blocks).
open_questions_body() {
  awk '/^```/{f=!f} !f && tolower($0) ~ /^## open questions/{on=1; next} on && !f && /^## /{exit} on{print}' "$1"
}

cmd_check() {
  local spec=$1 first gen num
  parse "$spec"
  if [ "$HAS_LINE" -eq 0 ]; then
    gen=$(header "$spec" | grep -m1 '^Generated:' | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -n1)
    num=$(basename "$spec" | grep -o '^SPEC-[0-9]*' | head -n1 | sed 's/SPEC-//')
    [ -n "$num" ] || num=$(header "$spec" | grep -m1 -o '^# SPEC-[0-9]*' | sed 's/# SPEC-//')
    if [ -n "$gen" ] && ! [[ $gen < $DEPTH_REQUIRED_FROM ]]; then
      problem "no Depth line in the header (Generated $gen, required from $DEPTH_REQUIRED_FROM)"
    elif [ -n "$num" ] && [ "$((10#$num))" -ge "$DEPTH_REQUIRED_FROM_SPEC" ]; then
      problem "no Depth line in the header (SPEC-$num, required from SPEC-$DEPTH_REQUIRED_FROM_SPEC)"
    else
      echo "spec-depth: warning: no Depth line in $spec (older spec, counts as standard)" >&2
    fi
  elif [ "$LEVELS" = "standard" ]; then
    first=$(open_questions_body "$spec" | grep -m1 '[^[:space:]]' | sed 's/^[[:space:]]*//' | tr 'A-Z' 'a-z')
    case $first in
      ""|"(none"*|"none"|"none."|"none;"*) ;;
      *) problem "standard, but '## Open questions' is not empty: an open question is an unknown only research closes" ;;
    esac
  fi
  [ -z "$PROBLEMS" ] && return 0
  printf '%s' "$PROBLEMS"
  return 1
}

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$verb" in
    -h|--help|help|"") usage; return 0 ;;
    level|wants|check) ;;
    *) echo "spec-depth: unknown verb '$verb' (try: spec-depth --help)" >&2; return 2 ;;
  esac
  local spec="${1:-}"
  if [ -z "$spec" ] || [ ! -f "$spec" ]; then echo "spec-depth: $verb needs a spec file (got '${spec}')" >&2; return 2; fi
  case "$verb" in
    level)
      parse "$spec"
      if [ -n "$LEVELS" ]; then echo "$LEVELS"
      else
        echo "spec-depth: no valid Depth line in $spec, treating as standard" >&2
        echo standard
      fi ;;
    wants)
      case "${2:-}" in research-repo|research-outside|blind-spot) ;;
        *) echo "spec-depth: wants needs research-repo|research-outside|blind-spot" >&2; return 2 ;;
      esac
      parse "$spec"
      case " $LEVELS " in *" $2 "*) return 0 ;; *) return 1 ;; esac ;;
    check) cmd_check "$spec" ;;
  esac
}

main "$@"
