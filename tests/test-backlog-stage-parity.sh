#!/usr/bin/env bash
# test-backlog-stage-parity.sh -- hooks/backlog-stage.sh reproduces the Python backlog-stage on
# every case in tests/fixtures/backlog-stage-parity/cases.jsonl. The expected results were
# generated from the Python hook behind its shim (gen-expected.sh) before the bash port replaced
# it: exit code, stdout, stderr, the files left behind, the staging file, and the exact prompt the
# model was sent. A detached run is awaited through the harness's `settle` field.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$KIT_DIR/tests/fixtures/backlog-stage-parity"
HOOK="$KIT_DIR/hooks/backlog-stage.sh"
# shellcheck source=lib/hook-parity.sh
source "$KIT_DIR/tests/lib/hook-parity.sh"

out=$(hp_check "$FIX/cases.jsonl" "$FIX/expected.jsonl" bash "$HOOK")
rc=$?
printf '%s\n' "$out" | sed 's/^\([0-9]* passed, [0-9]* failed\)$/backlog-stage parity: \1/'
[ "$rc" -eq 0 ]
