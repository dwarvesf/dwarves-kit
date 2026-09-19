#!/usr/bin/env bash
# test-board-run.sh -- `board run <ID>`: the single-board-row dispatch path
# (lib/board/board-run.sh + the `row` verb it composes on in lib/board/backlog.sh).
#
# Proves:
#   AC1  board run scaffolds a minimal megadir under the repo's default
#        _meta/megagoals/<id-slug>/: ROADMAP.md with one `- [ ] SG-01 <item> , auto`
#        line, POINTER_PROMPT.md seeded from the row's Item + Notes, a goals/01-*.md
#        contract (Model: + **Branch:** headers orchestrate reads), HANDOFF.md and
#        DECISIONS.md stubs
#   AC2  orchestrate.sh next <dir> reads the scaffolded SG row (id + auto policy) --
#        dry-run-level proof the megadir rides the existing driver, no claude launch
#   AC3  the run prints the exact `orchestrate.sh run <dir>` command
#   AC4  --dir <path> wins the megadir resolution outright
#   AC5  a megagoal_root: hint in the repo's CLAUDE.md beats auto-detect + default
#   AC6  an in-use docs/megagoals root is detected over the _meta/megagoals default
#   AC7  an in-use .claude/goals megadir shape is detected (the kit's own convention)
#   AC8  --exec composes the launch: `-- --dry-run` forwards to
#        `orchestrate.sh run <dir> --dry-run` (plan printed, still no claude)
#   AC9  a second `board run` is idempotent: existing files are kept verbatim,
#        never overwritten
#   AC10 the 6-col row shape (Title|Source|Target|Lane|Status) reads through
#        `backlog.sh row` with every middle cell joined into Notes
#
#   NC-a absent ID            -> exit non-zero, nothing scaffolded
#   NC-b duplicate-ID rows    -> exit non-zero (dedupe first), nothing scaffolded
#   NC-c no BACKLOG.md        -> exit non-zero
#   NC-d terminal-state row   -> scaffolds anyway with a loud WARN on stderr
#
# Run: bash tests/test-board-run.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARD="$KIT_DIR/bin/board"
ORCH="$KIT_DIR/lib/queue/orchestrate.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-board-run.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() {  # <dir> -- a git repo with a _meta/BACKLOG.md
  local d="$1"
  mkdir -p "$d/_meta"
  git init -q "$d"; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  cat > "$d/_meta/BACKLOG.md" <<'BOARD'
# Backlog

## Active queue

| ID | Item | Notes & source | Status |
|----|------|----------------|--------|
| ID-902 | board run row dispatch #u-mid | Intent: one board row rides orchestrate machinery; scaffold a megadir and print the run command. lane=normal. | queued |
| ID-903 | done already | note | shipped [PR #1] |
| ID-904 | dup one | a | queued |
| ID-904 | dup two | b | queued |
BOARD
}

echo "== AC1-AC3: scaffold, orchestrate next, printed run command =="
R1="$TMP/repo1"; mkrepo "$R1"
out="$(cd "$R1" && bash "$BOARD" run ID-902 --backlog-file "$R1/_meta/BACKLOG.md" 2>&1)"; rc=$?
assert "board run exits 0 on a queued row" "$rc"
D="$R1/_meta/megagoals/id-902-board-run-row-dispatch"
assert "megadir resolves under _meta/megagoals/<id-slug>" "$([ -d "$D" ]; echo $?)"
assert "ROADMAP carries the single auto SG line" "$(grep -qE '^- \[ \] SG-01 board run row dispatch #u-mid , auto' "$D/ROADMAP.md"; echo $?)"
assert "ROADMAP puts the SG line under a ## Sub-goals section" "$(awk '/^## Sub-goals/{f=1} f&&/^- \[ \] SG-01/{print;exit}' "$D/ROADMAP.md" | grep -q .; echo $?)"
assert "POINTER_PROMPT seeds the item" "$(grep -qF 'board run row dispatch' "$D/POINTER_PROMPT.md"; echo $?)"
assert "POINTER_PROMPT seeds the notes verbatim" "$(grep -qF 'scaffold a megadir and print the run command' "$D/POINTER_PROMPT.md"; echo $?)"
assert "goals/01-*.md exists" "$(ls "$D"/goals/01-*.md >/dev/null 2>&1; echo $?)"
assert "goal file carries a routable Model: line" "$(grep -qE '^Model: (haiku|sonnet|opus)$' "$D"/goals/01-*.md; echo $?)"
assert "goal file carries a **Branch:** header (rid telemetry)" "$(grep -qE '^\*\*Branch:\*\*' "$D"/goals/01-*.md; echo $?)"
assert "HANDOFF.md stub exists" "$([ -f "$D/HANDOFF.md" ]; echo $?)"
assert "DECISIONS.md stub exists" "$([ -f "$D/DECISIONS.md" ]; echo $?)"
nx="$(bash "$ORCH" next "$D" 2>/dev/null)"
assert "orchestrate next reads the SG row" "$(printf '%s' "$nx" | grep -q '^SG-01'; echo $?)"
assert "orchestrate next reads the auto policy" "$(printf '%s' "$nx" | grep -q $'\tauto$'; echo $?)"
assert "the printed command is orchestrate.sh run <dir>" "$(printf '%s' "$out" | grep -qE "orchestrate\.sh run .*/id-902-board-run-row-dispatch"; echo $?)"

echo "== AC4: --dir wins outright =="
out="$(cd "$R1" && bash "$BOARD" run ID-902 --backlog-file "$R1/_meta/BACKLOG.md" --dir "$TMP/explicit-dir" 2>&1)"
assert "--dir scaffolds into the named dir" "$(grep -qE '^- \[ \] SG-01' "$TMP/explicit-dir/ROADMAP.md"; echo $?)"

echo "== AC5: megagoal_root: CLAUDE.md hint =="
R2="$TMP/repo2"; mkrepo "$R2"
printf 'megagoal_root: custom/megas\n' > "$R2/CLAUDE.md"
(cd "$R2" && bash "$BOARD" run ID-902 --backlog-file "$R2/_meta/BACKLOG.md" >/dev/null 2>&1)
assert "megagoal_root hint redirects the scaffold" "$([ -f "$R2/custom/megas/id-902-board-run-row-dispatch/ROADMAP.md" ]; echo $?)"

echo "== AC6: in-use docs/megagoals detected =="
R3="$TMP/repo3"; mkrepo "$R3"
mkdir -p "$R3/docs/megagoals/prior-mega"; echo "# prior" > "$R3/docs/megagoals/prior-mega/ROADMAP.md"
(cd "$R3" && bash "$BOARD" run ID-902 --backlog-file "$R3/_meta/BACKLOG.md" >/dev/null 2>&1)
assert "existing docs/megagoals convention wins over the default" "$([ -f "$R3/docs/megagoals/id-902-board-run-row-dispatch/ROADMAP.md" ]; echo $?)"

echo "== AC7: in-use .claude/goals megadir shape detected =="
R4="$TMP/repo4"; mkrepo "$R4"
mkdir -p "$R4/.claude/goals/prior-mega"; echo "# prior" > "$R4/.claude/goals/prior-mega/ROADMAP.md"
touch "$R4/.claude/goals/a-single-goal-draft.md"   # drafts alone must NOT claim the shape
(cd "$R4" && bash "$BOARD" run ID-902 --backlog-file "$R4/_meta/BACKLOG.md" >/dev/null 2>&1)
assert ".claude/goals/*/ROADMAP.md marks the kit convention" "$([ -f "$R4/.claude/goals/id-902-board-run-row-dispatch/ROADMAP.md" ]; echo $?)"
R5="$TMP/repo5"; mkrepo "$R5"
mkdir -p "$R5/.claude/goals"; touch "$R5/.claude/goals/draft-only.md"
(cd "$R5" && bash "$BOARD" run ID-902 --backlog-file "$R5/_meta/BACKLOG.md" >/dev/null 2>&1)
assert "drafts-only .claude/goals does NOT claim the shape (falls to default)" "$([ -f "$R5/_meta/megagoals/id-902-board-run-row-dispatch/ROADMAP.md" ]; echo $?)"

echo "== AC8: --exec composes orchestrate.sh run (args after -- forward) =="
R6="$TMP/repo6"; mkrepo "$R6"
out="$(cd "$R6" && bash "$BOARD" run ID-902 --backlog-file "$R6/_meta/BACKLOG.md" --exec -- --dry-run 2>&1)"; rc=$?
assert "--exec -- --dry-run exits 0" "$rc"
assert "--exec drove orchestrate's plan (no claude launch)" "$(printf '%s' "$out" | grep -q '\[plan\] mega-goal:'; echo $?)"

echo "== AC9: idempotent re-run keeps files =="
sentinel="$D/ROADMAP.md"; printf '# OPERATOR EDIT\n' >> "$sentinel"
out="$(cd "$R1" && bash "$BOARD" run ID-902 --backlog-file "$R1/_meta/BACKLOG.md" 2>&1)"
assert "re-run reports kept, not created" "$(printf '%s' "$out" | grep -q 'kept .*ROADMAP.md'; echo $?)"
assert "re-run never overwrites an existing file" "$(grep -qF 'OPERATOR EDIT' "$sentinel"; echo $?)"

echo "== AC10: 6-col row shape reads middle cells into Notes =="
R7="$TMP/repo7"; mkdir -p "$R7/_meta"
git init -q "$R7"; git -C "$R7" config user.email t@t; git -C "$R7" config user.name t
cat > "$R7/_meta/BACKLOG.md" <<'BOARD'
| ID | Title | Source | Target | Lane | Status |
|----|-------|--------|--------|------|--------|
| DF-001 | six col item | the source cell | TBD | normal | queued |
BOARD
(cd "$R7" && bash "$BOARD" run DF-001 --backlog-file "$R7/_meta/BACKLOG.md" >/dev/null 2>&1)
D7="$R7/_meta/megagoals/df-001-six-col-item"
assert "6-col row scaffolds too" "$([ -f "$D7/ROADMAP.md" ]; echo $?)"
assert "middle cells join into Notes" "$(grep -qF 'the source cell | TBD | normal' "$D7/POINTER_PROMPT.md"; echo $?)"

echo "== NC-a: absent ID refuses =="
out="$(cd "$R1" && bash "$BOARD" run ID-999 --backlog-file "$R1/_meta/BACKLOG.md" 2>&1)"; rc=$?
assert "absent ID exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
assert "absent ID names the miss" "$(printf '%s' "$out" | grep -q 'no Active-queue row for ID-999'; echo $?)"
assert "absent ID scaffolds nothing" "$([ -z "$(find "$R1/_meta/megagoals" -name 'id-999*' 2>/dev/null)" ]; echo $?)"

echo "== NC-b: duplicate-ID rows refuse =="
out="$(cd "$R1" && bash "$BOARD" run ID-904 --backlog-file "$R1/_meta/BACKLOG.md" 2>&1)"; rc=$?
assert "duplicate ID exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
assert "duplicate ID says dedupe first" "$(printf '%s' "$out" | grep -q 'dedupe first'; echo $?)"
assert "duplicate ID scaffolds nothing" "$([ -z "$(find "$R1/_meta/megagoals" -name 'id-904*' 2>/dev/null)" ]; echo $?)"

echo "== NC-c: no BACKLOG.md refuses =="
R8="$TMP/repo8"; mkdir -p "$R8"
out="$(cd "$R8" && bash "$BOARD" run ID-001 2>&1)"; rc=$?
assert "missing board exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
assert "missing board names the file" "$(printf '%s' "$out" | grep -q 'no BACKLOG.md'; echo $?)"

echo "== NC-d: terminal-state row warns but scaffolds =="
out="$(cd "$R1" && bash "$BOARD" run ID-903 --backlog-file "$R1/_meta/BACKLOG.md" --dir "$TMP/shipped-dir" 2>&1)"; rc=$?
assert "shipped row still scaffolds (exit 0)" "$rc"
assert "shipped row warns on stderr" "$(printf '%s' "$out" | grep -q "WARN row ID-903 is 'shipped'"; echo $?)"

echo
echo "== totals: $PASS/$TOTAL passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
