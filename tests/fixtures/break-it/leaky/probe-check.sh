#!/usr/bin/env bash
# Proves the leaky fixture's hole by EXIT CODE, not by prose (DEC-009).
#
# Feeds probe.txt (the one input the suite never pins) to impl.sh and exits 0
# ONLY when the documented contract is violated: the contract says an n above 10
# is rejected, and this implementation accepts it. If someone "fixes" impl.sh,
# this check goes red, which is correct: the fixture would no longer represent
# a suite that fails to constrain its code.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

PROBE=$(tr -d '[:space:]' < "$HERE/probe.txt")
GOT=$(bash "$HERE/impl.sh" "$PROBE")

echo "probe: batch_size $PROBE"
echo "expected (contract): reject"
echo "observed:            $GOT"

if [ "$GOT" = "ok" ]; then
  echo "HOLE CONFIRMED: the contract says reject, the code says ok, and test.sh stays green."
  exit 0
fi

echo "NO HOLE: the implementation honours the contract, so this fixture no longer carries the defect."
exit 1
