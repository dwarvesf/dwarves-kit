#!/bin/bash
# run-workflow.sh -- run every `run: bash tests/...` step of .github/workflows/test.yml locally,
# in the workflow's order, and print only the red ones. The 2026-09-05 repair of that workflow
# (three weeks hand-disabled, seven suites red) scripted this loop four times before it lived
# here; the battery verifier is its other caller. Exit 1 when any step is red, 0 when clean.
#
#   bash tests/run-workflow.sh            # failures only, then a one-line summary
#   bash tests/run-workflow.sh -v         # every step with its exit code
#
# A few suites rewrite their sample docs under docs/verification as a side effect; any tracked
# file that was clean before the run and dirty after it is restored, so a local run leaves the
# tree as it found it. Nothing else is touched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.." || exit 1
WF="${RUN_WORKFLOW_FILE:-.github/workflows/test.yml}"
verbose=0; [ "${1:-}" = "-v" ] && verbose=1

before=$(git status --porcelain 2>/dev/null | awk '$1=="M"||$1==" M"{print $2}' | sort)
total=0; red=0
while read -r cmd; do
  [ -n "$cmd" ] || continue
  total=$((total + 1))
  out=$($cmd 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    red=$((red + 1))
    echo "RED  $cmd (rc=$rc)"
    printf '%s\n' "$out" | grep -E 'FAIL|ORPHAN|offend|Error' | grep -v PASS | head -4 | sed 's/^/       /'
  elif [ "$verbose" = 1 ]; then
    echo "ok   $cmd"
  fi
done < <(grep -E '^\s+(- )?run: bash tests/' "$WF" | sed 's/.*run: //')

# restore side-effect files: tracked, clean before, modified by the run
after=$(git status --porcelain 2>/dev/null | awk '$1=="M"||$1==" M"{print $2}' | sort)
touched=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)
if [ -n "$touched" ]; then
  # shellcheck disable=SC2086
  git checkout -q -- $touched && echo "restored $(printf '%s\n' "$touched" | wc -l | tr -d ' ') side-effect file(s)"
fi

echo "run-workflow: $red red of $total steps"
[ "$red" -eq 0 ]
