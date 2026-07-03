#!/usr/bin/env bash
# test-proof-table-gen.sh -- the generated proof-of-done confirmation table (SPEC-132).
#
# Pins: round-trip against a fixture ledger, additive-tolerance BOTH ways (01's
# caught=/dur_ms= marker present vs. entirely absent), the hard "never overwrite the
# canonical proof-of-done.md" backstop (explicit path + the default path), the
# coverage-delta row with a known lane and with an unknown lane, and a fully empty
# ledger (no crash).
#
# Run: bash tests/test-proof-table-gen.sh
# Exit 0 = all pass. Exit 1 = failures.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$KIT_DIR/lib/proof-table-gen.sh"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0; TOTAL=0

ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} $1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} $1"; }
expect()  { if printf '%s' "$3" | grep -qF "$2"; then ok "$1"; else bad "$1 (missing '$2' in: $3)"; fi; }
refute()  { if printf '%s' "$3" | grep -qF "$2"; then bad "$1 (unexpected '$2' present)"; else ok "$1"; fi; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-proof-table-gen.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export DWARVES_KIT_LOG_DIR="$WORK/logs"
mkdir -p "$DWARVES_KIT_LOG_DIR/runs"

# ============================================================
echo "=== T1/T6: round-trip + coverage-delta (lane known) ==="
# ============================================================
RID1="fixture-known"
cat > "$DWARVES_KIT_LOG_DIR/runs/$RID1.log" <<'EOF'
2026-07-04T09:00:00Z | START | lane=normal classified=normal type=spec-feature repo=dwarves-kit
2026-07-04T09:00:01Z | GATE | spec | ran | spec authored
2026-07-04T09:00:02Z | GATE | build | ran | implemented
2026-07-04T09:00:03Z | GATE | ship | skipped | held for review
EOF
OUT1="$WORK/out1.md"
RES1="$(bash "$GEN" "$RID1" "$OUT1" 2>&1)"; RC1=$?
assert_eq "T1: generator exits 0 on a populated fixture" "$RC1" "0"
BODY1="$(cat "$OUT1" 2>/dev/null)"
expect "T1: confirmation row for spec (phase/when/state/reason, round-trip)" "| 1 | spec | 2026-07-04T09:00:01Z | ran | spec authored |" "$BODY1"
expect "T1: confirmation row for build" "| 2 | build | 2026-07-04T09:00:02Z | ran | implemented |" "$BODY1"
expect "T1: confirmation row for ship (skipped state preserved)" "| 3 | ship | 2026-07-04T09:00:03Z | skipped | held for review |" "$BODY1"
refute "T1 (implies T3): no Caught/Duration columns when zero OUTCOME lines exist" "Duration (ms)" "$BODY1"
expect "T6: coverage-delta covers spec+build" "Covered: build, spec" "$BODY1"
expect "T6: coverage-delta names ship as uncovered (required, only skipped)" "Uncovered: ship" "$BODY1"
expect "T6: acceptance row reflects lane=normal" "lane \`normal\`" "$BODY1"

# ============================================================
echo ""
echo "=== T2: additive-tolerance, OUTCOME markers present (assumed 01 shape) ==="
# ============================================================
RID2="fixture-outcomes"
cat > "$DWARVES_KIT_LOG_DIR/runs/$RID2.log" <<'EOF'
2026-07-04T09:00:00Z | START | lane=normal classified=normal type=spec-feature repo=dwarves-kit
2026-07-04T09:00:01Z | GATE | spec | ran | spec authored
2026-07-04T09:00:02Z | GATE | build | ran | implemented
2026-07-04T09:00:01Z | OUTCOME | spec | caught=false start=2026-07-04T09:00:01Z end=2026-07-04T09:00:01Z dur_ms=1200
2026-07-04T09:00:02Z | OUTCOME | build | caught=true dur_ms=4300
EOF
OUT2="$WORK/out2.md"
bash "$GEN" "$RID2" "$OUT2" >/dev/null 2>&1
BODY2="$(cat "$OUT2" 2>/dev/null)"
expect "T2: Caught/Duration columns appear when OUTCOME lines exist" "Caught | Duration (ms)" "$BODY2"
expect "T2: spec row populates caught=false dur=1200" "| 1 | spec | 2026-07-04T09:00:01Z | ran | spec authored | false | 1200 |" "$BODY2"
expect "T2: build row populates caught=true dur=4300" "| 2 | build | 2026-07-04T09:00:02Z | ran | implemented | true | 4300 |" "$BODY2"

# same fixture, add a phase with NO outcome line -> that row degrades to n/a per-row
RID2B="fixture-outcomes-partial"
cat > "$DWARVES_KIT_LOG_DIR/runs/$RID2B.log" <<'EOF'
2026-07-04T09:00:00Z | START | lane=normal classified=normal type=spec-feature repo=dwarves-kit
2026-07-04T09:00:01Z | GATE | spec | ran | spec authored
2026-07-04T09:00:03Z | GATE | ship | ran | opened PR
2026-07-04T09:00:01Z | OUTCOME | spec | caught=false dur_ms=900
EOF
OUT2B="$WORK/out2b.md"
bash "$GEN" "$RID2B" "$OUT2B" >/dev/null 2>&1
BODY2B="$(cat "$OUT2B" 2>/dev/null)"
expect "T2: per-row degrade -- a phase with no OUTCOME line gets n/a, not a crash" "| 2 | ship | 2026-07-04T09:00:03Z | ran | opened PR | n/a | n/a |" "$BODY2B"

# ============================================================
echo ""
echo "=== T3: additive-tolerance, OUTCOME markers entirely absent ==="
# ============================================================
# (RID1 above already has zero OUTCOME lines; reuse it to prove the whole-table grain)
expect "T3: whole-table grain -- no Caught/Duration header when 0 OUTCOME lines anywhere" "| # | Phase | When (ISO8601) | State | Reason |" "$BODY1"
refute "T3: no crash / no stray Caught column text on the no-outcome fixture" "Caught" "$BODY1"

# ============================================================
echo ""
echo "=== T4/T5: never overwrites the canonical proof-of-done.md ==="
# ============================================================
CANON="$WORK/docs/verification/proof-of-done.md"
mkdir -p "$(dirname "$CANON")"
printf 'HAND-AUTHORED CANONICAL -- do not touch\n' > "$CANON"
bash "$GEN" "$RID1" "$CANON" >/dev/null 2>&1
RC4=$?
assert_eq "T4: explicit canonical out-path is refused (non-zero exit)" "$RC4" "1"
CANON_BODY="$(cat "$CANON")"
assert_eq "T4: canonical file content is untouched after the refused call" "$CANON_BODY" "HAND-AUTHORED CANONICAL -- do not touch"

DEFAULT_OUT_LINE="$(bash "$GEN" "$RID1" 2>&1 | grep -oE 'wrote [^ ]+' | cut -d' ' -f2)"
expect "T5: default out-path lands under docs/runs/" "docs/runs/$RID1.md" "$DEFAULT_OUT_LINE"
rm -f "$KIT_DIR/docs/runs/$RID1.md" 2>/dev/null || true   # generated artifact, not part of this test's fixture

# ============================================================
echo ""
echo "=== T7: coverage-delta, lane unknown (no START line) ==="
# ============================================================
RID7="fixture-no-start"
cat > "$DWARVES_KIT_LOG_DIR/runs/$RID7.log" <<'EOF'
2026-07-04T09:00:01Z | GATE | spec | ran | spec authored
EOF
OUT7="$WORK/out7.md"
bash "$GEN" "$RID7" "$OUT7" >/dev/null 2>&1
RC7=$?
assert_eq "T7: generator exits 0 even with no START line" "$RC7" "0"
BODY7="$(cat "$OUT7" 2>/dev/null)"
expect "T7: lane reported as unknown, no crash" "n/a (no START line for this rid; lane unknown)" "$BODY7"
expect "T7: coverage-delta uncovered degrades to lane-unknown text" "Uncovered: n/a (lane unknown; no START line for this rid)" "$BODY7"

# ============================================================
echo ""
echo "=== T8: fully empty ledger (rid has no ledger file at all) ==="
# ============================================================
OUT8="$WORK/out8.md"
bash "$GEN" "no-such-rid-ever" "$OUT8" >/dev/null 2>&1
RC8=$?
assert_eq "T8: generator exits 0 on a rid with no ledger file" "$RC8" "0"
BODY8="$(cat "$OUT8" 2>/dev/null)"
expect "T8: empty-ledger table is still well-formed (no-crash marker row)" "(none -- empty ledger)" "$BODY8"
expect "T8: empty-ledger still names the (n/a) acceptance criterion" "## 1. Acceptance criteria" "$BODY8"

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}$PASS${NC} / $TOTAL"
if [ "$FAIL" -gt 0 ]; then echo -e "${RED}$FAIL assertions failed.${NC}"; exit 1; fi
echo -e "${GREEN}proof-table-gen green.${NC}"
