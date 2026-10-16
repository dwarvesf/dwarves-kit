#!/usr/bin/env bash
# gen-expected.sh [rev] -- regenerate expected.jsonl from the Python context-hints at a
# pinned revision, run through that revision's own bash shim. The bash port must reproduce
# every line; the Python file itself is gone from HEAD. The Python swallowed every crash
# itself (exit 0, nothing printed), so no golden needs a recorded divergence.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-b9306b37}"
# shellcheck source=../../lib/hook-parity.sh
source "$KIT_ROOT/tests/lib/hook-parity.sh"
HP_KIT_ROOT="$KIT_ROOT" hp_gen_expected "$REV" context-hints "$HERE/cases.jsonl" "$HERE/expected.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"
