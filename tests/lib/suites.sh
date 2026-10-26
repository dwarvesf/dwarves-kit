#!/usr/bin/env bash
# suites.sh -- the one definition of "a suite". Sourced by tests/run-all.sh and bin/test-affected,
# so the two collect the same files. Run from the repo root.
#
#   source tests/lib/suites.sh
#   suite_list          every suite path, repo-relative, one per line: tests/test-*.sh first, then
#                       the module suites (test-*.sh and smoke.sh directly under lib/<m>/tests/ or
#                       lib/<m>/<sub>/tests/). Fixtures and tests/lib helpers are not suites.
#   is_suite <path>     0 when the path has a suite's shape (the file need not exist)
#   suite_id <path>     the name a suite goes by in reports, bin/test-affected.timeouts and the
#                       timing history: tests/test-x.sh -> test-x, lib/stats/tests/test-x.sh ->
#                       lib-stats-test-x (a bare basename would collide: two suites are named
#                       test-docs-wiring)
#   suite_path <id>     the inverse; prints the path, exit 1 when no suite has that id
#   suite_owner <path>  the module a module suite belongs to (lib/stats, lib/session for
#                       lib/session/audit/tests/smoke.sh); empty for tests/ suites

suite_list() {
  local f
  for f in tests/test-*.sh lib/*/tests/test-*.sh lib/*/tests/smoke.sh \
           lib/*/*/tests/test-*.sh lib/*/*/tests/smoke.sh; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

is_suite() {
  local d="${1%/*}" b="${1##*/}" n
  case "$b" in test-*.sh|smoke.sh) ;; *) return 1 ;; esac
  case "$d" in
    tests) [ "$b" != smoke.sh ]; return ;;
    lib/*/tests)
      n="${d#lib/}"; n="${n%/tests}"
      case "$n" in */*/*) return 1 ;; esac
      return 0 ;;
  esac
  return 1
}

suite_id() {
  local p="${1%.sh}"
  case "$p" in
    tests/*) printf '%s\n' "${p#tests/}" ;;
    *) p="${p/\/tests\///}"; printf '%s\n' "${p//\//-}" ;;
  esac
}

suite_path() {
  local s
  for s in $(suite_list); do
    if [ "$(suite_id "$s")" = "$1" ]; then printf '%s\n' "$s"; return 0; fi
  done
  return 1
}

suite_owner() {
  local m
  case "$1" in lib/*/tests/*) m="${1#lib/}"; printf 'lib/%s\n' "${m%%/*}" ;; esac
  return 0
}
