#!/usr/bin/env bash
# test-gate-ledger-plan-record.sh -- `gate-ledger.sh plan-record <rid> <lane> ...` writes one GATE
# line per named plan phase in a single call, and refuses without writing anything when the
# disposition set is incomplete or invalid.
#
# Isolation: every case runs under a fresh DWARVES_KIT_LOG_DIR so the real machine corpus is
# never touched.
#
# Run: bash tests/test-gate-ledger-plan-record.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

LOGD=""
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" "$@"; }
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }
# Bytes on disk for a rid, honest-empty when the verb refused before writing.
ledger_of() { cat "$LOGD/runs/$1.log" 2>/dev/null; }

# The full normal-lane set minus grill, reused by the cases that vary only one disposition.
NORMAL_TAIL=(--ran think:"traced it" --ran spec:"wrote it" --ran design-record:"in the spec"
             --skipped test-plan:"prose only" --ran build --ran review --ran docs)

echo "=== gate-ledger plan-record (ID-877) ==="

# ---------------------------------------------------------------------------
# C1: happy path -- one call disposes every normal-lane phase and leaves check clean.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r1 normal --skipped grill:"reason=home-turf: known area" \
         "${NORMAL_TAIL[@]}" --ran ship:"pushed" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && assert "C1 plan-record exits 0" 0 || assert "C1 plan-record exits 0 (got $RC: $OUT)" 1
printf '%s\n' "$OUT" | grep -q '^check: clean for lane normal$' \
  && assert "C1 prints check's clean verdict" 0 || assert "C1 prints check's clean verdict (got: $OUT)" 1
[ "$(printf '%s\n' "$OUT" | grep -c '^[a-z-]* *\(ran\|skipped\|override\)$')" -eq 9 ] \
  && assert "C1 one printed line per phase written" 0 || assert "C1 one printed line per phase written (got: $OUT)" 1
gl check normal r1 >/dev/null 2>&1 \
  && assert "C1 check passes with no further calls" 0 || assert "C1 check passes with no further calls" 1
# the lines are byte-identical to what record()/override() write by hand
ledger_of r1 | grep -q '| GATE | grill | skipped | reason=home-turf: known area$' \
  && assert "C1 grill line keeps the record() format" 0 || assert "C1 grill line keeps the record() format (got: $(ledger_of r1))" 1
[ "$(ledger_of r1 | grep -c '| GATE | ')" -eq 9 ] \
  && assert "C1 exactly 9 GATE lines written" 0 || assert "C1 exactly 9 GATE lines written (got: $(ledger_of r1 | grep -c '| GATE | '))" 1

# ---------------------------------------------------------------------------
# C2: a required plan phase with no disposition refuses, and writes nothing.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r2 normal --skipped grill:"reason=home-turf: x" --ran think \
         --ran design-record --skipped test-plan:"prose" --ran build --ran review --ran docs 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C2 missing 'spec' exits 64" 0 || assert "C2 missing 'spec' exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'no disposition' \
  && assert "C2 names the undisposed phase" 0 || assert "C2 names the undisposed phase (got: $OUT)" 1
[ -z "$(ledger_of r2)" ] && assert "C2 writes nothing" 0 || assert "C2 writes nothing (got: $(ledger_of r2))" 1

# ---------------------------------------------------------------------------
# C3: a lite phase with no disposition refuses too -- the operator names every plan phase.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r3 normal --skipped grill:"reason=home-turf: x" --ran spec --ran design-record \
         --skipped test-plan:"prose" --ran build --ran review --ran docs --ran ship 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C3 missing lite phase 'think' exits 64" 0 || assert "C3 missing lite phase 'think' exits 64 (got $RC)" 1
[ -z "$(ledger_of r3)" ] && assert "C3 writes nothing" 0 || assert "C3 writes nothing" 1

# ---------------------------------------------------------------------------
# C4: a phase that is not in the lane's plan refuses, and writes nothing.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r4 normal --skipped grill:"reason=home-turf: x" "${NORMAL_TAIL[@]}" \
         --ran ship --ran reflect:"not a normal-lane phase" 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C4 off-plan phase exits 64" 0 || assert "C4 off-plan phase exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q "is not a phase of lane 'normal'" \
  && assert "C4 says the phase is off-plan" 0 || assert "C4 says the phase is off-plan (got: $OUT)" 1
[ -z "$(ledger_of r4)" ] && assert "C4 writes nothing" 0 || assert "C4 writes nothing" 1

# ---------------------------------------------------------------------------
# C5: the same phase given twice refuses, and writes nothing.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r5 normal --skipped grill:"reason=home-turf: x" "${NORMAL_TAIL[@]}" \
         --ran ship --ran build:"again" 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C5 duplicate phase exits 64" 0 || assert "C5 duplicate phase exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q "phase 'build' given twice" \
  && assert "C5 names the duplicated phase" 0 || assert "C5 names the duplicated phase (got: $OUT)" 1
[ -z "$(ledger_of r5)" ] && assert "C5 writes nothing" 0 || assert "C5 writes nothing" 1

# ---------------------------------------------------------------------------
# C6: --skipped with no reason refuses; --ran with no reason is fine (record() allows it).
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r6 normal --skipped grill:"reason=home-turf: x" --ran think --ran spec \
         --ran design-record --skipped test-plan --ran build --ran review --ran docs --ran ship 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C6 --skipped without a reason exits 64" 0 || assert "C6 --skipped without a reason exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'needs a reason' \
  && assert "C6 asks for the reason" 0 || assert "C6 asks for the reason (got: $OUT)" 1
[ -z "$(ledger_of r6)" ] && assert "C6 writes nothing" 0 || assert "C6 writes nothing" 1

# ---------------------------------------------------------------------------
# C7: an --override with no reason refuses (override() requires one; the dry run never starts).
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r7 normal --skipped grill:"reason=home-turf: x" --ran think --override spec \
         --ran design-record --skipped test-plan:"prose" --ran build --ran review --ran docs 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C7 --override without a reason exits 64" 0 || assert "C7 --override without a reason exits 64 (got $RC)" 1
[ -z "$(ledger_of r7)" ] && assert "C7 writes nothing" 0 || assert "C7 writes nothing" 1

# ---------------------------------------------------------------------------
# C8: the grill-skip reason enum still fires through plan-record, and nothing lands.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r8 normal --skipped grill:"just because" "${NORMAL_TAIL[@]}" --ran ship 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && assert "C8 bad grill reason enum refuses" 0 || assert "C8 bad grill reason enum refuses (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'a grill skip needs reason=' \
  && assert "C8 the enum rule speaks for itself" 0 || assert "C8 the enum rule speaks for itself (got: $OUT)" 1
[ -z "$(ledger_of r8)" ] && assert "C8 writes nothing, no partial ledger" 0 || assert "C8 writes nothing (got: $(ledger_of r8))" 1

# ---------------------------------------------------------------------------
# C9: the distinct-override-reason guard still fires across two phases of ONE call.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r9 normal --skipped grill:"reason=home-turf: x" --ran think \
         --override spec:"same reason twice" --override design-record:"same reason twice" \
         --skipped test-plan:"prose" --ran build --ran review --ran docs 2>&1)"; RC=$?
[ "$RC" -eq 65 ] && assert "C9 duplicate override reason exits 65" 0 || assert "C9 duplicate override reason exits 65 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'each gate override needs its own reason' \
  && assert "C9 the override guard speaks for itself" 0 || assert "C9 the override guard speaks for itself (got: $OUT)" 1
[ -z "$(ledger_of r9)" ] && assert "C9 writes nothing" 0 || assert "C9 writes nothing (got: $(ledger_of r9))" 1

# ---------------------------------------------------------------------------
# C10: an override whose reason a PRIOR call already used for another phase is still rejected,
# so the dry run reads the run's real history and not just its own set.
# ---------------------------------------------------------------------------
new_log
gl record r10 spec ran >/dev/null 2>&1
gl override r10 build "one pasted reason" >/dev/null 2>&1
OUT="$(gl plan-record r10 normal --skipped grill:"reason=home-turf: x" --ran think --ran spec \
         --override design-record:"one pasted reason" --skipped test-plan:"prose" --ran build \
         --ran review --ran docs 2>&1)"; RC=$?
[ "$RC" -eq 65 ] && assert "C10 reason reused from an earlier call exits 65" 0 || assert "C10 reason reused from an earlier call exits 65 (got $RC)" 1
[ "$(ledger_of r10 | grep -c '| GATE | ')" -eq 2 ] \
  && assert "C10 the pre-existing ledger is untouched" 0 || assert "C10 the pre-existing ledger is untouched (got: $(ledger_of r10))" 1

# ---------------------------------------------------------------------------
# C11: ship omitted is accepted (the push records it); the verb exits 0 and says a gate is open.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r11 normal --skipped grill:"reason=home-turf: x" "${NORMAL_TAIL[@]}" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && assert "C11 ship omitted exits 0" 0 || assert "C11 ship omitted exits 0 (got $RC: $OUT)" 1
[ "$(ledger_of r11 | grep -c '| GATE | ')" -eq 8 ] \
  && assert "C11 the other 8 phases were written" 0 || assert "C11 the other 8 phases were written" 1
printf '%s\n' "$OUT" | grep -q 'MISSING-GATE: ship' \
  && assert "C11 check's open-gate verdict is surfaced" 0 || assert "C11 check's open-gate verdict is surfaced (got: $OUT)" 1

# ---------------------------------------------------------------------------
# C12: an unknown lane refuses before any parse or write.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r12 nosuchlane --ran build 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && assert "C12 unknown lane refuses" 0 || assert "C12 unknown lane refuses (got $RC)" 1
[ -z "$(ledger_of r12)" ] && assert "C12 writes nothing" 0 || assert "C12 writes nothing" 1

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ] || exit 1
