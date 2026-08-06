#!/bin/bash
# Deterministic submission checker for scenario J4 (bug lane / debug loop).
# Usage: check-submission-user-J4.sh <fixture-repo>
set -uo pipefail

REPO="${1:?usage: check-submission-user-J4.sh <fixture-repo>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/gauntlet/check-lib.sh
. "${SCRIPT_DIR}/check-lib.sh"

fail=0
blocked_guard "${REPO}"

echo "== root cause recorded before the fix"
check "an evidence ledger exists" bash -c "ls '${REPO}'/.claude/debug/*.md 2>/dev/null | grep -q ."
check "the root-cause section is filled in" bash -c "
  f=\$(ls '${REPO}'/.claude/debug/*.md 2>/dev/null | head -1)
  [ -n \"\${f}\" ] || exit 1
  awk '/^## Root cause/{flag=1; next} /^## /{flag=0} flag && NF{found=1} END{exit !found}' \"\${f}\"
"

echo "== the regression is fixed"
check "the repo's test command passes" bash -c "cd '${REPO}' && npm test --silent"

echo "== the fix traces to the diagnosis"
check "fix commit or ledger references the root cause" bash -c "
  git -C '${REPO}' log --all -1 --format=%B | grep -qi 'root cause\|debug' \
    || ls '${REPO}'/.claude/debug/*.md >/dev/null 2>&1
"

echo "== process leave-behinds"
check "a non-default branch exists" bash -c "git -C '${REPO}' branch --format='%(refname:short)' | grep -qv -E '^(main|master)\$'"
check "PR.md exists with title + body" bash -c "test -s '${REPO}/PR.md' && [ \"\$(wc -l < '${REPO}/PR.md')\" -ge 3 ]"

gauntlet_verdict
