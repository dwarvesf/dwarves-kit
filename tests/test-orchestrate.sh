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
}

# --- mock claude: flips the named sub-goal's box + writes a handoff (the "good" session) ---
mk_mock_good() {
  cat > "$TMP/claude-good" <<'EOF'
#!/usr/bin/env bash
# args: -p "<prompt>"  ; env: MOCK_ROADMAP, MOCK_DIR
prompt="${2:-}"
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
prompt="\${2:-}"
id=\$(printf '%s' "\$prompt" | grep -oE 'SG-[0-9]+' | head -1)
# record whether this turn's prompt carried a HANDOFF section
printf '%s handoff=%s\n' "\$id" "\$(printf '%s' "\$prompt" | grep -c 'HANDOFF from the previous')" >> "$TMP/probe.log"
awk -v id="\$id" '{ if (\$0 ~ ("^- \\\\[ \\\\] " id " ")) sub(/\\[ \\]/, "[x]"); print }' "$D3/ROADMAP.md" > "$D3/ROADMAP.md.tmp" && mv "$D3/ROADMAP.md.tmp" "$D3/ROADMAP.md"
echo "h" > "$D3/HANDOFF.md"
EOF
chmod +x "$TMP/claude-probe"
: > "$TMP/probe.log"
CLAUDE_CMD="$TMP/claude-probe" bash "$ORCH" run "$D3" >/dev/null 2>&1
# SG-01: no handoff yet (0); SG-02: handoff injected (1)
grep -q 'SG-01 handoff=0' "$TMP/probe.log" && grep -q 'SG-02 handoff=1' "$TMP/probe.log" \
  && pass "handoff injected into SG-02's prompt but not SG-01's" || { fail "handoff injection wrong"; cat "$TMP/probe.log"; }

# ============================ TEST 4: negative control ============================
D4="$TMP/mg4"; mk_megagoal "$D4"; mk_mock_bad
CLAUDE_CMD="$TMP/claude-bad" bash "$ORCH" run "$D4" > "$TMP/neg.out" 2>&1
rc=$?
[ "$rc" != 0 ] && pass "negative control: run halts nonzero when box not flipped" || fail "neg control did not halt (rc=$rc)"
grep -q 'did not check its ROADMAP box' "$TMP/neg.out" && pass "negative control: explains the halt" || fail "no halt message"
grep -q '^- \[ \] SG-01' "$D4/ROADMAP.md" && pass "negative control: SG-01 stays unchecked" || fail "SG-01 wrongly checked"

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
