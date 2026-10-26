#!/usr/bin/env bash
# test-board-add.sh -- `backlog.sh add`, the one verb that mints NEW board rows.
#
# Proves:
#   AC1  eight concurrent adds mint eight unique ids and every row lands (the board lock
#        covers the whole read -> mint -> write, including the verbs that used to hand-edit)
#   AC2  the row takes the target table's OWN column count: 4-column and 6-column boards both
#        get well-formed rows, and `backlog.sh lint` follows the header, not a hardcoded 4
#   AC3  a mixed board (6-column Active queue + a 4-column intake section) writes each section
#        in its own shape; --section creates a missing section from the primary header
#   AC4  pipes in a title are escaped, newlines flattened, a leading-dash title survives `--`,
#        too many --mid values and an unknown status are refused with nothing written
#   AC5  ids follow the board: its own prefix, zero-pad width of the widest padded id
#   AC6  `board capture` and `board promote` write through the same verb (6-column board
#        gets 6-cell rows from both)
#   AC7  `bin/board add --backlog-file` reaches the verb
#   AC8  hostile status, section and title text cannot forge rows, headings or cells
#   AC10 board-normalize pads short rows without losing an id; the kit board lints clean
#   AC9  suffixed headings, legend tables, ids above 999, git-history floor, batch order
#
# Run: bash tests/test-board-add.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BL="$KIT_DIR/lib/board/backlog.sh"
BOARD_SH="$KIT_DIR/lib/board/board.sh"
ADD_BACKLOG="$KIT_DIR/lib/board/bin/add-backlog"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3"; echo $?)"; }
chk_not_has() { chk "$1" "$(printf '%s' "$2" | grep -qF -- "$3"; [ $? -ne 0 ]; echo $?)"; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-board-add-test.XXXXXX")" || exit 1
TMPD="$(cd "$TMPD" && pwd)"
trap 'rm -rf "$TMPD"' EXIT

bl() { BACKLOG_FILE="$1" bash "$BL" "${@:2}"; }

new4() {
  printf '# B\n\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n| ID-1 | a | n | queued |\n' > "$1"
}
new6() {
  printf '# B\n\n## Active queue\n\n| ID | Title | Source | Target artifact | Lane | Status |\n|----|-------|--------|-----------------|------|--------|\n| ID-006 | a | s | t | normal | shipped |\n' > "$1"
}

# ============================================================
echo "== AC1: eight concurrent adds mint eight unique ids, none lost =="
# ============================================================
B="$TMPD/one.md"; new4 "$B"
for i in 1 2 3 4 5 6 7 8; do
  ( bl "$B" add "race $i" --notes "n$i" >"$TMPD/one.$i.out" 2>"$TMPD/one.$i.err" ) &
done
wait
minted="$(cat "$TMPD"/one.*.out | grep -oE '[0-9]+' | sort -n | uniq | grep -c .)"
chk "eight adds, eight unique ids" "$([ "$minted" -eq 8 ]; echo $?)"
chk "board holds nine rows (the original plus eight)" \
    "$([ "$(grep -cE '^\| ID-[0-9]+ \|' "$B")" -eq 9 ]; echo $?)"
chk "ids start past the existing ID-1 (highest minted is ID-9)" "$([ "$(grep -oE '^\| ID-[0-9]+' "$B" | grep -oE '[0-9]+' | sort -n | tail -1)" -eq 9 ]; echo $?)"
chk "lint is clean after the race" "$([ "$(bl "$B" lint)" = "(no lint findings)" ]; echo $?)"

# ============================================================
echo "== AC2: the row follows the table's column count; lint follows the header =="
# ============================================================
B4="$TMPD/c4.md"; new4 "$B4"
id4="$(bl "$B4" add "four col" --notes "note")"
chk "4-col: prints the minted id" "$([ "$id4" = "ID-2" ]; echo $?)"
chk_has "4-col: row has 4 cells" "$(cat "$B4")" "| ID-2 | four col | note | queued |"
chk "4-col: lint clean" "$([ "$(bl "$B4" lint)" = "(no lint findings)" ]; echo $?)"

B6="$TMPD/c6.md"; new6 "$B6"
id6="$(bl "$B6" add "six col" --mid "freeform intake" --mid "SPEC-1" --mid "normal")"
chk "6-col: zero-pad width follows the board (ID-006 -> ID-007)" "$([ "$id6" = "ID-007" ]; echo $?)"
chk_has "6-col: row has 6 cells" "$(cat "$B6")" "| ID-007 | six col | freeform intake | SPEC-1 | normal | queued |"
chk "6-col: lint clean (not judged against a hardcoded 4)" "$([ "$(bl "$B6" lint)" = "(no lint findings)" ]; echo $?)"
bl "$B6" add "notes only" --notes "just notes" >/dev/null
chk_has "6-col: --notes alone leaves the later cells empty" "$(cat "$B6")" "| notes only | just notes |  |  | queued |"
chk "6-col: lint still clean" "$([ "$(bl "$B6" lint)" = "(no lint findings)" ]; echo $?)"

# a 4-cell row under a 6-col header is what the old writers produced; lint now says so
printf '| ID-050 | legacy | n | queued |\n' >> "$B6"
out="$(bl "$B6" lint)"
chk_has "lint: a 4-cell row under a 6-col header is flagged against 6" "$out" "expected 6 cells, found 4"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-9 | a | n | queued |\n' > "$TMPD/lint4.md"
chk "lint: a clean 4-col table is still clean" "$([ "$(bl "$TMPD/lint4.md" lint)" = "(no lint findings)" ]; echo $?)"

# ============================================================
echo "== AC3: mixed board, per-section shape; --section creates from the primary header =="
# ============================================================
BM="$TMPD/mixed.md"; new6 "$BM"
printf '\n### Conversation intake\n\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n| ID-001 | old | n | queued |\n' >> "$BM"
idm="$(bl "$BM" add "intake row" --notes "from intake" --section "### Conversation intake")"
chk_has "section: the 4-col intake table gets a 4-cell row" "$(cat "$BM")" "| $idm | intake row | from intake | queued |"
idq="$(bl "$BM" add "queue row" --mid s --mid t --mid tiny)"
chk_has "section: the primary 6-col table gets a 6-cell row" "$(cat "$BM")" "| $idq | queue row | s | t | tiny | queued |"
chk "section: lint clean on the mixed board" "$([ "$(bl "$BM" lint)" = "(no lint findings)" ]; echo $?)"
ids2="$(bl "$BM" add "new section row" --notes x --section "### Fresh section")"
chk_has "section: a missing section is created" "$(cat "$BM")" "### Fresh section"
fresh="$(sed -n '/^### Fresh section/,$p' "$BM")"
chk_has "section: the new table copies the primary 6-col header" "$fresh" "| ID | Title | Source | Target artifact | Lane | Status |"
chk_has "section: its row is 6 cells" "$fresh" "| $ids2 | new section row | x |  |  | queued |"

# ============================================================
echo "== AC4: escaping and refusals =="
# ============================================================
B="$TMPD/esc.md"; new4 "$B"
id="$(bl "$B" add "pipe | and
newline" --notes "a | b")"
chk_has "escape: pipes are escaped" "$(cat "$B")" "| $id | pipe \\| and newline | a \\| b | queued |"
chk "escape: lint clean" "$([ "$(bl "$B" lint)" = "(no lint findings)" ]; echo $?)"
id="$(bl "$B" add -- "--leading dash")"
chk_has "dash: a title starting with -- survives after the end-of-flags marker" "$(cat "$B")" "| $id | --leading dash |"
before="$(shasum -a 256 "$B" | cut -d' ' -f1)"
bl "$B" add "too many" --mid a --mid b >/dev/null 2>"$TMPD/err1"; rc=$?
chk "refuse: too many --mid values exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
bl "$B" add "bad state" --status nonsense >/dev/null 2>"$TMPD/err2"; rc2=$?
chk "refuse: unknown status exits 64" "$([ "$rc2" -eq 64 ]; echo $?)"
chk_has "refuse: the status error names the legal states" "$(cat "$TMPD/err2")" "states:"
chk "refuse: nothing written by either refusal" "$([ "$(shasum -a 256 "$B" | cut -d' ' -f1)" = "$before" ]; echo $?)"
bl "$B" add >/dev/null 2>&1; chk "refuse: no title exits 64" "$([ $? -eq 64 ]; echo $?)"
id="$(bl "$B" add "claimed one" --status claimed)"
chk_has "status: a legal non-default status is written" "$(cat "$B")" "| $id | claimed one |  | claimed |"

# ============================================================
echo "== AC5: the board's own prefix and padding =="
# ============================================================
BP="$TMPD/prefix.md"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| WS-12 | a | n | queued |\n| WS-9 | b | n | queued |\n' > "$BP"
chk "prefix: mints in the board's own prefix, past the max" "$([ "$(bl "$BP" add x)" = "WS-13" ]; echo $?)"
BE="$TMPD/empty.md"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n' > "$BE"
chk "empty board: first id is ID-001" "$([ "$(bl "$BE" add x)" = "ID-001" ]; echo $?)"

# ============================================================
echo "== AC6: capture and promote write through the same verb =="
# ============================================================
BC="$TMPD/cap.md"; new6 "$BC"
out="$(bash "$BOARD_SH" capture "captured thing" -b "why" --backlog-file "$BC" 2>/dev/null)"
chk_has "capture: reports the id" "$out" "filed: ID-007"
chk_has "capture: a 6-col board gets a 6-cell row" "$(cat "$BC")" "| ID-007 | captured thing | why |  |  | queued |"

TODAY="$(date +%Y-%m-%d)"
ST="$TMPD/backlog-staging.md"
cat > "$ST" <<EOF
# Backlog staging

## [staged] Promote me
- Intent: a real reason to do this
- Approach: do it
- Tags: #u-mid #f-hi
- Home: dwarves-kit
- Source: session $TODAY
EOF
pout="$(BACKLOG_STAGE_BACKLOG="$BC" BACKLOG_STAGE_STAGING="$ST" python3 "$ADD_BACKLOG" 1 2>&1)"
chk_has "promote: reports the id past capture's" "$pout" "promoted ID-008"
grep -q '^### Conversation intake' "$BC"; chk "promote: intake section created on the 6-col board" "$?"
intake="$(sed -n '/^### Conversation intake/,$p' "$BC")"
chk_has "promote: the section table copies the board's 6-col header" "$intake" "| ID | Title | Source | Target artifact | Lane | Status |"
chk_has "promote: its row has 6 cells" "$intake" "| ID-008 | Promote me | Intent: a real reason to do this . Approach: do it #u-mid #f-hi -> dwarves-kit (session $TODAY) |  |  | queued |"
chk "promote: lint clean on the board after both writers" "$([ "$(bl "$BC" lint)" = "(no lint findings)" ]; echo $?)"

# ============================================================
echo "== AC8: hostile input cannot forge rows, headings or cells =="
# ============================================================
BH="$TMPD/hostile.md"; new4 "$BH"
before="$(shasum -a 256 "$BH" | cut -d' ' -f1)"
bl "$BH" add --status $'queued\n| ID-999 | forged | x | done' -- t >/dev/null 2>&1; rc=$?
chk "status with a newline and a forged row is refused (exit 64)" "$([ "$rc" -eq 64 ]; echo $?)"
bl "$BH" add --status 'queued | ID-998 | forged | x | done' -- t >/dev/null 2>&1; rc=$?
chk "status with pipes is refused (exit 64)" "$([ "$rc" -eq 64 ]; echo $?)"
bl "$BH" add --section $'## x\n## [staged] y' -- t >/dev/null 2>&1; rc=$?
chk "a section with an embedded newline is refused (exit 64)" "$([ "$rc" -eq 64 ]; echo $?)"
bl "$BH" add --section '| ID-77777 | forged | x | done |' -- t >/dev/null 2>&1; rc=$?
chk "a section that is table syntax is refused (exit 64)" "$([ "$rc" -eq 64 ]; echo $?)"
chk "none of the four refusals wrote anything" "$([ "$(shasum -a 256 "$BH" | cut -d' ' -f1)" = "$before" ]; echo $?)"
bl "$BH" add -- '--status foo' >/dev/null 2>&1; rc=$?
chk_has "a title after -- may contain flag words" "$(cat "$BH")" "| --status foo |"
tfile="$TMPD/marker"
bl "$BH" add --notes '$(touch '"$tfile"')' -- '`touch '"$tfile"'`' >/dev/null 2>&1
chk "shell metacharacters in single quotes stay inert" "$([ ! -e "$tfile" ]; echo $?)"

# ============================================================
echo "== AC9: section matching, table choice, ids, history floor =="
# ============================================================
BS="$TMPD/suffix.md"; new4 "$BS"
printf '\n### Conversation intake (auto)\n\n| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-5 | old | n | queued |\n' >> "$BS"
bl "$BS" add --notes n --section "### Conversation intake" -- "joins the suffixed section" >/dev/null
chk "a heading with a suffix is the same section (no second section made)" "$([ "$(grep -c '^### Conversation intake' "$BS")" -eq 1 ]; echo $?)"
chk_has "the row landed under the suffixed heading" "$(sed -n '/^### Conversation intake/,$p' "$BS")" "joins the suffixed section"

BLEG="$TMPD/legend.md"
printf '# B\n\n| Key | Meaning |\n|---|---|\n| u | urgent |\n\n| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-3 | a | n | queued |\n' > "$BLEG"
bl "$BLEG" add -- "lands in the ID table" >/dev/null
chk "a legend table before the ID table is skipped" "$([ "$(grep -n 'lands in the ID table' "$BLEG" | cut -d: -f1)" -gt "$(grep -n '^| ID | Item' "$BLEG" | cut -d: -f1)" ]; echo $?)"

B1="$TMPD/big.md"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-999 | a | n | queued |\n' > "$B1"
chk "ids above 999 keep counting (ID-999 -> ID-1000)" "$([ "$(bl "$B1" add x)" = "ID-1000" ]; echo $?)"

BN="$TMPD/notable.md"; printf '# nothing here\n' > "$BN"
bl "$BN" add x >/dev/null 2>&1; rc=$?
chk "a board with no table refuses a plain add" "$([ "$rc" -ne 0 ]; echo $?)"
idn="$(bl "$BN" add --section '### New' -- x 2>/dev/null)"
chk_has "a section add on a table-less board creates a default table" "$(cat "$BN")" "| $idn | x |"

BO="$TMPD/order.md"; new4 "$BO"
python3 - "$KIT_DIR/lib/board" "$BO" <<'ORDER'
import sys
sys.path.insert(0, sys.argv[1])
import board_add
board_add.add_rows(sys.argv[2], [{"title": "first"}, {"title": "second"}, {"title": "third"}])
ORDER
chk "a batch lands newest on top (third, second, first)" "$([ "$(grep -E '^\| ID-[0-9]+ \| (first|second|third) ' "$BO" | awk -F'|' '{gsub(/ /,"",$3); printf "%s,", $3}')" = "third,second,first," ]; echo $?)"

BG="$TMPD/gitfloor"; mkdir -p "$BG"
git -C "$BG" init -q 2>/dev/null
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-50 | gone | n | queued |\n' > "$BG/BACKLOG.md"
git -C "$BG" -c user.name=t -c user.email=t@example.org add BACKLOG.md
git -C "$BG" -c user.name=t -c user.email=t@example.org commit -q -m seed 2>/dev/null
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n' > "$BG/BACKLOG.md"
chk "git history raises the mint floor (a deleted ID-50 is never reused)" "$([ "$(bl "$BG/BACKLOG.md" add x)" = "ID-051" ]; echo $?)"

# ============================================================
echo "== AC7: the public door, bin/board add --backlog-file =="
# ============================================================
BB="$TMPD/door.md"; new4 "$BB"
did="$(bash "$KIT_DIR/bin/board" add "via the door" --notes "dn" --backlog-file "$BB")"
chk "door: prints the minted id" "$([ "$did" = "ID-2" ]; echo $?)"
chk_has "door: the row is written" "$(cat "$BB")" "| ID-2 | via the door | dn | queued |"

# ============================================================
echo "== AC10: board-normalize pads short rows, keeps every id, is idempotent =="
# ============================================================
NORM="$KIT_DIR/lib/board/bin/board-normalize"
BZ="$TMPD/short.md"
printf '# B\n\n| ID | Title | Source | Target artifact | Lane | Status |\n|----|-------|--------|-----------------|------|--------|\n| ID-1 | full | s | t | normal | queued |\n| ID-2 | short | notes with \\| pipe | claimed |\n| ID-3 | five | a | b | shipped |\n\n| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-4 | four | n | queued |\n\nprose | with | pipes\n' > "$BZ"
python3 "$NORM" --check "$BZ" >/dev/null; rc=$?
chk "--check exits 1 and writes nothing while a row is short" "$([ "$rc" -eq 1 ] && grep -q '^| ID-2 | short | notes with \\| pipe | claimed |$' "$BZ"; echo $?)"
out="$(python3 "$NORM" "$BZ")"
chk_has "the counts line shows 4 ids before and after" "$out" "row ids before: 4, after: 4, padded: 2"
chk_has "a 4-cell row spreads into the first middle cell" "$(cat "$BZ")" "| ID-2 | short | notes with \\| pipe |  |  | claimed |"
chk_has "a 5-cell row keeps its cells in order" "$(cat "$BZ")" "| ID-3 | five | a | b |  | shipped |"
chk_has "the 4-column table after the blank line is untouched" "$(cat "$BZ")" "| ID-4 | four | n | queued |"
chk_has "prose with pipes is untouched" "$(cat "$BZ")" "prose | with | pipes"
chk "lint is clean afterwards" "$([ "$(bl "$BZ" lint)" = "(no lint findings)" ]; echo $?)"
before="$(shasum -a 256 "$BZ" | cut -d' ' -f1)"
python3 "$NORM" "$BZ" >/dev/null; python3 "$NORM" --check "$BZ" >/dev/null
chk "a second run changes nothing and --check exits 0" "$([ "$?" -eq 0 ] && [ "$(shasum -a 256 "$BZ" | cut -d' ' -f1)" = "$before" ]; echo $?)"
# A fixture board in the kit's own shape (the real one is not in the public tree).
FX="$TMPD/fixture-board.md"
printf '# Task Backlog\n\n## Active queue\n\n| ID | Title | Source | Target artifact | Lane | Status |\n|----|-------|--------|-----------------|------|--------|\n| ID-2 | second | s | t | normal | shipped [#2] |\n| ID-1 | first | s | t | normal | queued |\n' > "$FX"
chk "a well-formed fixture board has no shape findings" "$([ "$(bl "$FX" lint)" = "(no lint findings)" ]; echo $?)"

echo ""
echo "== no default board (a public kit clone has no _meta/): one line, never a crash =="
NOBOARD="$TMPD/absent/BACKLOG.md"
out="$(bl "$NOBOARD" board 2>&1)"; rc=$?
chk "a verb that needs the default board exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "and names the missing file on one line" "$out" "no board at $NOBOARD"
chk "and prints exactly one line" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ]; echo $?)"
chk "states needs no board" "$([ "$(bl "$NOBOARD" states | head -1)" = "queued" ]; echo $?)"
chk "lint <file> reads its own file, not the default board" "$([ "$(bl "$NOBOARD" lint "$FX")" = "(no lint findings)" ]; echo $?)"
printf '| ID-3 | dup | s | t | normal | queued |\n| ID-3 | dup | s | t | normal | shipped |\n' >> "$FX"
chk_has "dedupe-all <file> sweeps its own file with no default board" "$(bl "$NOBOARD" dedupe-all "$FX" 2>&1)" "ID-3"

echo ""
echo "== $TOTAL run, $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
