#!/usr/bin/env bash
# test-citation-guard-parity.sh -- hooks/citation-guard.sh reproduces the Python
# citation-guard on every case in tests/fixtures/citation-guard-parity/cases.jsonl. The
# expected results were generated from the Python hook (gen-expected.sh) before the bash
# port replaced it: exit code, stderr, and the log line minus its epoch.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/citation-guard-parity"
pass=0; fail=0
while IFS= read -r c; do
  name=$(jq -r .name <<<"$c")
  exp=$(grep -F "\"name\":\"$name\"" "$FIX/expected.jsonl")
  got=$(printf '%s' "$c" | bash "$FIX/run-case.sh" bash "$KIT_DIR/hooks/citation-guard.sh")
  if [ "$got" = "$exp" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAIL $name"
    echo "    want: $exp"
    echo "    got:  $got"
  fi
done < "$FIX/cases.jsonl"
echo "citation-guard parity: $pass passed, $fail failed"

# Latency: a Stop hook reads the whole transcript, and a long session's transcript runs to
# tens of MB, with multi-MB single lines (tool results). A ~20 MB transcript must check well inside the hook timeout; the budget is
# 500 ms on an idle machine (the Python took 72 ms), and the assertion allows 2 s so a
# loaded machine does not flake it, which still catches a slurp-the-file jq pass.
T="$(mktemp -d)"
filler=$(head -c 5000 /dev/zero | tr '\0' 'x')
big=$(head -c 5000000 /dev/zero | tr '\0' 'y')
{ i=0; while [ "$i" -lt 3000 ]; do i=$((i + 1))
    printf '{"type":"user","message":{"content":"question %d"}}\n' "$i"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s turn %d a.md:1"}]}}\n' "$filler" "$i"; done
  # one large tool result on a single line, as a long session's transcript carries
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s"}]}}\n' "$big"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"final nope.md:1"}]}}\n'; } > "$T/big.jsonl"
start=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || date +%s000)
err=$(cd "$FIX/root" && printf '{"transcript_path":"%s","cwd":"%s"}' "$T/big.jsonl" "$FIX/root" \
  | env -i PATH="$PATH" HOME="$T" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 CITATION_GUARD_LOG="$T/l.log" CITATION_GUARD_STRICT=1 bash "$KIT_DIR/hooks/citation-guard.sh" 2>&1 >/dev/null); rc=$?
end=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || date +%s000)
ms=$((end - start))
if [ "$ms" -lt 2000 ] && [ "$rc" = 2 ] && printf '%s' "$err" | grep -q 'nope.md:1'; then
  echo "  PASS 20 MB transcript checked in ${ms} ms"
else
  fail=$((fail + 1)); echo "  FAIL 20 MB transcript: ${ms} ms, rc=$rc"
fi
[ "$fail" -eq 0 ]
