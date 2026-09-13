#!/usr/bin/env bash
# verbatim-rows.sh -- assert every row an agent wrote into a rewritten structured index
# still appears verbatim in the pre-edit original.
#
# An agent rewriting MEMORY.md re-derived each row from frontmatter instead of copying it,
# and hard-truncated many rows mid-sentence. It restored the rows it kept verbatim but not
# the 209 it moved to an archive file, so 23 archive rows shipped cut -- one ending mid-word
# on "so a later git stash pop pops a". Every truncated row still ends in a legal character,
# so it survives an eyeball check; the only thing that caught it was a byte-for-byte diff
# against git. This mechanises that diff so it runs on any structured index (a kanban board,
# a MANIFEST, a GLOSSARY, a memory index), not just the one incident that found it.
#
# It asserts ONE property: every row line in the new file(s) exists, unchanged, somewhere in
# the original. It does not repair rows, count whether rows went missing, or judge which file
# a row should live in -- a moved-but-intact row is fine, a shortened one is not.
#
# Usage: verbatim-rows.sh <git-ref> <original-path> <new-path> [<new-path>...] [--pattern <regex>]
#   <git-ref>:<original-path>  the pre-edit file, read via `git show`
#   <new-path>                 a post-edit file on disk (repeatable)
#   --pattern <regex>          row-matching regex (default: ^- \[, markdown index rows)
# A "row" is any line in a file matching the pattern. Match is fixed-string, whole-line
# (`grep -Fqx --`, since rows start with "- " which grep would otherwise read as options).
# Exit 0: every row verbatim. Exit 1: at least one row is not. Exit 2: usage error or the
# git ref/path could not be read.
set -uo pipefail

pattern='^- \['
args=()
git_ref=""
orig_path=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pattern) pattern="${2:-}"; shift 2 ;;
    *)
      if [ -z "$git_ref" ]; then git_ref="$1"
      elif [ -z "$orig_path" ]; then orig_path="$1"
      else args+=("$1")
      fi
      shift ;;
  esac
done

if [ -z "$git_ref" ] || [ -z "$orig_path" ] || [ "${#args[@]}" -eq 0 ]; then
  echo "usage: verbatim-rows.sh <git-ref> <original-path> <new-path> [<new-path>...] [--pattern <regex>]" >&2
  exit 2
fi

orig_content="$(git show "${git_ref}:${orig_path}" 2>/dev/null)"
if [ $? -ne 0 ]; then
  echo "verbatim-rows: cannot read ${git_ref}:${orig_path} (bad ref or path)" >&2
  exit 2
fi

orig_tmp="$(mktemp)"
trap 'rm -f "$orig_tmp"' EXIT
printf '%s\n' "$orig_content" | grep -E "$pattern" -- > "$orig_tmp" || true

checked=0
bad=0
for f in "${args[@]}"; do
  if [ ! -r "$f" ]; then
    echo "verbatim-rows: cannot read $f" >&2
    exit 2
  fi
  while IFS= read -r row; do
    checked=$((checked + 1))
    if ! grep -Fqx -- "$row" "$orig_tmp"; then
      bad=$((bad + 1))
      preview="$row"
      [ "${#preview}" -gt 80 ] && preview="${preview:0:80}..."
      echo "NOT VERBATIM: $f: $preview"
    fi
  done < <(grep -E "$pattern" -- "$f" || true)
done

echo "rows checked: $checked, verbatim: $((checked - bad)), not verbatim: $bad"
[ "$bad" -eq 0 ]
