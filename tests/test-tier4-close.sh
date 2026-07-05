#!/usr/bin/env bash
# test-tier4-close.sh (SPEC-118, executes ADR-0032 section 5)
# Pins the TIER-4 mega-close that replaces `orchestrate.sh`'s "done"-and-return. Three load-bearing
# properties, all via the CLAUDE_CMD mock seam (no live LLM):
#   1. VERIFIERS-RUN-BEFORE-GATE: after every box is checked, the close DISPATCHES a verifier session
#      AND emits `held` -- i.e. a verifier ran and the gate is held, NOT the bare done-and-return.
#   2. SEEDED-ORPHAN NEGATIVE CONTROL: a deliberately defined-but-never-dispatched AGENT (the c6fbd99
#      class) is CAUGHT by the mechanical no-orphan sweep (unit AND end-to-end), not silently passed.
#   3. GATE-HELD: the close HOLDS the human gate and NEVER auto-merges (no merge hook invoked).
# Plus: the opt-out (TIER4_CLOSE=0 restores done-and-return) and the whole-word dispatch match
# (advisor must not be satisfied by the word `advisory`).
#
# Coverage-delta is recorded in the proof-of-done. Uncovered by design: a LIVE integration-verifier/
# review-team/advisor VERDICT (the session content is the LLM's job, mocked here -- the driver only
# proves the session is DISPATCHED before the gate); and the softer flag/step no-orphan lens (delegated
# to the close session's integration-verifier).
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- fixtures -------------------------------------------------------------------------------------

# An all-auto 2-sub-goal mega-goal: cmd_run flips both boxes and reaches the _next-empty terminal (the
# close). Carries a `**Destination:**` line so the objective-extraction path is exercised too.
mk_megagoal() {  # dir
  local d="$1"; mkdir -p "$d/goals"
  cat > "$d/ROADMAP.md" <<'EOF'
# Mega-goal: tier4-close fixture
**Destination:** the assembled wave is verified as a whole before the human gate.
## Sub-goals
- [ ] SG-01 first thing , auto , PR #__
- [ ] SG-02 second thing , auto , PR #__
EOF
  echo "POINTER: resume from ROADMAP" > "$d/POINTER_PROMPT.md"
  printf '# SG-01\n**Branch:** feat/tier4-fixture\n' > "$d/goals/01-first.md"
  printf '# SG-02\n**Branch:** feat/tier4-fixture-2\n' > "$d/goals/02-second.md"
}

# A CLEAN corpus: one agent that IS dispatched by a command (whole-word reference).
mk_corpus_clean() {  # dir
  local c="$1"; mkdir -p "$c/agents" "$c/commands"
  echo "# good-agent" > "$c/agents/good-agent.md"
  echo "Dispatch the good-agent via the Task tool." > "$c/commands/uses-good.md"
}

# The mock claude: flips the named SG box on a sub-goal turn; on the CLOSE turn (prompt carries the
# 'TIER-4 MEGA-CLOSE' banner, no SG-NN to flip) it records that the verifier session was DISPATCHED by
# touching $CLOSE_SENTINEL, then exits 0. Quoted heredoc so $MOCK_RM/$CLOSE_SENTINEL resolve at runtime.
mk_mock() {  # path
  cat > "$1" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
if printf '%s' "$prompt" | grep -q 'TIER-4 MEGA-CLOSE'; then
  echo "close-session ran" > "$CLOSE_SENTINEL"
  exit 0
fi
id=$(printf '%s' "$prompt" | grep -oE 'SG-[0-9]+' | head -1)
[ -n "$id" ] && awk -v id="$id" '{ if ($0 ~ ("^- \\[ \\] " id " ")) sub(/\[ \]/, "[x]"); print }' "$MOCK_RM" > "$MOCK_RM.t" && mv "$MOCK_RM.t" "$MOCK_RM"
MOCK
  chmod +x "$1"
}

# A merge recorder: the close must NEVER invoke a merge hook. If it ever runs, this file gets a line.
mk_merge_recorder() {  # path recordfile
  cat > "$1" <<MERGE
#!/usr/bin/env bash
echo "MERGED \$*" >> "$2"
MERGE
  chmod +x "$1"
}

MOCK="$TMP/claude-mock"; mk_mock "$MOCK"

# =========================== A. clean close: verifiers-before-gate + gate-held ======================
DA="$TMP/mgA"; mk_megagoal "$DA"
CORPUS_A="$TMP/corpusA"; mk_corpus_clean "$CORPUS_A"
SENT_A="$TMP/close-A.sentinel"; MREC="$TMP/merge.rec"; : > "$MREC"
MERGE="$TMP/merge-recorder"; mk_merge_recorder "$MERGE" "$MREC"

MOCK_RM="$DA/ROADMAP.md" CLOSE_SENTINEL="$SENT_A" CLAUDE_FLAGS="" \
  TIER4_CORPUS="$CORPUS_A" WAVE_MERGE_CMD="$MERGE" \
  CLAUDE_CMD="$MOCK" bash "$ORCH" run "$DA" > "$TMP/A.out" 2>&1
rcA=$?

[ "$rcA" = 0 ] && pass "clean close: run exits 0 (held clean)" || { fail "clean close: rc=$rcA"; cat "$TMP/A.out"; }
grep -q '^- \[x\] SG-01' "$DA/ROADMAP.md" && grep -q '^- \[x\] SG-02' "$DA/ROADMAP.md" \
  && pass "clean close: both auto boxes flipped (reached the terminal)" || fail "clean close: boxes not both flipped"
# verifiers-before-gate: the verifier session was DISPATCHED (sentinel) AND the gate was held.
[ -f "$SENT_A" ] \
  && pass "verifiers-before-gate: verifier close session was DISPATCHED (not done-and-return)" \
  || { fail "verifiers-before-gate: verifier session never dispatched"; cat "$TMP/A.out"; }
grep -q 'HELD for the final human gate' "$TMP/A.out" \
  && pass "gate-held: the close HELD for the human gate" || { fail "gate-held: no held message"; cat "$TMP/A.out"; }
grep -q 'NOT auto-merged' "$TMP/A.out" \
  && pass "gate-held: message states NOT auto-merged (gated-final)" || fail "gate-held: no 'NOT auto-merged'"
[ ! -s "$MREC" ] \
  && pass "gate-held: NO merge hook invoked by the close (recorder empty)" || { fail "gate-held: a merge hook ran"; cat "$MREC"; }
# replaces done-and-return: the bare completion message is GONE (the close ran instead).
grep -q 'all sub-goals checked; done' "$TMP/A.out" \
  && fail "replaces-done-and-return: the bare done message still printed (close did not replace it)" \
  || pass "replaces-done-and-return: bare 'done' is gone; the close ran instead"

# =========================== B. no-orphan unit: clean corpus passes ================================
# Source orchestrate.sh to call the internal helper directly (the guard keeps main from firing).
( set -uo pipefail; source "$ORCH"
  out=$(_no_orphan_check "$CORPUS_A"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] && echo "UNIT_CLEAN_OK" || echo "UNIT_CLEAN_BAD rc=$rc out=$out"
) > "$TMP/B.out" 2>&1
grep -q '^UNIT_CLEAN_OK$' "$TMP/B.out" \
  && pass "no-orphan unit: clean corpus -> rc 0, no orphan printed" || { fail "no-orphan unit clean"; cat "$TMP/B.out"; }

# =========================== C. seeded-orphan NC: unit ============================================
CORPUS_ORPHAN="$TMP/corpusOrphan"; mk_corpus_clean "$CORPUS_ORPHAN"
echo "# seeded-orphan" > "$CORPUS_ORPHAN/agents/seeded-orphan.md"   # defined + present, no command dispatches it
( set -uo pipefail; source "$ORCH"
  out=$(_no_orphan_check "$CORPUS_ORPHAN"); rc=$?
  printf 'rc=%s\n%s\n' "$rc" "$out"
) > "$TMP/C.out" 2>&1
{ grep -q '^rc=1$' "$TMP/C.out" && grep -q 'seeded-orphan' "$TMP/C.out" && grep -q 'BLOCKING' "$TMP/C.out"; } \
  && pass "seeded-orphan NC (unit): the orphan agent is CAUGHT (rc 1, named, BLOCKING)" \
  || { fail "seeded-orphan NC (unit): not caught"; cat "$TMP/C.out"; }
# and the co-resident dispatched agent is NOT mis-flagged
grep -q 'good-agent' "$TMP/C.out" && fail "seeded-orphan NC (unit): false-flagged the dispatched good-agent" \
  || pass "seeded-orphan NC (unit): the dispatched good-agent is NOT flagged"

# =========================== D. seeded-orphan NC: end-to-end through the close ======================
DD="$TMP/mgD"; mk_megagoal "$DD"
SENT_D="$TMP/close-D.sentinel"
MOCK_RM="$DD/ROADMAP.md" CLOSE_SENTINEL="$SENT_D" CLAUDE_FLAGS="" \
  TIER4_CORPUS="$CORPUS_ORPHAN" \
  CLAUDE_CMD="$MOCK" bash "$ORCH" run "$DD" > "$TMP/D.out" 2>&1
rcD=$?
[ "$rcD" != 0 ] \
  && pass "seeded-orphan NC (e2e): the close HALTS nonzero on an orphan (not held clean)" \
  || { fail "seeded-orphan NC (e2e): close did not halt (rc=$rcD)"; cat "$TMP/D.out"; }
grep -q 'seeded-orphan' "$TMP/D.out" && grep -q 'BLOCKING' "$TMP/D.out" \
  && pass "seeded-orphan NC (e2e): the orphan is named as BLOCKING" || { fail "seeded-orphan NC (e2e): orphan not named"; cat "$TMP/D.out"; }
# fail-fast: the orphan halt happens BEFORE the verifier session is spent.
[ ! -f "$SENT_D" ] \
  && pass "seeded-orphan NC (e2e): fail-fast -- verifier session NOT dispatched after a blocking orphan" \
  || fail "seeded-orphan NC (e2e): verifier session ran despite a blocking orphan"
grep -q 'HELD for the final human gate' "$TMP/D.out" \
  && fail "seeded-orphan NC (e2e): the gate was held despite a blocking orphan" \
  || pass "seeded-orphan NC (e2e): the gate is NOT held on a blocking orphan"

# =========================== E. whole-word dispatch match (advisor != advisory) ====================
CORPUS_WORD="$TMP/corpusWord"; mkdir -p "$CORPUS_WORD/agents" "$CORPUS_WORD/commands"
echo "# advisor" > "$CORPUS_WORD/agents/advisor.md"
echo "This command is advisory only; it references no agent." > "$CORPUS_WORD/commands/note.md"
( set -uo pipefail; source "$ORCH"
  out=$(_no_orphan_check "$CORPUS_WORD"); rc=$?
  printf 'rc=%s\n%s\n' "$rc" "$out"
) > "$TMP/E.out" 2>&1
{ grep -q '^rc=1$' "$TMP/E.out" && grep -q 'agent advisor ' "$TMP/E.out"; } \
  && pass "whole-word match: 'advisor' is NOT satisfied by the word 'advisory' (grep -w works)" \
  || { fail "whole-word match: advisor wrongly treated as dispatched by 'advisory'"; cat "$TMP/E.out"; }

# =========================== F. opt-out: TIER4_CLOSE=0 restores done-and-return =====================
DF="$TMP/mgF"; mk_megagoal "$DF"
SENT_F="$TMP/close-F.sentinel"
MOCK_RM="$DF/ROADMAP.md" CLOSE_SENTINEL="$SENT_F" CLAUDE_FLAGS="" TIER4_CLOSE=0 \
  TIER4_CORPUS="$CORPUS_A" \
  CLAUDE_CMD="$MOCK" bash "$ORCH" run "$DF" > "$TMP/F.out" 2>&1
rcF=$?
[ "$rcF" = 0 ] && grep -q 'all sub-goals checked; done' "$TMP/F.out" \
  && pass "opt-out: TIER4_CLOSE=0 restores the bare done-and-return" || { fail "opt-out: done message missing (rc=$rcF)"; cat "$TMP/F.out"; }
[ ! -f "$SENT_F" ] \
  && pass "opt-out: TIER4_CLOSE=0 dispatches NO close session" || fail "opt-out: a close session ran despite TIER4_CLOSE=0"

# =========================== G. no-corpus: rc=2 skip (not a false halt) =============================
# _no_orphan_check on a path with no agents/ dir returns 2 (skip signal, not 0-clean, not 1-orphan).
( set -uo pipefail; source "$ORCH"
  _no_orphan_check "$TMP/does-not-exist" >/dev/null 2>&1; echo "rc=$?"
) > "$TMP/G1.out" 2>&1
grep -q '^rc=2$' "$TMP/G1.out" \
  && pass "no-corpus unit: _no_orphan_check returns 2 (skip signal) when there is no agents/ to sweep" \
  || { fail "no-corpus unit: expected rc 2"; cat "$TMP/G1.out"; }
# End-to-end: a corpus dir that exists but has NO agents/ -> the close SKIPS the sweep with a WARN,
# still dispatches the verifier session and HOLDS the gate (rc 2 must NOT be a false halt, and must
# NOT be mis-reported as a clean sweep).
DG="$TMP/mgG"; mk_megagoal "$DG"; SENT_G="$TMP/close-G.sentinel"
CORPUS_EMPTY="$TMP/corpusEmpty"; mkdir -p "$CORPUS_EMPTY"   # exists, but no agents/
MOCK_RM="$DG/ROADMAP.md" CLOSE_SENTINEL="$SENT_G" CLAUDE_FLAGS="" \
  TIER4_CORPUS="$CORPUS_EMPTY" CLAUDE_CMD="$MOCK" bash "$ORCH" run "$DG" > "$TMP/G2.out" 2>&1
rcG=$?
{ [ "$rcG" = 0 ] && [ -f "$SENT_G" ] && grep -q 'HELD for the final human gate' "$TMP/G2.out" \
    && grep -q 'skipping the no-orphan sweep' "$TMP/G2.out" \
    && ! grep -q 'no-orphan sweep clean' "$TMP/G2.out"; } \
  && pass "no-corpus e2e: rc 2 -> WARN+skip (not a halt, not mis-reported clean); session ran, gate held" \
  || { fail "no-corpus e2e: rc=$rcG (expected skip+hold, not halt/clean)"; cat "$TMP/G2.out"; }

# ---- summary --------------------------------------------------------------------------------------
echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
