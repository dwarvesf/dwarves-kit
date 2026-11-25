#!/usr/bin/env bash
# test-stamp-lessons.sh -- the lessons group of the team stamp: scripts/agent-lessons.sh, its generated
# test, the index and the five seed notes, stamped into a scratch repo and read back.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
TPL="$ROOT/templates/team-stamp"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-lessons.XXXXXX")" || exit 1
EM="$(printf '\342\200\224')"; EN="$(printf '\342\200\223')"
NOTES="ci-runner-has-no-procps ci-sets-ci-true queued-run-missing-from-lists guards-match-command-text stale-checks-after-a-rule-change"
chars() { wc -c < "$1" | tr -d ' '; }

R="$(mktemp -d "$WORK/r.XXXXXX")"; git -C "$R" init -q 2>/dev/null
OUT="$(bash lib/stamp.sh --only lessons --default-branch master --tags app,lib --product-paths app/,pkg/ "$R" 2>&1)"
expect "stamp the lessons group" [ $? -eq 0 ]

# 1. file set and modes
expect "scripts/agent-lessons.sh is written and executable" [ -x "$R/scripts/agent-lessons.sh" ]
expect "scripts/test-agent-lessons.sh is written and executable" [ -x "$R/scripts/test-agent-lessons.sh" ]
expect ".claude/memory/MEMORY.md is written" [ -f "$R/.claude/memory/MEMORY.md" ]
for n in $NOTES; do
  expect "seed note $n.md is written" [ -f "$R/.claude/memory/$n.md" ]
done
expect "the group writes exactly 8 files" bash -c "[ \$(awk '\$1==\"file\"' '$R/.claude/team-stamp.lock' | wc -l | tr -d ' ') -eq 8 ]"
expect "the index and the five notes are seed rows" bash -c "[ \$(grep -c '^seed	' '$TPL/manifest.d/20-lessons.tsv') -eq 6 ]"
expect "the two scripts are copy rows" bash -c "[ \$(grep -c '^copy	' '$TPL/manifest.d/20-lessons.tsv') -eq 2 ]"

# 2. the script on the stamped repo
bash "$R/scripts/agent-lessons.sh" > "$WORK/idx.out" 2>&1; rc=$?
expect "the script prints the stamped index" cmp -s "$R/.claude/memory/MEMORY.md" "$WORK/idx.out"
expect "the script exits 0" [ "$rc" -eq 0 ]
(cd "$WORK" && bash "$R/scripts/agent-lessons.sh" > "$WORK/elsewhere.out" 2>&1)
expect "the script finds the repo from another directory" cmp -s "$R/.claude/memory/MEMORY.md" "$WORK/elsewhere.out"
CP="$(mktemp -d "$WORK/cp.XXXXXX")"; mkdir -p "$CP/scripts"; cp "$R/scripts/agent-lessons.sh" "$CP/scripts/"
bash "$CP/scripts/agent-lessons.sh" > "$WORK/none.out" 2>&1; rc=$?
expect "no index: exit 0" [ "$rc" -eq 0 ]
expect "no index: no output" [ ! -s "$WORK/none.out" ]
mkdir -p "$CP/.claude/memory"
i=0; { echo "# Repo lessons"; while [ "$i" -lt 150 ]; do i=$((i + 1)); echo "- [Lesson $i](l$i.md): a line that pads the index past the cap, number $i, so the cut is measurable."; done; } > "$CP/.claude/memory/MEMORY.md"
size="$(chars "$CP/.claude/memory/MEMORY.md")"
bash "$CP/scripts/agent-lessons.sh" > "$WORK/cut.out" 2>&1; rc=$?
expect "an index of $size characters: exit 0" [ "$rc" -eq 0 ]
expect "an index past 9,000 characters is cut with a notice" bash -c "tail -n 1 '$WORK/cut.out' | grep -q '^agent-lessons: the index is $size characters'"
expect "the cut output stays under 10,000 characters" [ "$(chars "$WORK/cut.out")" -lt 10000 ]
if [ -x /bin/bash ]; then
  /bin/bash "$CP/scripts/agent-lessons.sh" > "$WORK/cut2.out" 2>&1
  expect "the system bash gives the same cut output" cmp -s "$WORK/cut.out" "$WORK/cut2.out"
fi

# 3. the generated test, with the scripts and notes as stamped
bash "$R/scripts/test-agent-lessons.sh" > "$WORK/gen.out" 2>&1; rc=$?
expect "the generated test passes" [ "$rc" -eq 0 ]
expect "the generated test ran its cases ($(grep -c '^PASS' "$WORK/gen.out"))" [ "$(grep -c '^PASS' "$WORK/gen.out")" -ge 15 ]
if [ -x /bin/bash ]; then
  /bin/bash "$R/scripts/test-agent-lessons.sh" > "$WORK/gen2.out" 2>&1
  expect "the generated test passes under the system bash" [ $? -eq 0 ]
fi
# the generated test goes red on a broken index
RB="$(mktemp -d "$WORK/rb.XXXXXX")"; cp -R "$R/scripts" "$R/.claude" "$RB/"
printf '\n- [Dead](dead-note.md): a link to a note that does not exist.\n' >> "$RB/.claude/memory/MEMORY.md"
bash "$RB/scripts/test-agent-lessons.sh" > "$WORK/red1.out" 2>&1; rc=$?
expect "a dead index link turns the generated test red" [ "$rc" -ne 0 ]
RC2="$(mktemp -d "$WORK/rc.XXXXXX")"; cp -R "$R/scripts" "$R/.claude" "$RC2/"
printf 'no frontmatter here\n' > "$RC2/.claude/memory/ci-sets-ci-true.md"
bash "$RC2/scripts/test-agent-lessons.sh" > "$WORK/red2.out" 2>&1; rc=$?
expect "a note without frontmatter turns the generated test red" [ "$rc" -ne 0 ]
RD="$(mktemp -d "$WORK/rd.XXXXXX")"; cp -R "$R/scripts" "$R/.claude" "$RD/"
sed 's/exit 0/exit 1/g' "$RD/scripts/agent-lessons.sh" > "$RD/scripts/x.sh" && mv "$RD/scripts/x.sh" "$RD/scripts/agent-lessons.sh"
bash "$RD/scripts/test-agent-lessons.sh" > "$WORK/red3.out" 2>&1; rc=$?
expect "a script that exits non-zero turns the generated test red" [ "$rc" -ne 0 ]

# 4. the seed notes
for n in $NOTES; do
  f="$TPL/files/.claude/memory/$n.md"
  fm="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f {print}' "$f")"
  expect "$n: line 1 is ---" [ "$(head -n 1 "$f")" = "---" ]
  expect "$n: name matches the file name" bash -c "printf '%s\n' \"\$1\" | grep -qx 'name: $n'" _ "$fm"
  expect "$n: has a description" bash -c "printf '%s\n' \"\$1\" | grep -q '^description: .'" _ "$fm"
  expect "$n: description is one sentence under 200 characters" bash -c "[ \$(printf '%s\n' \"\$1\" | grep '^description: ' | wc -c | tr -d ' ') -lt 215 ]" _ "$fm"
  expect "$n: under 1,200 characters ($(chars "$f"))" [ "$(chars "$f")" -lt 1200 ]
  expect "$n: states why and how to apply" bash -c "grep -q '^\*\*Why:\*\*' '$f' && grep -q '^\*\*How to apply:\*\*' '$f'"
  expect "$n: is listed in the index" grep -qF "]($n.md)" "$TPL/files/.claude/memory/MEMORY.md"
  expect "$n: holds no @-mention and no email address" bash -c "! grep -q '@' '$f'"
  expect "$n: holds no date" bash -c "! grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}' '$f'"
done
expect "the index is under 8,000 characters ($(chars "$TPL/files/.claude/memory/MEMORY.md"))" [ "$(chars "$TPL/files/.claude/memory/MEMORY.md")" -lt 8000 ]
expect "the index lists exactly five notes" bash -c "[ \$(grep -c '^- \[' '$TPL/files/.claude/memory/MEMORY.md') -eq 5 ]"
G="$TPL/files/.claude/memory/guards-match-command-text.md"
expect "the guard note lists known misses" grep -q '^Known misses:' "$G"
expect "the guard note names the variable-built command and the gh api merge" bash -c "grep -q 'variables' '$G' && grep -qF 'gh api' '$G'"
expect "the guard note stays under 1,200 characters" [ "$(chars "$G")" -lt 1200 ]
expect "the guard note points at the guard test for the probe rows" grep -qF 'scripts/test-agent-guard.sh' "$G"

# 5. hygiene of the group's files
for f in "$TPL"/files/.claude/memory/*.md "$TPL/files/scripts/agent-lessons.sh" "$TPL/files/scripts/test-agent-lessons.sh" "$TPL/manifest.d/20-lessons.tsv"; do
  b="${f#"$TPL"/}"
  expect "$b has no em or en dash" bash -c "! grep -qF -e '$EM' -e '$EN' '$f'"
  expect "$b has no bare 40 or 64 digit hex string" bash -c "! grep -Eq '(^|[^0-9a-fA-F])([0-9a-fA-F]{40}|[0-9a-fA-F]{64})([^0-9a-fA-F]|\$)' '$f'"
done
for f in "$TPL/files/scripts/agent-lessons.sh" "$TPL/files/scripts/test-agent-lessons.sh"; do
  b="${f#"$TPL"/}"
  expect "$b uses no python3, mapfile, readarray, grep -P or sed -r" bash -c "! grep -Eq 'python3|mapfile|readarray|grep -[a-zA-Z]*P|sed -[a-zA-Z]*r' '$f'"
  expect "$b parses under bash -n" bash -n "$f"
  if command -v shellcheck >/dev/null 2>&1; then
    expect "$b is shellcheck clean at warning level" shellcheck -S warning "$f"
  fi
done

# 6. idempotent, and repo edits to seed files never drift
OUT="$(bash lib/stamp.sh --only lessons "$R" 2>&1)"
expect "a second run prints only unchanged" bash -c "! printf '%s\n' \"\$1\" | grep -vq '^unchanged: '" _ "$OUT"
printf -- '- [Mine](mine.md): a lesson of this repo.\n' >> "$R/.claude/memory/MEMORY.md"
printf -- '---\nname: mine\ndescription: a repo note.\n---\n\nbody\n' > "$R/.claude/memory/mine.md"
bash lib/stamp.sh --only lessons --check "$R" >/dev/null 2>&1
expect "--check stays clean after the repo edits the index and adds a note" [ $? -eq 0 ]
bash "$R/scripts/test-agent-lessons.sh" > "$WORK/gen3.out" 2>&1
expect "the generated test accepts a repo's own note" [ $? -eq 0 ]

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
