#!/usr/bin/env bash
# test-learn-drain.sh -- SPEC-196 (harness-loop sub-goal 06).
# Proves `learn drain` (lib/learn/drain.py, staging-format.py, drain.sh, and the learn.sh
# dispatch that no longer refuses):
#   AC1  render on real-shaped data: grouped by Home, oldest-first within each group, one
#        line per candidate (title / age / tags / evidence), numbered over the staged subset
#   AC2  numbering parity: the index `learn drain` prints for a candidate == the index
#        `board promote` (list mode) prints for the same candidate, same file
#   AC3  NEGATIVE CONTROL, expiry: a 31d-old [staged] row moves to [expired]; a 5d-old
#        [staged] row does not
#   AC4  NEGATIVE CONTROL, move-not-delete: a byte-diff of before/after shows ONLY the
#        header token changed on the expired block -- every other byte (incl. every other
#        block) is identical
#   AC5  NEGATIVE CONTROL, idempotency: an immediate second drain run expires nothing new
#   AC6  NEGATIVE CONTROL, promote-unchanged: add-backlog's own fixture-backed list/promote/
#        reject flow still passes untouched, and an [expired] row never appears in its
#        numbered list (no add-backlog code change needed)
#   AC7  --days override: a custom window changes what counts as expired
#   AC8  honest-empty: no staging file -> "nothing staged", exit 0, no write
#
# Two separate fixture files by design: AC1/AC2 (render + numbering) use dates that all sit
# INSIDE the 30d default window (so a render assertion never races the expiry side effect
# every drain run performs); AC3-AC6 (expiry + move-not-delete + idempotency + add-backlog
# unchanged) use a fixture with one row deliberately past the window.
#
# Run: bash tests/test-learn-drain.sh   (exit 0 = all AC green)
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LEARN="$KIT_DIR/bin/learn"
ADD_BACKLOG="$KIT_DIR/lib/board/bin/add-backlog"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

if date -v-1d >/dev/null 2>&1; then
  _date_n_days_ago() { date -u -v-"$1"d +%Y-%m-%d; }
else
  _date_n_days_ago() { date -u -d "-$1 days" +%Y-%m-%d; }
fi

TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

D2="$(_date_n_days_ago 2)"    # inside window, newest
D5="$(_date_n_days_ago 5)"    # inside window
D12="$(_date_n_days_ago 12)"  # inside window, oldest of the render fixture
D31="$(_date_n_days_ago 31)"  # OUTSIDE the 30d default window -> expires

# ---------------------------------------------------------------------------
# AC1/AC2 fixture: real-shaped, multiple Home groups, mixed ages -- ALL inside the default
# window, so rendering it never triggers the expiry side effect.
# ---------------------------------------------------------------------------
RSTAGING="$TMPDIR_T/render/_meta/backlog-staging.md"
RBACKLOG="$TMPDIR_T/render/_meta/BACKLOG.md"
mkdir -p "$(dirname "$RSTAGING")"
cat > "$RSTAGING" <<EOF
# Backlog staging (auto, via backlog-stage)

Candidates auto-extracted from sessions. Review + promote by hand.

## [staged] Zeta task in repo B
- Intent: do the zeta thing
- Approach: just do it
- Tags: #u-lo #f-hi
- Home: repo-b
- Source: session $D2

## [staged] Alpha task in repo A
- Intent: do the alpha thing
- Approach: just do it
- Tags: #u-hi #f-mid
- Home: repo-a
- Source: session $D12

## [staged] Beta task in repo A, newer
- Intent: do the beta thing
- Approach: just do it
- Tags: #u-mid #f-hi
- Home: repo-a
- Source: session $D5
EOF

echo "=== AC1: render on real-shaped data ==="
OUT="$(BACKLOG_STAGE_STAGING="$RSTAGING" "$LEARN" drain 2>&1)"
assert "AC1a groups by Home (repo-a header present)" "$(grep -q '^## Home: repo-a' <<<"$OUT"; echo $?)"
assert "AC1b groups by Home (repo-b header present)" "$(grep -q '^## Home: repo-b' <<<"$OUT"; echo $?)"
assert "AC1c one line per candidate: title present" "$(grep -q 'Alpha task in repo A' <<<"$OUT"; echo $?)"
assert "AC1d age shown (Nd)" "$(grep -qE '[0-9]+d' <<<"$OUT"; echo $?)"
assert "AC1e tags shown" "$(grep -q '#u-hi #f-mid' <<<"$OUT"; echo $?)"
assert "AC1f evidence (Source) shown" "$(grep -q "session $D5" <<<"$OUT"; echo $?)"
ALPHA_LINENO="$(grep -n 'Alpha task in repo A' <<<"$OUT" | head -1 | cut -d: -f1)"
BETA_LINENO="$(grep -n 'Beta task in repo A, newer' <<<"$OUT" | head -1 | cut -d: -f1)"
assert "AC1g repo-a's older row (Alpha, 12d) sorts before its newer row (Beta, 5d)" \
  "$([ -n "$ALPHA_LINENO" ] && [ -n "$BETA_LINENO" ] && [ "$ALPHA_LINENO" -lt "$BETA_LINENO" ]; echo $?)"
assert "AC1h no expiry side effect: file untouched (all rows inside the window)" \
  "$(grep -q '^## \[expired\]' "$RSTAGING"; [ $? -ne 0 ]; echo $?)"

echo "=== AC2: numbering parity with board promote ==="
DRAIN_ALPHA_N="$(echo "$OUT" | grep 'Alpha task in repo A' | sed -E 's/^[[:space:]]*([0-9]+)\..*/\1/')"
PROMOTE_OUT="$(BACKLOG_STAGE_STAGING="$RSTAGING" BACKLOG_STAGE_BACKLOG="$RBACKLOG" python3 "$ADD_BACKLOG" list 2>&1)"
PROMOTE_ALPHA_N="$(echo "$PROMOTE_OUT" | grep 'Alpha task in repo A' | sed -E 's/^([0-9]+)\..*/\1/')"
assert "AC2 drain index == board promote index for the same candidate ($DRAIN_ALPHA_N == $PROMOTE_ALPHA_N)" \
  "$([ -n "$DRAIN_ALPHA_N" ] && [ "$DRAIN_ALPHA_N" = "$PROMOTE_ALPHA_N" ]; echo $?)"

# ---------------------------------------------------------------------------
# AC3-AC6 fixture: one row deliberately past the 30d window.
# ---------------------------------------------------------------------------
STAGING="$TMPDIR_T/expiry/_meta/backlog-staging.md"
BACKLOG="$TMPDIR_T/expiry/_meta/BACKLOG.md"
mkdir -p "$(dirname "$STAGING")"
cat > "$STAGING" <<EOF
# Backlog staging (auto, via backlog-stage)

Candidates auto-extracted from sessions. Review + promote by hand.

## [staged] Old candidate past the window
- Intent: do the old thing
- Approach: just do it
- Tags: #u-hi #f-mid
- Home: repo-a
- Source: session $D31

## [staged] Recent candidate inside the window
- Intent: do the recent thing
- Approach: just do it
- Tags: #u-lo #f-hi
- Home: repo-b
- Source: session $D5
EOF
cat > "$BACKLOG" <<'EOF'
# BACKLOG

| ID | Item | Notes | Status |
|---|---|---|---|
EOF
cp "$STAGING" "$TMPDIR_T/staging.before"

echo "=== AC3: NEGATIVE CONTROL, expiry (31d expires, 5d does not) ==="
BACKLOG_STAGE_STAGING="$STAGING" "$LEARN" drain >/dev/null 2>&1
assert "AC3a Old candidate (31d) moved to [expired]" \
  "$(grep -q '^## \[expired\] Old candidate past the window' "$STAGING"; echo $?)"
assert "AC3b Recent candidate (5d) still [staged]" \
  "$(grep -q '^## \[staged\] Recent candidate inside the window' "$STAGING"; echo $?)"

echo "=== AC4: NEGATIVE CONTROL, move-not-delete (byte-diff) ==="
DIFF="$(diff "$TMPDIR_T/staging.before" "$STAGING")"
DIFF_LINES_CHANGED="$(diff "$TMPDIR_T/staging.before" "$STAGING" | grep -cE '^[<>]')"
assert "AC4a exactly one line pair changed (the Old-candidate header only)" "$([ "$DIFF_LINES_CHANGED" -eq 2 ]; echo $?)"
assert "AC4b the changed line is only the bracket token, not the title" \
  "$(grep -q '^< ## \[staged\] Old candidate past the window$' <<<"$DIFF" && grep -q '^> ## \[expired\] Old candidate past the window$' <<<"$DIFF"; echo $?)"
assert "AC4c nothing deleted: every original body line still present" \
  "$(python3 -c "
import sys
before = open('$TMPDIR_T/staging.before').read()
after = open('$STAGING').read()
before_lines = set(l for l in before.splitlines() if l.strip() and not l.startswith('## ['))
after_lines = set(after.splitlines())
missing = before_lines - after_lines
sys.exit(0 if not missing else 1)
"; echo $?)"

echo "=== AC5: NEGATIVE CONTROL, idempotency (immediate re-run expires nothing new) ==="
cp "$STAGING" "$TMPDIR_T/staging.after-first-drain"
BACKLOG_STAGE_STAGING="$STAGING" "$LEARN" drain >/dev/null 2>&1
assert "AC5 re-run is a byte-identical no-op" "$(diff -q "$TMPDIR_T/staging.after-first-drain" "$STAGING" >/dev/null; echo $?)"

# ---------------------------------------------------------------------------
# AC6: add-backlog fixture flow unchanged; expired rows unselectable
# ---------------------------------------------------------------------------
echo "=== AC6: NEGATIVE CONTROL, promote-unchanged (add-backlog untouched, expired unselectable) ==="
LIST_OUT="$(BACKLOG_STAGE_STAGING="$STAGING" BACKLOG_STAGE_BACKLOG="$BACKLOG" python3 "$ADD_BACKLOG" list 2>&1)"
assert "AC6a expired candidate absent from board promote's numbered list" \
  "$(grep -q 'Old candidate past the window' <<<"$LIST_OUT"; [ $? -ne 0 ]; echo $?)"
assert "AC6b remaining staged candidate still listed" \
  "$(grep -q 'Recent candidate inside the window' <<<"$LIST_OUT"; echo $?)"
PROMOTE_OUT2="$(BACKLOG_STAGE_STAGING="$STAGING" BACKLOG_STAGE_BACKLOG="$BACKLOG" python3 "$ADD_BACKLOG" 1 2>&1)"
assert "AC6c board promote still promotes the first remaining staged candidate" \
  "$(grep -q '^promoted ID-' <<<"$PROMOTE_OUT2"; echo $?)"
assert "AC6d the promoted candidate is the recent one, not the expired one" \
  "$(grep -q 'Recent candidate inside the window' <<<"$PROMOTE_OUT2"; echo $?)"

# ---------------------------------------------------------------------------
# AC7: --days override
# ---------------------------------------------------------------------------
echo "=== AC7: --days override changes the expiry window ==="
STAGING2="$TMPDIR_T/staging2.md"
cat > "$STAGING2" <<EOF
## [staged] Under a 3-day window
- Intent: x
- Approach: x
- Tags: #u-lo #f-lo
- Home: repo-c
- Source: session $D5
EOF
BACKLOG_STAGE_STAGING="$STAGING2" "$LEARN" drain --days 3 >/dev/null 2>&1
assert "AC7 a 5d row expires under --days 3" "$(grep -q '^## \[expired\]' "$STAGING2"; echo $?)"

# ---------------------------------------------------------------------------
# AC8: honest-empty
# ---------------------------------------------------------------------------
echo "=== AC8: honest-empty (no staging file) ==="
NOFILE="$TMPDIR_T/does-not-exist/_meta/backlog-staging.md"
OUT8="$(BACKLOG_STAGE_STAGING="$NOFILE" "$LEARN" drain 2>&1)"; RC8=$?
assert "AC8a exits 0" "$RC8"
assert "AC8b reports nothing staged" "$(grep -q 'nothing staged' <<<"$OUT8"; echo $?)"
assert "AC8c never creates the file" "$([ ! -f "$NOFILE" ]; echo $?)"

echo ""
echo "TOTAL: $TOTAL   PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
