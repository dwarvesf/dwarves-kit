#!/usr/bin/env bash
# test-proof-board-only-inert.sh
# Pins the board-only rule in proof-ledger.sh classify(): a push whose COMMITTED paths are all board
# files (_meta/BACKLOG.md, BACKLOG.md, _meta/archive/BACKLOG*.md) is inert, so `check` owes no proof
# and no override, even when the checkout also carries unrelated uncommitted files. Any other path in
# the committed diff keeps today's class. An unreadable base falls back to today's behavior.
# Negative control: a copy of the lib with the board-only block stripped classifies the dirty-checkout
# fixture as behavioral again.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${PROOF_LEDGER_LIB:-$KIT/lib/gate/proof-ledger.sh}"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# build <dir> <committed-kind> <dirt-kind>
#   committed: board | boardcode | boardlookalike | none
#   dirt (left uncommitted): none | pdf | code
build() {
  local d="$1" kind="$2" dirt="$3"
  mkdir -p "$d/_meta/archive" "$d/lib" "$d/docs" "$d/sales"
  git -C "$d" init -q -b main
  git -C "$d" config user.email nobody@users.noreply.github.com; git -C "$d" config user.name nobody
  echo base > "$d/_meta/BACKLOG.md"; echo base > "$d/_meta/archive/BACKLOG-closed.md"
  echo base > "$d/BACKLOG.md"; echo base > "$d/docs/BACKLOG.md"; echo base > "$d/sales/deck.pdf"
  echo 'echo hi' > "$d/lib/y.sh"; echo 'echo hi' > "$d/_meta/board"; echo 'echo hi' > "$d/_meta/archive/BACKLOG-tool.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" checkout -qb chore/board-flip
  case "$kind" in
    board)
      echo '| DF-1 | row | shipped |' >> "$d/_meta/BACKLOG.md"
      echo '| DF-0 | old | closed |' >> "$d/_meta/archive/BACKLOG-closed.md"
      echo 'x' >> "$d/BACKLOG.md" ;;
    boardcode)
      echo '| DF-1 | row | shipped |' >> "$d/_meta/BACKLOG.md"; echo 'echo hi' >> "$d/lib/y.sh" ;;
    boardwrapper)
      echo '| DF-1 | row | shipped |' >> "$d/_meta/BACKLOG.md"; echo '# edit' >> "$d/_meta/board" ;;
    archivescript)
      echo 'echo hi' >> "$d/_meta/archive/BACKLOG-tool.sh" ;;
    lookalike)
      echo '| DF-1 | row | shipped |' >> "$d/_meta/BACKLOG.md"; echo 'x' >> "$d/docs/BACKLOG.md"; echo 'x' >> "$d/lib/BACKLOG.md" ;;
  esac
  [ "$kind" = none ] || { git -C "$d" add -A; git -C "$d" commit -qm "chore(board): mark DF-615 shipped"; }
  case "$dirt" in
    pdf)  echo dirt >> "$d/sales/deck.pdf" ;;
    code) echo 'echo dirt' >> "$d/lib/y.sh" ;;
  esac
}
fx() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit-board.XXXXXX")" || exit 1; build "$d" "$1" "$2"; printf '%s' "$d"; }
cls() { bash "$1" classify "$2" "${3:-$(git -C "$2" rev-parse main)}"; }
chk() { bash "$1" check "$2" "${3:-$(git -C "$2" rev-parse main)}" board-flip >/dev/null 2>&1; echo $?; }
expect() { # expect <label> <want> <got>
  [ "$3" = "$2" ] && pass "$1 -> $2" || fail "$1: want $2, got $3"
}

F="$(fx board none)";       expect "board-only commit, clean tree" inert "$(cls "$LIB" "$F")"
                            expect "board-only commit: check owes nothing (rc)" 0 "$(chk "$LIB" "$F")"
F="$(fx board pdf)";        expect "board-only commit, unrelated dirty pdf" inert "$(cls "$LIB" "$F")"
                            expect "board-only commit + dirty pdf: check rc" 0 "$(chk "$LIB" "$F")"
F="$(fx board code)";       expect "board-only commit, dirty code (not shipped by the push)" inert "$(cls "$LIB" "$F")"

# board + any other committed path keeps today's classification
F="$(fx boardcode none)";   expect "board + lib/y.sh commit" behavioral "$(cls "$LIB" "$F")"
                            expect "board + code: check still blocks (rc)" 1 "$(chk "$LIB" "$F")"
F="$(fx boardwrapper none)"; expect "board + _meta/board wrapper (no extension)" behavioral "$(cls "$LIB" "$F")"
F="$(fx archivescript none)"; expect "_meta/archive/BACKLOG-tool.sh is not a board file" behavioral "$(cls "$LIB" "$F")"
F="$(fx lookalike none)";   expect "board + docs/BACKLOG.md + lib/BACKLOG.md (lookalikes, still .md)" inert "$(cls "$LIB" "$F")"

# empty or unreadable diff: today's behavior
F="$(fx none none)";        expect "empty diff, clean tree" inert "$(cls "$LIB" "$F")"
F="$(fx none code)";        expect "empty committed diff, dirty code" behavioral "$(cls "$LIB" "$F")"
F="$(fx board code)";       expect "unreadable base ref, dirty code" behavioral "$(cls "$LIB" "$F" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)"

# negative control: strip the board-only block from a copy beside the real lib (siblings resolve
# relative to the lib path); the dirty-pdf fixture must read behavioral again.
OLD="$(dirname "$LIB")/.board-oldlib.tmp.sh"
trap 'rm -f "$OLD"' EXIT
awk '/# board-only: begin/{s=1} !s{print} /# board-only: end/{s=0}' "$LIB" > "$OLD"
F="$(fx board pdf)"
if [ -s "$OLD" ] && ! grep -q 'board-only: begin' "$OLD" && grep -q '^classify()' "$OLD"; then
  expect "block-stripped lib on board-only + dirty pdf (the bug; block is load-bearing)" behavioral "$(cls "$OLD" "$F")"
else
  echo "[NO EXECUTABLE CHECK: could not strip the board-only block]"; fails=$((fails+1))
fi

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
