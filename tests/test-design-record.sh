#!/bin/bash
# test-design-record.sh -- Proves the ADR-0031 §1 design record (BEFORE gate).
#
# /kit:spec-validate's Reviewer 6 is prompt text, not code, so this harness cannot drive the
# live LLM judgment. What it CAN prove, honestly, is the STRUCTURAL contract Reviewer 6 is
# specified to enforce: given a spec's own declared design-bearing status (the fixture's
# "Design-bearing (fixture declaration):" line stands in for the reviewer's classification
# step, which is unit-tested-out-of-scope, same limitation SPEC-008 already accepted for its
# advisory reviewers) and its `## Design` section body, does the pass/refuse call match what
# ADR-0031 §1 / Reviewer 6 specify? This is the COVERAGE-DELTA named in SPEC-122's Test plan.
#
# Run: bash tests/test-design-record.sh
# Exit 0 = all tests pass. Exit 1 = failures found.

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$KIT_DIR/tests/fixtures/design-record"
PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
# Reviewer 6's structural contract, reproduced as a pure function.
# ------------------------------------------------------------------

is_design_bearing() {
  # The fixture's declared ground truth (stands in for the reviewer's own judgment call --
  # named, not hidden: see the file header).
  grep -qE '^Design-bearing \(fixture declaration\): yes$' "$1" && echo yes || echo no
}

design_section_body() {
  # Everything between the literal "## Design" heading and the next "## " heading.
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
  # A bare `obvious: <why>` one-liner with nothing else load-bearing (no diagram).
  local body
  body="$(design_section_body_nonblank "$1")"
  [ "$(echo "$body" | grep -cE '^obvious:')" -ge 1 ] && [ "$(has_mermaid_diagram "$1")" = "no" ] && echo yes || echo no
}

reviewer6_verdict() {
  # Returns PASS or REFUSE, mirroring commands/spec-validate.md Reviewer 6 steps 2-3.
  local f="$1" bearing body
  bearing="$(is_design_bearing "$f")"
  body="$(design_section_body_nonblank "$f")"
  if [ "$bearing" = "yes" ]; then
    if [ -z "$body" ]; then
      echo REFUSE   # missing/empty Design block on a design-bearing spec
      return
    fi
    if [ "$(is_obvious_collapse "$f")" = "yes" ]; then
      echo REFUSE   # a bare obvious-collapse on a spec that IS design-bearing
      return
    fi
    if [ "$(has_mermaid_diagram "$f")" = "yes" ]; then
      echo PASS
      return
    fi
    echo REFUSE     # non-empty but no diagram + no obvious-collapse: still incomplete
    return
  fi
  # not design-bearing: obvious-collapse (no diagram) is the correct, proportional PASS
  echo PASS
}

# ============================================================
echo "=== ADR-0031 §1: design record fixtures (SPEC-122) ==="
# ============================================================

EMPTY_FIX="$FIXTURES/design-bearing-empty.md"
FILLED_FIX="$FIXTURES/design-bearing-filled.md"
OBVIOUS_FIX="$FIXTURES/obvious-collapse.md"

for f in "$EMPTY_FIX" "$FILLED_FIX" "$OBVIOUS_FIX"; do
  [ -f "$f" ] || { echo "FIXTURE MISSING: $f"; exit 1; }
done

echo ""
echo "--- NEGATIVE CONTROL: design-bearing spec with an EMPTY Design block ---"
BEARING_1="$(is_design_bearing "$EMPTY_FIX")"
VERDICT_1="$(reviewer6_verdict "$EMPTY_FIX")"
assert_eq "fixture 1 is declared design-bearing" "yes" "$BEARING_1"
assert_eq "fixture 1's Design section is empty" "" "$(design_section_body_nonblank "$EMPTY_FIX")"
assert_eq "Reviewer 6 REFUSES a design-bearing spec with an empty Design block" "REFUSE" "$VERDICT_1"

echo ""
echo "--- POSITIVE: design-bearing spec WITH a mermaid diagram + chosen approach ---"
BEARING_2="$(is_design_bearing "$FILLED_FIX")"
DIAGRAM_2="$(has_mermaid_diagram "$FILLED_FIX")"
VERDICT_2="$(reviewer6_verdict "$FILLED_FIX")"
assert_eq "fixture 2 is declared design-bearing" "yes" "$BEARING_2"
assert_eq "fixture 2's Design section carries a mermaid diagram" "yes" "$DIAGRAM_2"
assert_eq "Reviewer 6 PASSES a design-bearing spec with a filled Design block" "PASS" "$VERDICT_2"

echo ""
echo "--- PROPORTIONALITY CONTROL: obvious spec collapses Design, no diagram required ---"
BEARING_3="$(is_design_bearing "$OBVIOUS_FIX")"
DIAGRAM_3="$(has_mermaid_diagram "$OBVIOUS_FIX")"
COLLAPSE_3="$(is_obvious_collapse "$OBVIOUS_FIX")"
VERDICT_3="$(reviewer6_verdict "$OBVIOUS_FIX")"
assert_eq "fixture 3 is declared NOT design-bearing" "no" "$BEARING_3"
assert_eq "fixture 3 carries NO diagram (none required for obvious work)" "no" "$DIAGRAM_3"
assert_eq "fixture 3's Design section is a bare obvious-collapse" "yes" "$COLLAPSE_3"
assert_eq "Reviewer 6 PASSES an obvious spec with no diagram (proportionality)" "PASS" "$VERDICT_3"

# ============================================================
echo ""
echo "=== Structural wiring: the 4 surfaces SPEC-122 touches ==="
# ============================================================

SPEC_MD="$KIT_DIR/commands/spec.md"
VALIDATE_MD="$KIT_DIR/commands/spec-validate.md"
DESIGN_MD="$KIT_DIR/commands/design.md"
WORKFLOW_MD="$KIT_DIR/WORKFLOW.md"

RC=0; grep -qE '^## Design$' "$SPEC_MD" || RC=1
assert_eq "commands/spec.md template has a top-level ## Design heading" 0 $RC

RC=0; grep -qF 'design-bearing' "$SPEC_MD" || RC=1
assert_eq "commands/spec.md names the design-bearing trigger" 0 $RC

RC=0; grep -qF 'obvious: <why>' "$SPEC_MD" || RC=1
assert_eq "commands/spec.md names the obvious: <why> collapse" 0 $RC

RC=0; grep -qE 'Reviewer 6' "$VALIDATE_MD" || RC=1
assert_eq "commands/spec-validate.md has a Reviewer 6" 0 $RC

RC=0; grep -qiE 'BLOCKING' "$VALIDATE_MD" || RC=1
assert_eq "commands/spec-validate.md Reviewer 6 is marked blocking (unlike 1-5)" 0 $RC

RC=0; grep -qiE 'refus(e|es|ed)' "$VALIDATE_MD" || RC=1
assert_eq "commands/spec-validate.md uses ADR-0031's 'refuses' language" 0 $RC

RC=0; grep -qiE 'PROPORTIONALITY' "$VALIDATE_MD" || RC=1
assert_eq "commands/spec-validate.md Reviewer 6 carries the proportionality warning path" 0 $RC

# NEGATIVE CONTROL on the reviewer roster itself: Reviewers 1-5 present verbatim, unchanged.
for R in "Reviewer 1: Security Auditor" "Reviewer 2: Failure Mode Analyst" "Reviewer 3: Assumption Destroyer" "Reviewer 4: Scope Critic" "Reviewer 5: Solution-Design & Extensibility Critic"; do
  RC=0; grep -qF "$R" "$VALIDATE_MD" || RC=1
  assert_eq "commands/spec-validate.md: '$R' present unchanged" 0 $RC
done

RC=0; grep -qiE 'diagram' "$DESIGN_MD" || RC=1
assert_eq "commands/design.md's interactive lane asks about a diagram" 0 $RC

RC=0; grep -qiE 'ADR link' "$DESIGN_MD" || RC=1
assert_eq "commands/design.md's interactive lane records ADR link(s)" 0 $RC

RC=0; grep -qE '^\| Design record \(design-bearing, ADR-0031' "$WORKFLOW_MD" || RC=1
assert_eq "WORKFLOW.md depth matrix has a Design record row" 0 $RC

RC=0; grep -qF '| Design (opt-in) |' "$WORKFLOW_MD" || RC=1
assert_eq "WORKFLOW.md's new row is distinct from the existing 'Design (opt-in)' row" 0 $RC

# ============================================================
echo ""
echo "=== Results ==="
# ============================================================
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All design-record tests passed.${NC}"
  exit 0
fi
