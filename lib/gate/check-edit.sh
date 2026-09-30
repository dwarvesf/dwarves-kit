#!/usr/bin/env bash
# kit-verb: check-edit | check-edit signal for execute: did the build weaken the checks the spec names, from a base ref diff
# check-edit.sh -- the check-edit signal for /kit:execute: did the build weaken its own check?
#
#   check-edit.sh <base-ref> [named-path...]
#
# <named-path> are the files the spec's `## Verification` commands and acceptance criteria name.
# Prints, for `git diff <base-ref> HEAD`:
#   check-edited: <paths>          a named path changed, or a test file that already existed
#                                  at the base ref was modified (a new test file is not flagged)
#   check-weakened: <file>: <line> an added line in a test or named file that skips, expects
#                                  failure, swallows a failure, or comments out an assert
# Empty output means none. A finding, never a block: always exits 0 on a valid call.
set -u
base="${1:-}"
[ -n "$base" ] || { echo "usage: check-edit.sh <base-ref> [named-path...]" >&2; exit 64; }
shift
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "check-edit: unknown ref $base" >&2; exit 64; }

is_test() { case "$1" in tests/*|test/*|*/tests/*|*/test/*|*test_*|*_test.*|*.test.*|*.spec.*|*/test-*|test-*) return 0 ;; esac; return 1; }

named="$(printf '%s\n' "$@")"
edited=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s\n' "$named" | grep -qxF -- "$f"; then edited="$edited $f"; continue; fi
  if is_test "$f" && git cat-file -e "$base:$f" 2>/dev/null; then edited="$edited $f"; fi
done < <(git diff --name-only "$base" HEAD)
[ -z "$edited" ] || echo "check-edited:$edited"

TAB="$(printf '\t')"
weak="@pytest[.]mark[.](skip|xfail)|pytest[.]skip|[.]skip[(]|[.]only[(]|xit[(]|xdescribe[(]|t[.]Skip[(]|[|][|][[:space:]]*true|[[:space:]]skip *[:=]|${TAB}[[:space:]]*[#/]+[[:space:]]*(assert|expect)"
git diff -U0 "$base" HEAD | awk '
  /^\+\+\+ /  { f=substr($0,7); next }
  /^\+/       { print f "\t" substr($0,2) }
' | grep -E "$weak" | while IFS="$TAB" read -r f line; do
  if is_test "$f" || printf '%s\n' "$named" | grep -qxF -- "$f"; then
    echo "check-weakened: $f: $(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
  fi
done
exit 0
