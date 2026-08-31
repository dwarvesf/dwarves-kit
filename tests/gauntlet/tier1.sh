#!/bin/bash
# Gauntlet Tier 1 for the kit itself: deterministic checks, zero model cost.
# Green is the precondition for any paid probe round (two-tier scan rule).
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${KIT_ROOT}" || exit 1

fail=0
check() { # check <name> <cmd...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  ${name}"
  else
    echo "FAIL  ${name}"
    fail=1
  fi
}

echo "== T1.1 contributor-surface docs exist"
for f in README.md docs/MANUAL.md docs/guides/README.md docs/guides/gauntlet.md commands/gauntlet.md commands/onboard.md commands/adopt.md; do
  check "doc: ${f}" test -f "${f}"
done

echo "== T1.2 install-mode detection answers"
check "onboard-detect prints a mode" test -n "$(bash lib/onboard-detect.sh)"

echo "== T1.3 adoption cycle on a throwaway fixture (fresh -> adopted -> idempotent)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "${FIXTURE}"' EXIT
git -C "${FIXTURE}" init -q
check "fresh fixture reports NOT adopted" bash -c "! bash lib/adopt.sh --check '${FIXTURE}'"
check "adopt writes the contract" bash lib/adopt.sh "${FIXTURE}"
check "adopted fixture reports adopted" bash lib/adopt.sh --check "${FIXTURE}"
check "AGENTS.md injected" test -f "${FIXTURE}/AGENTS.md"
check "re-adopt is idempotent" bash lib/adopt.sh "${FIXTURE}"

echo "== T1.4 the kit's own adopt test suite"
check "tests/test-adopt.sh" bash tests/test-adopt.sh

echo "== T1.5 gauntlet prep scripts lint"
if command -v shellcheck >/dev/null 2>&1; then
  # Glob, not a hand-maintained list (SPEC-227 P3): every gauntlet script,
  # including the scenario-pack additions (make-card.sh, check-lib.sh, the
  # per-row checkers) and the cleanroom/deploy scripts (SPEC-236), gets
  # linted without a separate edit here per new row or new script.
  shopt -s nullglob
  gauntlet_scripts=(tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign)
  shopt -u nullglob
  # -x: follow the check-lib.sh source (SPEC-227 P3) so shellcheck sees `fail`
  # used inside its check()/gauntlet_verdict(), not just declared.
  check "shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign" shellcheck -x "${gauntlet_scripts[@]}"
else
  echo "SKIP  shellcheck not installed"
fi

echo
if [ "${fail}" -eq 0 ]; then echo "TIER1: GREEN"; else echo "TIER1: RED"; fi
exit "${fail}"
