#!/usr/bin/env bash
# gen-expected.sh [rev] -- regenerate expected.jsonl from the Python backlog-stage at a pinned
# revision, run through that revision's own shim, so a Python crash reads the way the shim
# surfaced it. The bash port must reproduce every line; the Python file itself is gone from HEAD.
# The Python imported lib/reflect/staging-format.py, and the shim's --surface pass runs
# hooks/intake-sweep.py, so both ride along from the same rev. A crash-* case is one the Python
# died on: the shim swallowed it (`|| true`), so the golden is a silent exit 0 plus whatever the
# Python had already written (the throttle stamp), which is what the port does too.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-b9306b37}"
# shellcheck source=../../lib/hook-parity.sh
source "$KIT_ROOT/tests/lib/hook-parity.sh"
HP_KIT_ROOT="$KIT_ROOT" HP_EXTRA_FILES="lib/reflect/staging-format.py hooks/intake-sweep.py hooks/intake-sweep.sh" \
  hp_gen_expected "$REV" backlog-stage "$HERE/cases.jsonl" "$HERE/expected.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"
