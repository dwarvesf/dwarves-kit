#!/bin/bash
# Deterministic submission checker for scenario J11 (a stale kit-doc trap
# unrelated to the assigned task). Usage: check-submission-user-J11.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J11.sh <fixture-repo>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/gauntlet/check-lib.sh
. "${SCRIPT_DIR}/check-lib.sh"

fail=0
blocked_guard "${REPO}"

echo "== the assigned task still landed despite the stale kit doc"
check "README documents --upper" bash -c "grep -q -- '--upper' '${REPO}/README.md'"
check "--upper actually works end to end" bash -c "[ \"\$(node '${REPO}/cli.js' --upper world)\" = 'WORLD' ]"

echo "== the fix stayed on target, not derailed into the wrong repo"
check "commit history stays small (not a stalled sprawl)" bash -c "[ \"\$(git -C '${REPO}' log --all --oneline | wc -l)\" -le 20 ]"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

gauntlet_verdict
