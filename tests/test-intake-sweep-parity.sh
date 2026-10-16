#!/usr/bin/env bash
# test-intake-sweep-parity.sh -- hooks/intake-sweep.sh reproduces the Python intake-sweep on
# every case in tests/fixtures/intake-sweep-parity/cases.jsonl. The expected results were
# generated from the Python hook behind its shim (gen-expected.sh) before the bash port
# replaced it: exit code, stdout, stderr, the files left behind, and the staging file and the
# swept-keys state after the run.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/intake-sweep-parity"
HOOK="$KIT_DIR/hooks/intake-sweep.sh"
# shellcheck source=lib/hook-parity.sh
source "$KIT_DIR/tests/lib/hook-parity.sh"

out=$(hp_check "$FIX/cases.jsonl" "$FIX/expected.jsonl" bash "$HOOK")
rc=$?
printf '%s\n' "$out" | sed 's/^\([0-9]* passed, [0-9]* failed\)$/intake-sweep parity: \1/'
[ "$rc" -eq 0 ]
