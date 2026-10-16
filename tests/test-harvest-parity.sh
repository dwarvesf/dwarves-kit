#!/usr/bin/env bash
# test-harvest-parity.sh -- hooks/harvest.sh reproduces the Python harvest on every case in
# tests/fixtures/harvest-parity/cases.jsonl. The expected results were generated from the Python
# hook behind its shim (gen-expected.sh) before the bash port replaced it: exit code, stdout,
# stderr, the files left behind, the ledger, the lab-log draft, and the exact prompt the model was
# sent. A detached run is awaited through the harness's `settle` field.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/harvest-parity"
HOOK="$KIT_DIR/hooks/harvest.sh"
# shellcheck source=lib/hook-parity.sh
source "$KIT_DIR/tests/lib/hook-parity.sh"

out=$(hp_check "$FIX/cases.jsonl" "$FIX/expected.jsonl" bash "$HOOK")
rc=$?
printf '%s\n' "$out" | sed 's/^\([0-9]* passed, [0-9]* failed\)$/harvest parity: \1/'
[ "$rc" -eq 0 ]
