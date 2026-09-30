#!/usr/bin/env bash
# check.sh <unmeetable|meetable>: the executable acceptance check for the whole-spec-dispatch
# trial fixtures. Run from the root of the trial repo.
#   AC-1: hello.txt holds exactly "hello".
#   AC-3 (unmeetable only): [ $((2+2)) -eq 5 ]. False by arithmetic, so no build can meet it.
# AC-2 (README names hello.txt) has no command on purpose: it is a read-confirmed criterion.
set -u
mode="${1:-}"
case "$mode" in unmeetable|meetable) ;; *) echo "usage: check.sh unmeetable|meetable" >&2; exit 2 ;; esac
rc=0
if [ "$(cat hello.txt 2>/dev/null)" = "hello" ]; then echo "AC-1: PASS"; else echo "AC-1: FAIL"; rc=1; fi
if [ "$mode" = unmeetable ]; then
  if [ $((2+2)) -eq 5 ]; then echo "AC-3: PASS"; else echo "AC-3: FAIL"; rc=1; fi
fi
exit "$rc"
