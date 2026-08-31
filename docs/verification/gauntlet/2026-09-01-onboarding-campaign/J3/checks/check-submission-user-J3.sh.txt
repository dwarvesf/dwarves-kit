#!/bin/bash
# Deterministic submission checker for scenario J3 (full lane).
# Usage: check-submission-user-J3.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J3.sh <fixture-repo>}"

fail=0
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  ${name}"; else echo "FAIL  ${name}"; fail=1; fi; }

if [ -f "${REPO}/BLOCKED.md" ]; then
  echo "BLOCKED submission: probe stopped honestly. Contents:"
  cat "${REPO}/BLOCKED.md"
  exit 3
fi

echo "== specced before built"
check "a spec file exists" bash -c "ls '${REPO}'/docs/specs/SPEC-*.md 2>/dev/null | grep -q ."
check "spec carries acceptance criteria + verification" bash -c "grep -rilq 'acceptance' '${REPO}/docs/specs/' && grep -rilq 'verif' '${REPO}/docs/specs/'"

echo "== the feature works"
check "--repeat 3 prints three lines" bash -c "[ \"\$(node '${REPO}/cli.js' --upper --repeat 3 hi | grep -c HI)\" -eq 3 ]"
check "--repeat 1 prints one line" bash -c "[ \"\$(node '${REPO}/cli.js' --upper --repeat 1 hi | grep -c HI)\" -eq 1 ]"
check "bad N handled (non-zero exit)" bash -c "! node '${REPO}/cli.js' --upper --repeat banana hi"

echo "== tests exist and pass"
check "a test file exists" bash -c "ls '${REPO}'/*test* '${REPO}'/test/* 2>/dev/null | grep -q ."
check "the repo's test command passes" bash -c "cd '${REPO}' && npm test --silent"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "review verdict recorded somewhere" bash -c "grep -rilq -e 'SHIP' -e 'review' '${REPO}/docs/' 2>/dev/null || grep -qil 'review' '${REPO}/PR.md'"
check "proof-of-done or override" bash -c "ls '${REPO}'/docs/verification/*.md 2>/dev/null | grep -q . || grep -qi 'override' '${REPO}/PR.md'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

echo
if [ "${fail}" -eq 0 ]; then echo "SUBMISSION: GREEN"; else echo "SUBMISSION: RED"; fi
exit "${fail}"
