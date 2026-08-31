#!/bin/bash
# Deterministic submission checker for scenario J7 (resume after a cold restart).
# Usage: check-submission-user-J7.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J7.sh <fixture-repo>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/gauntlet/check-lib.sh
. "${SCRIPT_DIR}/check-lib.sh"

fail=0
blocked_guard "${REPO}"

WORK_DIR="$(dirname "${REPO}")"

echo "== specced before built"
check "a spec file exists" bash -c "ls '${REPO}'/docs/specs/SPEC-*.md 2>/dev/null | grep -q ."

echo "== the round actually restarted (proof the no-redo check means something)"
check "RESUME-MARKER is present in /work" test -f "${WORK_DIR}/RESUME-MARKER"

echo "== completed work was not redone"
check "no duplicate-subject commits" bash -c "
  n=\$(git -C '${REPO}' log --all --format=%s | sort | uniq -d | wc -l)
  [ \"\${n}\" -eq 0 ]
"

echo "== final state is green"
check "--repeat works (N=3)" bash -c "[ \"\$(node '${REPO}/cli.js' --upper --repeat 3 hi | grep -c HI)\" -eq 3 ]"
check "the repo's test command passes" bash -c "cd '${REPO}' && npm test --silent"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

gauntlet_verdict
