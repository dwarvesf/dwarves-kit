#!/usr/bin/env bash
# The leaky fixture's own suite. It PASSES. It tests two interior values and the
# lower bound, never the upper bound the contract states, so it leaves the
# 11-is-accepted hole completely unconstrained.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FAIL=0

expect() { # expect <input> <want>
  got=$(bash "$HERE/impl.sh" "$1")
  if [ "$got" = "$2" ]; then
    echo "  PASS batch_size $1 -> $2"
  else
    echo "  FAIL batch_size $1 -> $got (want $2)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== leaky fixture suite ==="
expect 1 ok
expect 5 ok
expect 0 reject

[ "$FAIL" -eq 0 ]
