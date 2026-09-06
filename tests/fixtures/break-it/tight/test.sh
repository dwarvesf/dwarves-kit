#!/usr/bin/env bash
# The tight fixture's own suite. It pins BOTH boundaries, so it catches the probe
# the leaky suite leaves open. Removing the GUARD-LINE from impl.sh must turn this
# suite red; that is the negative control the spec's ## Verification names.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IMPL="${BREAK_IT_IMPL:-$HERE/impl.sh}"
FAIL=0

expect() { # expect <input> <want>
  got=$(bash "$IMPL" "$1")
  if [ "$got" = "$2" ]; then
    echo "  PASS batch_size $1 -> $2"
  else
    echo "  FAIL batch_size $1 -> $got (want $2)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== tight fixture suite ==="
expect 1 ok
expect 5 ok
expect 0 reject
expect 10 ok      # boundary: the last accepted value
expect 11 reject  # boundary: the probe the leaky suite never pins

[ "$FAIL" -eq 0 ]
