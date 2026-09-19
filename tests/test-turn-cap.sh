#!/usr/bin/env bash
# test-turn-cap.sh
# Pins the per-agent turn ceiling in lib/queue/orchestrate.sh (SPEC-303): a claude
# sub-goal session dispatched with TURN_CAP>0 runs under `--max-turns N` + a forced
# stream-json capture; a session that ends on `subtype:error_max_turns` gets a
# deterministic handoff-gen continuation (HANDOFF-<id>.seg.md) and re-dispatches
# the SAME sub-goal as a fresh segment, up to TURN_CAP_SEGMENTS.
#
# Controls:
#   * below the ceiling (subtype:success) -> exactly ONE dispatch, no continuation.
#   * a capped session that ALSO flipped its box -> no extra segment.
#   * the stall watchdog stays the LEASE: a lapsed lease alerts (stalled event)
#     and never kills; the same run completes in ONE segment.
#   * segment exhaustion emits a `blocked` event and halts the sub-goal.
#   * TURN_CAP=0 restores the pre-ceiling dispatch (no --max-turns, no capture).
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Pin the kit-root config layer to this checkout (same convention as test-orchestrate.sh)
# so `[mega].turn_cap` resolution reads THIS kit.toml, not a dev machine's installed copy.
export KIT_CONFIG_ROOT="${KIT_CONFIG_ROOT:-$KIT}"
export KIT_PROJECT_ROOT="${KIT_PROJECT_ROOT:-$(mktemp -d)}"
ORCH="$KIT/lib/queue/orchestrate.sh"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture: one auto sub-goal; the run ends "all checked; done" on flip ---
mk_megagoal() {
  local d="$1"
  mkdir -p "$d/goals"
  cat > "$d/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 first thing , auto , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  printf '# SG-01\n**Branch:** feat/turncap-fixture\n' > "$d/goals/01-first.md"
  printf 'Do the work for sub-goal SG-01, then flip its ROADMAP box.\n' > "$d/goals/01-first.prompt.md"
}

# --- mock claude: a segment counter + stream-json results driven by MOCK_DONE_AT ---
# Invocation N < MOCK_DONE_AT  -> emits an assistant usage event + result
#   subtype:error_max_turns and exits 1 (the real CLI's --max-turns exit shape).
# Invocation N >= MOCK_DONE_AT -> emits subtype:success, flips the box, exits 0.
# MOCK_CAP_AND_FLIP=1 -> invocation 1 emits error_max_turns AND flips the box
#   (finished exactly at the ceiling -> no successor segment may run).
# Records: per-invocation prompt to $MOCK_PDIR/prompt.N, argv to $MOCK_ARGS.
mk_mock() {
  cat > "$TMP/claude-mock" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_ARGS"
prompt=$(cat)
n=$(cat "$MOCK_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$MOCK_COUNT"
mkdir -p "$MOCK_PDIR"; printf '%s\n' "$prompt" > "$MOCK_PDIR/prompt.$n"
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
flip() { awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' \
  "$MOCK_ROADMAP" > "$MOCK_ROADMAP.tmp" && mv "$MOCK_ROADMAP.tmp" "$MOCK_ROADMAP"; }
[ "${MOCK_SLEEP:-0}" -gt 0 ] && sleep "$MOCK_SLEEP"
printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":20,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"seg %s"}]}}\n' "$n"
if [ "${MOCK_CAP_AND_FLIP:-0}" = 1 ] || [ "$n" -lt "${MOCK_DONE_AT:-1}" ]; then
  printf '{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":3}\n'
  [ "${MOCK_CAP_AND_FLIP:-0}" = 1 ] && flip
  exit 1
fi
printf '{"type":"result","subtype":"success","num_turns":2}\n'
flip
exit 0
EOF
  chmod +x "$TMP/claude-mock"
}

evlog() { [ -f "$1/.orchestrate/events.log" ] && cat "$1/.orchestrate/events.log"; }
ev_has() { awk -F'\t' -v id="$1" -v st="$2" '$2==id && $3==st{f=1} END{exit !f}' "$3"; }
invocations() { cat "$1" 2>/dev/null || echo 0; }

mk_mock

# ============================ TEST 1: ceiling triggers handoff + re-dispatch ==========
D1="$TMP/mg1"; mk_megagoal "$D1"
export MOCK_ROADMAP="$D1/ROADMAP.md" MOCK_COUNT="$TMP/count1" MOCK_PDIR="$TMP/pdir1" MOCK_ARGS="$TMP/args1.log" MOCK_DONE_AT=2
TIER4_CLOSE=0 TURN_CAP=3 CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D1" > "$TMP/t1.out" 2>&1 < /dev/null
rc=$?
[ "$rc" = 0 ] && pass "cap run rc 0" || { fail "cap run rc=$rc"; cat "$TMP/t1.out"; }
[ "$(invocations "$TMP/count1")" = 2 ] && pass "ceiling re-dispatched exactly once (2 segments)" \
  || fail "invocations: $(invocations "$TMP/count1")"
[ -f "$D1/HANDOFF-SG-01.seg.md" ] && grep -q 'Next sub-goal: SG-01' "$D1/HANDOFF-SG-01.seg.md" \
  && pass "deterministic segment handoff written (HANDOFF-SG-01.seg.md)" \
  || { fail "no segment handoff"; ls "$D1"; }
grep -q 'TURN-CEILING CONTINUATION' "$TMP/pdir1/prompt.2" \
  && pass "segment 2 prompt carries the continuation block" || fail "no continuation in segment-2 prompt"
grep -q "HANDOFF-SG-01.seg.md" "$TMP/pdir1/prompt.2" \
  && pass "continuation points at the per-id handoff" || fail "continuation missing handoff pointer"
! grep -q 'TURN-CEILING CONTINUATION' "$TMP/pdir1/prompt.1" \
  && pass "segment 1 prompt is the unmodified original" || fail "segment 1 prompt polluted"
ev_has SG-01 handoff "$D1/.orchestrate/events.log" \
  && pass "events.log records the segment handoff" || { fail "no handoff event"; evlog "$D1"; }
[ -f "$D1/.orchestrate/SG-01.seg1.stream.jsonl" ] && [ -f "$D1/.orchestrate/SG-01.stream.jsonl" ] \
  && pass "capped segment transcript archived, final segment kept the live name" \
  || { fail "segment transcripts wrong"; ls "$D1/.orchestrate"; }
grep -q '^- \[x\] SG-01' "$D1/ROADMAP.md" && pass "SG-01 box flipped by the successor segment" \
  || fail "SG-01 box unflipped"
[ -s "$D1/DECISIONS.md" ] && pass "DECISIONS.md appended by the segment regen" || fail "no DECISIONS.md"

# per-segment token accounting: the capped segment's usage is recorded before its
# transcript is archived (the caller's hook only sees the final segment's file).
LOGD="$TMP/tok-logs"; mkdir -p "$LOGD"
D1B="$TMP/mg1b"; mk_megagoal "$D1B"
export MOCK_ROADMAP="$D1B/ROADMAP.md" MOCK_COUNT="$TMP/count1b" MOCK_PDIR="$TMP/pdir1b" MOCK_ARGS="$TMP/args1b.log" MOCK_DONE_AT=2
TIER4_CLOSE=0 TURN_CAP=3 DWARVES_KIT_LOG_DIR="$LOGD" CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D1B" >/dev/null 2>&1 < /dev/null
TL="$LOGD/runs/turncap-fixture.log"
{ [ -f "$TL" ] && [ "$(grep -c '| TOKENS |' "$TL")" = 2 ]; } \
  && pass "both segments recorded TOKENS (capped segment + final)" \
  || { fail "per-segment TOKENS wrong"; cat "$TL" 2>&1; }

# ============================ TEST 2: negative control, below the ceiling =============
D2="$TMP/mg2"; mk_megagoal "$D2"
export MOCK_ROADMAP="$D2/ROADMAP.md" MOCK_COUNT="$TMP/count2" MOCK_PDIR="$TMP/pdir2" MOCK_ARGS="$TMP/args2.log" MOCK_DONE_AT=1 MOCK_CAP_AND_FLIP=0
TIER4_CLOSE=0 TURN_CAP=3 CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D2" > "$TMP/t2.out" 2>&1 < /dev/null
rc=$?
{ [ "$rc" = 0 ] && [ "$(invocations "$TMP/count2")" = 1 ]; } \
  && pass "below ceiling: exactly one dispatch, no re-dispatch" \
  || { fail "below-ceiling run wrong (rc=$rc, n=$(invocations "$TMP/count2"))"; cat "$TMP/t2.out"; }
[ ! -f "$D2/HANDOFF-SG-01.seg.md" ] && ! ls "$D2/.orchestrate/"*.seg*.stream.jsonl >/dev/null 2>&1 \
  && pass "below ceiling: no segment handoff or archived transcript" \
  || fail "below-ceiling run produced segment artifacts"

# ============================ TEST 3: capped AND box flipped -> no extra segment ======
D3="$TMP/mg3"; mk_megagoal "$D3"
export MOCK_ROADMAP="$D3/ROADMAP.md" MOCK_COUNT="$TMP/count3" MOCK_PDIR="$TMP/pdir3" MOCK_ARGS="$TMP/args3.log" MOCK_DONE_AT=99 MOCK_CAP_AND_FLIP=1
TIER4_CLOSE=0 TURN_CAP=3 CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D3" > "$TMP/t3.out" 2>&1 < /dev/null
{ [ "$(invocations "$TMP/count3")" = 1 ] && grep -q '^- \[x\] SG-01' "$D3/ROADMAP.md"; } \
  && pass "finished at the ceiling: box flipped, no successor segment" \
  || { fail "capped+flipped dispatched a successor (n=$(invocations "$TMP/count3"))"; cat "$TMP/t3.out"; }

# ============================ TEST 4: lease vs ceiling ================================
# The stall watchdog is the LEASE: it ALERTS on a lapsed lease and never kills. A mock
# that stalls past WATCHDOG_STALL_SECS then succeeds completes in ONE segment (the
# ceiling did not fire, the session was not stopped).
D4="$TMP/mg4"; mk_megagoal "$D4"
export MOCK_ROADMAP="$D4/ROADMAP.md" MOCK_COUNT="$TMP/count4" MOCK_PDIR="$TMP/pdir4" MOCK_ARGS="$TMP/args4.log" MOCK_DONE_AT=1 MOCK_CAP_AND_FLIP=0 MOCK_SLEEP=4
WATCHDOG_STALL_SECS=2 WATCHDOG_POLL_SECS=1 TIER4_CLOSE=0 TURN_CAP=3 CLAUDE_CMD="$TMP/claude-mock" \
  bash "$ORCH" run "$D4" > "$TMP/t4.out" 2>&1 < /dev/null
rc=$?
{ [ "$rc" = 0 ] && grep -q 'watchdog\] WARN: SG-01 stalled' "$TMP/t4.out" \
  && ev_has SG-01 stalled "$D4/.orchestrate/events.log"; } \
  && pass "lease lapsed: stall WARN + stalled event (advisory)" \
  || { fail "stall did not alert"; cat "$TMP/t4.out"; }
{ [ "$(invocations "$TMP/count4")" = 1 ] && grep -q '^- \[x\] SG-01' "$D4/ROADMAP.md"; } \
  && pass "lapsed lease did NOT stop the session (1 segment, box flipped)" \
  || { fail "lease stopped the session (n=$(invocations "$TMP/count4"))"; cat "$TMP/t4.out"; }
unset MOCK_SLEEP

# ============================ TEST 5: segment bound halts =============================
D5="$TMP/mg5"; mk_megagoal "$D5"
export MOCK_ROADMAP="$D5/ROADMAP.md" MOCK_COUNT="$TMP/count5" MOCK_PDIR="$TMP/pdir5" MOCK_ARGS="$TMP/args5.log" MOCK_DONE_AT=99 MOCK_CAP_AND_FLIP=0
TIER4_CLOSE=0 TURN_CAP=2 TURN_CAP_SEGMENTS=2 CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D5" > "$TMP/t5.out" 2>&1 < /dev/null
rc=$?
{ [ "$rc" != 0 ] && [ "$(invocations "$TMP/count5")" = 2 ]; } \
  && pass "segment bound: exactly TURN_CAP_SEGMENTS dispatches, then halt" \
  || { fail "segment bound wrong (rc=$rc, n=$(invocations "$TMP/count5"))"; cat "$TMP/t5.out"; }
ev_has SG-01 blocked "$D5/.orchestrate/events.log" \
  && grep -q 'exhausted 2 segments' "$D5/.orchestrate/events.log" \
  && pass "exhaustion recorded as a blocked event" || { fail "no exhaustion event"; evlog "$D5"; }
grep -q '^- \[ \] SG-01' "$D5/ROADMAP.md" && pass "exhausted sub-goal box stays unchecked" \
  || fail "exhausted sub-goal wrongly flipped"

# ============================ TEST 6: --max-turns reaches the argv =====================
D6="$TMP/mg6"; mk_megagoal "$D6"
export MOCK_ROADMAP="$D6/ROADMAP.md" MOCK_COUNT="$TMP/count6" MOCK_PDIR="$TMP/pdir6" MOCK_ARGS="$TMP/args6.log" MOCK_DONE_AT=1
TIER4_CLOSE=0 TURN_CAP=7 CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D6" >/dev/null 2>&1 < /dev/null
grep -q -- '--max-turns 7' "$TMP/args6.log" \
  && pass "--max-turns 7 on the claude argv" || { fail "no --max-turns"; cat "$TMP/args6.log"; }

# TURN_CAP=0: the off switch restores the pre-ceiling dispatch (no flag, no forced capture).
D6B="$TMP/mg6b"; mk_megagoal "$D6B"
export MOCK_ROADMAP="$D6B/ROADMAP.md" MOCK_COUNT="$TMP/count6b" MOCK_PDIR="$TMP/pdir6b" MOCK_ARGS="$TMP/args6b.log" MOCK_DONE_AT=1
TIER4_CLOSE=0 TURN_CAP=0 CLAUDE_CMD="$TMP/claude-mock" bash "$ORCH" run "$D6B" > "$TMP/t6b.out" 2>&1 < /dev/null
{ ! grep -q -- '--max-turns' "$TMP/args6b.log" && [ ! -f "$D6B/.orchestrate/SG-01.stream.jsonl" ]; } \
  && pass "TURN_CAP=0: no --max-turns, no forced capture (pre-ceiling dispatch)" \
  || { fail "TURN_CAP=0 still capped/captured"; cat "$TMP/args6b.log"; }

# ============================ TEST 7: config resolution + validation ==================
DEFCAP=$(cd "$KIT" && bash -c 'source lib/config/kit-config.sh; kit_config_get mega.turn_cap')
DEFSEG=$(cd "$KIT" && bash -c 'source lib/config/kit-config.sh; kit_config_get mega.turn_cap_segments')
[ "$DEFCAP" = 100 ] && pass "kit.toml ships [mega].turn_cap = 100" || fail "turn_cap resolves '$DEFCAP', want 100"
[ "$DEFSEG" = 10 ] && pass "kit.toml ships [mega].turn_cap_segments = 10" || fail "turn_cap_segments resolves '$DEFSEG', want 10"
out=$(TURN_CAP=9 TURN_CAP_SEGMENTS=4 bash "$ORCH" run "$D6" --dry-run)
echo "$out" | grep -q 'turn ceiling: 9 turns/segment, up to 4 segments' \
  && pass "env override resolves into the dry-run plan" || { fail "dry-run plan missing ceiling"; echo "$out"; }
TURN_CAP=abc bash "$ORCH" run "$D6" > "$TMP/t7b.out" 2>&1; rc=$?
{ [ "$rc" = 64 ] && grep -q 'TURN_CAP must be a non-negative integer' "$TMP/t7b.out"; } \
  && pass "non-numeric TURN_CAP rejected rc 64" || fail "TURN_CAP=abc not rejected (rc=$rc)"
TURN_CAP_SEGMENTS=0 bash "$ORCH" run "$D6" > "$TMP/t7c.out" 2>&1; rc=$?
{ [ "$rc" = 64 ] && grep -q 'TURN_CAP_SEGMENTS must be' "$TMP/t7c.out"; } \
  && pass "TURN_CAP_SEGMENTS=0 rejected rc 64" || fail "TURN_CAP_SEGMENTS=0 not rejected (rc=$rc)"

# ============================ TEST 8: handoff-gen --handoff-name ======================
SEED="$KIT/tests/fixtures/handoff-det/seed.jsonl"
HN="$TMP/hn"; mkdir -p "$HN"
python3 "$KIT/lib/goal/handoff/handoff_gen.py" "$SEED" --dir "$HN" --next-id SG-01 \
  --next-title "first thing" --date 2026-01-01 --handoff-name "HANDOFF-SG-01.seg.md" >/dev/null 2>&1
{ [ -f "$HN/HANDOFF-SG-01.seg.md" ] && [ -f "$HN/DECISIONS.md" ]; } \
  && pass "handoff-gen --handoff-name writes the named hot file + warm ledger" \
  || { fail "--handoff-name output missing"; ls "$HN"; }
python3 "$KIT/lib/goal/handoff/handoff_gen.py" "$SEED" --dir "$HN" --next-id SG-01 \
  --date 2026-01-01 --handoff-name "../escape.md" >/dev/null 2>&1; rc=$?
{ [ "$rc" = 2 ] && [ ! -f "$TMP/escape.md" ]; } \
  && pass "handoff-gen rejects a non-basename --handoff-name" \
  || fail "non-basename --handoff-name accepted (rc=$rc)"

echo "----"
if [ "$fails" = 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$fails FAILING"
  exit 1
fi
