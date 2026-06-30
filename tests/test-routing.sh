#!/bin/bash
# test-routing.sh -- data-driven model routing suggester (token-optim-v3 SG-06).
# Verifies lib/route-suggest.sh against v2 SG-09's ledger schema:
#   - rich data: suggests the measured-cheapest model that PASSED at parity
#   - failing-but-cheaper arm is NOT suggested (infinite-cost / anti-cherry-pick guard)
#   - thin data (one model measured): ABSTAINS instead of overfitting
#
# Run: bash tests/test-routing.sh   (exit 0 = pass, 1 = fail)

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RS="$KIT_DIR/lib/route-suggest.sh"
FIX="$KIT_DIR/tests/fixtures/routing"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo -e "  ${GREEN}PASS${NC} $1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${NC} $1"; }
chk() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

echo "=== route-suggest exists + executable ==="
[ -f "$RS" ]; chk "lib/route-suggest.sh exists" $?

echo ""
echo "=== rich data: suggest measured-cheapest-at-parity ==="
OUT=$(bash "$RS" "$FIX/rich-ledger.tsv" code-add-flag); RC=$?
echo "  -> $OUT"
[ "$RC" -eq 0 ]; chk "rich: exit 0 (a suggestion was made)" $?
echo "$OUT" | grep -q '^SUGGEST'; chk "rich: line is SUGGEST" $?
echo "$OUT" | grep -q 'model=haiku'; chk "rich: suggests haiku (cheapest PASS: 322602 < opus 901000)" $?
# negative control: the cheaper-but-FAILING sonnet arm (90000 tok) must not win
echo "$OUT" | grep -q 'model=sonnet' && bad "rich: failing sonnet NOT suggested" || ok "rich: failing sonnet NOT suggested (infinite-cost guard)"
echo "$OUT" | grep -q 'effort=abstain'; chk "rich: effort abstained (not in SG-09 schema)" $?

echo ""
echo "=== thin data: abstain, do not overfit ==="
OUT2=$(bash "$RS" "$FIX/thin-ledger.tsv" mini-mega); RC2=$?
echo "  -> $OUT2"
[ "$RC2" -eq 2 ]; chk "thin: exit 2 (abstained)" $?
echo "$OUT2" | grep -q '^ABSTAIN'; chk "thin: line is ABSTAIN" $?
echo "$OUT2" | grep -q 'thin-data'; chk "thin: reason names thin-data" $?

echo ""
echo "=== no passing data: abstain ==="
OUT3=$(bash "$RS" "$FIX/rich-ledger.tsv" no-such-task); RC3=$?
echo "  -> $OUT3"
[ "$RC3" -eq 2 ] && echo "$OUT3" | grep -q 'no-passing-data'; chk "unknown task: abstains with no-passing-data" $?

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
