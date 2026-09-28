#!/usr/bin/env bash
# gen-expected.sh -- regenerate expected.jsonl from the Python money-gate at a pinned
# revision. The bash port must reproduce it; the Python file itself is gone from HEAD.
# Usage: bash tests/fixtures/money-gate-parity/gen-expected.sh [rev]   (default ce08a00b)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-ce08a00b}"
PY="$(mktemp)"; git -C "$ROOT" show "$REV:hooks/money-gate.py" > "$PY"
TMP="$(mktemp -d)"
: > "$HERE/expected.jsonl"
while IFS= read -r c; do
  name=$(jq -r .name <<<"$c")
  log="$TMP/$name.log"
  envs=(); while IFS= read -r kv; do envs+=("$kv"); done < <(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' <<<"$c")
  rc=0
  out=$(jq -j .payload <<<"$c" | env -i PATH="$PATH" HOME="$TMP" MONEY_GATE_LOG="$log" "${envs[@]}" python3 "$PY") || rc=$?
  # stdout compares as normalized JSON (key order, spacing); the log compares minus its epoch column
  norm=$( [ -n "$out" ] && jq -S -c . <<<"$out" || true )
  logn=$( [ -f "$log" ] && cut -f2- "$log" || true )
  jq -c -n --arg name "$name" --argjson rc "$rc" --arg stdout "$norm" --arg log "$logn" \
    '{name:$name, rc:$rc, stdout:$stdout, log:$log}' >> "$HERE/expected.jsonl"
done < "$HERE/cases.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"
