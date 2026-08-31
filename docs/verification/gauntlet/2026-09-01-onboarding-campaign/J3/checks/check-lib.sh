#!/bin/bash
# Shared helpers for gauntlet submission checkers (SPEC-227 P3). Sourced, not
# executed. Every check-submission-user-<row>.sh does:
#   . "$(dirname "$0")/check-lib.sh"
#   fail=0
#   blocked_guard "${REPO}"
#   check "some assertion" some-cmd --with args
#   gauntlet_verdict

# check <name> <cmd...> -- runs cmd, prints PASS/FAIL, sets fail=1 on failure.
# Caller owns the `fail` variable (declare `fail=0` before the first call).
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  ${name}"
  else
    echo "FAIL  ${name}"
    fail=1
  fi
}

# blocked_guard <repo> -- a BLOCKED.md is a valid submission shape (the probe
# stopped honestly instead of guess-shipping); report it and exit 3.
blocked_guard() {
  local repo="$1"
  if [ -f "${repo}/BLOCKED.md" ]; then
    echo "BLOCKED submission: probe stopped honestly. Contents:"
    cat "${repo}/BLOCKED.md"
    exit 3
  fi
}

# gauntlet_verdict -- print the GREEN/RED summary line and exit with `fail`.
gauntlet_verdict() {
  echo
  if [ "${fail}" -eq 0 ]; then echo "SUBMISSION: GREEN"; else echo "SUBMISSION: RED"; fi
  exit "${fail}"
}
