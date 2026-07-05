#!/usr/bin/env bash
# TASK-009: fully-async negative control. A reviewer that sleeps a long time must NOT delay the
# hook return (the interactive turn is never blocked). Run: bash tests/test-async.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DIR/hooks/skill-review.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }
export CC_SI_STATE_DIR="$TMP/state" CC_SI_PROPOSALS_DIR="$TMP/proposals"
PAY="$TMP/pay.json"; jq -n --arg tp "$DIR/tests/fixtures/sample-transcript.jsonl" '{session_id:"a",transcript_path:$tp}' > "$PAY"

echo "[1] a slow (sleep 30) reviewer does not delay the hook return (<1.5s)"
# Tag the sleep's argv[0] uniquely (exec -a) so cleanup kills ONLY this test's sleep, never a
# concurrent loop's sleep 30.
TAG="ccsi-async-$$"
t0="$(python3 -c 'import time;print(time.time())')"
CC_SI_REVIEWER_CMD="echo go > $TMP/LAUNCHED; exec -a $TAG sleep 30" bash "$HOOK" < "$PAY"; rc=$?
t1="$(python3 -c 'import time;print(time.time())')"
el="$(python3 -c "print(round($t1-$t0,2))")"
fast="$(python3 -c "print(1 if ($t1-$t0)<1.5 else 0)")"
if [[ $rc -eq 0 && "$fast" -eq 1 ]]; then ok "hook returned in ${el}s while the reviewer still sleeps 30s"; else no "hook blocked: ${el}s rc=$rc"; fi

echo "[2] the reviewer DID launch out-of-band (detached), it just is not awaited"
launched=0; for _ in $(seq 1 12); do [[ -f "$TMP/LAUNCHED" ]] && { launched=1; break; }; sleep 0.25; done
if [[ "$launched" -eq 1 ]]; then ok "detached reviewer launched (LAUNCHED marker), not blocking"; else no "reviewer never launched"; fi

# Precise cleanup: only this test's tagged sleep.
pkill -f "$TAG" 2>/dev/null || true

echo
if [[ $fail -gt 0 ]]; then echo "test-async: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-async: all $pass passed"
