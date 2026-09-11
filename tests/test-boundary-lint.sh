#!/usr/bin/env bash
# test-boundary-lint.sh -- SG-01 (learning-boundary, SPEC-285): the engine names no
# consumer, by path or by skill. Green on this branch; the negative control (planting
# `learning-ledger` in lib/reflect/weekend-batch.sh) is run separately via negctl.sh
# against the real file, per docs/verification/engine-learn-seam.md.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

OUT="$(bash "$KIT_DIR/lib/gate/boundary-lint.sh" "$KIT_DIR" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'boundary-lint: PASS'; then
  echo "PASS boundary-lint: $OUT"
  exit 0
else
  echo "FAIL boundary-lint (rc=$RC):"
  printf '%s\n' "$OUT"
  exit 1
fi
