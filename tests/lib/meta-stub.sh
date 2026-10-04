#!/usr/bin/env bash
# meta-stub.sh -- shared harness for the tests/test-meta-<area>.sh suites.
# Verbatim from the old tests/test-meta.sh header: counter state, colors, and
# the two assert helpers. Sourced by each area suite after its own KIT_DIR line.
export KIT_CONFIG_OPERATOR="$KIT_DIR/tests/fixtures/gates-on"   # quality gates are opt-in; this suite exercises them ON
PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local NAME="$1" EXPECTED="$2" ACTUAL="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME (expected '$EXPECTED', got '$ACTUAL')"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local NAME="$1" RC="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$RC" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} $NAME"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $NAME"
    FAIL=$((FAIL + 1))
  fi
}

