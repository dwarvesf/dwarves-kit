#!/usr/bin/env bash
# test-agent-lessons.sh - tests for scripts/agent-lessons.sh and for the lesson notes of this repo.
#   bash scripts/test-agent-lessons.sh
# Needs only bash and the standard tools. bash 3.2 safe.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/scripts/agent-lessons.sh"
MEM="$ROOT/.claude/memory"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS  $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-agent-lessons.XXXXXX")" || exit 1

# A scratch repo holds a copy of the script, so the script finds the scratch index.
scratch() { # scratch <name> -> a dir with scripts/agent-lessons.sh and .claude/memory/
  local d="$WORK/$1"
  mkdir -p "$d/scripts" "$d/.claude/memory"
  cp "$SCRIPT" "$d/scripts/agent-lessons.sh"
  echo "$d"
}
chars() { wc -c < "$1" | tr -d ' '; }

# 1. the index is printed as it is
S="$(scratch small)"
printf '# Repo lessons\n\n- [One](one.md): a lesson.\n' > "$S/.claude/memory/MEMORY.md"
bash "$S/scripts/agent-lessons.sh" > "$WORK/small.out" 2> "$WORK/small.err"
rc=$?
expect "prints a small index unchanged" cmp -s "$S/.claude/memory/MEMORY.md" "$WORK/small.out"
expect "exits 0 with an index" [ "$rc" -eq 0 ]
expect "prints nothing on stderr with an index" [ ! -s "$WORK/small.err" ]

# 2. a missing index never blocks a session
M="$(scratch missing)"
bash "$M/scripts/agent-lessons.sh" > "$WORK/missing.out" 2> "$WORK/missing.err"
rc=$?
expect "exits 0 when the index is missing" [ "$rc" -eq 0 ]
expect "prints nothing when the index is missing" [ ! -s "$WORK/missing.out" ]
M2="$(scratch nomemdir)"
rmdir "$M2/.claude/memory"
bash "$M2/scripts/agent-lessons.sh" > /dev/null 2>&1
expect "exits 0 when the memory folder is missing" [ "$?" -eq 0 ]

# 3. an index over the cap is cut at a whole line with a notice
B="$(scratch big)"
{
  echo "# Repo lessons"
  i=0
  while [ "$i" -lt 200 ]; do
    i=$((i + 1))
    echo "- [Lesson $i](lesson-$i.md): a line that pads the index well past the cap, number $i, so the cut is measurable."
  done
} > "$B/.claude/memory/MEMORY.md"
bigsize="$(chars "$B/.claude/memory/MEMORY.md")"
expect "the fixture index is over 9,000 characters ($bigsize)" [ "$bigsize" -gt 9000 ]
bash "$B/scripts/agent-lessons.sh" > "$WORK/big.out" 2> "$WORK/big.err"
rc=$?
expect "exits 0 with an oversized index" [ "$rc" -eq 0 ]
expect "an oversized index ends with a notice" bash -c "tail -n 1 '$WORK/big.out' | grep -q '^agent-lessons: the index is $bigsize characters'"
bigout="$(chars "$WORK/big.out")"
expect "the output stays under the 10,000 character hook cap ($bigout)" [ "$bigout" -lt 10000 ]
expect "the output keeps the first line" bash -c "[ \"\$(head -n 1 '$WORK/big.out')\" = '# Repo lessons' ]"
expect "the cut is on a whole line" bash -c "grep -v '^agent-lessons: ' '$WORK/big.out' | grep -v '^\$' | tail -n 1 | grep -q '\\.\$'"
expect "the body is cut below 9,000 characters" bash -c "[ \$(grep -v '^agent-lessons: ' '$WORK/big.out' | wc -c | tr -d ' ') -le 9001 ]"

# 4. an index of exactly 9,000 characters is printed whole
E="$(scratch edge)"
head -c 8999 "$B/.claude/memory/MEMORY.md" > "$E/.claude/memory/MEMORY.md"
printf '\n' >> "$E/.claude/memory/MEMORY.md"
bash "$E/scripts/agent-lessons.sh" > "$WORK/edge.out" 2>&1
expect "an index of 9,000 characters is printed whole" cmp -s "$E/.claude/memory/MEMORY.md" "$WORK/edge.out"

# 5. the index and the notes of this repo
if [ -f "$MEM/MEMORY.md" ]; then
  expect "the repo index is under 8,000 characters ($(chars "$MEM/MEMORY.md"))" [ "$(chars "$MEM/MEMORY.md")" -lt 8000 ]
  bad=0; n=0
  for link in $(grep -o '([A-Za-z0-9._-]*\.md)' "$MEM/MEMORY.md" | tr -d '()'); do
    n=$((n + 1))
    [ -f "$MEM/$link" ] || { bad=$((bad + 1)); echo "      the index links $link and no such note exists"; }
  done
  expect "the repo index links at least one note ($n)" [ "$n" -gt 0 ]
  expect "every link in the repo index reaches a note" [ "$bad" -eq 0 ]
  unlisted=0; badnote=0
  for note in "$MEM"/*.md; do
    b="$(basename "$note")"
    [ "$b" = "MEMORY.md" ] && continue
    grep -qF "($b)" "$MEM/MEMORY.md" || { unlisted=$((unlisted + 1)); echo "      $b is not listed in the index"; }
    fm="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$note")"
    [ "$(head -n 1 "$note")" = "---" ] || { badnote=$((badnote + 1)); echo "      $b: line 1 is not ---"; }
    printf '%s\n' "$fm" | grep -q '^name: .' || { badnote=$((badnote + 1)); echo "      $b: no name in the frontmatter"; }
    printf '%s\n' "$fm" | grep -q '^description: .' || { badnote=$((badnote + 1)); echo "      $b: no description in the frontmatter"; }
    [ "$(chars "$note")" -lt 1200 ] || { badnote=$((badnote + 1)); echo "      $b: $(chars "$note") characters, the cap is 1,200"; }
  done
  expect "every note is listed in the repo index" [ "$unlisted" -eq 0 ]
  expect "every note has name and description frontmatter and is under 1,200 characters" [ "$badnote" -eq 0 ]
else
  no "the repo has .claude/memory/MEMORY.md"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
