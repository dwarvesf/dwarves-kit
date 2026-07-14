#!/usr/bin/env bash
# TASK-003 (basic): the PreCompact/SessionEnd hook returns fast (detached reviewer), and the
# reentrancy + enabled gates hold. The fuller sleep-30 async + reentrancy suite is sub-goal 03.
# Run: bash tests/test-hook-async.sh   Pass: "...: all N passed", exit 0.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DIR/hooks/skill-review.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

export SKILL_CURATOR_STATE_DIR="$TMP/state"
export SKILL_CURATOR_PROPOSALS_DIR="$TMP/proposals"
PAY="$TMP/payload.json"
jq -n --arg tp "$DIR/tests/fixtures/sample-transcript.jsonl" '{session_id:"sess-hook",transcript_path:$tp}' > "$PAY"
# A draft envelope the (slow) detached reviewer will stage.
jq -nc --arg b $'---\nname: async-skill\n---\n# Async skill\nstep one\n' \
  '{type:"result",total_cost_usd:0.001,result:({draft:{slug:"async-skill",name:"async-skill",description:"x",body:$b},reason:"y"}|tojson),usage:{input_tokens:10,output_tokens:5}}' \
  > "$TMP/env.json"

echo "[1] hook returns fast (<1.5s) even though the reviewer sleeps 2s (detached, non-blocking)"
t0="$(python3 -c 'import time;print(time.time())')"
SKILL_CURATOR_REVIEWER_CMD="sleep 2; cat $TMP/env.json" bash "$HOOK" < "$PAY"; rc=$?
t1="$(python3 -c 'import time;print(time.time())')"
el="$(python3 -c "print(round($t1-$t0,2))")"
fast="$(python3 -c "print(1 if ($t1-$t0)<1.5 else 0)")"
if [[ $rc -eq 0 && "$fast" -eq 1 ]]; then ok "hook returned in ${el}s, exit 0"; else no "hook slow/failed: ${el}s rc=$rc"; fi

echo "[2] the detached reviewer still completed out-of-band (draft appears after the hook returned)"
appeared=0; for _ in $(seq 1 40); do [[ -f "$SKILL_CURATOR_PROPOSALS_DIR/async-skill/SKILL.md" ]] && { appeared=1; break; }; sleep 0.25; done
if [[ "$appeared" -eq 1 ]]; then ok "detached reviewer staged async-skill"; else no "detached reviewer never staged"; fi

echo "[3] reentrancy: CLAUDE_REVIEWING set -> hook does nothing (no spawn, negative control)"
rm -rf "$SKILL_CURATOR_PROPOSALS_DIR" "$SKILL_CURATOR_STATE_DIR" 2>/dev/null
CLAUDE_REVIEWING=1 SKILL_CURATOR_REVIEWER_CMD="touch $TMP/REENT; cat $TMP/env.json" bash "$HOOK" < "$PAY"; rc=$?
sleep 0.6
if [[ $rc -eq 0 && ! -e "$TMP/REENT" ]]; then ok "reentrant hook is a no-op"; else no "reentrancy guard failed (rc=$rc, REENT=$( [ -e "$TMP/REENT" ] && echo yes || echo no))"; fi

echo "[4] disabled: SKILL_CURATOR_ENABLED=false -> hook does nothing (negative control)"
rm -rf "$SKILL_CURATOR_PROPOSALS_DIR" "$SKILL_CURATOR_STATE_DIR" 2>/dev/null
SKILL_CURATOR_ENABLED=false SKILL_CURATOR_REVIEWER_CMD="touch $TMP/DISABLED; cat $TMP/env.json" bash "$HOOK" < "$PAY"; rc=$?
sleep 0.6
if [[ $rc -eq 0 && ! -e "$TMP/DISABLED" ]]; then ok "disabled hook is a no-op"; else no "enabled-gate failed"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-hook-async: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-hook-async: all $pass passed"
