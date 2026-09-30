#!/usr/bin/env bash
# gen-expected.sh [rev] -- regenerate expected.jsonl from the Python money-gate at a
# pinned revision (default ce08a00b), run through that revision's own bash shim, so a
# Python crash reads the way the shim surfaced it (exit 0, nothing printed). The bash port
# must reproduce every line; the Python file itself is gone from HEAD.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-ce08a00b}"
H="$(mktemp -d)"; mkdir -p "$H/hooks" "$H/bin"
git -C "$ROOT" show "$REV:hooks/money-gate.sh" > "$H/hooks/money-gate.sh"
git -C "$ROOT" show "$REV:hooks/money-gate.py" > "$H/hooks/money-gate.py"
# the interpreter path is resolved once: under env -i a version-manager shim would
# reinstall python per call
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$H/bin/python3"
: > "$HERE/expected.jsonl"
while IFS= read -r c; do
  printf '%s' "$c" | PATH="$H/bin:$PATH" bash "$HERE/run-case.sh" bash "$H/hooks/money-gate.sh" >> "$HERE/expected.jsonl"
done < "$HERE/cases.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"
