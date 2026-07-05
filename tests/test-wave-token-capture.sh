#!/usr/bin/env bash
# test-wave-token-capture.sh (ID-094)
# Pins the WAVE (parallel) path's per-sub-goal TOKENS ledger extraction, closing the SPEC-117
# declared gap ("the wave-path per-sub-goal ledger extraction is a declared gap ... child.jsonl is
# still written lean-to-file under waves, only the extraction is deferred"; see
# tests/test-token-capture.sh's own COVERAGE-DELTA footer and orchestrate.sh's CAPTURE_TOKENS
# header comment, both pre-fix). The serial path's extraction (tests/test-token-capture.sh) is
# untouched by this fix; this suite is the wave-path twin.
#
# All via the CLAUDE_CMD mock seam (no live LLM), a real throwaway `git init` repo (so _wave_run
# stands up REAL worktrees), and a real ledger dir via DWARVES_KIT_LOG_DIR.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
HGEN="$KIT/lib/goal/handoff/handoff_gen.py"
# shellcheck source=../lib/queue/orchestrate.sh
source "$ORCH"   # guard in orchestrate.sh keeps main from running when sourced; exposes _wave_run etc.

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_git_mega() {  # repo-root
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
}

make_goal() {  # megadir id glob
  local mg="$1" id="$2" glob="$3"
  mkdir -p "$mg/goals"
  {
    printf '# %s: sub-goal\n' "$id"
    printf '**Branch:** feat/wave-tok-%s\n' "$(printf '%s' "$id" | tr 'A-Z' 'a-z')"
    printf '\n## Touches\n- %s\n' "$glob"
  } > "$mg/goals/${id#SG-}-${id}.md"
}

LEDGER_OF() { echo "$1/runs/wave-tok-$2.log"; }   # logdir rid-suffix(sg-01|sg-02)

# The known, real-shape stream-json the mock emits (same fixture shape as test-token-capture.sh).
# Assistant usage sums to in=1200 out=80 cache_read=8000 cache_create=0 per sub-goal; the trailing
# type:result line carries CUMULATIVE usage and must be excluded (would be in=2400 if double-counted).
EXPECT="in=1200 out=80 cache_read=8000 cache_create=0"

# Mock claude: emits the stream-json transcript to STDOUT, then flips the named sub-goal's box in
# the SHARED roadmap via the locked flip CLI (two wave sessions writing the same ROADMAP.md
# concurrently must go through the lock, mirroring the real session contract).
cat > "$TMP/claude-wtok" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
cat <<JSON
{"type":"system","subtype":"init","note":"wtok session start $id"}
{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":50,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}}}
{"type":"assistant","message":{"usage":{"input_tokens":200,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"type":"result","subtype":"success","message":{"usage":{"input_tokens":1200,"output_tokens":80,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}}}
JSON
bash "$ORCH" flip "$MEGADIR" "$id" >/dev/null 2>&1
MOCK
chmod +x "$TMP/claude-wtok"

# ============ POSITIVE: 2-sub-goal wave, CAPTURE_TOKENS=1 -> BOTH token lines land ============
WR="$TMP/wave-tok-repo"; mk_git_mega "$WR"
WM="$WR/mega"; mkdir -p "$WM"
cat > "$WM/ROADMAP.md" <<'EOF'
# Mega-goal: wave-token-capture
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WM/POINTER_PROMPT.md"
make_goal "$WM" SG-01 "lib/wtok-a/**"
make_goal "$WM" SG-02 "lib/wtok-b/**"

LOGDIR_POS="$TMP/logs-pos"; mkdir -p "$LOGDIR_POS"
wrc=0
( export ORCH="$ORCH" MEGADIR="$WM" CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-wtok" CAPTURE_TOKENS=1 \
    DWARVES_KIT_LOG_DIR="$LOGDIR_POS"
  _wave_run "$WM" "$WM/ROADMAP.md" ) > "$TMP/pos.out" 2>&1 || wrc=$?

b1=$(_sg_line "$WM/ROADMAP.md" SG-01); b2=$(_sg_line "$WM/ROADMAP.md" SG-02)
LED1="$(LEDGER_OF "$LOGDIR_POS" sg-01)"; LED2="$(LEDGER_OF "$LOGDIR_POS" sg-02)"
TOK1="$(grep '| TOKENS |' "$LED1" 2>/dev/null | head -1 | sed -E 's/.*\| TOKENS \| //')"
TOK2="$(grep '| TOKENS |' "$LED2" 2>/dev/null | head -1 | sed -E 's/.*\| TOKENS \| //')"

if [ "$wrc" = 0 ] && [ "$TOK1" = "$EXPECT" ] && [ "$TOK2" = "$EXPECT" ]; then
  pass "wave-token-capture POSITIVE: both wave sub-goals' TOKENS lines recorded (SG-01='$TOK1' SG-02='$TOK2')"
else
  fail "wave-token-capture POSITIVE: rc=$wrc SG-01-tok='$TOK1' SG-02-tok='$TOK2' b1='$b1' b2='$b2'"
  echo "--out--"; cat "$TMP/pos.out"
fi

# Run-table row (both lines, for the proof-of-done): print what landed.
echo "RUN-TABLE (wave token capture, positive):"
echo "  SG-01 rid=wave-tok-sg-01: $(grep '| TOKENS |' "$LED1" 2>/dev/null | head -1)"
echo "  SG-02 rid=wave-tok-sg-02: $(grep '| TOKENS |' "$LED2" 2>/dev/null | head -1)"

# The recorded usage also matches sum-usage of each sub-goal's own captured child.jsonl (the record
# IS the file's totals, not a cross-sub-goal mixup).
SLOG1="$WM/.orchestrate/SG-01.stream.jsonl"; SLOG2="$WM/.orchestrate/SG-02.stream.jsonl"
FSUM1="$(python3 "$HGEN" sum-usage "$SLOG1" 2>/dev/null)"; FSUM2="$(python3 "$HGEN" sum-usage "$SLOG2" 2>/dev/null)"
if [ "$TOK1" = "$FSUM1" ] && [ "$TOK2" = "$FSUM2" ]; then
  pass "wave-token-capture: each sub-goal's ledger usage == sum-usage of ITS OWN child.jsonl (no cross-sub-goal mixup)"
else
  fail "wave-token-capture: per-sub-goal mismatch (SG-01 led='$TOK1' file='$FSUM1'; SG-02 led='$TOK2' file='$FSUM2')"
fi

# ============ NEGATIVE CONTROL: SAME wave scenario, fix stubbed out -> ZERO token lines ============
# Demonstrates the fix's CAUSAL effect (not just post-fix presence): with the wave-path extraction
# call removed, the same 2-sub-goal wave run must produce NO TOKENS lines at all, even though the
# child.jsonl files are still written (CAPTURE_TOKENS still streams to file; only the ledger
# extraction is disabled). NC_SKIP_WAVE_TOKENS=1 is a test-only escape hatch wired into
# orchestrate.sh's wave reap loop for exactly this purpose (see the guard in _wave_run).
WR2="$TMP/wave-tok-repo-nc"; mk_git_mega "$WR2"
WM2="$WR2/mega"; mkdir -p "$WM2"
cat > "$WM2/ROADMAP.md" <<'EOF'
# Mega-goal: wave-token-capture-nc
## Sub-goals
- [ ] SG-01 alpha , auto , PR #__
- [ ] SG-02 beta , auto , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$WM2/POINTER_PROMPT.md"
make_goal "$WM2" SG-01 "lib/wtok-a/**"
make_goal "$WM2" SG-02 "lib/wtok-b/**"

LOGDIR_NC="$TMP/logs-nc"; mkdir -p "$LOGDIR_NC"
ncrc=0
( export ORCH="$ORCH" MEGADIR="$WM2" CLAUDE_FLAGS="" WAVE_CAP=2 CLAUDE_CMD="$TMP/claude-wtok" CAPTURE_TOKENS=1 \
    DWARVES_KIT_LOG_DIR="$LOGDIR_NC" NC_SKIP_WAVE_TOKENS=1
  _wave_run "$WM2" "$WM2/ROADMAP.md" ) > "$TMP/nc.out" 2>&1 || ncrc=$?

LED1N="$(LEDGER_OF "$LOGDIR_NC" sg-01)"; LED2N="$(LEDGER_OF "$LOGDIR_NC" sg-02)"
tok_lines=0
[ -f "$LED1N" ] && tok_lines=$((tok_lines + $(grep -c '| TOKENS |' "$LED1N" 2>/dev/null || echo 0)))
[ -f "$LED2N" ] && tok_lines=$((tok_lines + $(grep -c '| TOKENS |' "$LED2N" 2>/dev/null || echo 0)))
slog_present=0
[ -s "$WM2/.orchestrate/SG-01.stream.jsonl" ] && [ -s "$WM2/.orchestrate/SG-02.stream.jsonl" ] && slog_present=1

if [ "$ncrc" = 0 ] && [ "$tok_lines" = 0 ] && [ "$slog_present" = 1 ]; then
  pass "wave-token-capture NEGATIVE CONTROL: pre-fix-equivalent code (extraction stubbed) writes the SAME child.jsonl files but ZERO wave TOKENS lines -- causal effect demonstrated"
else
  fail "wave-token-capture NEGATIVE CONTROL: expected 0 token lines + child.jsonl present, got tok_lines=$tok_lines slog_present=$slog_present rc=$ncrc"
  echo "--out--"; cat "$TMP/nc.out"
fi

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
