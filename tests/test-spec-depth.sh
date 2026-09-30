#!/usr/bin/env bash
# test-spec-depth.sh: the spec header `Depth:` line (helper, command wiring, review routing).
# Run: bash tests/test-spec-depth.sh [section]
# Sections: level check inverse missing-line wants spec-md-wiring validate-wiring review-routing docs
# No section runs all. Exit 0 = every assert green.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
H="$KIT_DIR/lib/spec/spec-depth.sh"
FX="$KIT_DIR/tests/fixtures/spec-depth"
SECTION="${1:-all}"
PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1 (expected '$2', got '$3')"; FAIL=$((FAIL+1)); fi
}
want() { [ "$SECTION" = all ] || [ "$SECTION" = "$1" ]; }
lvl() { bash "$H" level "$FX/$1.md" 2>/dev/null; }
chk() { bash "$H" check "$FX/$1.md" >/dev/null 2>&1; echo $?; }
has() { grep -qF -- "$2" "$1" && echo 0 || echo 1; }

if want level; then
  echo "=== level (AC1) ==="
  assert_eq "standard"                  "standard"                        "$(lvl standard)"
  assert_eq "research (repo:)"          "research-repo"                   "$(lvl research-repo)"
  assert_eq "research (outside:)"       "research-outside"                "$(lvl research-outside)"
  assert_eq "blind-spot"                "blind-spot"                      "$(lvl blind-spot)"
  assert_eq "combined with +"           "research-outside blind-spot"     "$(lvl combined)"
  assert_eq "fenced example is ignored" "standard"                        "$(lvl fenced-example)"
  assert_eq "no header line"            "standard"                        "$(lvl no-depth)"
fi

if want check; then
  echo "=== check (AC2) ==="
  for f in bad-empty bad-importance bad-importance-noprefix bad-critical-core bad-noprefix bad-unknown bad-two; do
    assert_eq "$f exits 1" 1 "$(chk $f)"
  done
  assert_eq "honest outside reason exits 0"     0 "$(chk research-outside)"
  assert_eq "mixed importance + real unknown 0" 0 "$(chk mixed-reason)"
  for f in standard research-repo blind-spot combined fenced-example; do
    assert_eq "$f exits 0" 0 "$(chk $f)"
  done
fi

if want inverse; then
  echo "=== inverse (AC3) ==="
  assert_eq "standard + open question exits 1"      1 "$(chk inverse-open-q)"
  assert_eq "standard + (none; ...) exits 0"        0 "$(chk inverse-none)"
  assert_eq "standard + cannot be sampled exits 0"  0 "$(chk inverse-grounding)"
fi

if want missing-line; then
  echo "=== missing-line (AC5) ==="
  assert_eq "new spec (Generated on the pin date) exits 1" 1 "$(chk no-depth-new)"
  assert_eq "older spec exits 0"                           0 "$(chk no-depth)"
  assert_eq "no Generated line exits 0"                    0 "$(chk no-depth-nogen)"
  assert_eq "older spec warns on stderr" 1 "$(bash "$H" check "$FX/no-depth.md" 2>&1 >/dev/null | grep -c 'warning')"
  assert_eq "no-Generated spec warns on stderr" 1 "$(bash "$H" check "$FX/no-depth-nogen.md" 2>&1 >/dev/null | grep -c 'warning')"
  assert_eq "DEPTH_REQUIRED_FROM is pinned" 1 "$(grep -c '^DEPTH_REQUIRED_FROM="2026-09-30"$' "$H")"
fi

if want wants; then
  echo "=== wants (AC8) ==="
  bash "$H" wants "$FX/no-depth.md" research-repo; assert_eq "no header line: research-repo exits 1" 1 "$?"
  bash "$H" wants "$FX/no-depth.md" blind-spot;    assert_eq "no header line: blind-spot exits 1" 1 "$?"
  bash "$H" wants "$FX/standard.md" research-repo; assert_eq "standard wants nothing" 1 "$?"
  bash "$H" wants "$FX/research-repo.md" research-repo;       assert_eq "research-repo wants research-repo" 0 "$?"
  bash "$H" wants "$FX/research-repo.md" research-outside;    assert_eq "research-repo does not want outside" 1 "$?"
  bash "$H" wants "$FX/combined.md" research-outside;         assert_eq "combined wants research-outside" 0 "$?"
  bash "$H" wants "$FX/combined.md" blind-spot;               assert_eq "combined wants blind-spot" 0 "$?"
  bash "$H" wants "$FX/fenced-example.md" blind-spot;         assert_eq "fenced example does not want blind-spot" 1 "$?"
  bash "$H" wants "$FX/standard.md" nonsense 2>/dev/null;     assert_eq "unknown level exits 2" 2 "$?"
  assert_eq "spec.sh forwards depth" "standard" "$(bash "$KIT_DIR/lib/spec/spec.sh" depth level "$FX/standard.md" 2>/dev/null)"
fi

if want spec-md-wiring; then
  echo "=== spec-md-wiring (TASK-2, AC4) ==="
  S="$KIT_DIR/commands/spec.md"
  assert_eq "AC4 include \`rid=<rid>\` phrase kept" 0 "$(has "$S" 'include `rid=<rid>`')"
  assert_eq "AC4 step 2 keeps rid=<rid>" 1 "$(sed -n '/^### Step 2/,/^### Step 3/p' "$S" | grep -c 'rid=<rid>' | awk '{print ($1>=1)?1:0}')"
  assert_eq "template carries the Depth: line under Lane" 0 "$(has "$S" '**Depth line.**')"
  assert_eq "step 1 asks the one question" 0 "$(has "$S" 'a fact you cannot settle from the code or one command')"
  assert_eq "step 2 routes research-repo" 0 "$(has "$S" 'spec-depth.sh wants <spec> research-repo')"
  assert_eq "step 2 routes research-outside" 0 "$(has "$S" 'spec-depth.sh wants <spec> research-outside')"
  assert_eq "outside pass writes the -outside file" 0 "$(has "$S" 'docs/research/<date>-<slug>-outside.md')"
  assert_eq "records the depth= action line" 0 "$(has "$S" 'depth=<levels> research_agents=<N>')"
  assert_eq "design pass keyed on gate-ledger plan" 0 "$(has "$S" 'gate-ledger.sh plan <lane>')"
  assert_eq "unconditional 4-agent brownfield rule is gone" 0 "$(grep -c 'If modifying existing code, run codebase research before generating the spec' "$S")"
fi

if want validate-wiring; then
  echo "=== validate-wiring (TASK-3) ==="
  V="$KIT_DIR/commands/spec-validate.md"
  assert_eq "Reviewer 4 runs spec-depth.sh check" 0 "$(has "$V" 'spec-depth.sh check')"
  assert_eq "importance lens question" 0 "$(has "$V" 'only importance')"
  assert_eq "standard-with-unknown lens question" 0 "$(has "$V" 'an unknown or a failure mode it cannot test alone')"
  R4=$(sed -n '/^### Reviewer 4/,/^### Reviewer 5/p' "$V")
  assert_eq "the check sits inside Reviewer 4" 1 "$(printf '%s' "$R4" | grep -c 'spec-depth.sh check' | awk '{print ($1>=1)?1:0}')"
fi

if want review-routing; then
  echo "=== review-routing (AC6) ==="
  P="$KIT_DIR/commands/test-plan.md"; T="$KIT_DIR/commands/test-plan-review-team.md"
  STEP4=$(sed -n '/^### Step 4: Hand off/,/^## Source/p' "$P")
  assert_eq "test-plan step 4 names --floor" 1 "$(printf '%s' "$STEP4" | grep -c -- '--floor' | awk '{print ($1>=1)?1:0}')"
  assert_eq "test-plan step 4 routes blind-spot to the full team" 1 "$(printf '%s' "$STEP4" | grep -c 'spec-depth.sh wants <spec> blind-spot' | awk '{print ($1>=1)?1:0}')"
  assert_eq "team doc documents --floor as lenses 1 and 2, one pass" 0 "$(has "$T" 'lens 1 (Coverage completeness) and lens 2 (Oracle & falsifiability) to the plan in one pass')"
  assert_eq "team doc writes the Scope: floor line" 0 "$(has "$T" 'Scope: floor (coverage + oracle)')"
  assert_eq "team doc runs no revise loop under --floor" 0 "$(has "$T" 'no revise round')"
  assert_eq "6-lens framing intact" 0 "$(has "$T" 'Dispatch 6 lenses')"
fi

if want docs; then
  echo "=== docs (TASK-5) ==="
  W="$KIT_DIR/docs/WORKFLOW.md"
  assert_eq "WORKFLOW has a Depth paragraph" 0 "$(has "$W" '**Depth.**')"
  assert_eq "WORKFLOW says floor pass at every depth" 0 "$(has "$W" 'the floor pass at every depth, the full team at blind-spot')"
  assert_eq "WORKFLOW command row names --floor" 0 "$(has "$W" '/kit:test-plan-review-team --floor')"
fi

echo
echo "spec-depth: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
