#!/usr/bin/env bash
# CONTRACT: identical to the leaky half. batch_size <n> prints "ok" for an n in
# the closed range 1..10, and "reject" for anything outside it.
#
# This is the TIGHT half of the break-it fixture pair. It honours the whole
# contract, not just the two integer boundaries: anything that is not a plain
# decimal integer in 1..10 is rejected. The tagged upper-bound line below is what
# the negative control strips; with it gone, test.sh must go red. The tag is
# written on that one line only, so the strip is exact.
#
# The shape guard exists because a live prober found the earlier version accepted
# "abc", "3.5", "0x5" and a 21-digit value: `[ "$n" -lt 1 ]` exits 2 on
# non-integer input, the `2>/dev/null` hid the error, the failed test read as
# false, and control fell through to "ok". A fixture that claims to be the
# constrained half has to actually be constrained.

batch_size() {
  n="$1"
  case "$n" in
    ''|*[!0-9]*) echo "reject"; return 0 ;;
  esac
  if [ "${#n}" -gt 2 ] || [ "$n" -lt 1 ]; then
    echo "reject"
    return 0
  fi
  if [ "$n" -gt 10 ]; then echo "reject"; return 0; fi  # GUARD-LINE
  echo "ok"
}

batch_size "$@"
