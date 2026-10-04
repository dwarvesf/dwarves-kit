#!/usr/bin/env bash
# runner: relays every tests/test-meta-<area>.sh suite and prints the summed counts.
# tests/run-all.sh skips files carrying this header, so each suite runs once; under
# --changed a pick that names THIS file expands to the runner-suites list below.
# runner-suites: plugin-hooks contract agents-commands spec-depth review-verifiers vmodel-dispatch goal-ledger docs-registry
#
# Not always-on: bin/test-affected picks this suite when a diff touches a path it
# reads (meta_input there). The nightly --all runs the area suites daily; CI --all
# before a release.
# test-meta.sh -- Structural integrity tests for kit artifacts, split per area.
# The monolith's `bash tests/test-meta.sh` invocation stays live: output is the
# concatenation of the suites' own output plus the summed `Passed:` line, and the
# assert-line set is unchanged.
#
# The suites share their harness through tests/lib/meta-stub.sh. tests/test-meta-agent.sh
# is NOT part of this group (it is the meta-agent drafter suite), so the list above
# is explicit, never a test-meta-*.sh glob.

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/run-lock.sh"; run_lock_exec "$KIT_DIR/tests/test-meta.sh" "$@"

# Suites run concurrently (META_JOBS at a time, largest file first so the slow
# ones start early). Each suite's output and exit code land in its own temp file;
# printing follows the runner-suites order.
META_JOBS="${META_JOBS:-4}"
export OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-meta.XXXXXX")"
trap 'rm -rf "$OUT_DIR"' EXIT

SUITES="$(sed -n 's/^# runner-suites: //p' "${BASH_SOURCE[0]}")"
for _a in $SUITES; do printf '%s\n' "$KIT_DIR/tests/test-meta-$_a.sh"; done \
  | xargs -n1 -P "$META_JOBS" bash -c \
  'n="$(basename "$1")"; bash "$1" >"$OUT_DIR/$n.out" 2>&1; echo $? >"$OUT_DIR/$n.rc"' _ >/dev/null
# the xargs call only dispatches: a suite's rc is read from its own file below.

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0; RC=0
for _a in $SUITES; do
  n="test-meta-$_a.sh"
  out="$(cat "$OUT_DIR/$n.out")"
  printf '%s\n' "$out"
  [ "$(cat "$OUT_DIR/$n.rc" 2>/dev/null || echo 1)" -eq 0 ] || RC=1
  PASS=$((PASS + $(printf '%s\n' "$out" | grep -acE '^  .\[0;32mPASS')))
  FAIL=$((FAIL + $(printf '%s\n' "$out" | grep -acE '^  .\[0;31mFAIL')))
done
TOTAL=$((PASS + FAIL))

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All meta tests passed.${NC}"
  exit 0
fi
