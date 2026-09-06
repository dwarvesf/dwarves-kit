#!/usr/bin/env bash
# The tight fixture's own suite. It pins BOTH boundaries AND the input shape, so
# it catches the probe the leaky suite leaves open and the malformed-input probe a
# live prober found in the first version of this fixture. Removing the tagged
# upper-bound line from impl.sh must turn this suite red; that is the negative
# control the spec's ## Verification names.

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
expect abc reject   # shape: a non-integer is outside 1..10
expect 3.5 reject   # shape: a non-integer is outside 1..10
expect "" reject    # shape: the empty string is outside 1..10
expect 999999999999999999999 reject  # shape: past the arithmetic range

[ "$FAIL" -eq 0 ]
