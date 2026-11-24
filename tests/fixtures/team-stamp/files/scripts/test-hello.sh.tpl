#!/usr/bin/env bash
# test-hello.sh - the fixture's own test: runs with no kit, with the stamped values.
set -u
cd "$(dirname "$0")/.." || exit 1
out="$(bash scripts/hello.sh)"
[ "$out" = "hello" ] || { echo "not ok: hello printed '$out'"; exit 1; }
grep -q '^Default branch: {{DEFAULT_BRANCH}}$' README.md || { echo "not ok: README lost the default branch"; exit 1; }
grep -q '^Tags: {{TAGS}}$' README.md || { echo "not ok: README lost the tags"; exit 1; }
command -v gate >/dev/null 2>&1 && { echo "not ok: a kit binary is on PATH"; exit 1; }
echo "ok: hello"
