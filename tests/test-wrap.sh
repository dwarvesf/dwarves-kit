#!/usr/bin/env bash
# runner: relays every tests/test-wrap-*.sh suite and prints the summed counts.
# tests/run-all.sh skips files carrying this header, so each suite runs once.
#
# The monolith's `bash tests/test-wrap.sh` invocation stays live: output is the
# concatenation of the suites' own output, the assert-line set unchanged, and the
# final line keeps its `test-wrap: ...` wording.
#
# The suites share their harness through tests/lib/wrap-stub.sh.
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Suites run concurrently (WRAP_JOBS at a time, largest file first so the slow ones start early).
# Each suite's output and exit code land in its own temp file; printing follows glob order.
WRAP_JOBS="${WRAP_JOBS:-4}"
export OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-wrap.XXXXXX")"
trap 'rm -rf "$OUT_DIR"' EXIT

# test-wrap counts the PASS lines of each suite; a cached land section prints none, so it runs fresh here.
ls -S "$KIT_DIR"/tests/test-wrap-*.sh | xargs -n1 -P "$WRAP_JOBS" bash -c \
  'n="$(basename "$1")"; LAND_CACHE=0 bash "$1" >"$OUT_DIR/$n.out" 2>&1; echo $? >"$OUT_DIR/$n.rc"' _ >/dev/null
# the xargs call only dispatches: a suite's rc is read from its own file below.

PASS=0; FAIL=0; RC=0
for t in "$KIT_DIR"/tests/test-wrap-*.sh; do
  n="$(basename "$t")"
  out="$(cat "$OUT_DIR/$n.out")"
  printf '%s\n' "$out"
  [ "$(cat "$OUT_DIR/$n.rc" 2>/dev/null || echo 1)" -eq 0 ] || RC=1
  PASS=$((PASS + $(printf '%s\n' "$out" | grep -acE '^  .\[0;32mPASS')))
  FAIL=$((FAIL + $(printf '%s\n' "$out" | grep -acE '^  .\[0;31mFAIL')))
done
TOTAL=$((PASS + FAIL))

echo
if [ "$RC" -ne 0 ]; then echo "test-wrap: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap: all $PASS passed"
