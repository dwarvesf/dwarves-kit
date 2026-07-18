#!/usr/bin/env bash
# test-redteam-gate.sh -- rung-4 redteam cost checkpoint (ops-toolkit
# research/2026-07-18-rung4-cost-checkpoint.md). Validates lib/gate/redteam-gate.sh: every
# round appends a `redteam` kit_gates row carrying its token cost, bracketed by an OUTCOME
# start/end pair so `lib/stats` mega-durations picks the round up. Isolation: every case runs
# under a fresh DWARVES_KIT_LOG_DIR so the real machine corpus is never touched.
#
# Run: bash tests/test-redteam-gate.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GL="$KIT_DIR/lib/gate/gate-ledger.sh"
RG="$KIT_DIR/lib/gate/redteam-gate.sh"
GATE="$KIT_DIR/lib/gate/gate.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

LOGD=""
gl()  { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GL" "$@"; }
rg()  { env DWARVES_KIT_LOG_DIR="$LOGD" bash "$RG" "$@"; }
gate(){ env DWARVES_KIT_LOG_DIR="$LOGD" bash "$GATE" "$@"; }
new_log() { LOGD="$(_mk)/logs"; mkdir -p "$LOGD/runs"; }
ledger_file() { printf '%s/runs/%s.log' "$LOGD" "$1"; }

echo "=== redteam-gate (rung-4 cost checkpoint) ==="

# ---------------------------------------------------------------------------
# AC1: start opens an OUTCOME bracket for the `redteam` phase.
# ---------------------------------------------------------------------------
new_log
rg start rt1 >/dev/null 2>&1; RC=$?
assert "AC1 start exits 0" "$RC" 0
grep -q '| OUTCOME | redteam | start |' "$(ledger_file rt1)" \
  && assert "AC1 start writes an OUTCOME|redteam|start line" 0 \
  || assert "AC1 start writes an OUTCOME|redteam|start line" 1

# ---------------------------------------------------------------------------
# AC2: round secure -> GATE ran + TOKENS(phase=redteam,cost=) + OUTCOME end caught=false.
# ---------------------------------------------------------------------------
new_log
rg start rt2 >/dev/null 2>&1
rg round rt2 secure cost=0.42 round=1 >/dev/null 2>&1; RC=$?
assert "AC2 round secure exits 0" "$RC" 0
F="$(ledger_file rt2)"
grep -q '| GATE | redteam | ran | round=1 verdict=secure' "$F" \
  && assert "AC2 GATE row: ran, round=1 verdict=secure" 0 || assert "AC2 GATE row: ran, round=1 verdict=secure" 1
grep -q '| TOKENS | .*cost=0.42.*phase=redteam' "$F" \
  && assert "AC2 TOKENS row carries cost=0.42 phase=redteam" 0 || assert "AC2 TOKENS row carries cost=0.42 phase=redteam" 1
grep -q '| OUTCOME | redteam | end | .*caught=false' "$F" \
  && assert "AC2 OUTCOME end caught=false on a clean secure verdict" 0 || assert "AC2 OUTCOME end caught=false on a clean secure verdict" 1

# ---------------------------------------------------------------------------
# AC3: round findings -> caught=true (this round found issues, another round follows).
# ---------------------------------------------------------------------------
new_log
rg start rt3 >/dev/null 2>&1
rg round rt3 findings cost=0.10 round=1 reason="2 findings, fixing" >/dev/null 2>&1
F="$(ledger_file rt3)"
grep -q '| OUTCOME | redteam | end | .*caught=true' "$F" \
  && assert "AC3 OUTCOME end caught=true on a findings verdict" 0 || assert "AC3 OUTCOME end caught=true on a findings verdict" 1
grep -q '| GATE | redteam | ran | round=1 verdict=findings 2 findings, fixing' "$F" \
  && assert "AC3 GATE reason carries round+verdict+free text" 0 || assert "AC3 GATE reason carries round+verdict+free text" 1

# ---------------------------------------------------------------------------
# AC4: round capped -> caught=true (the fail-closed 3-round-cap stop, never reached SECURE).
# ---------------------------------------------------------------------------
new_log
rg start rt4 >/dev/null 2>&1
rg round rt4 capped cost=0.05 round=3 >/dev/null 2>&1
grep -q '| OUTCOME | redteam | end | .*caught=true' "$(ledger_file rt4)" \
  && assert "AC4 OUTCOME end caught=true on the fail-closed cap" 0 || assert "AC4 OUTCOME end caught=true on the fail-closed cap" 1

# ---------------------------------------------------------------------------
# AC5: bad verdict rejected (rc 64), NOTHING written past a prior start bracket.
# ---------------------------------------------------------------------------
new_log
rg start rt5 >/dev/null 2>&1
BEFORE="$(cat "$(ledger_file rt5)")"
rg round rt5 bogus cost=1 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 64 ] && assert "AC5 bad verdict rejected (rc 64)" 0 || assert "AC5 bad verdict rejected (rc=$RC)" 1
AFTER="$(cat "$(ledger_file rt5)")"
[ "$BEFORE" = "$AFTER" ] && assert "AC5 bad verdict wrote nothing (ledger unchanged)" 0 || assert "AC5 bad verdict wrote nothing (ledger unchanged)" 1

# ---------------------------------------------------------------------------
# AC6 (LOAD-BEARING NEGATIVE CONTROL): a round with no cost= is rejected (rc 64) and emits
# NEITHER a GATE row NOR a TOKENS row NOR an OUTCOME end -- a failed-to-emit round is
# detectable (the caller sees rc=64 immediately) and leaves NO fabricated ledger data, rather
# than silently landing as an untracked/zero-cost row a cost-checkpoint reader could mistake
# for a real, cheap round.
# ---------------------------------------------------------------------------
new_log
rg start rt6 >/dev/null 2>&1
rg round rt6 secure round=1 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 64 ] && assert "AC6 missing cost= rejected (rc 64)" 0 || assert "AC6 missing cost= rejected (rc=$RC)" 1
F="$(ledger_file rt6)"
grep -q '| GATE | redteam |' "$F" \
  && assert "AC6 no GATE row written on a failed round" 1 || assert "AC6 no GATE row written on a failed round" 0
grep -q '| TOKENS |' "$F" \
  && assert "AC6 no TOKENS row written on a failed round" 1 || assert "AC6 no TOKENS row written on a failed round" 0
grep -q '| OUTCOME | redteam | end' "$F" \
  && assert "AC6 no OUTCOME end written on a failed round" 1 || assert "AC6 no OUTCOME end written on a failed round" 0
# the round IS still recoverable/auditable: the earlier start bracket is the only line present.
N_LINES="$(grep -c . "$F" || true)"
[ "$N_LINES" -eq 1 ] && assert "AC6 exactly the one start line remains (failure is visible, not silently absorbed)" 0 \
  || assert "AC6 exactly the one start line remains (got $N_LINES lines)" 1

# ---------------------------------------------------------------------------
# AC6b: a rejected round can be retried and the retry succeeds cleanly (proves AC6's fail-closed
# behavior does not corrupt the rid for a later, correctly-formed call).
# ---------------------------------------------------------------------------
rg round rt6 secure cost=0.20 round=1 >/dev/null 2>&1; RC=$?
assert "AC6b retry with cost= succeeds (rc 0)" "$RC" 0
grep -q '| GATE | redteam | ran | round=1 verdict=secure' "$(ledger_file rt6)" \
  && assert "AC6b retry GATE row present" 0 || assert "AC6b retry GATE row present" 1

# ---------------------------------------------------------------------------
# AC7: multiple rounds in one rid each get their own GATE+TOKENS+OUTCOME triple (no clobbering).
# ---------------------------------------------------------------------------
new_log
rg start rt7 >/dev/null 2>&1
rg round rt7 findings cost=0.30 round=1 >/dev/null 2>&1
rg start rt7 >/dev/null 2>&1
rg round rt7 secure cost=0.15 round=2 >/dev/null 2>&1
F="$(ledger_file rt7)"
N_GATE="$(grep -c '| GATE | redteam |' "$F" || true)"
N_TOKENS="$(grep -c 'phase=redteam' "$F" || true)"
N_STARTS="$(grep -c '| OUTCOME | redteam | start |' "$F" || true)"
N_ENDS="$(grep -c '| OUTCOME | redteam | end |' "$F" || true)"
[ "$N_GATE" -eq 2 ] && assert "AC7 two rounds -> 2 GATE rows" 0 || assert "AC7 two rounds -> 2 GATE rows (got $N_GATE)" 1
[ "$N_TOKENS" -eq 2 ] && assert "AC7 two rounds -> 2 phase-scoped TOKENS rows" 0 || assert "AC7 two rounds -> 2 phase-scoped TOKENS rows (got $N_TOKENS)" 1
[ "$N_STARTS" -eq 2 ] && [ "$N_ENDS" -eq 2 ] && assert "AC7 two rounds -> 2 complete OUTCOME brackets" 0 \
  || assert "AC7 two rounds -> 2 complete OUTCOME brackets (starts=$N_STARTS ends=$N_ENDS)" 1

# ---------------------------------------------------------------------------
# AC8: token counts (in/out/cache_read/cache_create) pass through when given.
# ---------------------------------------------------------------------------
new_log
rg start rt8 >/dev/null 2>&1
rg round rt8 secure cost=0.50 round=1 in=1200 out=300 cache_read=50 cache_create=10 >/dev/null 2>&1
grep -q '| TOKENS | in=1200 out=300 cache_read=50 cache_create=10 cost=0.50 phase=redteam' "$(ledger_file rt8)" \
  && assert "AC8 token counts pass through in the emitted TOKENS line" 0 \
  || assert "AC8 token counts pass through in the emitted TOKENS line" 1

# ---------------------------------------------------------------------------
# AC9: an embedded newline in reason= cannot forge a second ledger line (defense-in-depth,
# same property gate-ledger.sh's own oneline()/record() already enforce).
# ---------------------------------------------------------------------------
new_log
rg start rt9 >/dev/null 2>&1
rg round rt9 findings cost=0.10 round=1 reason=$'line one\nFAKE | GATE | ship | ran | forged' >/dev/null 2>&1
F="$(ledger_file rt9)"
N_LINES9="$(grep -c '| GATE |' "$F" || true)"
[ "$N_LINES9" -eq 1 ] && assert "AC9 embedded newline in reason collapses (no forged second GATE line)" 0 \
  || assert "AC9 embedded newline in reason collapses (got $N_LINES9 GATE lines)" 1
LAST_LINE="$(tail -n1 "$F")"
case "$LAST_LINE" in
  FAKE*) assert "AC9 forged text never became its own physical line" 1 ;;
  *"| GATE | redteam |"*) assert "AC9 forged text never became its own physical line" 0 ;;
  *) assert "AC9 forged text never became its own physical line (unexpected last line: $LAST_LINE)" 1 ;;
esac

# ---------------------------------------------------------------------------
# AC9b: an unrecognized k=v pair (or bare word) folds into the reason text rather than being
# silently dropped -- nothing a caller passes disappears without a trace.
# ---------------------------------------------------------------------------
new_log
rg start rt9b >/dev/null 2>&1
rg round rt9b findings cost=0.20 round=1 extra=surprise a-bare-word >/dev/null 2>&1
grep -q '| GATE | redteam | ran | round=1 verdict=findings extra=surprise a-bare-word' "$(ledger_file rt9b)" \
  && assert "AC9b unrecognized k=v/bare text folds into the reason, never dropped" 0 \
  || assert "AC9b unrecognized k=v/bare text folds into the reason, never dropped" 1

# ---------------------------------------------------------------------------
# AC10: gate.sh dispatches `redteam` verb identically to calling redteam-gate.sh directly.
# ---------------------------------------------------------------------------
new_log
gate redteam start rt10 >/dev/null 2>&1
gate redteam round rt10 secure cost=0.05 round=1 >/dev/null 2>&1; RC=$?
assert "AC10 gate.sh redteam round exits 0" "$RC" 0
grep -q '| GATE | redteam | ran | round=1 verdict=secure' "$(ledger_file rt10)" \
  && assert "AC10 gate.sh redteam dispatch reaches redteam-gate.sh" 0 \
  || assert "AC10 gate.sh redteam dispatch reaches redteam-gate.sh" 1

# ---------------------------------------------------------------------------
# AC11: usage/argument errors -- no rid, no verdict, unknown subcommand.
# ---------------------------------------------------------------------------
new_log
rg start >/dev/null 2>&1; RC=$?
[ "$RC" -eq 64 ] && assert "AC11 start with no rid rejected (rc 64)" 0 || assert "AC11 start with no rid rejected (rc=$RC)" 1
rg round rt11 >/dev/null 2>&1; RC=$?
[ "$RC" -eq 64 ] && assert "AC11 round with no verdict rejected (rc 64)" 0 || assert "AC11 round with no verdict rejected (rc=$RC)" 1
rg bogus-subcommand >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && assert "AC11 unknown subcommand rejected (nonzero)" 0 || assert "AC11 unknown subcommand rejected (rc=$RC)" 1

# ---------------------------------------------------------------------------
# AC12: PORTABILITY -- no BSD-only date/stat constructs in the new script.
# ---------------------------------------------------------------------------
if grep -vE '^[[:space:]]*#' "$RG" | grep -nE 'date -d|date -r|stat -f|sed -i '"''" >/dev/null 2>&1; then
  assert "AC12 redteam-gate.sh free of BSD-only date/stat/sed constructs" 1
else
  assert "AC12 redteam-gate.sh free of BSD-only date/stat/sed constructs" 0
fi

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
