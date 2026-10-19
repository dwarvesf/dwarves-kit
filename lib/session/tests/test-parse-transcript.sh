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

echo "[8] --tail-text K: last K text turns as [role] text blocks, the skill-curator summary"
CUR="${DIR}/../skill-curator/tests/fixtures/sample-transcript.jsonl"
t2="$(bash "$PT" --tail-text 2 "$CUR")"
if [[ "$t2" == $'[assistant] running wrangler deploy now\n\n[assistant] deployed successfully' ]]; then ok "K=2 keeps the last two text turns"; else no "tail-text K=2 wrong: $t2"; fi
t0="$(bash "$PT" --tail-text 0 "$CUR")"
if [[ -z "$t0" ]]; then ok "K=0 keeps nothing"; else no "K=0 not empty: $t0"; fi
bash "$PT" --tail-text abc "$CUR" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 1 ]]; then ok "non-numeric K fails with exit 1"; else no "non-numeric K rc=$rc"; fi

echo "[9] --harvest-text MAX: text blocks newline-joined, last MAX chars, x sentinel"
HT="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"alpha"}]}}' \
  '{"type":"system","message":{"content":[{"type":"text","text":"ignored"}]}}' \
  'not json' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"beta"},{"type":"tool_use","name":"x"}]}}' > "$HT/ok.jsonl"
h="$(bash "$PT" --harvest-text 100 "$HT/ok.jsonl"; echo END)"
if [[ "$h" == $'alpha\nbetax\nEND' || "$h" == $'alpha\nbetaxEND' ]]; then ok "joined text plus sentinel, system and bad lines skipped"; else no "harvest-text wrong: $h"; fi
h="$(bash "$PT" --harvest-text 4 "$HT/ok.jsonl")"
if [[ "$h" == "betax" ]]; then ok "MAX keeps the last characters"; else no "MAX=4 wrong: $h"; fi
h="$(bash "$PT" --harvest-text 0 "$HT/ok.jsonl")"
if [[ "$h" == $'alpha\nbetax' ]]; then ok "MAX=0 keeps everything"; else no "MAX=0 wrong: $h"; fi
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"x"}]}}' '5' > "$HT/obj.jsonl"
printf '%s\n' '{"type":"user","message":"x"}' > "$HT/msg.jsonl"
printf '%s\n' '{"type":"user","message":{"content":7}}' > "$HT/content.jsonl"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":5}]}}' > "$HT/text.jsonl"
printf '\xff\xfe\n' > "$HT/utf8.jsonl"
for bad in obj msg content text utf8; do
  out="$(bash "$PT" --harvest-text 100 "$HT/$bad.jsonl" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 1 && -z "$out" ]]; then ok "crash shape '$bad' prints nothing, exit 1"; else no "crash shape '$bad' rc=$rc out=$out"; fi
done
bash "$PT" --harvest-text 100 "$HT/missing.jsonl" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 1 ]]; then ok "missing file exits 1"; else no "missing file rc=$rc"; fi
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"keep"}]}}' > "$HT/badbyte.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"bad \xff byte"}]}}\n' >> "$HT/badbyte.jsonl"
tb="$(bash "$PT" --tail-text 5 "$HT/badbyte.jsonl")"; rc=$?
if [[ $rc -eq 0 && "$tb" == *"[user] keep"* && "$tb" == *$'bad \xef\xbf\xbd byte'* ]]; then ok "--tail-text reads past invalid UTF-8 (U+FFFD), unlike --harvest-text"; else no "tail-text bad byte rc=$rc out=$tb"; fi

echo
if [[ $fail -eq 0 ]]; then
  echo "smoke: all $pass passed"
  exit 0
else
  echo "smoke: $fail FAILED, $pass passed" >&2
  exit 1
fi
