#!/bin/bash
# Deterministic submission checker, persona B (kit contributor).
# Usage: check-submission-contributor.sh <kit-clone>
set -uo pipefail

REPO="${1:?usage: check-submission-contributor.sh <kit-clone>}"

fail=0
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  ${name}"; else echo "FAIL  ${name}"; fail=1; fi; }

if [ -f "${REPO}/BLOCKED.md" ]; then
  echo "BLOCKED submission: probe stopped honestly. Contents:"
  cat "${REPO}/BLOCKED.md"
  exit 3
fi

echo "== the change"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "the branch touches docs/guides/" bash -c "git -C '${REPO}' log --all --oneline -- docs/guides/ | grep -q ."
check "conventional-commit subject" bash -c "git -C '${REPO}' log --all -1 --format=%s -- docs/guides/ | grep -qE '^(fix|docs|feat|chore|refactor|test)(\(.+\))?: '"
check "commit body cites evidence" bash -c "[ \"\$(git -C '${REPO}' log --all -1 --format=%b -- docs/guides/ | wc -w)\" -ge 10 ]"

echo "== the kit's own gate expectations (docs change: proof or documented override)"
check "proof-of-done file OR override recorded" bash -c "git -C '${REPO}' log --all --oneline -- docs/verification/ | grep -q . || grep -rq 'override' '${REPO}/.kit' 2>/dev/null || test -f '${REPO}/PR.md'"

echo "== the submission shape"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

echo
if [ "${fail}" -eq 0 ]; then echo "SUBMISSION: GREEN"; else echo "SUBMISSION: RED"; fi
exit "${fail}"
