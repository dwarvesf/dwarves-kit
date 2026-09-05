#!/bin/bash
# test-bench.sh -- repo-root entry for lib/bench's own Python tests (SPEC-200 C4 wants every
# module reachable from tests/); runs each module test file the way lib/bench/README.md says.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../lib/bench" || exit 1
fails=0
for t in tests/test_*.py; do
  if python3 "$t" >/dev/null 2>&1; then echo "  ok   $t"; else echo "  FAIL $t"; python3 "$t" 2>&1 | tail -20; fails=$((fails+1)); fi
done
[ "$fails" = 0 ] && echo "PASS: bench ($(ls tests/test_*.py | wc -l | tr -d ' ') files)" || { echo "FAIL: $fails file(s)"; exit 1; }
