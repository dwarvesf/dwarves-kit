#!/bin/bash
# run-workflow.sh -- run every `run: bash tests/...` step of .github/workflows/test.yml locally,
# in the workflow's order, and print only the red ones. The 2026-09-05 repair of that workflow
# (three weeks hand-disabled, seven suites red) scripted this loop four times before it lived
# here; the battery verifier is its other caller. Exit 1 when any step is red, 0 when clean.
#
#   bash tests/run-workflow.sh            # failures only, then a one-line summary
#   bash tests/run-workflow.sh -v         # every step with its exit code
#   bash tests/run-workflow.sh -j 4       # four suites at a time (they each build their own
#                                         # temp dirs; measured 2026-09-06: macOS CI leg 417s
#                                         # serial, the top four suites alone 226s of it)
#
# A few suites rewrite their sample docs under docs/verification as a side effect; any tracked
# file that was clean before the run and dirty after it is restored, so a local run leaves the
# tree as it found it. Nothing else is touched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.." || exit 1
WF="${RUN_WORKFLOW_FILE:-.github/workflows/test.yml}"
verbose=0; jobs=1
while [ $# -gt 0 ]; do
  case "$1" in
    -v) verbose=1 ;;
    -j) jobs="${2:-4}"; shift ;;
    *) echo "usage: run-workflow.sh [-v] [-j N]" >&2; exit 2 ;;
  esac
  shift
done

before=$(git status --porcelain 2>/dev/null | awk '$1=="M"||$1==" M"{print $2}' | sort)
# one step: run it, print RED (or ok under -v) as a single block, leave a marker on failure
run_step() {
  local cmd="$1" out rc
  out=$($cmd 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    { echo "RED  $cmd (rc=$rc)"; printf '%s\n' "$out" | grep -E 'FAIL|ORPHAN|offend|Error' | grep -v PASS | head -4 | sed 's/^/       /'; }
    : > "$RW_MARKS/$(printf '%s' "$cmd" | tr -c 'A-Za-z0-9' '_')"
  elif [ "$RW_VERBOSE" = 1 ]; then
    echo "ok   $cmd"
  fi
}
export -f run_step
RW_MARKS=$(mktemp -d); export RW_MARKS RW_VERBOSE="$verbose"
steps=$(grep -E '^\s+(- )?run: bash tests/' "$WF" | sed 's/.*run: //')
total=$(printf '%s\n' "$steps" | grep -c .)
# -P keeps the order of START only; each step's block prints whole, so red lines never interleave
printf '%s\n' "$steps" | xargs -P "$jobs" -I{} bash -c 'run_step "$1"' _ {}
red=$(ls "$RW_MARKS" | wc -l | tr -d ' ')
rm -rf "$RW_MARKS"

# restore side-effect files: tracked, clean before, modified by the run
after=$(git status --porcelain 2>/dev/null | awk '$1=="M"||$1==" M"{print $2}' | sort)
touched=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)
if [ -n "$touched" ]; then
  # shellcheck disable=SC2086
  git checkout -q -- $touched && echo "restored $(printf '%s\n' "$touched" | wc -l | tr -d ' ') side-effect file(s)"
fi

echo "run-workflow: $red red of $total steps"
[ "$red" -eq 0 ]
