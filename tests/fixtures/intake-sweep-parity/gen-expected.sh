#!/usr/bin/env bash
# gen-expected.sh [rev] -- regenerate expected.jsonl from the Python intake-sweep at a pinned
# revision, run through that revision's own shim, so a Python crash reads the way the shim
# surfaced it. The bash port must reproduce every line; the Python file itself is gone from HEAD.
# The Python imported lib/reflect/staging-format.py, so that file rides along from the same rev.
# A crash-* case is one the Python died on: the shim swallowed it (`|| true`), so the golden is a
# silent exit 0, which is what the port does too, and the stray files show what had been written
# before the crash.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-b9306b37}"
# shellcheck source=../../lib/hook-parity.sh
source "$KIT_ROOT/tests/lib/hook-parity.sh"
HP_KIT_ROOT="$KIT_ROOT" HP_EXTRA_FILES="lib/reflect/staging-format.py" \
  hp_gen_expected "$REV" intake-sweep "$HERE/cases.jsonl" "$HERE/expected.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"
