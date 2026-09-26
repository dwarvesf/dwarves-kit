#!/usr/bin/env bash
# test-ship-pr-body-verified.sh -- static pins on the PR-body verification rule.
#
# dwarvesf/foundation-apps' PR evidence check (a reusable workflow at
# tieubao/pr-evidence-check) converts a PR to draft when its "## How I verified it"
# section has no fenced code block, `$` line, or known tool name. PRs #153, #164, #169
# and #175 all failed it on 2026-09-26: wrong heading ("## Verify", "## Test plan"),
# bullet prose with no fence, or a 4-space indented block (the repo's own PR template
# shows that exact indented shape as its example, which is why an agent that copied it
# still failed). Nothing in the kit named the required heading or fence before this.
#
# These pins are static text checks, not a runtime harness: commands/ship.md and
# commands/wrap.md are prompt files, not code, so there is nothing to execute here.
#
# Run: bash tests/test-ship-pr-body-verified.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$({ trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$3"; echo $?)"; }

SHIP_MD="$(cat "$KIT_DIR/commands/ship.md")"
WRAP_MD="$(cat "$KIT_DIR/commands/wrap.md")"

chk_has "ship.md step 8 fallback template heads the verify section 'How I verified it'" \
  "$SHIP_MD" '## How I verified it'
chk_has "ship.md step 8 prefers the repo's own PULL_REQUEST_TEMPLATE.md headings" \
  "$SHIP_MD" 'PULL_REQUEST_TEMPLATE.md'
chk_has "ship.md step 8 requires a fenced code block for the verification section" \
  "$SHIP_MD" 'put the command and its output inside a fenced'
chk_has "ship.md step 8 requires a \$-prefixed command line" \
  "$SHIP_MD" 'prefixed with `$ `'
chk_has "ship.md step 8 calls out that an indented block does not count" \
  "$SHIP_MD" 'even when a repo'"'"'s own template example shows one'
chk_has "wrap.md step 10's (a)/(b) worker cites the same verification-section rule" \
  "$WRAP_MD" "commands/ship.md\` step 8's verification-section rule"
chk_has "wrap.md step 10's (a)/(b) worker heads the commit's proof 'How I verified it'" \
  "$WRAP_MD" '## How I verified it` heading in the commit body'

echo
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
