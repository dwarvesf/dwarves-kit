#!/usr/bin/env bash
# `backlog.sh`: a missing/unreadable BACKLOG_FILE exits 1 with a message naming the
# variable, instead of dying deep inside _rows()'s awk call with a bare "can't open
# file" and awk's generic exit code 2.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BL="$KIT_DIR/lib/board/backlog.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
MISSING="$TMP/does-not-exist.md"

# ---- 1. `board` against a missing file exits 1 and names BACKLOG_FILE ----
out="$(BACKLOG_FILE="$MISSING" bash "$BL" board 2>&1)"; rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "BACKLOG_FILE" && printf '%s' "$out" | grep -qF "$MISSING"; then
  pass "board on a missing BACKLOG_FILE exits 1 and names the variable: $out"
else
  fail "board on a missing BACKLOG_FILE: rc=$rc out=[$out]"
fi

# ---- 2. `set` against a missing file exits 1 too (not just `board`) ----
out="$(BACKLOG_FILE="$MISSING" bash "$BL" set ID-001 executing 2>&1)"; rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "BACKLOG_FILE"; then
  pass "set on a missing BACKLOG_FILE exits 1 and names the variable"
else
  fail "set on a missing BACKLOG_FILE: rc=$rc out=[$out]"
fi

# ---- 3. `states` needs no file and still works when BACKLOG_FILE is missing ----
out="$(BACKLOG_FILE="$MISSING" bash "$BL" states 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "queued"; then
  pass "states does not need BACKLOG_FILE to exist"
else
  fail "states should not require BACKLOG_FILE: rc=$rc out=[$out]"
fi

if [ "$FAILED" = 0 ]; then echo "ALL PASS"; else echo "$FAILED FAILED"; exit 1; fi
