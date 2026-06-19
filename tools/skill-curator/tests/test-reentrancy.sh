#!/usr/bin/env bash
# TASK-009: a reviewer cannot trigger a reviewer. The hook no-ops under CLAUDE_REVIEWING, and the
# reviewer sets CLAUDE_REVIEWING for the model call, so a hook fired from inside the reviewer is a
# no-op (no runaway recursion). Run: bash tests/test-reentrancy.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DIR/hooks/skill-review.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }
export CC_SI_STATE_DIR="$TMP/state" CC_SI_PROPOSALS_DIR="$TMP/proposals"
PAY="$TMP/pay.json"; jq -n --arg tp "$DIR/tests/fixtures/sample-transcript.jsonl" '{session_id:"r",transcript_path:$tp}' > "$PAY"

echo "[1] hook is a no-op when CLAUDE_REVIEWING is set (no spawn)"
CLAUDE_REVIEWING=1 CC_SI_REVIEWER_CMD="touch $TMP/SPAWNED" bash "$HOOK" < "$PAY"; rc=$?
sleep 0.5
if [[ $rc -eq 0 && ! -e "$TMP/SPAWNED" ]]; then ok "reentrant hook spawned nothing"; else no "reentrancy guard failed (rc=$rc)"; fi

echo "[2] the reviewer sets CLAUDE_REVIEWING for the model call (source guard)"
if grep -q 'CLAUDE_REVIEWING=1' "$DIR/lib/reviewer-run.sh"; then ok "reviewer exports CLAUDE_REVIEWING"; else no "reviewer does not set the sentinel"; fi

echo "[3] functional: a reviewer that re-invokes the hook does NOT recurse (counter stays 1)"
CTR="$TMP/REVIEWS"
# The reviewer mock appends one line, then re-invokes the hook. run_reviewer runs it with
# CLAUDE_REVIEWING=1, so the nested hook no-ops -> exactly one append, no runaway.
CC_SI_REVIEWER_CMD="echo x >> $CTR; bash $HOOK < $PAY" bash "$HOOK" < "$PAY"
n=0; for _ in $(seq 1 16); do [[ -f "$CTR" ]] && { n="$(wc -l < "$CTR" | tr -d ' ')"; [[ "$n" -ge 1 ]] && break; }; sleep 0.25; done
sleep 0.8   # give any (buggy) recursion time to pile up
n="$(wc -l < "$CTR" 2>/dev/null | tr -d ' ' || echo 0)"
if [[ "$n" -eq 1 ]]; then ok "reviewer ran once; nested hook no-oped (counter=1)"; else no "recursion / wrong count: $n"; fi
pkill -f "$CTR" 2>/dev/null || true

echo
if [[ $fail -gt 0 ]]; then echo "test-reentrancy: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-reentrancy: all $pass passed"
