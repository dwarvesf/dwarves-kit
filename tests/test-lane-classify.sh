#!/usr/bin/env bash
# test-lane-classify.sh -- SPEC-098, kit-telemetry SG-03.
# The classifier's first dedicated behavioral suite. Pins the kit-machinery hard-gate
# coverage fix (lane-telemetry / mega-merge / proof-ledger / kit-log-dir now escalate to
# full) plus the precedence + regression guards that must hold around it.
#
# Run: bash tests/test-lane-classify.sh   (exit 0 = all AC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LC="$KIT_DIR/lib/lane-classify.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
# classify_is <desc> <expected-lane> <label>
classify_is() {
  TOTAL=$((TOTAL+1)); local got; got="$(bash "$LC" classify "$1" 2>/dev/null)"
  if [ "$got" = "$2" ]; then echo -e "  ${GREEN}PASS${NC} $3 ($2)"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $3 -- got '$got', expected '$2'"; FAIL=$((FAIL+1)); fi
}

echo "=== lane-classify kit-machinery coverage (SPEC-098 AC1-AC6) ==="

# AC1-AC4: the four wave-touched enforcement/telemetry libs escalate to full.
classify_is "add a render subcommand to lib/lane-telemetry.sh" full "AC1 lane-telemetry -> full"
classify_is "add a code-level guard to lib/mega-merge.sh"      full "AC2 mega-merge -> full"
classify_is "log overrides in lib/proof-ledger.sh"            full "AC3 proof-ledger -> full"
classify_is "durable resolver in lib/kit-log-dir.sh"          full "AC4 kit-log-dir -> full"

# AC1b-AC4b (review completeness): the remaining machinery libs also escalate.
classify_is "add a subcommand to lib/orchestrate.sh"          full "AC1b orchestrate.sh -> full"
classify_is "add automation to lib/stack-merge.sh"            full "AC2b stack-merge -> full"
classify_is "change lib/role-classify.sh"                     full "AC3b role-classify -> full"
classify_is "change lib/goal-drafts.sh"                       full "AC4b goal-drafts -> full"

# AC5 [precedence preserved, NEGATIVE CONTROL]: a cosmetic edit to one of these libs is
# still tiny -- tiny beats the hard-gate, so the fix does not over-gate a typo.
classify_is "fix a typo in lib/lane-telemetry.sh"             tiny "AC5 [NC] cosmetic edit stays tiny (precedence)"

# AC5b [over-match NEGATIVE CONTROL]: 'orchestrate' is a common word, anchored to .sh so a
# non-kit task using it does NOT escalate; read-helper libs stay normal (deliberately held).
classify_is "orchestrate the marketing launch next quarter"  normal "AC5b [NC] bare 'orchestrate' does not over-match"
classify_is "tweak lib/route-suggest.sh output format"       normal "AC5b [NC] read-helper lib stays normal"

# AC6 [no regression]: previously-covered machinery stays full; a plain feature stays normal.
classify_is "fix the parser in lib/gate-ledger.sh"           full   "AC6 gate-ledger still full"
classify_is "add a check to lib/lane-classify.sh"            full   "AC6 lane-classify still full"
classify_is "add user authentication with jwt sessions"      full   "AC6 auth hard-gate still full"
classify_is "add a date picker to the settings page"         normal "AC6 plain feature still normal"
classify_is "fix a typo in the README"                       tiny   "AC6 plain typo still tiny"

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
