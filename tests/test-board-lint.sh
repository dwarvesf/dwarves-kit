#!/usr/bin/env bash
# `backlog.sh lint`: enumerate malformed board rows under the bash parser's contract --
# the failures sync and the board renderer trip on. Enumerator contract like
# lib/lint/scattered-ids.sh: prints findings, exits 0 even when findings exist.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BL="$KIT_DIR/lib/board/backlog.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

HDR='| ID | Title | Source | Status |
|----|-------|--------|--------|'

# ---- 1. a clean board reports no findings and exits 0 ----
B="$TMP/clean.md"
printf '## Active queue\n\n%s\n| ID-001 | a | src | queued |\n| ID-002 | b | src | shipped [PR #1] |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "(no lint findings)" ]; then
  pass "clean board: no findings, exit 0"
else
  fail "clean board: rc=$rc out=[$out]"
fi

# ---- 2. duplicate ids are reported with both line numbers, exit still 0 ----
B="$TMP/dup.md"
printf '## Active queue\n\n%s\n| ID-401 | a | src | queued |\n| ID-401 | a mirror | src | shipped |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'duplicate-id.*ID-401.*2 rows'; then
  pass "duplicate id reported: $out"
else
  fail "duplicate id missed: rc=$rc out=[$out]"
fi

# ---- 3. a row with an extra cell is reported ----
B="$TMP/cells.md"
printf '## Active queue\n\n%s\n| ID-500 | a | src | queued | stray |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if printf '%s\n' "$out" | grep -q 'cell-count.*found 5'; then
  pass "extra cell reported: $out"
else
  fail "extra cell missed: [$out]"
fi

# ---- 4. an escaped pipe inside the STATUS cell corrupts the bash read ----
B="$TMP/escape.md"
printf '## Active queue\n\n%s\n| ID-021 | a | src | queued \\| more |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if printf '%s\n' "$out" | grep -q 'escaped-pipe' && printf '%s\n' "$out" | grep -q 'unknown-status'; then
  pass "status-cell escape reported: $out"
else
  fail "status-cell escape missed: [$out]"
fi

# ---- 4b. a mid-row escaped pipe is legal (&#124; contract) and not flagged ----
B="$TMP/escape-ok.md"
printf '## Active queue\n\n%s\n| ID-022 | a \\| b | src | queued |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if [ "$out" = "(no lint findings)" ]; then
  pass "mid-row escape is not flagged"
else
  fail "mid-row escape flagged: [$out]"
fi

# ---- 5. an unrecognized leading status is reported ----
B="$TMP/status.md"
printf '## Active queue\n\n%s\n| ID-777 | a | src | in-flight |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if printf '%s\n' "$out" | grep -q 'unknown-status.*in-flight'; then
  pass "unknown status reported: $out"
else
  fail "unknown status missed: [$out]"
fi

# ---- 6. a non-id first cell inside the board table is reported ----
B="$TMP/badid.md"
printf '## Active queue\n\n%s\n| not-an-id | a | src | queued |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if printf '%s\n' "$out" | grep -q 'id-format'; then
  pass "non-id first cell reported: $out"
else
  fail "non-id first cell missed: [$out]"
fi

# ---- 6b. divider rows (bold prose, empty rest) are a layout convention ----
B="$TMP/divider.md"
printf '## Active queue\n\n%s\n| **I1 -- a section** | | | | | |\n| ID-033 | a | src | queued |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if [ "$out" = "(no lint findings)" ]; then
  pass "divider rows ignored"
else
  fail "divider row flagged: [$out]"
fi

# ---- 7. a different table's rows are not linted ----
B="$TMP/other-table.md"
printf '## Active queue\n\n%s\n| ID-001 | a | src | queued |\n\n## Unrelated\n\n| Name | Val |\n|------|-----|\n| x | y |\n' "$HDR" > "$B"
out="$(bash "$BL" lint "$B")"
if [ "$out" = "(no lint findings)" ]; then
  pass "non-board table ignored"
else
  fail "non-board table linted: [$out]"
fi

# ---- 8. a missing file refuses with exit 1 ----
out="$(bash "$BL" lint "$TMP/absent.md" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'no readable file'; then
  pass "missing file refuses: rc=1"
else
  fail "missing file: rc=$rc out=[$out]"
fi

echo
if [ "$FAILED" -eq 0 ]; then echo "all lint tests passed"; else echo "$FAILED test(s) FAILED"; exit 1; fi
