#!/bin/bash
# Deterministic submission checker for scenario J6 (mid-flight drift).
# Usage: check-submission-user-J6.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J6.sh <fixture-repo>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/gauntlet/check-lib.sh
. "${SCRIPT_DIR}/check-lib.sh"

fail=0
blocked_guard "${REPO}"

echo "== specced before built"
check "a spec file exists" bash -c "ls '${REPO}'/docs/specs/SPEC-*.md 2>/dev/null | grep -q ."

echo "== the amendment is add-only, not a silent rewrite"
check "an ## Amendments entry exists in the spec" bash -c "grep -rilq '^## Amendments' '${REPO}/docs/specs/'"
check "amendment mentions the empty-string case" bash -c "grep -riq 'empty' '${REPO}/docs/specs/'"

echo "== the amended behavior is real"
check "--repeat still works (N=3)" bash -c "[ \"\$(node '${REPO}/cli.js' --upper --repeat 3 hi | grep -c HI)\" -eq 3 ]"
check "the repo's test command passes" bash -c "cd '${REPO}' && npm test --silent"
check "a test covers the empty-string case" bash -c "grep -rilq 'empty' '${REPO}'/*test* '${REPO}'/test/* 2>/dev/null"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

gauntlet_verdict
