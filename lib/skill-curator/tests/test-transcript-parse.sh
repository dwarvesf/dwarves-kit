#!/usr/bin/env bash
# TASK-002: lock the transcript parser against the committed sample schema. No live model.
# Run: bash tests/test-transcript-parse.sh   Pass: "test-transcript-parse: all N passed", exit 0.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/lib/transcript.sh"
FIX="$DIR/tests/fixtures/sample-transcript.jsonl"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

out="$(transcript_compact "$FIX" 40)"

echo "[1] keeps user + assistant text turns, role-tagged"
grep -q '^\[user\] deploy the worker with wrangler' <<<"$out" \
  && grep -q '^\[assistant\] running wrangler deploy now' <<<"$out" \
  && grep -q '^\[assistant\] deployed successfully' <<<"$out" \
  && ok "all three text turns present" || no "missing a turn: $out"

echo "[2] skips thinking blocks"
if ! grep -q 'THINKING-should-be-skipped' <<<"$out"; then ok "thinking skipped"; else no "thinking leaked"; fi

echo "[3] skips summary lines"
if ! grep -q 'OLD-SUMMARY-LINE' <<<"$out"; then ok "summary skipped"; else no "summary leaked"; fi

echo "[4] skips a turn with no text block (tool_result only)"
# the tool_result user turn has no text; only 3 role-tagged blocks should exist
n="$(grep -c '^\[' <<<"$out")"
if [[ "$n" -eq 3 ]]; then ok "exactly 3 text turns (tool_result skipped)"; else no "got $n turns"; fi

echo "[5] respects K (last turn only)"
out1="$(transcript_compact "$FIX" 1)"
if [[ "$(grep -c '^\[' <<<"$out1")" -eq 1 ]] && grep -q 'deployed successfully' <<<"$out1"; then
  ok "K=1 -> only the last turn"; else no "K cap wrong: $out1"; fi

echo "[6] missing / empty path -> empty output, no error"
e1="$(transcript_compact "/nonexistent.jsonl" 40)"; e2="$(transcript_compact "" 40)"
if [[ -z "$e1" && -z "$e2" ]]; then ok "missing/empty path -> empty"; else no "non-empty on missing path"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-transcript-parse: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-transcript-parse: all $pass passed"
