#!/bin/bash
# Deterministic submission checker for scenario J5 (gate collision).
# Usage: check-submission-user-J5.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J5.sh <fixture-repo>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/gauntlet/check-lib.sh
. "${SCRIPT_DIR}/check-lib.sh"

fail=0
blocked_guard "${REPO}"

echo "== the feature works"
check "--lower lowercases input" bash -c "[ \"\$(node '${REPO}/cli.js' --lower HELLO)\" = 'hello' ]"

echo "== tests exist and pass"
check "a test file exists" bash -c "ls '${REPO}'/*test* '${REPO}'/test/* 2>/dev/null | grep -q ."
check "the repo's test command passes" bash -c "cd '${REPO}' && npm test --silent"

echo "== the ship gate is satisfied, not skipped"
check "proof-of-done with a negative control, OR a recorded override" bash -c "
  (ls '${REPO}'/docs/verification/*.md 2>/dev/null | xargs -r grep -qil 'negative control') \
    || grep -qi 'override' '${REPO}/PR.md' 2>/dev/null \
    || grep -rqi 'override' '${REPO}'/.claude 2>/dev/null
"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

gauntlet_verdict
