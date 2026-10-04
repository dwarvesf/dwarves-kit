#!/usr/bin/env bash
# test-money-gate-parity.sh -- hooks/money-gate.sh reproduces the Python money-gate on
# every case in tests/fixtures/money-gate-parity/cases.jsonl. The expected results were
# generated from the Python hook behind its shim (gen-expected.sh) before the bash port
# replaced it: exit code, stdout as normalized JSON, the log line minus its epoch, and any
# stray file. A last check holds the hook to its latency budget on a 1 MB Write.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/money-gate-parity"
HOOK="$KIT_DIR/hooks/money-gate.sh"
pass=0; fail=0
while IFS= read -r c; do
  name=$(jq -r .name <<<"$c")
  exp=$(grep -F "\"name\":\"$name\"" "$FIX/expected.jsonl")
  got=$(printf '%s' "$c" | bash "$FIX/run-case.sh" bash "$HOOK")
  if [ "$got" = "$exp" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAIL $name"
    echo "    want: $exp"
    echo "    got:  $got"
  fi
done < "$FIX/cases.jsonl"
echo "money-gate parity: $pass passed, $fail failed"

# Latency: a 1 MB Write in a financial repo must finish well inside the hook's 5 s timeout
# (a hook that times out does not fire). The budget is 500 ms on an idle machine; the
# assertion is the hook timeout itself (5 s), because a 2 s bound flaked at load average
# 113 to 198. It still catches a per-match copy of the rest (17 s on the dense 1 MB). Two payloads: a sparse one
# (1 MB of filler, one hit at the end) and a dense one (one line of minified JSON full of
# hits), which catches a scan that copies the rest of the string once per match.
T="$(mktemp -d)"
head -c 1048576 /dev/zero | tr '\0' 'a' > "$T/sparse"
i=0; : > "$T/dense"; unit='{\"amount\":1,\"currency\":\"usd\",\"tokenize\":\"x\"},'
while [ "$(wc -c < "$T/dense")" -lt 1048576 ]; do
  i=$((i + 1)); printf '%s%s%s%s%s%s%s%s' "$unit" "$unit" "$unit" "$unit" "$unit" "$unit" "$unit" "$unit" >> "$T/dense"
done
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || date +%s000; }
for kind in sparse dense; do
  printf '{"tool_input":{"file_path":"/w/fin/big.json","content":"%s usd"},"cwd":"/w/fin"}' "$(cat "$T/$kind")" > "$T/payload"
  start=$(now_ms)
  out=$(env -i PATH="$PATH" HOME="$T" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 MONEY_GATE_LOG="$T/l.log" MONEY_GATE_REPOS=fin MONEY_GATE_STRICT=1 bash "$HOOK" < "$T/payload")
  ms=$(( $(now_ms) - start ))
  if [ "$ms" -lt 5000 ] && printf '%s' "$out" | grep -q '"ask"'; then
    echo "  PASS 1 MB $kind Write checked in ${ms} ms"
  else
    fail=$((fail + 1)); echo "  FAIL 1 MB $kind Write: ${ms} ms, ask=$(printf '%s' "$out" | grep -c '"ask"')"
  fi
done

# jq missing: the gate is off, visibly. A PATH with bash and a few basics but no jq (macOS
# ships /usr/bin/jq, so /usr/bin itself cannot be on it).
B="$(mktemp -d)"
for t in bash env cat dirname mkdir date; do p=$(command -v "$t") && ln -s "$p" "$B/$t"; done
err=$(printf '{"tool_input":{"file_path":"/w/fin/x.py","new_string":"usd"},"cwd":"/w/fin"}' \
  | env -i PATH="$B" HOME="$T" MONEY_GATE_REPOS=fin MONEY_GATE_STRICT=1 "$B/bash" "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" = 0 ] && [ "$(printf '%s\n' "$err" | grep -c 'jq')" = 1 ]; then
  echo "  PASS jq missing: exit 0, one stderr line"
else
  fail=$((fail + 1)); echo "  FAIL jq missing: rc=$rc stderr=$err"
fi
[ "$fail" -eq 0 ]
