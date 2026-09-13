#!/usr/bin/env bash
# scattered-ids.sh -- enumerate scattered spec/task/ADR/ticket ids outside their three
# sanctioned homes (CONTRIBUTING.md "Where an ID may appear"). Prints one hit per line as
# path:line:text, or a bare count with --count.
#
# This is the reproducible item-enumeration command docs/patterns/audit-loop.md asks every
# audit-loop instance to have. tests/test-no-scattered-ids.sh calls it once per clean zone
# instead of carrying its own ad hoc grep; a future cleanup batch calls it to size the next
# zone before touching a file.
#
# Usage:
#   scattered-ids.sh --zone <name>   scan one named zone (see ZONES below)
#   scattered-ids.sh --all           scan every named zone
#   scattered-ids.sh --zone <name> --count   print a hit count instead of the hit lines
#
# ZONES (name -> tracked files scanned):
#   hooks       hooks/*.sh
#   bin         bin/*
#   skills      skills/*/SKILL.md
#   agents      agents/*.md
#   commands    commands/*.md
#   lib         lib/**/*.sh, lib/**/*.py (excluding nested tests/ dirs)
#   docs-specs  docs/specs/*.md
#
# EXEMPTIONS (on top of the CONTRIBUTING.md clause 1/2/3 sanctioned homes):
#   - own-number header: the id also names the file itself (its basename), e.g. a spec or
#     ADR citing its own number.
#   - a frontmatter/key line: Relates-to: / Backlog: / id: / generated-by:
#   - a provenance footer: <!-- provenance: ... --> (markdown) or # provenance: ... (a
#     bottom-of-file shell/python comment, the same clause-3 footer in a language with no
#     HTML-comment syntax)
#   - a board-row table line: | ID-nnn | ... (a row keyed by the id, clause 2)
#   - a dated log line: starts with a YYYY-MM-DD date, or a `## YYYY-MM-DD` heading
#     (LAB_LOG / CHANGELOG / retro shape, clause 2)
#   - a tool.toml board array: board = [...]
#   - anything under a tests/ or fixtures/ directory (test input, not scattered prose)
#   - docs/verification/gauntlet/** (proof records, never rewritten, per the gauntlet-proof-
#     audit instance)
#   - docs/FEATURES.md, docs/CHANGELOG.md (generated projection / release-note ledger)
#
# hooks/commit-format.sh's own guard regex (`SPEC-[0-9]|TASK-[0-9]|...`) is the mechanism
# that BLOCKS ids from commit subjects, not a scattered id: it needs no special-case here
# because the regex source (`SPEC-[0-9]`, no digit after the dash) never matches ID_RE below
# in the first place. If the guard regex ever grows a literal digit, exempt that line by name
# when it happens; do not pre-build an exemption for a shape that cannot occur today.

# No -e: a grep with zero matches is an expected outcome all through this script (a clean
# file, an empty zone), not a failure to abort on.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$KIT_DIR" || exit 1

ID_RE='(SPEC|TASK|ADR|SG|DEC|ID)-[0-9]+'

usage() { echo "usage: scattered-ids.sh [--zone <name>|--all] [--count]" >&2; exit 1; }

zone_files() {
  case "$1" in
    hooks)      git ls-files 'hooks/*.sh' ;;
    bin)        git ls-files 'bin/*' ;;
    skills)     git ls-files 'skills/*/SKILL.md' ;;
    agents)     git ls-files 'agents/*.md' ;;
    commands)   git ls-files 'commands/*.md' ;;
    lib)        git ls-files 'lib/*.sh' 'lib/*/*.sh' 'lib/*/*/*.sh' 'lib/*/*.py' 'lib/*/*/*.py' \
                  | grep -v '/tests/' || true ;;
    docs-specs) git ls-files 'docs/specs/*.md' ;;
    *) echo "scattered-ids: unknown zone '$1'" >&2; return 1 ;;
  esac
}

all_zones() { printf '%s\n' hooks bin skills agents commands lib docs-specs; }

# Does the id also name the file itself (own-number header, clause 1)?
own_number() {  # own_number <path> <id>
  case "$(basename "$1")" in
    *"$2"*) return 0 ;;
  esac
  return 1
}

is_exempt() {  # is_exempt <path> <line-text> <id>
  path="$1"; text="$2"; id="$3"
  case "$path" in
    */tests/*|*/fixtures/*)             return 0 ;;
    docs/verification/gauntlet/*)       return 0 ;;
    docs/FEATURES.md|docs/CHANGELOG.md) return 0 ;;
  esac
  own_number "$path" "$id" && return 0
  case "$text" in
    *SPEC-%s*|*ID-%s*) return 0 ;;   # a printf substitution: the VALUE is the reserved id
  esac
  printf '%s\n' "$text" | grep -qE '^[[:space:]]*(Relates-to|Backlog|id|generated-by):' && return 0
  printf '%s\n' "$text" | grep -qE '<!--[[:space:]]*provenance:' && return 0
  printf '%s\n' "$text" | grep -qE '^[[:space:]]*#[[:space:]]*provenance:' && return 0
  printf '%s\n' "$text" | grep -qE '^\|[[:space:]]*[A-Z]+-[0-9]+[[:space:]]*\|' && return 0
  printf '%s\n' "$text" | grep -qE '^[[:space:]]*#{0,3}[[:space:]]*\[?[0-9]{4}-[0-9]{2}-[0-9]{2}\]?' && return 0
  printf '%s\n' "$text" | grep -qE 'board[[:space:]]*=[[:space:]]*\[' && return 0
  return 1
}

scan_zone() {  # scan_zone <name> -> path:line:text per hit, exemptions applied
  zone="$1"
  files="$(zone_files "$zone")" || exit 1
  [ -n "$files" ] || return 0
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -nE "$ID_RE" "$f" 2>/dev/null | while IFS=: read -r lineno rest; do
      id="$(printf '%s\n' "$rest" | grep -oE "$ID_RE" | head -1)"
      is_exempt "$f" "$rest" "$id" && continue
      printf '%s:%s:%s\n' "$f" "$lineno" "$rest"
    done
  done
}

ZONE=""; ALL=0; COUNT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --zone) ZONE="${2:-}"; shift 2 ;;
    --all) ALL=1; shift ;;
    --count) COUNT=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$ZONE" ] || [ "$ALL" -eq 1 ] || usage

if [ "$ALL" -eq 1 ]; then
  ZONES="$(all_zones)"
else
  ZONES="$ZONE"
  # Validate up front: a bad zone must exit 1 even though the real scan below runs inside a
  # pipe subshell, whose exit status a plain `$(...)` assignment does not propagate.
  case "$ZONE" in
    hooks|bin|skills|agents|commands|lib|docs-specs) : ;;
    *) echo "scattered-ids: unknown zone '$ZONE'" >&2; exit 1 ;;
  esac
fi

HITS="$(printf '%s\n' "$ZONES" | while IFS= read -r z; do scan_zone "$z"; done)"
if [ "$COUNT" -eq 1 ]; then
  [ -z "$HITS" ] && echo 0 || printf '%s\n' "$HITS" | grep -c .
else
  [ -n "$HITS" ] && printf '%s\n' "$HITS"
  exit 0
fi
