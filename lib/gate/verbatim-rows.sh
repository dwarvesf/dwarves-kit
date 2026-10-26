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
#        verbatim-rows.sh --words [--ignore-headings] <git-ref> <original-path> <new-path>
#   <git-ref>:<original-path>  the pre-edit file, read via `git show`
#   <new-path>                 a post-edit file on disk (repeatable in row mode, exactly one
#                              in --words mode)
#   --pattern <regex>          row-matching regex (default: ^- \[, markdown index rows)
#   --words                    prose mode, see below
#   --ignore-headings          --words only: drop lines starting with # in the new file
# A "row" is any line in a file matching the pattern. Match is fixed-string, whole-line
# (`grep -Fqx --`, since rows start with "- " which grep would otherwise read as options).
# Exit 0: every row verbatim. Exit 1: at least one row is not. Exit 2: usage error or the
# git ref/path could not be read.
#
# --words handles prose that was REFORMATTED (headings added, paragraphs split, lines
# reflowed) in a source kept word for word, where whole-line matching fails though no word
# changed. It compares the WORD SEQUENCE of the original with the new file, ignoring
# whitespace and line breaks, and prints every deleted, inserted, or replaced span with a
# few words of context. YAML frontmatter is skipped in both files, and a markdown marker
# standing alone (>, -, *, +, 1. or 1)) is not a word. Same exit contract: 0 every word
# preserved in order, 1 a change found, 2 usage or read error. The word diff needs python3.
set -uo pipefail

pattern='^- \['
words=0
ignore_headings=0
args=()
git_ref=""
orig_path=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pattern) pattern="${2:-}"; shift 2 ;;
    --words) words=1; shift ;;
    --ignore-headings) ignore_headings=1; shift ;;
    *)
      if [ -z "$git_ref" ]; then git_ref="$1"
      elif [ -z "$orig_path" ]; then orig_path="$1"
      else args+=("$1")
      fi
      shift ;;
  esac
done

if [ -z "$git_ref" ] || [ -z "$orig_path" ] || [ "${#args[@]}" -eq 0 ] \
   || { [ "$words" -eq 1 ] && [ "${#args[@]}" -ne 1 ]; } \
   || { [ "$words" -eq 0 ] && [ "$ignore_headings" -eq 1 ]; }; then
  echo "usage: verbatim-rows.sh <git-ref> <original-path> <new-path> [<new-path>...] [--pattern <regex>]" >&2
  echo "       verbatim-rows.sh --words [--ignore-headings] <git-ref> <original-path> <new-path>" >&2
  exit 2
fi

orig_content="$(git show "${git_ref}:${orig_path}" 2>/dev/null)"
if [ $? -ne 0 ]; then
  echo "verbatim-rows: cannot read ${git_ref}:${orig_path} (bad ref or path)" >&2
  exit 2
fi

orig_tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
trap 'rm -f "$orig_tmp"' EXIT

if [ "$words" -eq 1 ]; then
  if [ ! -r "${args[0]}" ]; then
    echo "verbatim-rows: cannot read ${args[0]}" >&2
    exit 2
  fi
  command -v python3 >/dev/null 2>&1 || { echo "verbatim-rows: --words needs python3" >&2; exit 2; }
  printf '%s\n' "$orig_content" > "$orig_tmp"
  python3 -I - "$orig_tmp" "${args[0]}" "$ignore_headings" <<'PY'
import difflib, re, sys

def words(path, drop_headings):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() in ("---", "..."):
                lines = lines[i + 1:]
                break
    if drop_headings:
        lines = [l for l in lines if not l.startswith("#")]
    marker = re.compile(r"^(>+|[-*+]|\d+[.)])$")
    return [w for w in " ".join(lines).split() if not marker.match(w)]

try:
    orig, new = words(sys.argv[1], False), words(sys.argv[2], sys.argv[3] == "1")
except OSError as e:
    print("verbatim-rows: %s" % e, file=sys.stderr)
    sys.exit(2)
changes = 0
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, orig, new, autojunk=False).get_opcodes():
    if tag == "equal":
        continue
    changes += 1
    print("WORDS %s: ...%s [-%s +%s] %s..." % (
        {"delete": "DELETED", "insert": "INSERTED", "replace": "REPLACED"}[tag],
        " ".join(orig[max(0, i1 - 4):i1]), " ".join(orig[i1:i2]) or "(none)",
        " ".join(new[j1:j2]) or "(none)", " ".join(orig[i2:i2 + 4])))
print("words in original: %d, changes: %d" % (len(orig), changes))
sys.exit(1 if changes else 0)
PY
  exit $?
fi

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
