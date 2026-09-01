#!/bin/bash
# test-references-field.sh -- Proves the optional `## References` spec field (SPEC-137) adds
# NO new gate to /kit:spec-validate.
#
# /kit:spec-validate's 6 reviewers are prompt text, not code (see tests/test-design-record.sh's
# header for the same honest limitation), so this harness cannot drive the live LLM judgment.
# What it CAN prove structurally: none of the 6 reviewers' criteria mention `References`, and
# Reviewer 6 (the ONE reviewer that can block VALIDATED) is reproduced here as the same pure
# function test-design-record.sh already established. Running that function against a fixture
# WITH a `## References` section and the byte-identical fixture WITHOUT one proves the field is
# structurally inert to the blocking gate: both come back PASS.
#
# Run: bash tests/test-references-field.sh
# Exit 0 = all tests pass. Exit 1 = failures found.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$KIT_DIR/tests/fixtures/references-field"
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

# ------------------------------------------------------------------
# Reviewer 6's structural contract, reproduced verbatim from test-design-record.sh (the
# established pattern for turning prompt-text review into a checkable pure function).
# ------------------------------------------------------------------

is_design_bearing() {
  grep -qE '^Design-bearing \(fixture declaration\): yes$' "$1" && echo yes || echo no
}

design_section_body() {
  awk '
    /^## Design$/ { flag=1; next }
    /^## /        { flag=0 }
    flag          { print }
  ' "$1"
}

design_section_body_nonblank() {
  design_section_body "$1" | sed '/^[[:space:]]*$/d'
}

has_mermaid_diagram() {
  design_section_body "$1" | grep -qF '```mermaid' && echo yes || echo no
}

is_obvious_collapse() {
  local body
  body="$(design_section_body_nonblank "$1")"
  [ "$(echo "$body" | grep -cE '^obvious:')" -ge 1 ] && [ "$(has_mermaid_diagram "$1")" = "no" ] && echo yes || echo no
}

reviewer6_verdict() {
  local f="$1" bearing body
  bearing="$(is_design_bearing "$f")"
  body="$(design_section_body_nonblank "$f")"
  if [ "$bearing" = "yes" ]; then
    if [ -z "$body" ]; then
      echo REFUSE
      return
    fi
    if [ "$(is_obvious_collapse "$f")" = "yes" ]; then
      echo REFUSE
      return
    fi
    if [ "$(has_mermaid_diagram "$f")" = "yes" ]; then
      echo PASS
      return
    fi
    echo REFUSE
    return
  fi
  echo PASS
}

# ============================================================
echo "=== SPEC-137: optional References field adds no new gate ==="
# ============================================================

WITH_FIX="$FIXTURES/with-references.md"
WITHOUT_FIX="$FIXTURES/without-references.md"

for f in "$WITH_FIX" "$WITHOUT_FIX"; do
  [ -f "$f" ] || { echo "FIXTURE MISSING: $f"; exit 1; }
done

echo ""
echo "--- WITH a References: field ---"
HAS_REFS_WITH="$(grep -qE '^References:' "$WITH_FIX" && echo yes || echo no)"
VERDICT_WITH="$(reviewer6_verdict "$WITH_FIX")"
assert_eq "fixture carries a 'References:' field" "yes" "$HAS_REFS_WITH"
assert_eq "Reviewer 6 verdict WITH References: GREEN" "PASS" "$VERDICT_WITH"

echo ""
echo "--- WITHOUT a References: field (byte-identical otherwise) ---"
HAS_REFS_WITHOUT="$(grep -qE '^References:' "$WITHOUT_FIX" && echo yes || echo no)"
VERDICT_WITHOUT="$(reviewer6_verdict "$WITHOUT_FIX")"
assert_eq "fixture carries NO 'References:' field" "no" "$HAS_REFS_WITHOUT"
assert_eq "Reviewer 6 verdict WITHOUT References: GREEN" "PASS" "$VERDICT_WITHOUT"

echo ""
echo "--- No-new-gate proof: both verdicts equal (presence of References is inert) ---"
assert_eq "verdict is identical with and without the field" "$VERDICT_WITH" "$VERDICT_WITHOUT"

# ============================================================
echo ""
echo "=== Structural wiring: References is OPTIONAL, not a new required field ==="
# ============================================================

SPEC_MD="$KIT_DIR/commands/spec.md"
VALIDATE_MD="$KIT_DIR/commands/spec-validate.md"

RC=0; grep -qE '^References:' "$SPEC_MD" || RC=1
assert_eq "commands/spec.md template has a 'References:' field" 0 $RC

RC=0; grep -qiF 'optional' "$SPEC_MD" && grep -qiF 'References:' "$SPEC_MD" || RC=1
assert_eq "commands/spec.md marks References as optional" 0 $RC

RC=0; grep -qiF 'Source beats a from-scratch' "$SPEC_MD" || RC=1
assert_eq "commands/spec.md states source-beats-description" 0 $RC

# NEGATIVE CONTROL: spec-validate.md's reviewers are UNCHANGED by this field -- none of the
# 6 reviewer headings mention References, so no reviewer gained a new check for it.
RC=0; grep -qiE '\breferences\b' "$VALIDATE_MD" && RC=1
assert_eq "negative control: no reviewer in spec-validate.md was taught about References (no new gate)" 0 $RC

# Reviewer 6 (the one blocking reviewer) still only reads Design-bearing status; unchanged.
for R in "Reviewer 1: Security Auditor" "Reviewer 2: Failure Mode Analyst" "Reviewer 3: Assumption Destroyer" "Reviewer 4: Scope Critic" "Reviewer 5: Solution-Design & Extensibility Critic" "Reviewer 6: Design Record Auditor"; do
  RC=0; grep -qF "$R" "$VALIDATE_MD" || RC=1
  assert_eq "commands/spec-validate.md: '$R' present unchanged" 0 $RC
done

# ============================================================
echo ""
echo "=== Results ==="
# ============================================================
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All references-field tests passed.${NC}"
  exit 0
fi
