#!/usr/bin/env bash
# `backlog.sh dedupe-all`: the whole-file sweep a union re-merge runs automatically, as
# opposed to `dedupe <id>` which a human names one id to. Keep-rule: prefer whichever copy
# of an id is NOT queued (the row a branch flipped), file order breaks a tie between two
# copies that share a status.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BL="$KIT_DIR/lib/board/backlog.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

status_of() { awk -F'|' -v id="$2" '$0 ~ ("^\\| *" id " *\\|") { c=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",c); print c }' "$1"; }
count_of()  { grep -c "^| *$2 *|" "$1"; }

# ---- 1. queued + shipped dedupes to the shipped copy ----
B="$TMP/queued-shipped.md"
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-401 | a | src | queued |\n| ID-401 | a mirror | src | shipped |\n' > "$B"
out="$(bash "$BL" dedupe-all "$B")"
if [ "$(count_of "$B" ID-401)" = 1 ] && [ "$(status_of "$B" ID-401)" = "shipped" ] && [ "$out" = "ID-401" ]; then
  pass "queued+shipped dedupes to the shipped copy: $out"
else
  fail "queued+shipped dedupe wrong: n=$(count_of "$B" ID-401) status=$(status_of "$B" ID-401) out=$out"
fi

# ---- 2. two rows sharing the SAME status keep the first occurrence ----
B="$TMP/tie-same-status.md"
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-500 | first | src | queued |\n| ID-500 | second | src | queued |\n' > "$B"
out="$(bash "$BL" dedupe-all "$B")"
kept_title="$(awk -F'|' '/^\| *ID-500 *\|/ { t=$3; gsub(/^[ \t]+|[ \t]+$/,"",t); print t }' "$B")"
if [ "$(count_of "$B" ID-500)" = 1 ] && [ "$kept_title" = "first" ] && [ "$out" = "ID-500" ]; then
  pass "a tied status keeps the first occurrence: $out"
else
  fail "tie-break wrong: n=$(count_of "$B" ID-500) kept=$kept_title out=$out"
fi

# ---- 3. a clean board (no duplicate ids) makes no change and reports nothing ----
B="$TMP/clean.md"
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-001 | a | src | queued |\n| ID-002 | b | src | executing |\n' > "$B"
before="$(cat "$B")"
out="$(bash "$BL" dedupe-all "$B")"
after="$(cat "$B")"
if [ -z "$out" ] && [ "$before" = "$after" ]; then
  pass "a clean board is untouched, no ids reported"
else
  fail "a clean board should be a no-op, got out=[$out]"
fi

# ---- 4. several duplicated ids in one file are all swept in a single pass ----
B="$TMP/multi.md"
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-401 | a | src | queued |\n| ID-402 | b | src | queued |\n| ID-401 | a mirror | src | shipped |\n| ID-402 | b mirror | src | executing |\n' > "$B"
out="$(bash "$BL" dedupe-all "$B")"
if [ "$(count_of "$B" ID-401)" = 1 ] && [ "$(status_of "$B" ID-401)" = "shipped" ] \
   && [ "$(count_of "$B" ID-402)" = 1 ] && [ "$(status_of "$B" ID-402)" = "executing" ] \
   && [ "$out" = "ID-401 ID-402" ]; then
  pass "multiple duplicated ids are all deduped in one pass: $out"
else
  fail "multi-id sweep wrong: out=[$out], ID-401=$(status_of "$B" ID-401), ID-402=$(status_of "$B" ID-402)"
fi

if [ "$FAILED" = 0 ]; then echo "ALL PASS"; else echo "$FAILED FAILED"; exit 1; fi
