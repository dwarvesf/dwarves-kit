#!/usr/bin/env bash
# test-gate-ledger-plan-record.sh -- `gate-ledger.sh plan-record <rid> <lane> ...` writes one GATE
# line per named plan phase in a single call, and refuses without writing anything when the
# disposition set is incomplete or invalid.
#
# The record-batch cases (RB1-RB7) at the end pin `record-batch <rid> <lane> <phase>=<state>:<evidence> ...`:
# per-phase evidence, start-or-amend, override routing, refuse-before-write, and check's exit status.
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
_mk() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

LOGD=""
gl() { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" "$@"; }
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }
# Bytes on disk for a rid, honest-empty when the verb refused before writing.
ledger_of() { cat "$LOGD/runs/$1.log" 2>/dev/null; }

# The full normal-lane set minus grill, reused by the cases that vary only one disposition.
NORMAL_TAIL=(--ran think:"traced it" --ran spec:"wrote it" --ran validate:"APPROVED fresh agent=t"
             --ran design-record:"in the spec"
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
[ "$(printf '%s\n' "$OUT" | grep -c '^[a-z-]* *\(ran\|skipped\|override\)$')" -eq 10 ] \
  && assert "C1 one printed line per phase written" 0 || assert "C1 one printed line per phase written (got: $OUT)" 1
gl check normal r1 >/dev/null 2>&1 \
  && assert "C1 check passes with no further calls" 0 || assert "C1 check passes with no further calls" 1
# the lines are byte-identical to what record()/override() write by hand
ledger_of r1 | grep -q '| GATE | grill | skipped | reason=home-turf: known area$' \
  && assert "C1 grill line keeps the record() format" 0 || assert "C1 grill line keeps the record() format (got: $(ledger_of r1))" 1
[ "$(ledger_of r1 | grep -c '| GATE | ')" -eq 10 ] \
  && assert "C1 exactly 10 GATE lines written" 0 || assert "C1 exactly 10 GATE lines written (got: $(ledger_of r1 | grep -c '| GATE | '))" 1

# ---------------------------------------------------------------------------
# C2: a required plan phase with no disposition refuses, and writes nothing.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r2 normal --skipped grill:"reason=home-turf: x" --ran think --ran validate \
         --ran design-record --skipped test-plan:"prose" --ran build --ran review --ran docs 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C2 missing 'spec' exits 64" 0 || assert "C2 missing 'spec' exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'no disposition' \
  && assert "C2 names the undisposed phase" 0 || assert "C2 names the undisposed phase (got: $OUT)" 1
[ -z "$(ledger_of r2)" ] && assert "C2 writes nothing" 0 || assert "C2 writes nothing (got: $(ledger_of r2))" 1

# ---------------------------------------------------------------------------
# C3: a lite phase with no disposition refuses too -- the operator names every plan phase.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r3 normal --skipped grill:"reason=home-turf: x" --ran spec --ran validate --ran design-record \
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
         --ran validate --ran design-record --skipped test-plan --ran build --ran review --ran docs --ran ship 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C6 --skipped without a reason exits 64" 0 || assert "C6 --skipped without a reason exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'needs a reason' \
  && assert "C6 asks for the reason" 0 || assert "C6 asks for the reason (got: $OUT)" 1
[ -z "$(ledger_of r6)" ] && assert "C6 writes nothing" 0 || assert "C6 writes nothing" 1

# ---------------------------------------------------------------------------
# C7: an --override with no reason refuses (override() requires one; the dry run never starts).
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r7 normal --skipped grill:"reason=home-turf: x" --ran think --override spec \
         --ran validate --ran design-record --skipped test-plan:"prose" --ran build --ran review --ran docs 2>&1)"; RC=$?
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
         --ran validate --skipped test-plan:"prose" --ran build --ran review --ran docs 2>&1)"; RC=$?
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
         --ran validate --override design-record:"one pasted reason" --skipped test-plan:"prose" --ran build \
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
[ "$(ledger_of r11 | grep -c '| GATE | ')" -eq 9 ] \
  && assert "C11 the other 9 phases were written" 0 || assert "C11 the other 9 phases were written" 1
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
# C13: happy path on a rid that already has a START line (the real shape: start, then
# plan-record). The dry run appends to its scratch copy, so the drift check must compare
# the live file against a pristine copy, not against the mutated one.
# ---------------------------------------------------------------------------
new_log
gl start r13 normal normal spec-feature spec-feature >/dev/null 2>&1
OUT="$(gl plan-record r13 normal --skipped grill:"reason=home-turf: known area" \
         "${NORMAL_TAIL[@]}" --ran ship:"pushed" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && assert "C13 plan-record exits 0 after start" 0 || assert "C13 plan-record exits 0 after start (got $RC: $OUT)" 1
gl check normal r13 >/dev/null 2>&1 \
  && assert "C13 check passes after start plus one call" 0 || assert "C13 check passes after start plus one call" 1

# ---------------------------------------------------------------------------
# C14: validate is a normal-lane plan phase (run-lite), so plan-record refuses without its
# disposition and names it; with one, the same call exits 0.
# ---------------------------------------------------------------------------
new_log
OUT="$(gl plan-record r14 normal --skipped grill:"reason=home-turf: x" --ran think --ran spec \
         --ran design-record --skipped test-plan:"prose" --ran build --ran review --ran docs --ran ship 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "C14 missing validate exits 64" 0 || assert "C14 missing validate exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q 'no disposition:.*validate' \
  && assert "C14 names validate as undisposed" 0 || assert "C14 names validate as undisposed (got: $OUT)" 1
[ -z "$(ledger_of r14)" ] && assert "C14 writes nothing" 0 || assert "C14 writes nothing" 1
new_log
OUT="$(gl plan-record r14 normal --skipped grill:"reason=home-turf: x" --ran think --ran spec \
         --skipped validate:"NEEDS REVISION: critical=1" --ran design-record --skipped test-plan:"prose" \
         --ran build --ran review --ran docs --ran ship 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && assert "C14 with a validate disposition exits 0" 0 || assert "C14 with a validate disposition exits 0 (got $RC: $OUT)" 1

# ---------------------------------------------------------------------------
# record-batch: per-phase evidence, start-or-amend, then check.
# ---------------------------------------------------------------------------
echo "=== gate-ledger record-batch ==="

FULL_BATCH=(grill=skipped:"reason=operator-wave: design approved elsewhere" think=ran:"design PR 12" design=ran:"design PR 12 body"
            design-critique=ran:"critique in design PR" spec=ran:"spec merged" validate=ran:"APPROVED fresh agent=t"
            design-record=ran:"in the spec" test-plan=ran:"matrix in spec" build=ran:"branch built"
            review=ran:"review-team clean" docs=ran:"docs updated" ship=ran:"pushed" reflect=override:"lead reflects at wrap")

# RB1: a full batch on a fresh rid opens the run, writes every phase, and check passes (exit 0).
new_log
OUT="$(gl record-batch b1 full "${FULL_BATCH[@]}" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && assert "RB1 full batch exits 0" 0 || assert "RB1 full batch exits 0 (got $RC: $OUT)" 1
gl check full b1 >/dev/null 2>&1 && assert "RB1 check full passes" 0 || assert "RB1 check full passes" 1
[ "$(ledger_of b1 | grep -c '| START | ')" -eq 1 ] && assert "RB1 exactly one START line" 0 || assert "RB1 exactly one START line" 1
[ "$(ledger_of b1 | grep -c '| GATE | ')" -eq 13 ] && assert "RB1 13 GATE lines" 0 || assert "RB1 13 GATE lines (got $(ledger_of b1 | grep -c '| GATE | '))" 1
ledger_of b1 | grep -q '| GATE | design | ran | design PR 12 body$' \
  && assert "RB1 each phase keeps its own evidence in the record() format" 0 || assert "RB1 each phase keeps its own evidence" 1

# RB2: --evidence-default fills items with no evidence; an item's own evidence wins.
new_log
OUT="$(gl record-batch b2 full --evidence-default "ran in design PR 12" think=ran design=ran spec=ran:"own text" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && assert "RB2 partial batch exits with check's status (1)" 0 || assert "RB2 partial batch exits 1 (got $RC)" 1
ledger_of b2 | grep -q '| GATE | think | ran | ran in design PR 12$' \
  && assert "RB2 default evidence fills a bare item" 0 || assert "RB2 default evidence fills a bare item" 1
ledger_of b2 | grep -q '| GATE | spec | ran | own text$' \
  && assert "RB2 item evidence beats the default" 0 || assert "RB2 item evidence beats the default" 1
printf '%s\n' "$OUT" | grep -q 'MISSING-GATE: build' \
  && assert "RB2 check names the still-open gates" 0 || assert "RB2 check names the still-open gates (got: $OUT)" 1

# RB3: a phase outside the lane's plan refuses with 64 and writes nothing, START included.
new_log
OUT="$(gl record-batch b3 full think=ran:"x" nonsense=ran:"y" 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "RB3 unknown phase exits 64" 0 || assert "RB3 unknown phase exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q "'nonsense' is not a phase of lane 'full'" \
  && assert "RB3 names the unknown phase" 0 || assert "RB3 names the unknown phase (got: $OUT)" 1
[ -z "$(ledger_of b3)" ] && assert "RB3 writes nothing" 0 || assert "RB3 writes nothing" 1

# RB4: an item with no evidence and no default refuses; so does an unknown state.
new_log
OUT="$(gl record-batch b4 full think=ran:"x" design=ran 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && assert "RB4 missing evidence exits 64" 0 || assert "RB4 missing evidence exits 64 (got $RC)" 1
printf '%s\n' "$OUT" | grep -q "'design' has no evidence" \
  && assert "RB4 names the phase with no evidence" 0 || assert "RB4 names the phase with no evidence (got: $OUT)" 1
[ -z "$(ledger_of b4)" ] && assert "RB4 writes nothing" 0 || assert "RB4 writes nothing" 1
OUT="$(gl record-batch b4 full think=ran:"x" design=maybe:"y" 2>&1)"; RC=$?
[ "$RC" -eq 64 ] && [ -z "$(ledger_of b4)" ] && assert "RB4 unknown state exits 64 and writes nothing" 0 || assert "RB4 unknown state exits 64 and writes nothing (got $RC)" 1

# RB5: an existing ledger is amended, never given a second plain START, and keeps its type.
new_log
gl start b5 normal normal incident incident >/dev/null 2>&1
OUT="$(gl record-batch b5 full "${FULL_BATCH[@]}" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && assert "RB5 batch on an existing ledger exits 0" 0 || assert "RB5 batch on an existing ledger exits 0 (got $RC: $OUT)" 1
[ "$(ledger_of b5 | grep -c '| START | ')" -eq 1 ] && [ "$(ledger_of b5 | grep -c '| START-AMEND | ')" -eq 1 ] \
  && assert "RB5 one START plus one START-AMEND" 0 || assert "RB5 one START plus one START-AMEND" 1
ledger_of b5 | grep '| START-AMEND | ' | grep -q 'lane=full classified=normal type=incident' \
  && assert "RB5 the amend moves the lane and keeps classified and type" 0 || assert "RB5 the amend moves the lane and keeps classified and type (got: $(ledger_of b5 | grep START-AMEND))" 1
OUT="$(gl record-batch b5 full think=ran:"again" 2>&1)"
[ "$(ledger_of b5 | grep -c '| START | ')" -eq 1 ] && assert "RB5 a second call still adds no plain START" 0 || assert "RB5 a second call still adds no plain START" 1

# RB6: override items land as override lines through override(), with the distinct-reason guard.
new_log
gl record-batch b6 full think=override:"approved in design PR" design=override:"approved in design review" >/dev/null 2>&1
ledger_of b6 | grep -q '| GATE | think | override | approved in design PR$' \
  && ledger_of b6 | grep -q '| GATE | design | override | approved in design review$' \
  && assert "RB6 override items land as override lines" 0 || assert "RB6 override items land as override lines (got: $(ledger_of b6))" 1
new_log
OUT="$(gl record-batch b6 full --evidence-default "same words" think=override design=override 2>&1)"; RC=$?
[ "$RC" -eq 65 ] && assert "RB6 a shared override reason exits 65" 0 || assert "RB6 a shared override reason exits 65 (got $RC: $OUT)" 1
[ -z "$(ledger_of b6)" ] && assert "RB6 the refused batch writes nothing, START included" 0 || assert "RB6 the refused batch writes nothing (got: $(ledger_of b6))" 1

# RB7: a bad lane and a malformed item refuse.
new_log
gl record-batch b7 nolane think=ran:"x" >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && [ -z "$(ledger_of b7)" ] && assert "RB7 unknown lane refuses and writes nothing" 0 || assert "RB7 unknown lane refuses (got $RC)" 1
gl record-batch b7 full think >/dev/null 2>&1; RC=$?
[ "$RC" -eq 64 ] && [ -z "$(ledger_of b7)" ] && assert "RB7 item without = exits 64" 0 || assert "RB7 item without = exits 64 (got $RC)" 1
gl record-batch b7 full think=ran:"x" think=ran:"y" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 64 ] && [ -z "$(ledger_of b7)" ] && assert "RB7 a phase given twice exits 64" 0 || assert "RB7 a phase given twice exits 64 (got $RC)" 1

echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ] || exit 1
