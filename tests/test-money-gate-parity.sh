#!/usr/bin/env bash
# test-money-gate-parity.sh -- hooks/money-gate.sh reproduces the Python money-gate's
# behavior on every case in tests/fixtures/money-gate-parity/cases.jsonl. The expected
# outputs were generated from the Python hook (gen-expected.sh) before the bash port
# replaced it: exit code, stdout as normalized JSON, and the log line minus its epoch.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/money-gate-parity"
HOOK="$KIT_DIR/hooks/money-gate.sh"
TMP="$(mktemp -d)"
pass=0; fail=0
while IFS= read -r c; do
  name=$(jq -r .name <<<"$c")
  exp=$(grep -F "\"name\":\"$name\"" "$FIX/expected.jsonl")
  log="$TMP/$name.log"
  envs=(); while IFS= read -r kv; do envs+=("$kv"); done < <(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' <<<"$c")
  rc=0
  out=$(jq -j .payload <<<"$c" | env -i PATH="$PATH" HOME="$TMP" MONEY_GATE_LOG="$log" "${envs[@]}" bash "$HOOK") || rc=$?
  norm=$( [ -n "$out" ] && jq -S -c . <<<"$out" 2>/dev/null || printf '%s' "$out" )
  logn=$( [ -f "$log" ] && cut -f2- "$log" || true )
  got=$(jq -c -n --arg name "$name" --argjson rc "$rc" --arg stdout "$norm" --arg log "$logn" \
    '{name:$name, rc:$rc, stdout:$stdout, log:$log}')
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
[ "$fail" -eq 0 ]
