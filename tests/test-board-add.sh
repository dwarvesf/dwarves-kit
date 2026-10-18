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
chk "ids start past the existing ID-1" "$([ "$(grep -cE '^\| ID-1 \|' "$B")" -eq 1 ]; echo $?)"
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
echo "== AC7: the public door, bin/board add --backlog-file =="
# ============================================================
BB="$TMPD/door.md"; new4 "$BB"
did="$(bash "$KIT_DIR/bin/board" add "via the door" --notes "dn" --backlog-file "$BB")"
chk "door: prints the minted id" "$([ "$did" = "ID-2" ]; echo $?)"
chk_has "door: the row is written" "$(cat "$BB")" "| ID-2 | via the door | dn | queued |"

echo ""
echo "== $TOTAL run, $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
