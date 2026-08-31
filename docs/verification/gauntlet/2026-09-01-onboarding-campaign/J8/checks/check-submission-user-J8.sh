#!/bin/bash
# Deterministic submission checker for scenario J8 (review response).
# Usage: check-submission-user-J8.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J8.sh <fixture-repo>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/gauntlet/check-lib.sh
. "${SCRIPT_DIR}/check-lib.sh"

fail=0
blocked_guard "${REPO}"

echo "== tests exist, including the edge case"
check "a test file exists" bash -c "ls '${REPO}'/*test* '${REPO}'/test/* 2>/dev/null | grep -q ."
check "a test covers empty input" bash -c "grep -rilq -e 'empty' -e 'no.*arg' '${REPO}'/*test* '${REPO}'/test/* 2>/dev/null"
check "the repo's test command passes" bash -c "cd '${REPO}' && npm test --silent"

echo "== review verdict recorded and names the hole"
check "a review verdict is recorded" bash -c "
  grep -rilq -e 'SHIP' -e 'FIX-REQUIRED' -e 'DO NOT SHIP' '${REPO}/docs/' 2>/dev/null \
    || grep -qil -e 'SHIP' -e 'review' '${REPO}/PR.md'
"
check "the review names the edge-case hole" bash -c "
  grep -rilq -e 'empty' -e 'edge.case' '${REPO}/docs/' 2>/dev/null \
    || grep -qil -e 'empty' -e 'edge.case' '${REPO}/PR.md'
"

echo "== the hole is fixed, matching the documented behavior"
check "empty --upper input now errors (non-zero exit)" bash -c "! node '${REPO}/cli.js' --upper"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

gauntlet_verdict
