#!/usr/bin/env bash
# `backlog.sh set` note semantics: a terminal state's note SUPERSEDES the in-flight ones,
# every other state keeps stacking them.
#
# Why this suite exists: stacking on a terminal state let a shipped row keep an older note
# that still described the work as open, and a reader cannot tell which note is current.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BL="$KIT_DIR/lib/board/backlog.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fresh one-row board per case, so no case can see another's writes.
mk_board() {  # path
  printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-001 | a row | src | queued |\n' > "$1"
}
cell() {  # path -> the row's status cell, whitespace-trimmed
  awk -F'|' '/^\| *ID-001 *\|/ { c=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", c); print c }' "$1"
}

# ---- 1. in-flight states still STACK (the behaviour that must not regress) ----
B="$TMP/inflight.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "first" >/dev/null
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "second" >/dev/null
c=$(cell "$B")
case "$c" in
  'executing [second] [first]') pass "in-flight keeps stacking, newest first: $c" ;;
  *) fail "in-flight should stack both notes, got: $c" ;;
esac

# ---- 2. shipped REPLACES ----
B="$TMP/shipped.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "half done, next: decide" >/dev/null
BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "done, PR #1" >/dev/null
c=$(cell "$B")
case "$c" in
  'shipped [done, PR #1]') pass "shipped supersedes the in-flight note: $c" ;;
  *) fail "shipped should carry only its own note, got: $c" ;;
esac

# ---- 3. dropped REPLACES ----
B="$TMP/dropped.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "in progress" >/dev/null
BACKLOG_FILE="$B" bash "$BL" set ID-001 dropped "superseded by ID-002" >/dev/null
c=$(cell "$B")
case "$c" in
  'dropped [superseded by ID-002]') pass "dropped supersedes the in-flight note: $c" ;;
  *) fail "dropped should carry only its own note, got: $c" ;;
esac

# ---- 4. terminal with NO note keeps what is there (deliberate carve-out) ----
# Erasing on a bare flip would destroy the only record and leave nothing in its place.
B="$TMP/nonote.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "the only record" >/dev/null
BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped >/dev/null
c=$(cell "$B")
case "$c" in
  'shipped [the only record]') pass "terminal with no note preserves the existing note: $c" ;;
  *) fail "a bare terminal flip must not erase the note, got: $c" ;;
esac

# ---- 5. parked is NOT terminal: a parked row is resumable, so its history stays ----
B="$TMP/parked.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "context to resume from" >/dev/null
BACKLOG_FILE="$B" bash "$BL" set ID-001 parked "waiting on review" >/dev/null
c=$(cell "$B")
case "$c" in
  'parked [waiting on review] [context to resume from]') pass "parked keeps stacking: $c" ;;
  *) fail "parked is resumable and must keep its history, got: $c" ;;
esac

# ---- 6. the real ID-834 shape: the row that motivated this ----
B="$TMP/id834.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 executing "PARTIAL: still failed under load. Next: decide barrier vs wire" >/dev/null
BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "proven under matched load" >/dev/null
c=$(cell "$B")
if printf '%s' "$c" | grep -q 'PARTIAL'; then
  fail "the shipped row still carries the superseded PARTIAL note: $c"
else
  pass "the ID-834 shape lands a single current note: $c"
fi

# ---- 7. the row keeps its shape: exactly one status cell, table intact ----
B="$TMP/shape.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "note" >/dev/null
n=$(awk -F'|' '/^\| *ID-001 *\|/ { print NF }' "$B")
[ "$n" = 6 ] && pass "row still has its original field count ($n)" \
  || fail "row field count changed to $n (was 6)"

if [ "$FAILED" = 0 ]; then echo "ALL PASS"; else echo "$FAILED FAILED"; exit 1; fi
