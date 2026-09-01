#!/bin/bash
# Fast doc-projection subset of tests/test-meta.sh, run by hooks/ship-gate.sh
# on kit-repo pushes whose diff touches the projection surfaces. Lives in
# lib/gate/ (a helper the gate calls), not hooks/ (event hooks only, the
# roster-parity pins count that dir). Exists because
# the same drift class shipped twice (ID-467 2026-08-10, ID-639 2026-09-01):
# an agent/command lands without its MANUAL/architecture rows and nobody runs
# the suite until weeks later. Grep-only (milliseconds); the slow checks
# (FEATURES regen ~17s) stay in the full suite. Exit 1 = drift, caller blocks.
set -uo pipefail
ROOT="${1:?usage: doc-projection-check.sh <kit-root>}"
fail=0

# 1. Every agent has a MANUAL table row.
for f in "$ROOT"/agents/*.md; do
  a=$(basename "$f" .md)
  grep -q "^| \`$a\` " "$ROOT/docs/MANUAL.md" \
    || { echo "doc-projection: agent '$a' has no docs/MANUAL.md row" >&2; fail=1; }
done

# 2. Architecture V-phase inventory row count == live command+agent file count.
rows=$(sed -n '/^## Command and agent V-phase inventory/,/^## /p' "$ROOT/docs/architecture.md" \
  | grep '^|' | grep -cv '^| Entry\|^|---')
live=$(ls "$ROOT"/commands/*.md "$ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$rows" = "$live" ] \
  || { echo "doc-projection: architecture.md inventory has $rows rows for $live live command/agent files" >&2; fail=1; }

# 3. Every cycle-table phase appears in the V-model lens section (same rule as
#    the suite: the ", downstream" qualifier may be dropped in the lens).
lens=$(sed -n '/^## The V-model lens/,/^## /p' "$ROOT/docs/WORKFLOW.md")
while IFS= read -r phase; do
  t=${phase/, downstream/}
  printf '%s' "$lens" | grep -qF "$t" \
    || { echo "doc-projection: V-model lens missing cycle phase '$phase'" >&2; fail=1; }
done < <(sed -n '/^## The cycle/,/^## The V-model lens/p' "$ROOT/docs/WORKFLOW.md" \
  | grep '^|' | grep -v '^| Phase\|^|---' | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//' | grep -v '^$')

exit "$fail"
