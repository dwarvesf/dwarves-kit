#!/usr/bin/env bash
# test-orchestrate.sh
# Pins lib/orchestrate.sh (SPEC-087 phase 1): the non-LLM driver finds the next unchecked
# sub-goal, runs the auto chain via a MOCK `claude` (CLAUDE_CMD), injects the previous
# HANDOFF, stops at the first gate, and advances only when a sub-goal flips its ROADMAP box.
# Negative control: a session that does NOT flip its box halts the loop (no self-claim).
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/orchestrate.sh"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture: a mega-goal dir with 2 auto sub-goals then a gate ---
mk_megagoal() {
  local d="$1"
  mkdir -p "$d"
  cat > "$d/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 first thing (x) , auto , PR #__
- [ ] SG-02 second thing , auto , PR #__
- [ ] SG-03 third thing , gate , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  mkdir -p "$d/goals"
  echo "GOALFILE-MARKER-01 contract for SG-01" > "$d/goals/01-first.md"
}

# --- mock claude: flips the named sub-goal's box + writes a handoff (the "good" session) ---
mk_mock_good() {
  cat > "$TMP/claude-good" <<'EOF'
#!/usr/bin/env bash
# the prompt now arrives on STDIN (orchestrator pipes a temp file); env: MOCK_ROADMAP, MOCK_DIR
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' \
  "$MOCK_ROADMAP" > "$MOCK_ROADMAP.tmp" && mv "$MOCK_ROADMAP.tmp" "$MOCK_ROADMAP"
printf 'Next: continue. Files already located: lib/orchestrate.sh\n' > "$MOCK_DIR/HANDOFF.md"
EOF
  chmod +x "$TMP/claude-good"
}

# --- mock claude: does NOT flip the box (the "lying" session, negative control) ---
mk_mock_bad() {
  cat > "$TMP/claude-bad" <<'EOF'
#!/usr/bin/env bash
echo "did work but forgot to check the box"
EOF
  chmod +x "$TMP/claude-bad"
}

# ============================ TEST 1: next ============================
D="$TMP/mg1"; mk_megagoal "$D"
out=$(bash "$ORCH" next "$D")
[ "$out" = "$(printf 'SG-01\tauto')" ] && pass "next -> SG-01 auto" || fail "next: got '$out'"

# ============================ TEST 2: dry-run plan ============================
out=$(bash "$ORCH" run "$D" --dry-run)
echo "$out" | grep -q 'SG-01 (auto)' && echo "$out" | grep -q 'SG-02 (auto)' \
  && echo "$out" | grep -q 'STOP at SG-03 (gate' \
  && pass "dry-run lists SG-01, SG-02, STOP at gate SG-03" || { fail "dry-run plan wrong"; echo "$out"; }
# dry-run must NOT invoke claude (no box flipped, no handoff written)
grep -q '^- \[ \] SG-01' "$D/ROADMAP.md" && [ ! -f "$D/HANDOFF.md" ] \
  && pass "dry-run did not execute anything" || fail "dry-run had side effects"

# ============================ TEST 3: real run via good mock ============================
D2="$TMP/mg2"; mk_megagoal "$D2"; mk_mock_good
export MOCK_ROADMAP="$D2/ROADMAP.md" MOCK_DIR="$D2"
CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$D2" > "$TMP/run.out" 2>&1
rc=$?
[ "$rc" = 0 ] && pass "run exited 0" || { fail "run exited $rc"; cat "$TMP/run.out"; }
grep -q '^- \[x\] SG-01' "$D2/ROADMAP.md" && grep -q '^- \[x\] SG-02' "$D2/ROADMAP.md" \
  && pass "auto SG-01 + SG-02 boxes flipped" || fail "auto boxes not flipped"
grep -q '^- \[ \] SG-03' "$D2/ROADMAP.md" && pass "gate SG-03 left unchecked (stopped)" || fail "gate SG-03 touched"
grep -q 'STOP: SG-03 is a gate' "$TMP/run.out" && pass "stopped at gate with message" || fail "no gate-stop message"
[ -s "$D2/HANDOFF.md" ] && pass "HANDOFF.md written for the next sub-goal" || fail "no HANDOFF.md"

# TEST 3b: handoff is injected into the next session's prompt
# (re-run next step's prompt build by checking the good mock saw a handoff on SG-02's turn:
#  after SG-01 wrote HANDOFF, the orchestrator should have injected it for SG-02.)
D3="$TMP/mg3"; mk_megagoal "$D3"
cat > "$TMP/claude-probe" <<EOF
#!/usr/bin/env bash
prompt=\$(cat)
id=\$(printf '%s' "\$prompt" | grep -oE 'SG-[0-9]+' | head -1)
# record whether this turn's prompt carried a HANDOFF section
printf '%s handoff=%s goal=%s\n' "\$id" "\$(printf '%s' "\$prompt" | grep -c 'HANDOFF from the previous')" "\$(printf '%s' "\$prompt" | grep -c 'GOALFILE-MARKER-01')" >> "$TMP/probe.log"
awk -v id="\$id" '{ if (\$0 ~ ("^- \\\\[ \\\\] " id " ")) sub(/\\[ \\]/, "[x]"); print }' "$D3/ROADMAP.md" > "$D3/ROADMAP.md.tmp" && mv "$D3/ROADMAP.md.tmp" "$D3/ROADMAP.md"
echo "h" > "$D3/HANDOFF.md"
EOF
chmod +x "$TMP/claude-probe"
: > "$TMP/probe.log"
CLAUDE_CMD="$TMP/claude-probe" bash "$ORCH" run "$D3" >/dev/null 2>&1
# SG-01: no handoff yet (0); SG-02: handoff injected (1)
grep -q 'SG-01 handoff=0' "$TMP/probe.log" && grep -q 'SG-02 handoff=1' "$TMP/probe.log" \
  && pass "handoff injected into SG-02's prompt but not SG-01's" || { fail "handoff injection wrong"; cat "$TMP/probe.log"; }
grep -q 'SG-01 .*goal=1' "$TMP/probe.log" \
  && pass "goal-file content injected into the prompt (not just a path)" || { fail "goal-file not injected"; cat "$TMP/probe.log"; }

# ============================ TEST 4: negative control ============================
D4="$TMP/mg4"; mk_megagoal "$D4"; mk_mock_bad
CLAUDE_CMD="$TMP/claude-bad" bash "$ORCH" run "$D4" > "$TMP/neg.out" 2>&1
rc=$?
[ "$rc" != 0 ] && pass "negative control: run halts nonzero when box not flipped" || fail "neg control did not halt (rc=$rc)"
grep -q 'did not check its ROADMAP box' "$TMP/neg.out" && pass "negative control: explains the halt" || fail "no halt message"
grep -q '^- \[ \] SG-01' "$D4/ROADMAP.md" && pass "negative control: SG-01 stays unchecked" || fail "SG-01 wrongly checked"

# ============================ TEST 5: permission posture flag ============================
# A mock that records its args + flips the box (so the auto chain completes). ARGS_LOG/ARGS_RM
# are set per-run so one mock serves multiple fixtures.
cat > "$TMP/claude-args" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$ARGS_LOG"
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$ARGS_RM" > "$ARGS_RM.tmp" && mv "$ARGS_RM.tmp" "$ARGS_RM"
EOF
chmod +x "$TMP/claude-args"

D5="$TMP/mg5"; mk_megagoal "$D5"; : > "$TMP/args.log"
ARGS_LOG="$TMP/args.log" ARGS_RM="$D5/ROADMAP.md" CLAUDE_CMD="$TMP/claude-args" bash "$ORCH" run "$D5" >/dev/null 2>&1
grep -q -- '--dangerously-skip-permissions' "$TMP/args.log" \
  && pass "default posture flag (--dangerously-skip-permissions) passed to claude" \
  || { fail "default posture flag missing"; cat "$TMP/args.log"; }

D6="$TMP/mg6"; mk_megagoal "$D6"; : > "$TMP/args.log"
ARGS_LOG="$TMP/args.log" ARGS_RM="$D6/ROADMAP.md" CLAUDE_FLAGS="--allowedTools Read" \
  CLAUDE_CMD="$TMP/claude-args" bash "$ORCH" run "$D6" >/dev/null 2>&1
{ grep -q -- '--allowedTools' "$TMP/args.log" && ! grep -q -- '--dangerously-skip-permissions' "$TMP/args.log"; } \
  && pass "CLAUDE_FLAGS overrides the default posture" \
  || { fail "CLAUDE_FLAGS override wrong"; cat "$TMP/args.log"; }

# ============================ TEST 6: two-tier handoff injection ============================
# Probe mock dumps the received prompt (stdin) to a capture file, then flips the box.
cat > "$TMP/claude-cap" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
printf '%s' "$prompt" > "$CAP_FILE"
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$CAP_RM" > "$CAP_RM.tmp" && mv "$CAP_RM.tmp" "$CAP_RM"
EOF
chmod +x "$TMP/claude-cap"

# Fixture: single auto sub-goal, pre-seeded with the committed HOT/WARM pair.
D7="$TMP/mg7"; mk_megagoal "$D7"
# make SG-01 the only runnable (gate at SG-02 so the loop stops right after SG-01)
cat > "$D7/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
- [ ] SG-02 gate , gate , PR #__
EOF
cp "$KIT/tests/fixtures/handoff-sample/HANDOFF.md" "$D7/HANDOFF.md"
cp "$KIT/tests/fixtures/handoff-sample/DECISIONS.md" "$D7/DECISIONS.md"
CAP_FILE="$TMP/cap.txt" CAP_RM="$D7/ROADMAP.md" CLAUDE_CMD="$TMP/claude-cap" bash "$ORCH" run "$D7" >/dev/null 2>&1

# 6a: HOT handoff injected in full (small file -> a deep body line present, no truncation notice)
{ grep -q 'Read-pointers (verified this run)' "$TMP/cap.txt" && ! grep -q 'truncated at' "$TMP/cap.txt"; } \
  && pass "hot HANDOFF injected in full (under cap)" || { fail "hot handoff not fully injected"; }
# 6b: WARM ledger injected as a POINTER only (path present, body NOT inlined)
{ grep -q 'WARM LEDGER' "$TMP/cap.txt" && grep -q 'DECISIONS.md' "$TMP/cap.txt" && ! grep -q 'append-only: invariants + dead-ends, read on demand' "$TMP/cap.txt"; } \
  && pass "warm DECISIONS injected as pointer, body not inlined" || { fail "warm ledger leaked its body or missing pointer"; }
# 6c: the "report IN the records" wording is present
grep -q 'report findings IN the records' "$TMP/cap.txt" \
  && pass "report-in-the-records wording injected" || fail "missing report-in-records wording"

# 6d: hot handoff CAP -> head + truncation notice when over HANDOFF_MAX_LINES
D8="$TMP/mg8"; mk_megagoal "$D8"
cat > "$D8/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
- [ ] SG-02 gate , gate , PR #__
EOF
seq 1 20 | sed 's/^/LINE-/' > "$D8/HANDOFF.md"   # 20 lines: LINE-1 .. LINE-20
CAP_FILE="$TMP/cap2.txt" CAP_RM="$D8/ROADMAP.md" HANDOFF_MAX_LINES=5 \
  CLAUDE_CMD="$TMP/claude-cap" bash "$ORCH" run "$D8" >/dev/null 2>&1
{ grep -q 'LINE-5' "$TMP/cap2.txt" && ! grep -q 'LINE-20' "$TMP/cap2.txt" && grep -q 'truncated at 5/20 lines' "$TMP/cap2.txt"; } \
  && pass "hot HANDOFF capped at HANDOFF_MAX_LINES with a truncation notice" \
  || { fail "handoff cap wrong"; }

# ============================ TEST 7 + 8: model/effort routing ============================
# Mixed-tier fixture: SG-01 carries Model:/Effort: hints, SG-02 carries none (inherit).
mk_routed() {
  local d="$1"; mk_megagoal "$d"
  cat > "$d/goals/01-first.md" <<'EOF'
# SG-01
Model: sonnet
Effort: low

GOALFILE-MARKER-01 contract for SG-01
EOF
  # SG-02 deliberately has NO goal file -> no hints -> inherit.
}

# TEST 7: --dry-run prints the chosen tier per sub-goal (and "inherit" when absent).
DR="$TMP/mgr"; mk_routed "$DR"
out=$(bash "$ORCH" run "$DR" --dry-run)
echo "$out" | grep -qE 'SG-01 \(auto\).*model: sonnet, effort: low' \
  && pass "dry-run shows SG-01 routed model/effort" || { fail "dry-run SG-01 tier wrong"; echo "$out"; }
echo "$out" | grep -qE 'SG-02 \(auto\).*model: inherit, effort: inherit' \
  && pass "dry-run shows SG-02 inherit (no hints)" || { fail "dry-run SG-02 inherit wrong"; echo "$out"; }

# TEST 8: real run passes --model/--effort for the hinted sub-goal, none for the inherit one.
# Prompt arrives on STDIN now, so the mock logs "<id>|<flags>" from "$@" (flags only, no prompt arg).
cat > "$TMP/claude-route" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
printf '%s|%s\n' "$id" "$*" >> "$ROUTE_LOG"
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$ROUTE_RM" > "$ROUTE_RM.tmp" && mv "$ROUTE_RM.tmp" "$ROUTE_RM"
EOF
chmod +x "$TMP/claude-route"

DR2="$TMP/mgr2"; mk_routed "$DR2"; : > "$TMP/route.log"
ROUTE_LOG="$TMP/route.log" ROUTE_RM="$DR2/ROADMAP.md" CLAUDE_FLAGS="" \
  CLAUDE_CMD="$TMP/claude-route" bash "$ORCH" run "$DR2" >/dev/null 2>&1
grep -q '^SG-01|.*--model sonnet --effort low' "$TMP/route.log" \
  && pass "run passes --model/--effort for hinted SG-01" || { fail "SG-01 routing flags missing"; cat "$TMP/route.log"; }
{ grep '^SG-02|' "$TMP/route.log" | grep -qv -- '--model'; } \
  && pass "run passes no --model for inherit SG-02" || { fail "SG-02 got an unexpected --model"; cat "$TMP/route.log"; }

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
