#!/usr/bin/env bash
# test-watchdog-token-capture.sh (ID-097)
# Pins token accounting on the SG-11 watchdog-stall branch of `_run_one_session`/orchestrate.sh:
# a session that STALLS (WATCHDOG_STALL_SECS fires) but then finishes must still have its tokens
# captured to `$slog` and recorded to the SPEC-110 `| TOKENS |` ledger, mirroring the non-watchdog
# capture path's stream-json format + deterministic filename (`_record_tokens`, ID-094/SPEC-117).
# Pre-fix, the watchdog branch NEVER exposed a slog to its caller, so `_record_tokens` always
# no-op'd on a watchdog run -- a stall was an accounting black hole, not just an event.
#
# All via the CLAUDE_CMD mock seam (no live LLM). The mock sleeps long enough to trip the
# watchdog's stall warning, THEN emits the stream-json transcript and flips its box, so the run
# exercises the REAL stall-then-recover path (SG-11), not just a plain watchdog pass-through.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
HGEN="$KIT/lib/goal/handoff/handoff_gen.py"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

EXPECT="in=1200 out=80 cache_read=8000 cache_create=0"

# Mock claude: sleeps 3s (long enough for WATCHDOG_STALL_SECS=1/WATCHDOG_POLL_SECS=1 to fire the
# stall warning at least once, pid still alive throughout), then emits the stream-json transcript
# and flips SG-01's box in the shared roadmap.
cat > "$TMP/claude-wdtok" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
sleep 3
cat <<'JSON'
{"type":"system","subtype":"init","note":"wdtok session start"}
{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":50,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}}}
{"type":"assistant","message":{"usage":{"input_tokens":200,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"type":"result","subtype":"success","message":{"usage":{"input_tokens":1200,"output_tokens":80,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}}}
JSON
awk '{ if ($0 ~ /^- \[ \] SG-01 /) sub(/\[ \]/, "[x]"); print }' "$WDTOK_RM" > "$WDTOK_RM.t" && mv "$WDTOK_RM.t" "$WDTOK_RM"
MOCK
chmod +x "$TMP/claude-wdtok"

mk_mg() {  # dir branch
  local d="$1" branch="$2"
  mkdir -p "$d/goals"
  cat > "$d/ROADMAP.md" <<'EOF'
# Mega-goal: watchdog-token-capture fixture
## Sub-goals
- [ ] SG-01 do the thing , auto , PR #__
- [ ] SG-02 gated thing , gate , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  printf '# SG-01\n**Branch:** %s\n' "$branch" > "$d/goals/01-do.md"
}

LEDGER_OF() { echo "$TMP/logs/runs/$1.log"; }

# ============ POSITIVE: watchdog ON + --capture-tokens -> stall warning fires, TOKENS still lands ============
D1="$TMP/mg1"; mk_mg "$D1" "feat/kit-wdtok-c1"
WDTOK_RM="$D1/ROADMAP.md" CLAUDE_CMD="$TMP/claude-wdtok" WAVE_CAP=1 \
  WATCHDOG_STALL_SECS=1 WATCHDOG_POLL_SECS=1 \
  DWARVES_KIT_LOG_DIR="$TMP/logs" bash "$ORCH" run "$D1" --capture-tokens > "$TMP/c1.out" 2>&1 < /dev/null
SLOG1="$D1/.orchestrate/SG-01.stream.jsonl"
LED1="$(LEDGER_OF kit-wdtok-c1)"

# Sanity: the run actually went through the STALL path (not just a plain watchdog pass-through).
if grep -q '\[watchdog\] WARN: SG-01 stalled' "$TMP/c1.out"; then
  pass "positive fixture: the run actually stalled (watchdog WARN fired) before finishing"
else
  fail "positive fixture: no stall WARN seen; test does not exercise the stall branch"; cat "$TMP/c1.out"
fi

TOKLINE="$(grep '| TOKENS |' "$LED1" 2>/dev/null | head -1 | sed -E 's/.*\| TOKENS \| //')"
if [ "$TOKLINE" = "$EXPECT" ]; then
  pass "watchdog-stall TOKENS recorded despite the stall ($EXPECT)"
else
  fail "watchdog-stall TOKENS missing/wrong: got '$TOKLINE' want '$EXPECT'"; echo "--out--"; cat "$TMP/c1.out"; echo "--led--"; cat "$LED1" 2>&1
fi

FSUM="$(python3 "$HGEN" sum-usage "$SLOG1" 2>/dev/null)"
if [ "$TOKLINE" = "$FSUM" ]; then
  pass "watchdog-stall capture-from-file: recorded usage == sum-usage(SG-01.stream.jsonl) ($FSUM)"
else
  fail "watchdog-stall mismatch: ledger '$TOKLINE' vs file '$FSUM'"
fi

echo "RUN-TABLE (watchdog-stall token capture, positive):"
echo "  stall WARN seen: $(grep -c '\[watchdog\] WARN: SG-01 stalled' "$TMP/c1.out" 2>/dev/null || echo 0)"
echo "  SG-01 rid=kit-wdtok-c1: $(grep '| TOKENS |' "$LED1" 2>/dev/null | head -1)"

# ============ NEGATIVE CONTROL: same stall scenario, watchdog ON but NO capture flag ============
# Pre-fix-equivalent behavior for the default (no --capture-tokens/no DETERMINISTIC_HANDOFF)
# posture: the watchdog branch must stay byte-identical -- plain .session.log, no stream.jsonl,
# NO TOKENS line, even though the session stalls-then-ships exactly as above.
D2="$TMP/mg2"; mk_mg "$D2" "feat/kit-wdtok-nc"
WDTOK_RM="$D2/ROADMAP.md" CLAUDE_CMD="$TMP/claude-wdtok" WAVE_CAP=1 \
  WATCHDOG_STALL_SECS=1 WATCHDOG_POLL_SECS=1 \
  DWARVES_KIT_LOG_DIR="$TMP/logs" bash "$ORCH" run "$D2" > "$TMP/c2.out" 2>&1 < /dev/null
LED2="$(LEDGER_OF kit-wdtok-nc)"

if grep -q '\[watchdog\] WARN: SG-01 stalled' "$TMP/c2.out"; then
  pass "negative-control fixture: this run also stalled (same scenario as the positive arm)"
else
  fail "negative-control fixture: no stall WARN seen"; cat "$TMP/c2.out"
fi

if [ ! -f "$D2/.orchestrate/SG-01.stream.jsonl" ] && [ -s "$D2/.orchestrate/SG-01.session.log" ] \
   && { [ ! -f "$LED2" ] || ! grep -q '| TOKENS |' "$LED2"; }; then
  pass "watchdog-stall NEGATIVE CONTROL: default (no capture requested) drops the token line -- the pre-fix black hole, still true when capture is OFF"
else
  fail "watchdog-stall NEGATIVE CONTROL: expected plain .session.log + no TOKENS line"
  ls "$D2/.orchestrate/" 2>&1; cat "$LED2" 2>&1
fi

echo "RUN-TABLE (watchdog-stall token capture, negative control -- capture OFF):"
echo "  stall WARN seen: $(grep -c '\[watchdog\] WARN: SG-01 stalled' "$TMP/c2.out" 2>/dev/null || echo 0)"
echo "  stream.jsonl present: $([ -f "$D2/.orchestrate/SG-01.stream.jsonl" ] && echo yes || echo no)"
echo "  TOKENS line: $(grep '| TOKENS |' "$LED2" 2>/dev/null | head -1 || echo '(none)')"

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
