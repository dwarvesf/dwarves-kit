#!/usr/bin/env bash
# CONTRACT: identical to the leaky half. batch_size <n> prints "ok" for an n in
# the closed range 1..10, and "reject" for anything outside it.
#
# This is the TIGHT half of the break-it fixture pair. It carries the upper-bound
# guard the leaky half omits, and its suite pins the boundary. The line tagged
# GUARD-LINE below is what the negative control strips: with it gone, test.sh
# must go red.

batch_size() {
  n="$1"
  if [ -z "$n" ] || [ "$n" -lt 1 ] 2>/dev/null; then
    echo "reject"
    return 0
  fi
  if [ "$n" -gt 10 ] 2>/dev/null; then echo "reject"; return 0; fi  # GUARD-LINE
  echo "ok"
}

batch_size "$@"
