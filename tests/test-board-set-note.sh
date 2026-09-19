#!/usr/bin/env bash
# `backlog.sh set` note semantics: a terminal state's note SUPERSEDES the in-flight ones,
# every other state keeps stacking them.
#
# Why this suite exists: stacking on a terminal state let a shipped row keep an older note
# that still described the work as open, and a reader cannot tell which note is current.
#
# Cases 8-11: `set` refuses when an id matches more than one row (a union merge can re-add a
# stale duplicate) instead of flipping both silently, and `dedupe` collapses duplicates down
# to one, preferring a shipped/dropped/parked copy over the last occurrence.
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

# ---- 8. set REFUSES on a duplicate id, writing nothing ----
B="$TMP/dup-refuse.md"
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-871 | a | src | queued |\n| ID-871 | a mirror | src | shipped |\n' > "$B"
before="$(cat "$B")"
if err="$(BACKLOG_FILE="$B" bash "$BL" set ID-871 executing "x" 2>&1)"; then
  fail "set on a 2-row id should exit nonzero, got 0"
else
  case "$err" in
    *"ID-871 matches 2 rows"*"dedupe first"*) pass "set refuses the duplicate id: $err" ;;
    *) fail "set's refusal message is wrong: $err" ;;
  esac
fi
after="$(cat "$B")"
[ "$before" = "$after" ] && pass "set on a duplicate id wrote nothing" \
  || fail "set on a duplicate id should not touch the file"

# ---- 9. set still works on a unique id (no regression) ----
B="$TMP/dup-unique.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "done" >/dev/null
c=$(cell "$B")
[ "$c" = "shipped [done]" ] && pass "set on a unique id is unaffected: $c" \
  || fail "set on a unique id regressed, got: $c"

# ---- 10. dedupe keeps the shipped copy over the queued one ----
B="$TMP/dup-dedupe.md"
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-871 | a | src | queued |\n| ID-871 | a mirror | src | shipped |\n' > "$B"
out="$(BACKLOG_FILE="$B" bash "$BL" dedupe ID-871)"
n="$(grep -c '^| *ID-871 *|' "$B")"
kept="$(awk -F'|' '/^\| *ID-871 *\|/{print $(NF-1)}' "$B" | tr -d ' ')"
if [ "$n" = 1 ] && [ "$kept" = "shipped" ]; then
  pass "dedupe kept the shipped row, dropped the queued one: $out"
else
  fail "dedupe should leave exactly one shipped row, got n=$n kept=$kept ($out)"
fi

# ---- 11. dedupe on a unique id is a no-op ----
B="$TMP/dup-noop.md"; mk_board "$B"
before="$(cat "$B")"
out="$(BACKLOG_FILE="$B" bash "$BL" dedupe ID-001)"
after="$(cat "$B")"
if [ "$out" = "nothing to dedupe" ] && [ "$before" = "$after" ]; then
  pass "dedupe on a unique id is a no-op"
else
  fail "dedupe on a unique id should be a no-op, got: $out"
fi

# ---- 12-14. the default-branch warning: the row is still flipped, the caller is told not
# to commit it here. Cases 1-11 above already prove the silent path, since $TMP is no repo.
GR="$TMP/boardrepo"
git init -q -b main "$GR" 2>/dev/null
git -C "$GR" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
B="$GR/BACKLOG.md"; mk_board "$B"

out="$(BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "on main" 2>&1)"
if printf '%s' "$out" | grep -q 'on the default branch (main)' && [ "$(cell "$B")" = 'shipped [on main]' ]; then
  pass "set on the default branch warns and still flips the row"
else
  fail "set on the default branch should warn and flip, got: $out / $(cell "$B")"
fi

out="$(BACKLOG_FILE="$B" bash "$BL" dedupe ID-001 2>&1)"
if printf '%s' "$out" | grep -q 'nothing to dedupe'; then
  pass "dedupe with nothing to do stays silent about the branch"
else
  fail "dedupe no-op should not warn, got: $out"
fi

mk_board "$B"
printf '| ID-001 | a row | src | queued |\n' >> "$B"
out="$(BACKLOG_FILE="$B" bash "$BL" dedupe-all 2>&1)"
if printf '%s' "$out" | grep -q 'on the default branch (main)' \
   && [ "$(grep -c '^| ID-001 ' "$B")" = 1 ]; then
  pass "dedupe-all on the default branch warns and still collapsed the duplicate"
else
  fail "dedupe-all on the default branch should warn and collapse, got: $out"
fi

git -C "$GR" checkout -q -b feat/board-guard
mk_board "$B"
out="$(BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "on a branch" 2>&1)"
if printf '%s' "$out" | grep -q 'default branch'; then
  fail "set on a feature branch should not warn, got: $out"
else
  pass "set on a feature branch does not warn"
fi

# ---- 15. set REFUSES a stray flag after the note, writing nothing ----
# The 2026-09-17 CL-056 incident: a consumer's root `board` wrapper forwards straight to
# backlog.sh (it does not accept --backlog-file), and `set` used to fold the literal flag
# text into the note instead of rejecting it.
B="$TMP/stray-flag.md"; mk_board "$B"
before="$(cat "$B")"
if err="$(BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "done" --backlog-file /some/path.md 2>&1)"; then
  fail "set with a trailing --backlog-file should exit nonzero, got 0"
else
  case "$err" in
    *"stray argument"*"--backlog-file"*) pass "set refuses the stray flag: $err" ;;
    *) fail "set's stray-flag refusal message is wrong: $err" ;;
  esac
fi
after="$(cat "$B")"
[ "$before" = "$after" ] && pass "set with a stray flag wrote nothing" \
  || fail "set with a stray flag should not touch the file"

# ---- 16. a legitimately multi-word QUOTED note still works ----
B="$TMP/quoted-note.md"; mk_board "$B"
BACKLOG_FILE="$B" bash "$BL" set ID-001 shipped "fixed in console-labs #233" >/dev/null
c=$(cell "$B")
[ "$c" = "shipped [fixed in console-labs #233]" ] && pass "quoted multi-word note still works: $c" \
  || fail "quoted multi-word note regressed, got: $c"

# ---- 17. dedupe on an ABSENT id reports instead of dying silently under set -e ----
# The count used to be `printf '%s\n' "$rows" | grep -c .` evaluated before any row check;
# grep -c exits 1 on zero matches, so an absent id killed the script with no message at all.
B="$TMP/absent.md"; mk_board "$B"
before="$(cat "$B")"
if err="$(BACKLOG_FILE="$B" bash "$BL" dedupe ID-999 2>&1)"; then
  fail "dedupe on an absent id should exit nonzero, got 0"
else
  case "$err" in
    *"no Active-queue row for ID-999"*) pass "dedupe on an absent id reports: $err" ;;
    *) fail "dedupe's absent-id message is wrong (silent death?): '$err'" ;;
  esac
fi
after="$(cat "$B")"
[ "$before" = "$after" ] && pass "dedupe on an absent id wrote nothing" \
  || fail "dedupe on an absent id should not touch the file"

if [ "$FAILED" = 0 ]; then echo "ALL PASS"; else echo "$FAILED FAILED"; exit 1; fi
