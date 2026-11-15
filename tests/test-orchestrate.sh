#!/usr/bin/env bash
# test-orchestrate.sh
# Pins lib/queue/orchestrate.sh (SPEC-087 phase 1): the non-LLM driver finds the next unchecked
# sub-goal, runs the auto chain via a MOCK `claude` (CLAUDE_CMD), injects the previous
# HANDOFF, stops at the first gate, and advances only when a sub-goal flips its ROADMAP box.
# Negative control: a session that does NOT flip its box halts the loop (no self-claim).
set -uo pipefail
# Fence off the host operator kit.toml: a real operator file must not change what this suite asserts.
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-no-operator.$$"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The kit-root config layer is $HOME/.claude/dwarves-kit by default, which CI does not have and
# a dev machine has as an installed copy of THIS checkout. Pin it to the checkout so the
# no-Model: expectations below (read from $KIT/kit.toml) hold in both places.
export KIT_CONFIG_ROOT="${KIT_CONFIG_ROOT:-$KIT}"
[ -n "${KIT_PROJECT_ROOT:-}" ] || KIT_PROJECT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; export KIT_PROJECT_ROOT
# The expectation comes from the resolver itself, never a re-implementation of its toml parse.
kit_default_model() { ( cd "$KIT" && bash -c 'source lib/config/kit-config.sh; kit_config_get mega.default_model' ); }
ORCH="$KIT/lib/queue/orchestrate.sh"
# The kit-root kit.toml ships `[mega].default_model`; a sub-goal with no Model: field
# dispatches it (SPEC-087 chain). Read the shipped value rather than pin either outcome.
DEF_MODEL=$(kit_default_model)
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
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
printf 'Next: continue. Files already located: lib/queue/orchestrate.sh\n' > "$MOCK_DIR/HANDOFF.md"
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
{ trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'SG-01 (auto)' && { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'SG-02 (auto)' \
  && { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'STOP at SG-03 (gate' \
  && pass "dry-run lists SG-01, SG-02, STOP at gate SG-03" || { fail "dry-run plan wrong"; echo "$out"; }
# dry-run must NOT invoke claude (no box flipped, no handoff written)
grep -q '^- \[ \] SG-01' "$D/ROADMAP.md" && [ ! -f "$D/HANDOFF.md" ] \
  && pass "dry-run did not execute anything" || fail "dry-run had side effects"

# ============================ TEST 3: real run via good mock ============================
D2="$TMP/mg2"; mk_megagoal "$D2"; mk_mock_good
export MOCK_ROADMAP="$D2/ROADMAP.md" MOCK_DIR="$D2"
# MEGA_GATE_DISPATCH=0 pins the LEGACY stop-BEFORE-running posture this test was written for; the
# default (dispatch the gate sub-goal, then hold for the human merge) is covered by
# tests/test-orchestrate-gate-dispatch.sh.
MEGA_GATE_DISPATCH=0 CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$D2" > "$TMP/run.out" 2>&1
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
{ trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -qE 'SG-01 \(auto\).*model: sonnet, effort: low' \
  && pass "dry-run shows SG-01 routed model/effort" || { fail "dry-run SG-01 tier wrong"; echo "$out"; }
{ trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -qE "SG-02 \(auto\).*model: ${DEF_MODEL:-inherit}, effort: inherit" \
  && pass "dry-run shows SG-02 ${DEF_MODEL:-inherit} (no hints)" || { fail "dry-run SG-02 inherit wrong"; echo "$out"; }

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
# The inherit fallback (SPEC-087, "no config -> no flag") stays asserted: with BOTH config
# layers pointed at empty dirs, SG-02 must dispatch with no --model at all.
EMPTY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
DR3="$TMP/mgr3"; mk_routed "$DR3"; : > "$TMP/route3.log"
KIT_CONFIG_ROOT="$EMPTY_ROOT" KIT_PROJECT_ROOT="$EMPTY_ROOT" ROUTE_LOG="$TMP/route3.log" ROUTE_RM="$DR3/ROADMAP.md" CLAUDE_FLAGS="" \
  CLAUDE_CMD="$TMP/claude-route" bash "$ORCH" run "$DR3" >/dev/null 2>&1
{ grep '^SG-02|' "$TMP/route3.log" | grep -qv -- '--model'; } \
  && pass "no config layer at all -> SG-02 inherits (no --model)" || { fail "inherit fallback lost: SG-02 got a --model with no config"; cat "$TMP/route3.log"; }

# SG-02 carries no Model: field: see DEF_MODEL at the top.
if [ -n "$DEF_MODEL" ]; then
  grep -q "^SG-02|.*--model $DEF_MODEL" "$TMP/route.log" \
    && pass "run passes the kit-root default --model $DEF_MODEL for inherit SG-02" || { fail "SG-02 did not get the default --model $DEF_MODEL"; cat "$TMP/route.log"; }
else
  { grep '^SG-02|' "$TMP/route.log" | grep -qv -- '--model'; } \
    && pass "run passes no --model for inherit SG-02" || { fail "SG-02 got an unexpected --model"; cat "$TMP/route.log"; }
fi

# ============================ TEST 9: --step run-modes (SG-01) ============================
# 9a: --step --dry-run annotates the plan with pause points (no claude invoked).
DS="$TMP/mgs"; mk_megagoal "$DS"
out=$(bash "$ORCH" run "$DS" --step --dry-run)
{ { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'pause for the operator after each sub-goal' \
  && { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q '\[--step\] pause here'; } \
  && pass "--step --dry-run shows pause points" || { fail "--step dry-run missing pauses"; echo "$out"; }
grep -q '^- \[ \] SG-01' "$DS/ROADMAP.md" && pass "--step --dry-run did not execute" || fail "--step dry-run had side effects"

# 9b: --step real run, operator resumes (Enter) -> chain completes, stops at gate.
D9="$TMP/mg9"; mk_megagoal "$D9"; mk_mock_good
export MOCK_ROADMAP="$D9/ROADMAP.md" MOCK_DIR="$D9"
printf '\n\n' | MEGA_GATE_DISPATCH=0 CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$D9" --step > "$TMP/step.out" 2>&1
{ grep -q '^- \[x\] SG-01' "$D9/ROADMAP.md" && grep -q '^- \[x\] SG-02' "$D9/ROADMAP.md" \
  && grep -q '^- \[ \] SG-03' "$D9/ROADMAP.md"; } \
  && pass "--step resume: SG-01+SG-02 ran, gate SG-03 untouched" || { fail "--step resume wrong"; cat "$TMP/step.out"; }
grep -q '\-\-step: SG-01 done' "$TMP/step.out" && pass "--step paused after SG-01" || { fail "no pause prompt"; cat "$TMP/step.out"; }

# 9c: --step real run, operator quits (q) after SG-01 -> SG-02 NOT run, exit 0.
D10="$TMP/mg10"; mk_megagoal "$D10"
export MOCK_ROADMAP="$D10/ROADMAP.md" MOCK_DIR="$D10"
printf 'q\n' | CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$D10" --step > "$TMP/quit.out" 2>&1
rc=$?
{ [ "$rc" = 0 ] && grep -q '^- \[x\] SG-01' "$D10/ROADMAP.md" && grep -q '^- \[ \] SG-02' "$D10/ROADMAP.md"; } \
  && pass "--step quit: SG-01 ran, SG-02 stopped, exit 0" || { fail "--step quit wrong (rc=$rc)"; cat "$TMP/quit.out"; }
grep -q 'operator stopped after SG-01' "$TMP/quit.out" && pass "--step quit: explains the stop" || fail "no quit message"

# Negative control for SG-01: default (no --step) run does NOT pause (unchanged behavior).
D11="$TMP/mg11"; mk_megagoal "$D11"
export MOCK_ROADMAP="$D11/ROADMAP.md" MOCK_DIR="$D11"
CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$D11" > "$TMP/nostep.out" 2>&1 < /dev/null
{ ! grep -q -- '--step:' "$TMP/nostep.out" && grep -q '^- \[x\] SG-02' "$D11/ROADMAP.md"; } \
  && pass "default (no --step) does not pause; chain runs unchanged" || { fail "default mode changed"; cat "$TMP/nostep.out"; }

# ============================ TEST 10: --stream capture (SG-01) ============================
# Mock emits two lines (simulated stream-json) and flips the box; orchestrator tee's to capture.
cat > "$TMP/claude-stream" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
printf '{"type":"assistant","sg":"%s"}\n{"type":"result"}\n' "$id"
awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$STREAM_RM" > "$STREAM_RM.tmp" && mv "$STREAM_RM.tmp" "$STREAM_RM"
EOF
chmod +x "$TMP/claude-stream"
D12="$TMP/mg12"; mk_megagoal "$D12"
cat > "$D12/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
- [ ] SG-02 gate , gate , PR #__
EOF
STREAM_RM="$D12/ROADMAP.md" CLAUDE_CMD="$TMP/claude-stream" bash "$ORCH" run "$D12" --stream > "$TMP/stream.out" 2>&1 < /dev/null
{ [ -f "$D12/.orchestrate/SG-01.stream.jsonl" ] && grep -q '"type":"result"' "$D12/.orchestrate/SG-01.stream.jsonl"; } \
  && pass "--stream captured the session output to .orchestrate/SG-01.stream.jsonl" || { fail "--stream capture missing"; cat "$TMP/stream.out"; }
grep -q '"type":"result"' "$TMP/stream.out" && pass "--stream tee'd output live to stdout" || fail "--stream not teed live"
grep -q '^- \[x\] SG-01' "$D12/ROADMAP.md" && pass "--stream run still advances on box flip" || fail "--stream did not advance"

# Unknown flag is rejected.
bash "$ORCH" run "$DS" --bogus > "$TMP/bogus.out" 2>&1; rc=$?
{ [ "$rc" = 64 ] && grep -q 'unknown flag' "$TMP/bogus.out"; } && pass "unknown flag -> exit 64" || fail "unknown flag not rejected (rc=$rc)"

# ============================ TEST 11: board-view / event-sourced status (SG-10) ============
# 11a: detect default -> backlog.sh present => both; dry-run renders the board + derives BOARD.md.
DB="$TMP/mgb"; mk_megagoal "$DB"
out=$(bash "$ORCH" run "$DB" --dry-run)
{ { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'board mode: both' && [ -f "$DB/BOARD.md" ] && grep -q '| SG-01 |' "$DB/BOARD.md"; } \
  && pass "detect default -> both; dry-run derives BOARD.md" || { fail "board detect/derive wrong"; echo "$out"; }
# dry-run must NOT write an events.log (board derived from ROADMAP only, no execution)
[ ! -f "$DB/.orchestrate/events.log" ] && pass "dry-run board writes no events.log (no execution)" || fail "dry-run wrote events"

# 11b: roadmap fallback -> no kanban tooling => roadmap mode, no board rendered.
DBF="$TMP/mgbf"; mk_megagoal "$DBF"
out=$(BACKLOG_LIB="$TMP/nope.sh" bash "$ORCH" run "$DBF" --dry-run)
{ ! { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'board mode' && [ ! -f "$DBF/BOARD.md" ]; } \
  && pass "no backlog.sh -> detect fail-safes to roadmap (no board)" || { fail "roadmap fallback wrong"; echo "$out"; }

# 11c: explicit --board=roadmap suppresses the board even when backlog.sh is present.
DBR="$TMP/mgbr"; mk_megagoal "$DBR"
out=$(bash "$ORCH" run "$DBR" --board=roadmap --dry-run)
{ ! { trap '' PIPE; echo "$out" 2>/dev/null || :; } | grep -q 'board mode' && [ ! -f "$DBR/BOARD.md" ]; } \
  && pass "--board=roadmap suppresses the board" || { fail "--board=roadmap wrong"; echo "$out"; }

# 11d: ready/blocked derivation from deps. SG-03 depends on unchecked SG-02 => blocked; SG-02 has
# no deps => ready; SG-01 checked => shipped.
DBD="$TMP/mgbd"; mk_megagoal "$DBD"
cat > "$DBD/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [x] SG-01 done thing , auto , PR #1
- [ ] SG-02 ready thing , auto , PR #__
- [ ] SG-03 blocked thing , gate , PR #__ , depends SG-02
EOF
bash "$ORCH" run "$DBD" --board=kanban --dry-run >/dev/null
{ grep -q '| SG-01 | .* | shipped |' "$DBD/BOARD.md" \
  && grep -q '| SG-02 | .* | queued \[ready\] |' "$DBD/BOARD.md" \
  && grep -q '| SG-03 | .* | parked \[blocked: needs SG-02\] |' "$DBD/BOARD.md"; } \
  && pass "board derives shipped / ready / blocked-on-dep from ROADMAP" || { fail "board state derivation wrong"; cat "$DBD/BOARD.md"; }

# 11e: event-sourced replay. A real run emits executing then shipped for SG-01; BOARD.md (derived
# by replay, last event wins) shows SG-01 shipped. SG-02 gate => a blocked event.
DBE="$TMP/mgbe"; mk_megagoal "$DBE"
cat > "$DBE/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 only auto , auto , PR #__
- [ ] SG-02 the gate , gate , PR #__
EOF
export MOCK_ROADMAP="$DBE/ROADMAP.md" MOCK_DIR="$DBE"
CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$DBE" --board=both >/dev/null 2>&1 < /dev/null
ev_has() { awk -F'\t' -v id="$1" -v st="$2" '$2==id && $3==st{f=1} END{exit !f}' "$DBE/.orchestrate/events.log"; }
{ ev_has SG-01 executing && ev_has SG-01 shipped; } \
  && pass "event log records executing then shipped for SG-01" || { fail "event log wrong"; cat "$DBE/.orchestrate/events.log" 2>&1; }
ev_has SG-02 blocked && pass "gate sub-goal emits a blocked event" || fail "no gate blocked event"
grep -q '| SG-01 | .* | shipped |' "$DBE/BOARD.md" && pass "board derived by replay shows SG-01 shipped" || { fail "board replay wrong"; cat "$DBE/BOARD.md"; }

# 11f: unknown --board mode rejected.
bash "$ORCH" run "$DB" --board=bogus --dry-run > "$TMP/bm.out" 2>&1; rc=$?
{ [ "$rc" != 0 ] && grep -q "unknown --board mode" "$TMP/bm.out"; } && pass "unknown --board mode rejected" || fail "bad --board mode not rejected (rc=$rc)"

# ============================ TEST 12: loop robustness (SG-11) ==============================
evlog_has() { awk -F'\t' -v id="$1" -v st="$2" '$2==id && $3==st{f=1} END{exit !f}' "$3"; }

# 12a: stalled-watchdog. Mock emits nothing for ~3s (pid alive) then flips the box. With
# WATCHDOG_STALL_SECS=1 the watchdog flags `stalled` (event + WARN) but does NOT kill -> the
# session recovers and ships.
DW="$TMP/mgw"; mk_megagoal "$DW"
cat > "$TMP/claude-slow" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
sleep 3
awk '{ if ($0 ~ /^- \[ \] SG-01 /) sub(/\[ \]/, "[x]"); print }' "$SLOW_RM" > "$SLOW_RM.t" && mv "$SLOW_RM.t" "$SLOW_RM"
echo "late output"
EOF
chmod +x "$TMP/claude-slow"
SLOW_RM="$DW/ROADMAP.md" WATCHDOG_STALL_SECS=1 WATCHDOG_POLL_SECS=1 \
  CLAUDE_CMD="$TMP/claude-slow" bash "$ORCH" run "$DW" --board=roadmap > "$TMP/wd.out" 2>&1 < /dev/null
{ grep -q '\[watchdog\] WARN: SG-01 stalled' "$TMP/wd.out" && evlog_has SG-01 stalled "$DW/.orchestrate/events.log"; } \
  && pass "watchdog flags a stalled session (event + WARN)" || { fail "watchdog stall detection wrong"; cat "$TMP/wd.out"; }
{ evlog_has SG-01 shipped "$DW/.orchestrate/events.log" && grep -q '^- \[x\] SG-01' "$DW/ROADMAP.md"; } \
  && pass "watchdog is advisory: stalled-but-alive session not killed, recovers + ships" || fail "watchdog wrongly killed/blocked the session"

# 12b: dead-session reconciliation. Under the watchdog, a session that exits nonzero halts the
# loop (rc!=0), does NOT advance the box, and records a blocked event (no self-claim on a dead run).
DD="$TMP/mgd"; mk_megagoal "$DD"
cat > "$TMP/claude-die" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 7
EOF
chmod +x "$TMP/claude-die"
WATCHDOG_STALL_SECS=1 WATCHDOG_POLL_SECS=1 CLAUDE_CMD="$TMP/claude-die" bash "$ORCH" run "$DD" --board=roadmap > "$TMP/dd.out" 2>&1 < /dev/null
rc=$?
{ [ "$rc" != 0 ] && grep -q '^- \[ \] SG-01' "$DD/ROADMAP.md" && evlog_has SG-01 blocked "$DD/.orchestrate/events.log"; } \
  && pass "watchdog dead-session: halts, box not advanced, blocked event recorded" || { fail "dead-session reconcile wrong (rc=$rc)"; cat "$TMP/dd.out"; }

# 12c: guardrail. An AUTO sub-goal with no goals/ file warns before launch (re-discovery hazard).
DG="$TMP/mgg"; mkdir -p "$DG"
cat > "$DG/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 no goal file , auto , PR #__
- [ ] SG-02 gate , gate , PR #__
EOF
echo "POINTER" > "$DG/POINTER_PROMPT.md"   # NOTE: deliberately no goals/ dir
export MOCK_ROADMAP="$DG/ROADMAP.md" MOCK_DIR="$DG"
CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$DG" --board=roadmap > "$TMP/gg.out" 2>&1 < /dev/null
grep -q '\[guardrail\] WARN: SG-01 has no goals/ file' "$TMP/gg.out" \
  && pass "guardrail warns on a sub-goal missing its goal file" || { fail "missing-goal-file guardrail wrong"; cat "$TMP/gg.out"; }

# 12d: default (watchdog OFF) is unchanged -- no [watchdog] lines, synchronous path runs.
DO="$TMP/mgo"; mk_megagoal "$DO"
export MOCK_ROADMAP="$DO/ROADMAP.md" MOCK_DIR="$DO"
CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$DO" --board=roadmap > "$TMP/wo.out" 2>&1 < /dev/null
{ ! grep -q '\[watchdog\]' "$TMP/wo.out" && grep -q '^- \[x\] SG-02' "$DO/ROADMAP.md"; } \
  && pass "watchdog off by default: no bg path, chain runs unchanged" || { fail "default watchdog-off changed"; cat "$TMP/wo.out"; }

# ============================ TEST 13: deterministic handoff (v3 SG-02) ====================
HGEN="$KIT/lib/goal/handoff-gen"
SEED="$KIT/tests/fixtures/handoff-det/seed.jsonl"
ANCHORS="$KIT/tests/fixtures/handoff-det/anchors.json"

# 13a: determinism -- same transcript + args + --date => byte-identical HANDOFF.md and DECISIONS.md.
H1="$TMP/h1"; H2="$TMP/h2"; mkdir -p "$H1" "$H2"
"$HGEN" "$SEED" --dir "$H1" --next-id SG-04 --next-title "distilled returns" --date 2026-06-30 2>/dev/null
"$HGEN" "$SEED" --dir "$H2" --next-id SG-04 --next-title "distilled returns" --date 2026-06-30 2>/dev/null
{ cmp -s "$H1/HANDOFF.md" "$H2/HANDOFF.md" && cmp -s "$H1/DECISIONS.md" "$H2/DECISIONS.md"; } \
  && pass "deterministic handoff: HANDOFF.md + DECISIONS.md byte-identical across runs (cmp-clean)" \
  || { fail "handoff not deterministic"; }

# 13b: idempotent append -- re-running into the SAME dir does not duplicate the DECISIONS block.
"$HGEN" "$SEED" --dir "$H1" --next-id SG-04 --next-title "distilled returns" --date 2026-06-30 2>/dev/null
n=$(grep -c '<!-- handoff-gen:' "$H1/DECISIONS.md")
[ "$n" = 1 ] && pass "deterministic handoff: DECISIONS append is idempotent (1 block after 2 runs)" \
  || fail "DECISIONS appended duplicate blocks ($n)"

# 13c: fidelity + negative control -- every load-bearing anchor appears in the combined two-tier
# output; the negative control (never in the transcript) does NOT. Reuses SG-01's hand-labeled fixture.
cat "$H1/HANDOFF.md" "$H1/DECISIONS.md" > "$TMP/combined.md"
if python3 - "$ANCHORS" "$TMP/combined.md" <<'PY'
import json, sys
anchors = json.load(open(sys.argv[1]))
text = open(sys.argv[2]).read()
missing = [a for a in anchors["present"] if a not in text]
leaked = anchors["negative_control"] in text
if missing: sys.stderr.write("MISSING: %r\n" % missing)
if leaked: sys.stderr.write("LEAKED negative control\n")
sys.exit(1 if (missing or leaked) else 0)
PY
then pass "deterministic handoff: all load-bearing anchors present, negative control absent"
else fail "handoff fidelity/negative-control failed"; fi

# 13d: the HOT handoff carries the contract fields (next sub-goal + read-pointers grounded in real files).
{ grep -q 'Next sub-goal: SG-04' "$H1/HANDOFF.md" \
  && grep -q 'Read-pointers' "$H1/HANDOFF.md" \
  && grep -q 'src/fetch_client.py' "$H1/HANDOFF.md"; } \
  && pass "hot HANDOFF carries next-sub-goal + grounded read-pointers" || { fail "hot handoff fields wrong"; cat "$H1/HANDOFF.md"; }

# 13e: no-LLM contract -- the generator + ported extractor import no network/model libs.
! grep -REq '\b(import|from)\b.*\b(anthropic|openai|requests|httpx|urllib|socket)\b' "$KIT/lib/goal/handoff/" \
  && pass "deterministic handoff: no LLM/network imports (no-LLM contract)" || fail "handoff code imports a network/model lib"

# 13f: orchestrator integration -- DETERMINISTIC_HANDOFF=1 regenerates the handoff from the
# captured transcript, OVERWRITING the LLM-written one. Mock emits the seed fixture as its
# "stream" then flips the box.
cat > "$TMP/claude-dh" <<EOF
#!/usr/bin/env bash
cat >/dev/null
cat "$SEED"
id=\$(grep -oE 'SG-[0-9]+' "\$DH_RM" | head -1)
awk '{ if (\$0 ~ /^- \[ \] SG-01 /) sub(/\[ \]/, "[x]"); print }' "\$DH_RM" > "\$DH_RM.t" && mv "\$DH_RM.t" "\$DH_RM"
EOF
chmod +x "$TMP/claude-dh"
DH="$TMP/mgdh"; mk_megagoal "$DH"
cat > "$DH/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 first thing , auto , PR #__
- [ ] SG-02 second thing , gate , PR #__
EOF
echo "STALE LLM HANDOFF that should be overwritten" > "$DH/HANDOFF.md"
DH_RM="$DH/ROADMAP.md" DETERMINISTIC_HANDOFF=1 CLAUDE_CMD="$TMP/claude-dh" \
  bash "$ORCH" run "$DH" > "$TMP/dh.out" 2>&1 < /dev/null
{ grep -q 'Next sub-goal: SG-02' "$DH/HANDOFF.md" && ! grep -q 'STALE LLM HANDOFF' "$DH/HANDOFF.md" \
  && grep -q 'src/fetch_client.py' "$DH/HANDOFF.md"; } \
  && pass "DETERMINISTIC_HANDOFF=1: orchestrator regenerated HANDOFF.md from the transcript (overwrote LLM's)" \
  || { fail "deterministic handoff not wired into orchestrator"; cat "$TMP/dh.out"; echo "--"; cat "$DH/HANDOFF.md"; }
{ [ -s "$DH/DECISIONS.md" ] && grep -q 'manual backoff loop' "$DH/DECISIONS.md"; } \
  && pass "DETERMINISTIC_HANDOFF=1: DECISIONS.md appended deterministically" || fail "DECISIONS not appended by orchestrator"

# 13g: negative control -- default (flag OFF) does NOT regenerate; the session's own HANDOFF stands.
DHN="$TMP/mgdhn"; mk_megagoal "$DHN"
cat > "$DHN/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 first thing , auto , PR #__
- [ ] SG-02 second thing , gate , PR #__
EOF
# TURN_CAP=0 pins the pre-ceiling dispatch: the turn ceiling (default on) also forces a
# stream-json capture, so without the pin this control would see a capture it predates.
DH_RM="$DHN/ROADMAP.md" TURN_CAP=0 CLAUDE_CMD="$TMP/claude-dh" bash "$ORCH" run "$DHN" > "$TMP/dhn.out" 2>&1 < /dev/null
{ [ ! -f "$DHN/HANDOFF.md" ] || ! grep -q 'Next sub-goal: SG-02' "$DHN/HANDOFF.md"; } \
  && [ ! -f "$DHN/.orchestrate/SG-01.stream.jsonl" ] \
  && pass "default (flag off): no deterministic regeneration, no forced capture (behavior unchanged)" \
  || { fail "deterministic handoff fired with flag off"; cat "$TMP/dhn.out"; }

# ============ TEST 14: gate-ledger START wiring (SPEC-101 / ID-085) ============
# The automated dispatch emits a START per sub-goal so mega-dispatched runs are tracked
# (real lane/type), not '?' in lane-telemetry. rid derived from the goal file's **Branch:**.
mk_mock_good
LOGDIR="$TMP/startwire-logs"; mkdir -p "$LOGDIR"

# fixture: goal files carry **Branch:** so the driver can derive the rid
SW="$TMP/mgsw"; mkdir -p "$SW/goals"
cat > "$SW/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 add a guard clause , auto , PR #__
- [ ] SG-02 second thing , gate , PR #__
EOF
echo "POINTER" > "$SW/POINTER_PROMPT.md"
printf '# SG-01\n**Branch:** feat/kit-clean-fx1-startwire\n' > "$SW/goals/01-first.md"
export MOCK_ROADMAP="$SW/ROADMAP.md" MOCK_DIR="$SW"
DWARVES_KIT_LOG_DIR="$LOGDIR" CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$SW" >/dev/null 2>&1
SWLOG="$LOGDIR/runs/kit-clean-fx1-startwire.log"
{ [ -f "$SWLOG" ] && grep -q 'START' "$SWLOG" && grep -qE 'lane=[a-z]+ ' "$SWLOG" && grep -qE 'type=[a-z-]+' "$SWLOG"; } \
  && ! grep -q 'lane=? ' "$SWLOG" \
  && pass "START wiring: dispatched SG-01 carries a START with lane+type (rid from **Branch:**)" \
  || { fail "START wiring: no tracked START line"; ls "$LOGDIR/runs" 2>&1; cat "$SWLOG" 2>&1; }

# negative control: a goal file with NO **Branch:** emits NO START (run left untracked, '?')
SWN="$TMP/mgswn"; mkdir -p "$SWN/goals"
cat > "$SWN/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 add a guard clause , auto , PR #__
- [ ] SG-02 second thing , gate , PR #__
EOF
echo "POINTER" > "$SWN/POINTER_PROMPT.md"
printf '# SG-01\nno branch header here\n' > "$SWN/goals/01-first.md"
LOGDIRN="$TMP/startwire-logs-neg"; mkdir -p "$LOGDIRN"
export MOCK_ROADMAP="$SWN/ROADMAP.md" MOCK_DIR="$SWN"
DWARVES_KIT_LOG_DIR="$LOGDIRN" CLAUDE_CMD="$TMP/claude-good" bash "$ORCH" run "$SWN" > "$TMP/swn.out" 2>&1
{ [ ! -d "$LOGDIRN/runs" ] || ! grep -rq 'START' "$LOGDIRN/runs" 2>/dev/null; } \
  && grep -q "no '\*\*Branch:\*\*' header" "$TMP/swn.out" \
  && pass "START wiring negative control: no **Branch:** -> no START (still '?'), WARN emitted" \
  || { fail "neg control: START emitted or no WARN"; cat "$TMP/swn.out"; ls "$LOGDIRN/runs" 2>&1; }

# dry-run stays side-effect-free: no START
SWD="$TMP/mgswd"; mkdir -p "$SWD/goals"
cp "$SW/ROADMAP.md" "$SWD/ROADMAP.md"; echo "POINTER" > "$SWD/POINTER_PROMPT.md"
printf '# SG-01\n**Branch:** feat/kit-clean-fxd-startwire\n' > "$SWD/goals/01-first.md"
LOGDIRD="$TMP/startwire-logs-dry"; mkdir -p "$LOGDIRD"
DWARVES_KIT_LOG_DIR="$LOGDIRD" bash "$ORCH" run "$SWD" --dry-run >/dev/null 2>&1
{ [ ! -d "$LOGDIRD/runs" ] || ! grep -rq 'START' "$LOGDIRD/runs" 2>/dev/null; } \
  && pass "START wiring: --dry-run emits no START (side-effect-free)" \
  || { fail "dry-run emitted a START"; ls "$LOGDIRD/runs" 2>&1; }

# ============ SPEC-110: token accounting (capture-gated) ============
# sum-usage sums ASSISTANT-only usage from the seed transcript (6 assistant entries).
SU="$(python3 "$KIT/lib/goal/handoff/handoff_gen.py" sum-usage "$SEED")"
[ "$SU" = "in=7200 out=480 cache_read=24000 cache_create=0" ] \
  && pass "SPEC-110 sum-usage: seed transcript sums assistant usage" \
  || fail "SPEC-110 sum-usage wrong: $SU"
# NC: a final type:result event carries CUMULATIVE usage and must NOT be double-summed.
SUR="$(python3 "$KIT/lib/goal/handoff/handoff_gen.py" sum-usage "$KIT/tests/fixtures/handoff-det/usage-with-result.jsonl")"
[ "$SUR" = "in=100 out=10 cache_read=50 cache_create=0" ] \
  && pass "SPEC-110 sum-usage NC: type:result cumulative line not double-counted" \
  || fail "SPEC-110 sum-usage result-line double-count: $SUR"

# capture path: DETERMINISTIC_HANDOFF=1 (a stream capture) + a goal file with **Branch:** -> the
# orchestrate token hook parses the capture and writes a TOKENS line for the run's rid.
TOKMG="$TMP/mgtok"; mkdir -p "$TOKMG/goals"
cat > "$TOKMG/ROADMAP.md" <<'EOF'
# Mega-goal: fixture
## Sub-goals
- [ ] SG-01 first thing , auto , PR #__
- [ ] SG-02 second thing , gate , PR #__
EOF
echo "POINTER" > "$TOKMG/POINTER_PROMPT.md"
printf '# SG-01\n**Branch:** feat/kit-tok-fx1\n' > "$TOKMG/goals/01-first.md"
TOKLOG="$TMP/tok-logs"; mkdir -p "$TOKLOG"
DH_RM="$TOKMG/ROADMAP.md" DETERMINISTIC_HANDOFF=1 CLAUDE_CMD="$TMP/claude-dh" \
  DWARVES_KIT_LOG_DIR="$TOKLOG" bash "$ORCH" run "$TOKMG" > "$TMP/tok.out" 2>&1 < /dev/null
TL="$TOKLOG/runs/kit-tok-fx1.log"
{ [ -f "$TL" ] && grep -q '| TOKENS |' "$TL" && grep -qE 'in=7200 out=480 cache_read=24000' "$TL"; } \
  && pass "SPEC-110 wiring: capture path CALLS gate-ledger tokens (TOKENS line carries the seed sum)" \
  || { fail "SPEC-110 wiring: no TOKENS line from the capture path"; cat "$TMP/tok.out"; cat "$TL" 2>&1; }

# NC: the default (no-capture) path writes NO TOKENS line (honest usage=?, never a fake zero).
TOKMGN="$TMP/mgtokn"; mkdir -p "$TOKMGN/goals"
cp "$TOKMG/ROADMAP.md" "$TOKMGN/ROADMAP.md"; echo "POINTER" > "$TOKMGN/POINTER_PROMPT.md"
printf '# SG-01\n**Branch:** feat/kit-tok-fxn\n' > "$TOKMGN/goals/01-first.md"
TOKLOGN="$TMP/tok-logs-n"; mkdir -p "$TOKLOGN"
# TURN_CAP=0 pins the pre-ceiling no-capture path (the ceiling's forced capture would
# otherwise write a TOKENS line and void this control's "no capture" premise).
DH_RM="$TOKMGN/ROADMAP.md" TURN_CAP=0 CLAUDE_CMD="$TMP/claude-dh" \
  DWARVES_KIT_LOG_DIR="$TOKLOGN" bash "$ORCH" run "$TOKMGN" > "$TMP/tokn.out" 2>&1 < /dev/null
TLN="$TOKLOGN/runs/kit-tok-fxn.log"
{ [ ! -f "$TLN" ] || ! grep -q '| TOKENS |' "$TLN"; } \
  && pass "SPEC-110 NC: default no-capture path writes NO TOKENS line (usage=?)" \
  || { fail "SPEC-110 NC: a TOKENS line was written without a capture"; cat "$TLN" 2>&1; }

# ============================ TEST 7: no-claim retry (box not flipped) ============================
# A session that exits 0 without flipping its box is re-dispatched ONCE in a fresh session, then the
# loop halts as before. The driver never flips a box itself: only a session's own flip advances.
# Mock: invocation N flips the box only when N >= $MOCK_FLIP_AT (0 = never); $MOCK_EXIT sets its rc.
cat > "$TMP/claude-retry" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
n=$(cat "$MOCK_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$MOCK_COUNT"
printf '%s\n' "$prompt" > "$MOCK_COUNT.prompt.$n"
if [ "${MOCK_FLIP_AT:-0}" -gt 0 ] && [ "$n" -ge "$MOCK_FLIP_AT" ]; then
  awk '{ if ($0 ~ /^- \[ \] SG-01 /) sub(/\[ \]/, "[x]"); print }' "$MOCK_RM" > "$MOCK_RM.tmp" && mv "$MOCK_RM.tmp" "$MOCK_RM"
fi
exit "${MOCK_EXIT:-0}"
EOF
chmod +x "$TMP/claude-retry"
mk_retry_fixture() {  # dir -> one auto sub-goal whose goal file carries a HANDOFF-worthy marker
  local d="$1"; mkdir -p "$d/goals"
  printf '# Mega-goal: retry fixture\n## Sub-goals\n- [ ] SG-01 only thing , auto , PR #__\n' > "$d/ROADMAP.md"
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  printf '# SG-01\n**Branch:** feat/noclaim-retry\n' > "$d/goals/01-only.md"
  echo "HANDOFF-MARKER from the previous sub-goal" > "$d/HANDOFF.md"
}
run_retry() {  # dir flip_at retries exit -> rc; leaves $TMP/retry.out and the count in $TMP/retry.count
  local d="$1"; rm -f "$TMP/retry.count" "$TMP/retry.count.prompt."*
  MOCK_COUNT="$TMP/retry.count" MOCK_RM="$d/ROADMAP.md" MOCK_FLIP_AT="$2" NOCLAIM_RETRIES="$3" MOCK_EXIT="${4:-0}" TIER4_CLOSE=0 \
    CLAUDE_CMD="$TMP/claude-retry" bash "$ORCH" run "$d" > "$TMP/retry.out" 2>&1 < /dev/null
}

# 7a: first session leaves the box unflipped, the retry flips it -> the run completes.
R1="$TMP/mg-retry1"; mk_retry_fixture "$R1"; run_retry "$R1" 2 1; rc=$?
{ [ "$rc" = 0 ] && [ "$(cat "$TMP/retry.count")" = 2 ] && grep -q '^- \[x\] SG-01' "$R1/ROADMAP.md"; } \
  && pass "no-claim retry: unflipped first session -> one fresh retry flips the box, run completes (2 sessions)" \
  || { fail "no-claim retry: expected rc 0, 2 sessions, box flipped (rc=$rc sessions=$(cat "$TMP/retry.count" 2>/dev/null))"; cat "$TMP/retry.out"; }
{ ! grep -q 'RETRY' "$TMP/retry.count.prompt.1" && grep -q 'RETRY 1 of 1' "$TMP/retry.count.prompt.2"; } \
  && pass "no-claim retry: only the second prompt carries the RETRY block" || fail "no-claim retry: RETRY block placement wrong"
grep -q 'HANDOFF-MARKER' "$TMP/retry.count.prompt.2" \
  && pass "no-claim retry: the retry prompt still carries the previous HANDOFF" || fail "no-claim retry: retry prompt lost the HANDOFF"
grep -q 'retrying in a fresh session (1/1)' "$TMP/retry.out" \
  && pass "no-claim retry: the loop says it is retrying" || fail "no-claim retry: no retry message"

# 7b: NEGATIVE CONTROL for no-self-claim: a session that never flips is retried ONCE, then the loop
# halts, the box stays unchecked, and the driver flipped nothing itself.
R2="$TMP/mg-retry2"; mk_retry_fixture "$R2"; run_retry "$R2" 0 1; rc=$?
{ [ "$rc" != 0 ] && [ "$(cat "$TMP/retry.count")" = 2 ] && grep -q '^- \[ \] SG-01' "$R2/ROADMAP.md" \
  && grep -q 'did not check its ROADMAP box; halting' "$TMP/retry.out"; } \
  && pass "no-claim retry NC: never flipping -> exactly 2 sessions, then halt, box still unchecked (no self-claim)" \
  || { fail "no-claim retry NC: expected halt after 2 sessions with the box unchecked (rc=$rc sessions=$(cat "$TMP/retry.count" 2>/dev/null))"; cat "$TMP/retry.out"; }

# 7c: NOCLAIM_RETRIES=0 restores the old halt-at-once behavior (one session).
R3="$TMP/mg-retry3"; mk_retry_fixture "$R3"; run_retry "$R3" 0 0; rc=$?
{ [ "$rc" != 0 ] && [ "$(cat "$TMP/retry.count")" = 1 ]; } \
  && pass "no-claim retry: NOCLAIM_RETRIES=0 halts after one session (old behavior)" \
  || { fail "no-claim retry: NOCLAIM_RETRIES=0 ran $(cat "$TMP/retry.count" 2>/dev/null) sessions (rc=$rc)"; cat "$TMP/retry.out"; }

# 7d: a session that exits nonzero is a different failure and is NOT retried here.
R4="$TMP/mg-retry4"; mk_retry_fixture "$R4"; run_retry "$R4" 0 1 1; rc=$?
{ [ "$rc" != 0 ] && [ "$(cat "$TMP/retry.count")" = 1 ]; } \
  && pass "no-claim retry: a nonzero session exit is not retried" \
  || { fail "no-claim retry: nonzero exit ran $(cat "$TMP/retry.count" 2>/dev/null) sessions (rc=$rc)"; cat "$TMP/retry.out"; }

# 7e: the retry budget is per sub-goal, not per run: NOCLAIM_RETRIES=2 allows two retries (3 sessions).
R5="$TMP/mg-retry5"; mk_retry_fixture "$R5"; run_retry "$R5" 3 2; rc=$?
{ [ "$rc" = 0 ] && [ "$(cat "$TMP/retry.count")" = 3 ] && grep -q 'RETRY 2 of 2' "$TMP/retry.count.prompt.3"; } \
  && pass "no-claim retry: NOCLAIM_RETRIES=2 -> two retries, third session flips" \
  || { fail "no-claim retry: NOCLAIM_RETRIES=2 wrong (rc=$rc sessions=$(cat "$TMP/retry.count" 2>/dev/null))"; cat "$TMP/retry.out"; }

echo "----"
[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails FAILED"; exit 1; }
