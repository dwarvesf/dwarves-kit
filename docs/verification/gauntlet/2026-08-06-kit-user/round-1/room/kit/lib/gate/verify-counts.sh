#!/usr/bin/env bash
# verify-counts.sh -- single-source the kit's verification suite numbers.
#
# Borrowed from the codebase-tool-benchmark's gen_docs.py pattern (the experiment sibling
# of the proof-of-done discipline): a figure should be GENERATED from one source, never
# hand-typed into N docs where it drifts. This runs the kit's own suites and writes their
# pass counts into the marked block of docs/verification/COUNTS.md. A verification log that
# needs "the suite is at N" links to COUNTS.md instead of transcribing a number.
#
# Usage: bash lib/gate/verify-counts.sh   (regenerates docs/verification/COUNTS.md)
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"  # repo root = two levels above lib/gate/
OUT="$KIT/docs/verification/COUNTS.md"

# Run a suite, echo "passed/total" from its "Passed: N / N" summary line.
suite_count() {
  local script="$1" line
  line="$(bash "$KIT/tests/$script" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^Passed:' | tail -1)"
  # line: "Passed: 365 / 365"
  echo "$line" | sed -E 's/^Passed:[[:space:]]*([0-9]+)[[:space:]]*\/[[:space:]]*([0-9]+).*/\1\/\2/'
}

META="$(suite_count test-meta.sh)"
HOOKS="$(suite_count test-hooks.sh)"

BLOCK="<!-- BEGIN GEN:counts -->
| Suite | Passing |
|---|---|
| meta (tests/test-meta.sh) | ${META:-?} |
| hooks (tests/test-hooks.sh) | ${HOOKS:-?} |
<!-- END GEN:counts -->"

if [ ! -f "$OUT" ] || ! grep -q '<!-- BEGIN GEN:counts -->' "$OUT"; then
  mkdir -p "$(dirname "$OUT")"
  cat > "$OUT" <<EOF
# Verification suite counts (generated)

> Numbers between the GEN markers are written by \`lib/gate/verify-counts.sh\` from the live
> suites. Do NOT hand-edit them. To change a number, change the tests then re-run the
> generator. A verification log links here instead of transcribing a count. This is the
> single-source-numbers pattern borrowed from the codebase-tool-benchmark (the sibling
> experiment discipline); see docs/verification/README.md.

$BLOCK
EOF
else
  python3 - "$OUT" "$BLOCK" <<'PY'
import re, sys
path, block = sys.argv[1], sys.argv[2]
txt = open(path).read()
txt = re.sub(r"<!-- BEGIN GEN:counts -->.*?<!-- END GEN:counts -->", block, txt, flags=re.S)
open(path, "w").write(txt)
PY
fi
echo "wrote $OUT (meta=${META:-?}, hooks=${HOOKS:-?})"
