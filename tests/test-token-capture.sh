#!/usr/bin/env bash
# test-token-capture.sh (SPEC-117)
# Pins the LEAN token capture under delegation (ADR-0032 section 3): a delegated child streams to a
# FILE (`.orchestrate/<id>.stream.jsonl`), usage is extracted FROM that file and recorded to the kit
# token ledger via the SPEC-110 `| TOKENS |` marker, and the CONDUCTOR reads only the box-flip, NEVER
# the child transcript. The two load-bearing properties are BOTH tested, plus the false-bloat NC that
# proves piping the transcript to the conductor (`--stream` tee) is the forbidden bloat path.
#
# All via the CLAUDE_CMD mock seam (no live LLM). WAVE_CAP=1 forces the SERIAL delegate path this
# spec targets (the ADR-0032 s3 canonical single child); the wave-path ledger extraction is a
# declared, out-of-scope gap.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
HGEN="$KIT/lib/goal/handoff/handoff_gen.py"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The known, real-shape stream-json the mock emits. Assistant usage sums to
# in=1200 out=80 cache_read=8000 cache_create=0. The final type:result line carries the CUMULATIVE
# usage and MUST NOT be re-summed (SPEC-110) -- if it were, in would be 2400, so asserting 1200 also
# proves the result-line is excluded. Each transcript line carries the unique BLOAT_SENTINEL so we can
# detect whether the child transcript reached the conductor. `--verbose` diagnostics go to STDERR
# (DIAG_SENTINEL) so the fd-separation test can prove the transcript is fd1-only.
EXPECT="in=1200 out=80 cache_read=8000 cache_create=0"

# Mock claude: emits the stream-json transcript to STDOUT (fd1), a diagnostic to STDERR (fd2), then
# flips the named sub-goal's box in the SHARED roadmap ($CAP_RM). Ignores its args + reads stdin, like
# the real `claude -p`. Quoted heredocs so $CAP_RM stays literal (resolved at mock runtime).
cat > "$TMP/claude-cap" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null   # consume the injected prompt on stdin
cat <<'JSON'
{"type":"system","subtype":"init","note":"BLOAT_SENTINEL_XYZZY session start"}
{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":50,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}},"note":"BLOAT_SENTINEL_XYZZY reasoning turn one lots of transcript body"}
{"type":"assistant","message":{"usage":{"input_tokens":200,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"note":"BLOAT_SENTINEL_XYZZY reasoning turn two more body"}
{"type":"result","subtype":"success","message":{"usage":{"input_tokens":1200,"output_tokens":80,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}},"note":"BLOAT_SENTINEL_XYZZY cumulative result"}
JSON
echo "DIAG_SENTINEL_STDERR verbose diagnostic noise" >&2
awk '{ if ($0 ~ /^- \[ \] SG-01 /) sub(/\[ \]/, "[x]"); print }' "$CAP_RM" > "$CAP_RM.t" && mv "$CAP_RM.t" "$CAP_RM"
MOCK
chmod +x "$TMP/claude-cap"

# Stand up a mega-goal: SG-01 auto (executes) then SG-02 gate (natural stop). The goal file carries
# **Branch:** so the rid (and thus the ledger file) is derivable. No `## Touches` -> serial path.
mk_mg() {  # dir branch
  local d="$1" branch="$2"
  mkdir -p "$d/goals"
  cat > "$d/ROADMAP.md" <<'EOF'
# Mega-goal: token-capture fixture
## Sub-goals
- [ ] SG-01 do the thing , auto , PR #__
- [ ] SG-02 gated thing , gate , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  printf '# SG-01\n**Branch:** %s\n' "$branch" > "$d/goals/01-do.md"
}

run_cap() {  # dir extra-flags... ; sets stdout/stderr to $TMP/<name>.{out,err} via caller redirection
  local d="$1"; shift
  CAP_RM="$d/ROADMAP.md" CLAUDE_CMD="$TMP/claude-cap" WAVE_CAP=1 \
    DWARVES_KIT_LOG_DIR="$TMP/logs" bash "$ORCH" run "$d" "$@" < /dev/null
}

LEDGER_OF() { echo "$TMP/logs/runs/$1.log"; }

# ============ C1 + C2 + C4: --capture-tokens serial run (correctness + lean + fd-separation) ============
D1="$TMP/mg1"; mk_mg "$D1" "feat/kit-captok-c1"
run_cap "$D1" --capture-tokens > "$TMP/c1.out" 2> "$TMP/c1.err"
SLOG1="$D1/.orchestrate/SG-01.stream.jsonl"
LED1="$(LEDGER_OF kit-captok-c1)"

# C1a: a TOKENS line was recorded, and it equals the child's assistant-only totals (result not double-counted).
TOKLINE="$(grep '| TOKENS |' "$LED1" 2>/dev/null | head -1 | sed -E 's/.*\| TOKENS \| //')"
[ "$TOKLINE" = "$EXPECT" ] \
  && pass "C1 capture-correctness: TOKENS line == child assistant totals ($EXPECT); result line not double-counted" \
  || { fail "C1 TOKENS wrong: got '$TOKLINE' want '$EXPECT'"; echo "--out--"; cat "$TMP/c1.out"; echo "--led--"; cat "$LED1" 2>&1; }

# C1b: the recorded usage MATCHES sum-usage of the captured child.jsonl (the record IS the file's totals).
FSUM="$(python3 "$HGEN" sum-usage "$SLOG1" 2>/dev/null)"
[ "$TOKLINE" = "$FSUM" ] \
  && pass "C1 capture-from-file: recorded usage == sum-usage(child.jsonl) ($FSUM)" \
  || fail "C1 mismatch: ledger '$TOKLINE' vs file '$FSUM'"

# C2: conductor stays lean -- the child transcript sentinel is ABSENT from the conductor's stdout,
#     PRESENT in the child.jsonl file.
if ! grep -q 'BLOAT_SENTINEL_XYZZY' "$TMP/c1.out" && grep -q 'BLOAT_SENTINEL_XYZZY' "$SLOG1"; then
  pass "C2 conductor-stays-lean: child transcript in child.jsonl, ABSENT from conductor stdout"
else
  fail "C2 leak: transcript reached the conductor stdout (or missing from file)"; echo "--out--"; cat "$TMP/c1.out"
fi

# C4: fd-separation -- with stdout/stderr captured SEPARATELY, the TRANSCRIPT sentinel is absent from
#     fd1 (the stream cmd_run forwards). The stderr diagnostic is fd2-only (not the transcript).
if ! grep -q 'BLOAT_SENTINEL_XYZZY' "$TMP/c1.out"; then
  pass "C4 fd1-rigorous: transcript sentinel absent from the conductor's fd1 (leanness proven, not merged-capture)"
else
  fail "C4: transcript sentinel present on fd1"
fi

# ============ C7: default (no flag/env) NC -- no stream capture, no TOKENS line, usage=? ============
D7="$TMP/mg7"; mk_mg "$D7" "feat/kit-captok-c7"
run_cap "$D7" > "$TMP/c7.out" 2>&1
LED7="$(LEDGER_OF kit-captok-c7)"
if [ ! -f "$D7/.orchestrate/SG-01.stream.jsonl" ] && { [ ! -f "$LED7" ] || ! grep -q '| TOKENS |' "$LED7"; }; then
  pass "C7 default NC: no stream-json child file, NO TOKENS line (honest usage=?, default invocation intact)"
else
  fail "C7: default path captured/recorded something"; ls "$D7/.orchestrate/" 2>&1; cat "$LED7" 2>&1
fi

# ============ C3: false-bloat NEGATIVE CONTROL -- --stream tees the transcript to the conductor ============
# SAME child, two paths. --stream (tee) => transcript IN the conductor stdout (bloat). --capture-tokens
# (redirect) => transcript ABSENT (lean). Both record the SAME correct TOKENS line (capture unaffected).
D3="$TMP/mg3"; mk_mg "$D3" "feat/kit-captok-c3"
run_cap "$D3" --stream > "$TMP/c3_stream.out" 2>/dev/null
LED3="$(LEDGER_OF kit-captok-c3)"
STREAM_TOK="$(grep '| TOKENS |' "$LED3" 2>/dev/null | head -1 | sed -E 's/.*\| TOKENS \| //')"

if grep -q 'BLOAT_SENTINEL_XYZZY' "$TMP/c3_stream.out"; then
  pass "C3 false-bloat NC: --stream (tee) PUTS the child transcript in the conductor stdout (bloat proven)"
else
  fail "C3: --stream did not bloat (tee path broken?)"; head -5 "$TMP/c3_stream.out"
fi
# lean arm already proven at C2 (--capture-tokens leaves the conductor stdout clean); assert the contrast + equal capture.
if ! grep -q 'BLOAT_SENTINEL_XYZZY' "$TMP/c1.out" && [ "$STREAM_TOK" = "$EXPECT" ] && [ "$TOKLINE" = "$EXPECT" ]; then
  pass "C3 contrast: stream-to-FILE leaves the conductor lean while --stream bloats; BOTH record the same TOKENS ($EXPECT)"
else
  fail "C3 contrast: stream_tok='$STREAM_TOK' cap_tok='$TOKLINE'"
fi

# ============ C5: env parity -- CAPTURE_TOKENS=1 (no flag) behaves like --capture-tokens ============
D5="$TMP/mg5"; mk_mg "$D5" "feat/kit-captok-c5"
CAP_RM="$D5/ROADMAP.md" CLAUDE_CMD="$TMP/claude-cap" WAVE_CAP=1 CAPTURE_TOKENS=1 \
  DWARVES_KIT_LOG_DIR="$TMP/logs" bash "$ORCH" run "$D5" > "$TMP/c5.out" 2> "$TMP/c5.err" < /dev/null
LED5="$(LEDGER_OF kit-captok-c5)"
ENV_TOK="$(grep '| TOKENS |' "$LED5" 2>/dev/null | head -1 | sed -E 's/.*\| TOKENS \| //')"
if [ "$ENV_TOK" = "$EXPECT" ] && ! grep -q 'BLOAT_SENTINEL_XYZZY' "$TMP/c5.out"; then
  pass "C5 env parity: CAPTURE_TOKENS=1 env records TOKENS + keeps the conductor lean (flag is sugar over the global)"
else
  fail "C5 env parity broken: tok='$ENV_TOK' (stdout leak? $(grep -c BLOAT_SENTINEL_XYZZY "$TMP/c5.out"))"
fi

# ============ C6: --capture-tokens is an accepted flag (not 'unknown flag') ============
D6="$TMP/mg6"; mk_mg "$D6" "feat/kit-captok-c6"
CAP_RM="$D6/ROADMAP.md" WAVE_CAP=1 DWARVES_KIT_LOG_DIR="$TMP/logs" \
  bash "$ORCH" run "$D6" --capture-tokens --dry-run > "$TMP/c6.out" 2>&1 < /dev/null; rc6=$?
if [ "$rc6" = 0 ] && ! grep -q 'unknown flag' "$TMP/c6.out" && grep -q -- '--capture-tokens:' "$TMP/c6.out"; then
  pass "C6 flag accepted: --capture-tokens parses (not rejected) + shows its dry-run advisory"
else
  fail "C6 flag not accepted (rc=$rc6)"; cat "$TMP/c6.out"
fi

echo "----"
echo "COVERAGE-DELTA (SPEC-117):"
echo "  covered:   C1 capture-correctness(+result-not-double-counted) | C2 conductor-lean | C3 false-bloat NC |"
echo "             C4 fd1-rigorous | C5 env-parity | C6 flag-accepted | C7 default-NC(usage=?)"
echo "  UNcovered: wave-path per-sub-goal ledger extraction (declared gap, _wave_run has no hook) |"
echo "             watchdog-path capture (pre-existing SPEC-110 gap) | live LLM run (mock seam only) |"
echo "             stderr-redirect hardening (fd2 not redirected; C4 proves fd1 is the load-bearing property)"
echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
