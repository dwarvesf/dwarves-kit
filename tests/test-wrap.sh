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

PASS=0; FAIL=0; RC=0
for t in "$KIT_DIR"/tests/test-wrap-*.sh; do
  out="$(bash "$t" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  [ "$rc" -eq 0 ] || RC=1
  PASS=$((PASS + $(printf '%s\n' "$out" | grep -acE '^  .\[0;32mPASS')))
  FAIL=$((FAIL + $(printf '%s\n' "$out" | grep -acE '^  .\[0;31mFAIL')))
done
TOTAL=$((PASS + FAIL))

echo
if [ "$RC" -ne 0 ]; then echo "test-wrap: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap: all $PASS passed"
