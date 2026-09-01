#!/usr/bin/env bash
# test-parse-transcript.sh -- unit test for the shared JSONL turn-parser
# (lib/session/parse-transcript.sh / parse_transcript.py), exercised as a
# standalone shell unit, independent of session-observe / session-recall.
#
# Run: bash lib/session/tests/test-parse-transcript.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"     # lib/session
PT="${DIR}/parse-transcript.sh"
FIX="${DIR}/tests/fixtures"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] golden path: 9 turns in, 9 valid JSON objects out"
out="$(bash "$PT" "$FIX/sample.jsonl")"
n=$(printf '%s\n' "$out" | grep -c .)
if [[ "$n" -eq 9 ]]; then ok "9 lines out"; else no "expected 9, got $n"; fi

echo "[2] golden path: every emitted line is valid JSON"
if printf '%s\n' "$out" | python3 -c "import sys,json
for l in sys.stdin:
    l=l.strip()
    if l: json.loads(l)"; then ok "all lines parse as JSON"; else no "a line failed to parse"; fi

echo "[3] NC malformed: one bad line skipped, the two good ones survive, exit 0 (not fatal)"
mout="$(bash "$PT" "$FIX/malformed.jsonl")"
mrc=$?
mn=$(printf '%s\n' "$mout" | grep -c .)
if [[ "$mn" -eq 2 && $mrc -eq 0 ]]; then ok "2 of 3 lines survive, exit 0"; else no "expected 2 lines/exit 0, got $mn lines/exit $mrc"; fi

echo "[4] NC empty transcript: honest-zero (0 lines, exit 0, no crash)"
eout="$(bash "$PT" "$FIX/empty.jsonl")"
erc=$?
en=$(printf '%s\n' "$eout" | grep -c .)
if [[ "$en" -eq 0 && $erc -eq 0 ]]; then ok "0 lines, exit 0"; else no "expected 0 lines/exit 0, got $en lines/exit $erc"; fi

echo "[5] NC missing file: clean one-line stderr message, exit 1, no Python traceback"
set +e
merr="$(bash "$PT" "$FIX/does-not-exist.jsonl" 2>&1 >/dev/null)"
mrc2=$?
set -e 2>/dev/null || true
if [[ $mrc2 -eq 1 ]] && ! grep -q "Traceback" <<<"$merr"; then ok "exit 1, clean message: $merr"; else no "expected exit1/no-traceback, got rc=$mrc2: $merr"; fi

echo "[6] NC no argument: usage + exit 2 (not a crash)"
set +e
uerr="$(bash "$PT" 2>&1)"
urc=$?
if [[ $urc -eq 2 ]] && grep -qi usage <<<"$uerr"; then ok "exit 2 with usage"; else no "expected exit2/usage, got rc=$urc: $uerr"; fi

echo "[7] Python API: iter_entries(path) is a generator (streaming), load(path) is a list"
if python3 -c "
import sys, os
sys.path.insert(0, '$DIR')
import parse_transcript as pt
import inspect
assert inspect.isgeneratorfunction(pt.iter_entries), 'iter_entries must be a generator function'
entries = pt.load('$FIX/sample.jsonl')
assert isinstance(entries, list), 'load() must return a list'
assert len(entries) == 9, f'expected 9, got {len(entries)}'
assert entries[0]['message']['content'] == 'please tidy the repo and commit'
print('ok')
" | grep -q '^ok$'; then ok "iter_entries generator, load list, content preserved"; else no "python API contract check failed"; fi

echo
if [[ $fail -eq 0 ]]; then
  echo "smoke: all $pass passed"
  exit 0
else
  echo "smoke: $fail FAILED, $pass passed" >&2
  exit 1
fi
