#!/usr/bin/env bash
# cc-observe smoke test. Parses tests/fixtures/sample.jsonl (a synthetic transcript
# with a known Skill, two Bash calls (one errored), a Read, and a system entry whose
# hookInfos carries a deliberately slow hook (500ms) next to a fast one (12ms)).
#
# Run: bash tests/smoke.sh
# Pass: prints "smoke: all N passed", exit 0. Fail: prints which, exit 1.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CC="${DIR}/bin/cc-observe"
FIX="${DIR}/tests/fixtures/sample.jsonl"

pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
no() { echo "  FAIL: $*" >&2; fail=$((fail+1)); }

echo "[1] skills: prose-rag counted once"
out="$("$CC" skills --file "$FIX")"
if grep -q 'prose-rag' <<<"$out" && grep -Eq 'prose-rag[[:space:]]+1' <<<"$out"; then ok "skill prose-rag count 1"; else no "skills output: $out"; fi

echo "[2] tools: Bash counted twice with one error"
out="$("$CC" tools --file "$FIX")"
if grep -Eq 'Bash[[:space:]]+2[[:space:]]+1' <<<"$out"; then ok "Bash count 2, errors 1"; else no "tools output: $out"; fi

echo "[3] tools: Read present (count 1, no error)"
if grep -Eq 'Read[[:space:]]+1[[:space:]]+0' <<<"$out"; then ok "Read count 1, errors 0"; else no "Read row wrong: $out"; fi

echo "[4] hooks: slow hook flagged with max >= 500 (negative control vs fast hook)"
out="$("$CC" hooks --file "$FIX")"
slowmax="$(awk '/slow-hook\.sh/ {print $5}' <<<"$out")"
if grep -q 'slow-hook.sh' <<<"$out" && [[ "${slowmax:-0}" -ge 500 ]]; then ok "slow-hook.sh maxms=${slowmax}"; else no "slow hook not flagged: $out"; fi

echo "[5] hooks: fast inline-echo hook stays small (< 100ms)"
fastmax="$(awk '/inline-echo/ {print $5}' <<<"$out")"
if [[ -n "${fastmax:-}" && "${fastmax}" -lt 100 ]]; then ok "inline-echo maxms=${fastmax} (negative control)"; else no "fast hook wrong: $out"; fi

echo "[6] hooks: hook error surfaced (count 1)"
if grep -q '1 hook errors' <<<"$out"; then ok "1 hook error surfaced"; else no "hook errors not surfaced: $out"; fi

echo "[7] --json emits valid JSON"
if "$CC" report --file "$FIX" --json | python3 -m json.tool >/dev/null 2>&1; then ok "valid json"; else no "json invalid"; fi

echo "[8] missing file -> exit 1"
set +e; "$CC" skills --file "${DIR}/tests/fixtures/nope.jsonl" >/dev/null 2>&1; rc=$?; set -e
if [[ $rc -eq 1 ]]; then ok "exit 1 on missing file"; else no "got rc=$rc"; fi

echo "[9] report runs all three sections"
out="$("$CC" report --file "$FIX")"
if grep -q '# skills' <<<"$out" && grep -q '# tools' <<<"$out" && grep -q '# hooks' <<<"$out"; then ok "report has all sections"; else no "report incomplete"; fi

echo
if [[ $fail -gt 0 ]]; then echo "smoke: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "smoke: all $pass passed"
