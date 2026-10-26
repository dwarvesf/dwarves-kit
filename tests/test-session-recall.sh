#!/usr/bin/env bash
# test-session-recall.sh -- repo-root entry for lib/session/recall's stdlib unittest file, which no
# runner collected: run-all.sh and bin/test-affected pick tests/test-*.sh and the lib shell suites,
# not Python files. Stdlib only, offline; the same shape as tests/test-bench.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../lib/session/recall" || exit 1
if python3 tests/test_recall.py >/dev/null 2>&1; then
  echo "PASS: session-recall"
else
  echo "FAIL: session-recall"; python3 tests/test_recall.py 2>&1 | tail -20; exit 1
fi
