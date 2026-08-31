#!/bin/bash
# Deterministic submission checker, persona A (kit user).
# Usage: check-submission-user.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user.sh <fixture-repo>}"
# Kit-root resolution, room-safe (gauntlet round-1 finding: ../.. from
# /work/checks resolved to /): env override first, then the probe's own
# installed kit, then the source-tree relative path.
if [ -n "${KIT_ROOT:-}" ]; then
  :
elif [ -d "${HOME}/.claude/dwarves-kit/lib" ]; then
  KIT_ROOT="${HOME}/.claude/dwarves-kit"
else
  KIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

fail=0
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  ${name}"; else echo "FAIL  ${name}"; fail=1; fi; }

# A BLOCKED.md is a valid submission shape: report it and stop (the findings
# live in the transcript, not here).
if [ -f "${REPO}/BLOCKED.md" ]; then
  echo "BLOCKED submission: probe stopped honestly. Contents:"
  cat "${REPO}/BLOCKED.md"
  exit 3
fi

echo "== adoption leave-behinds"
check "kit reports the repo adopted" bash "${KIT_ROOT}/lib/adopt.sh" --check "${REPO}"
check "AGENTS.md present" test -f "${REPO}/AGENTS.md"

echo "== the change itself"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "the branch changed the README example" bash -c "git -C '${REPO}' log --all --oneline -- README.md | grep -q ."
check "conventional-commit subject" bash -c "git -C '${REPO}' log --all -1 --format=%s -- README.md | grep -qE '^(fix|docs|feat|chore|refactor|test)(\(.+\))?: '"

echo "== the submission shape"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

echo
if [ "${fail}" -eq 0 ]; then echo "SUBMISSION: GREEN"; else echo "SUBMISSION: RED"; fi
exit "${fail}"
