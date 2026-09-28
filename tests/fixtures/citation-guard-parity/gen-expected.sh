#!/usr/bin/env bash
# gen-expected.sh [rev] -- regenerate expected.jsonl from the Python citation-guard at a
# pinned revision (default ce08a00b), run through that revision's own shim. The bash port
# must reproduce it; the Python file itself is gone from HEAD.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
REV="${1:-ce08a00b}"
# the interpreter path is resolved once: under env -i a version-manager shim would
# reinstall python per call
H="$(mktemp -d)"; mkdir -p "$H/hooks" "$H/bin"
git -C "$ROOT" show "$REV:hooks/citation-guard.sh" > "$H/hooks/citation-guard.sh"
git -C "$ROOT" show "$REV:hooks/citation-guard.py" > "$H/hooks/citation-guard.py"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$H/bin/python3"
: > "$HERE/expected.jsonl"
while IFS= read -r c; do
  printf '%s' "$c" | PATH="$H/bin:$PATH" bash "$HERE/run-case.sh" bash "$H/hooks/citation-guard.sh" >> "$HERE/expected.jsonl"
done < "$HERE/cases.jsonl"
# Deliberate divergence (SPEC-356): the Python crashed (exit 1, a traceback, never a block)
# on a non-object payload and on three malformed transcript shapes; the port exits 0
# silently, like every other malformed input.
tmpf="$(mktemp)"
jq -c 'if (.name | IN("non-object-payload", "crash-nonobject-line", "crash-message-string", "crash-text-null")) then .rc = 0 | .stderr = "" | .log = "" | .stray = "" else . end' "$HERE/expected.jsonl" > "$tmpf"
mv -f "$tmpf" "$HERE/expected.jsonl"
echo "wrote $(wc -l < "$HERE/expected.jsonl" | tr -d ' ') cases from $REV"
