#!/usr/bin/env bash
# test-board-atomic-mint.sh -- board row id minting is serialized by the shared
# per-board flock (sync_core.board_lock), so concurrent sessions can never mint
# the same id and a union merge can never land duplicate rows.
#
# Proves:
#   AC1  N concurrent `board capture` runs each mint a unique id and every row
#        lands (no lost write)
#   AC2  a capture queued behind a lock holder that appends ID-4 while holding
#        the lock mints ID-5, not ID-4: the id is derived from a fresh read
#        INSIDE the hold, never from a pre-lock snapshot
#   AC3  `board promote` (add-backlog) and `board capture` share the one lock
#        address (tmpdir board-<md5(realpath)>.lock), so a promote racing
#        captures still mints uniquely
#
# Run: bash tests/test-board-atomic-mint.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARD_SH="$KIT_DIR/lib/board/board.sh"
SYNC_LIB="$KIT_DIR/lib/sync"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-atomic-mint-test.XXXXXX")"
TMPD="$(cd "$TMPD" && pwd)"
trap 'rm -rf "$TMPD"' EXIT

new_board() {  # <path>: board with header + ID-1..ID-3
  cat > "$1" <<'EOF'
| ID | Item | Notes | Status |
|---|---|---|---|
| ID-1 | first | n | queued |
| ID-2 | second | n | queued |
| ID-3 | third | n | queued |
EOF
}

# numeric ids minted onto a board file (ID-004 -> 4, so promote's zero-padded
# form and capture's bare form compare as the same number)
board_ids() { grep -oE '^\| ID-[0-9]+ \|' "$1" | grep -oE '[0-9]+' | awk '{print $1+0}' | sort -n; }

# ============================================================
echo "== AC1: six concurrent captures mint six unique ids =="
# ============================================================
BOARD1="$TMPD/one/BACKLOG.md"; mkdir -p "$(dirname "$BOARD1")"; new_board "$BOARD1"
for i in 1 2 3 4 5 6; do
  ( bash "$BOARD_SH" capture "race item $i" --backlog-file "$BOARD1" \
      >"$TMPD/one/cap.$i.out" 2>"$TMPD/one/cap.$i.err" ) &
done
wait

minted="$(cat "$TMPD/one/cap."*.out | grep -oE 'filed: ID-[0-9]+' | grep -oE '[0-9]+' | awk '{print $1+0}')"
uniq_count="$(printf '%s\n' "$minted" | sort -n | uniq | grep -c .)"
chk "six captures each report a minted id" "$([ "$(printf '%s\n' "$minted" | grep -c .)" -eq 6 ]; echo $?)"
chk "all six minted ids are unique" "$([ "$uniq_count" -eq 6 ]; echo $?)"
chk "no id collides with the pre-existing 1-3" \
    "$(printf '%s\n' "$minted" | awk '$1 <= 3 {bad=1} END{exit bad+0}'; echo $?)"
chk "board holds all 9 rows (none lost to a clobbered write)" \
    "$([ "$(board_ids "$BOARD1" | grep -c .)" -eq 9 ]; echo $?)"

# ============================================================
echo "== AC2: a capture behind a held lock re-reads and mints past the holder's row =="
# ============================================================
BOARD2="$TMPD/two/BACKLOG.md"; mkdir -p "$(dirname "$BOARD2")"; new_board "$BOARD2"
LOCKPATH="$(BOARD_SYNC_LIB="$SYNC_LIB" python3 - "$BOARD2" <<'PY'
import os, sys
sys.path.insert(0, os.environ["BOARD_SYNC_LIB"])
from sync_core import board_lock_path
print(board_lock_path(sys.argv[1]))
PY
)"

# A holder takes the same lock, signals it, sleeps, then appends ID-4 by hand
# and releases -- the shape of a rival writer that got there first.
python3 - "$LOCKPATH" "$BOARD2" "$TMPD/two/held" <<'PY' &
import fcntl, sys, time
lockf, board, sentinel = sys.argv[1:4]
fh = open(lockf, "w")
fcntl.flock(fh, fcntl.LOCK_EX)
open(sentinel, "w").close()
time.sleep(1.5)
with open(board, "a") as b:
    b.write("| ID-4 | holder row | appended under the held lock | queued |\n")
PY
holder=$!
for i in $(seq 1 60); do [ -f "$TMPD/two/held" ] && break; sleep 0.05; done
chk "lock holder acquired the lock" "$([ -f "$TMPD/two/held" ]; echo $?)"

start=$(date +%s)
out="$(bash "$BOARD_SH" capture "queued behind the lock" --backlog-file "$BOARD2" 2>/dev/null)"
elapsed=$(( $(date +%s) - start ))
wait "$holder"

chk "blocked capture minted ID-5, not the taken ID-4" \
    "$(printf '%s' "$out" | grep -q 'filed: ID-5'; echo $?)"
chk "capture waited for the holder (>=1s elapsed)" "$([ "$elapsed" -ge 1 ]; echo $?)"
chk "both rows survive: holder's ID-4 and capture's ID-5" \
    "$(board_ids "$BOARD2" | grep -qx 4 && board_ids "$BOARD2" | grep -qx 5; echo $?)"

# ============================================================
echo "== AC3: a promote racing captures mints uniquely through the same lock =="
# ============================================================
BOARD3="$TMPD/three/BACKLOG.md"; mkdir -p "$(dirname "$BOARD3")"; new_board "$BOARD3"
cat > "$TMPD/three/backlog-staging.md" <<EOF
# Backlog staging (auto)

## [staged] promoted candidate
- Intent: fix the flapping widget reconnect
- Approach: patch widget.c reconnect path
- Tags: #u-hi #f-mid
- Source: session $(date +%F)
EOF

( bash "$BOARD_SH" promote all --backlog-file "$BOARD3" >"$TMPD/three/promote.out" 2>&1 ) &
for i in 1 2 3; do
  ( bash "$BOARD_SH" capture "cap $i" --backlog-file "$BOARD3" \
      >"$TMPD/three/cap.$i.out" 2>/dev/null ) &
done
wait

promoted_id="$(grep -oE 'promoted ID-[0-9]+' "$TMPD/three/promote.out" | grep -oE '[0-9]+' | awk '{print $1+0}')"
cap_ids="$(cat "$TMPD/three/cap."*.out | grep -oE 'filed: ID-[0-9]+' | grep -oE '[0-9]+' | awk '{print $1+0}')"
all_new="$(printf '%s\n%s\n' "$promoted_id" "$cap_ids" | sort -n)"
chk "promote minted one row" "$([ -n "$promoted_id" ]; echo $?)"
chk "promote + 3 captures minted 4 unique ids" \
    "$([ "$(printf '%s\n' "$all_new" | uniq | grep -c .)" -eq 4 ]; echo $?)"
chk "board holds all 7 rows" "$([ "$(board_ids "$BOARD3" | grep -c .)" -eq 7 ]; echo $?)"

echo
echo "atomic-mint: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
