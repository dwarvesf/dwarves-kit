#!/usr/bin/env bash
# CONTRACT: batch_size <n> prints "ok" for an n in the closed range 1..10, and
# "reject" for anything outside it. The upper bound is part of the contract, not
# an implementation detail: a caller passing 11 must be rejected.
#
# This is the LEAKY half of the break-it fixture pair. It enforces the lower
# bound only. Its own suite (test.sh) is green, because that suite tests two
# INTERIOR values and never the boundary. That is the whole point: a green suite
# that does not constrain the code.

batch_size() {
  n="$1"
  if [ -z "$n" ] || [ "$n" -lt 1 ] 2>/dev/null; then
    echo "reject"
    return 0
  fi
  echo "ok"
}

batch_size "$@"
