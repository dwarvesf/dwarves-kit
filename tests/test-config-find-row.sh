#!/usr/bin/env bash
# test-config-find-row.sh -- pins `_find_row` in lib/config/config.sh against a fixture registry.
# `_find_row <key>` prints the first registry row whose env-var OR kit.toml-key cell equals
# <key>. It is one awk pass that must keep the split-and-trim rules of `_row_get`. Each row's Doc
# cell is its own id (r1, r2, ...), so an assert names the row that won. The fixture covers:
# a duplicate key where the first row wins, empty and `-` cells, an escaped pipe inside a cell,
# tab padding, a short row, an HTML comment line, cells that look numeric (compared as strings,
# never as numbers), and a last row with no trailing newline.
# Run: bash tests/test-config-find-row.sh
set -uo pipefail
KIT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REG="$WORK/module-registry.md"

{
  printf '%s\n' '# fixture module-registry.md for test-config-find-row.sh'
  printf '%s\n' '## Env <-> key registry'
  printf '%s\n' '| Env var | kit.toml key | Default | Status | Module | Doc |'
  printf '%s\n' '|---|---|---|---|---|---|'
  printf '%s\n' '| A_ENV | a.key | 1 | live | m | r1 |'
  printf '%s\n' '| A_ENV | dup.key | 2 | live | m | r2 |'
  printf '%s\n' '| B_ENV | a.key | 3 | live | m | r3 |'
  printf '%s\n' '| - | dash.key | x | live | m | r4 |'
  printf '%s\n' '|  | empty.key | x | live | m | r5 |'
  printf '%s\n' '| PIPE_ENV | pipe.key | x | live | m | repo\|scripts\|skills |'
  printf '%s\n' '| E\|ENV | esc.key | x | live | m | r7 |'
  printf '|\tTAB_ENV\t|\ttab.key\t| x | live | m | r8 |\n'
  printf '%s\n' '| SHORT_ENV | short.key'
  printf '%s\n' '| 1.0 | n.a | x | live | m | r10 |'
  printf '%s\n' '| 01 | n.b | x | live | m | r11 |'
  printf '%s\n' '| 1 | n.c | x | live | m | r12 |'
  printf '%s\n' '| BS_ENV | b\s.key | x | live | m | r13 |'
  printf '%s\n' '<!-- | COMMENT_ENV | comment.key | x | live | m | r14 | -->'
  printf '%s' '| LAST_ENV | last.key | x | live | m | r15 |'
} > "$REG"

CONFIG_REGISTRY_FILE="$REG"; export CONFIG_REGISTRY_FILE
set --
# shellcheck source=lib/config/config.sh
source "$KIT_DIR/lib/config/config.sh" >/dev/null 2>&1
set +e

# winner <key> <doc-id>: the lookup succeeds and the winning row's Doc cell is <doc-id>.
winner() {
  local row rc
  row="$(_find_row "$1")"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(_row_get "$row" 6)" = "$2" ]
}
# absent <key>: the lookup fails with no output.
absent() {
  local out rc
  out="$(_find_row "$1")"; rc=$?
  [ "$rc" -ne 0 ] && [ -z "$out" ]
}

chk "env var column matches, first of two rows with that env var wins" "$(winner A_ENV r1; echo $?)"
chk "toml key column matches, first of two rows with that key wins" "$(winner a.key r1; echo $?)"
chk "a later row with a repeated env var is still reachable by its own key" "$(winner dup.key r2; echo $?)"
chk "a row whose toml key repeats an earlier row is reachable by its env var" "$(winner B_ENV r3; echo $?)"
chk "a literal - cell matches the key -" "$(winner - r4; echo $?)"
chk "an empty env cell does not hide the toml key" "$(winner empty.key r5; echo $?)"
chk "an empty key matches the first row with an empty cell, as the old loop did" "$(winner '' r5; echo $?)"
chk "a Doc cell keeps its escaped pipes as literal pipes" "$(winner pipe.key 'repo|scripts|skills'; echo $?)"
chk "an escaped pipe in the env cell matches as a literal pipe" "$(winner 'E|ENV' r7; echo $?)"
chk "an escaped pipe does not open a phantom cell" "$({ absent E && absent ENV; }; echo $?)"
chk "tab padding is trimmed on the env cell" "$(winner TAB_ENV r8; echo $?)"
chk "tab padding is trimmed on the toml key cell" "$(winner tab.key r8; echo $?)"
chk "a short row matches by env var" "$(winner SHORT_ENV ''; echo $?)"
chk "a short row matches by toml key" "$(winner short.key ''; echo $?)"
chk "1.0 matches its own row as a string" "$(winner 1.0 r10; echo $?)"
chk "01 matches its own row as a string" "$(winner 01 r11; echo $?)"
chk "1 skips the earlier 1.0 and 01 rows: strings, not numbers" "$(winner 1 r12; echo $?)"
chk "1.00 and +1 match no row" "$({ absent 1.00 && absent +1; }; echo $?)"
chk "a backslash in a key is compared verbatim" "$(winner 'b\s.key' r13; echo $?)"
chk "the dot in a key is not a wildcard" "$(absent aXkey; echo $?)"
chk "a key inside an HTML comment line is not a row" "$({ absent COMMENT_ENV && absent comment.key; }; echo $?)"
chk "the last row without a trailing newline is found by env var" "$(winner LAST_ENV r15; echo $?)"
chk "the last row without a trailing newline is found by toml key" "$(winner last.key r15; echo $?)"
chk "an unknown key fails with no output" "$(absent NO_SUCH_KEY; echo $?)"
chk "the whole raw row is printed, unchanged" "$([ "$(_find_row A_ENV)" = '| A_ENV | a.key | 1 | live | m | r1 |' ]; echo $?)"

[ "$fail" -eq 0 ] && echo "PASS: _find_row matches the pinned lookup rules" || { echo "SOME TESTS FAILED"; exit 1; }
