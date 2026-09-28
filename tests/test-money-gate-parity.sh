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
# assertion allows 2 s so a loaded machine does not flake it, which still catches a
# per-position scan (4 s at 100 KB under the stock macOS awk).
T="$(mktemp -d)"
head -c 1048576 /dev/zero | tr '\0' 'a' > "$T/filler"
printf '{"tool_input":{"file_path":"/w/fin/big.csv","content":"%s usd"},"cwd":"/w/fin"}' "$(cat "$T/filler")" > "$T/payload"
start=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || date +%s000)
out=$(env -i PATH="$PATH" HOME="$T" MONEY_GATE_LOG="$T/l.log" MONEY_GATE_REPOS=fin MONEY_GATE_STRICT=1 bash "$HOOK" < "$T/payload")
end=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || date +%s000)
ms=$((end - start))
if [ "$ms" -lt 2000 ] && printf '%s' "$out" | grep -q '"ask"'; then
  echo "  PASS 1 MB Write checked in ${ms} ms"
else
  fail=$((fail + 1)); echo "  FAIL 1 MB Write: ${ms} ms, ask=$(printf '%s' "$out" | grep -c '"ask"')"
fi
[ "$fail" -eq 0 ]
