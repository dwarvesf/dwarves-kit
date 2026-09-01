#!/usr/bin/env bash
# test-loop-engineering-contract.sh -- ID-452 backfill item 2/6, SPEC-209.
#
# Pins the contract claims of skills/loop-engineering/SKILL.md, a prompt-file
# skill with no prior spec or test coverage. One assertion per SPEC-209 Test
# plan row (rows 1-27; row 28 is the one-time recorded live negative control,
# see docs/verification/backfill-loop-engineering.md). Exact-string pins are
# the point: the tested contract IS the prose, so a reword (or a re-wrap: the
# body is hard-wrapped, several pins are single-physical-line fragments) breaks
# the row and prompts a re-verify (same stance as SPEC-208).
#
# Run: bash tests/test-loop-engineering-contract.sh   (exit 0 = all rows green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
S="$KIT_DIR/skills/loop-engineering/SKILL.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }

echo "=== AC-1: identity + invocation + scope-outs ==="

[ -f "$S" ]; assert "skills/loop-engineering/SKILL.md exists" $?

awk '/^---$/{c++; next} c==1' "$S" | grep -qx 'name: loop-engineering'
assert "row 1: frontmatter name is loop-engineering" $?

grep -qF 'NOT for a one-off in-session Stop-hook goal (use goal-craft)' "$S"
assert "row 2: description scopes OUT one-off Stop-hook goals" $?

grep -qF 'NOT for the debug loop (already exists, use /kit:debug)' "$S"
assert "row 3: description scopes OUT the debug loop" $?

grep -qF "NOT for building the loop's actual code" "$S"
assert "row 4: description scopes OUT building the loop's code" $?

grep -qx 'disable-model-invocation: false' "$S" && grep -qF 'Karpathy loop / autoresearch / hill-climb / search-and-select' "$S"
assert "row 25: model invocation enabled + Karpathy-family triggers present" $?

echo ""
echo "=== AC-2: the four gate criteria ==="

grep -qF '**Bounded-in-session only.**' "$S"
assert "row 5: gate criterion bounded-in-session" $?

grep -qF '**Serves 2+ lifecycle phases.**' "$S"
assert "row 6: gate criterion serves 2+ phases" $?

grep -qF '**Explainable in one sentence.**' "$S"
assert "row 7: gate criterion one-sentence explainable" $?

grep -qF '**Has a source citation.**' "$S"
assert "row 8: gate criterion source citation" $?

grep -qF 'If any of these fail, the idea is not a loop.' "$S" && grep -qF 'A side-flow is simpler and does not need this skill.' "$S"
assert "row 9: gate fail path falls back to a one-shot side-flow" $?

echo ""
echo "=== AC-3: three shapes + routing question ==="

grep -qF '**Bounded-revise engine.**' "$S" && grep -qF '**Campaign / worklist iteration.**' "$S" && grep -qF '**Bounded search-select.**' "$S"
assert "row 10: all three shape headings present" $?

grep -qF 'does the loop make ONE thing' "$S" && grep -qF 'check MANY existing things (campaign' "$S" && grep -qF 'BEST VARIANT of one thing (search-select)?' "$S"
assert "row 11: ONE/MANY/BEST-VARIANT routing question (three fragments)" $?

echo ""
echo "=== AC-4/AC-5: engine parameterization + severity-aware convergence ==="

grep -qF 'Parameterize three things: the artifact, who scans it (N lenses), and who revises it.' "$S"
assert "row 12: engine parameterizes artifact + N scanners + reviser" $?

grep -qF 'reviser must be distinct from every scanner' "$S"
assert "row 13: reviser distinct from every scanner" $?

grep -qF 'convergence rule tracks severity, not raw' "$S" && grep -qF 'A flat K still counts as progress if the worst severity dropped.' "$S"
assert "row 14: severity-aware convergence rule (two fragments)" $?

grep -qF 'halt honestly' "$S" && grep -qF 'round += 1 (cap 3)' "$S" && grep -qF 'verdict: SOLID / REVISE / RECONSIDER' "$S"
assert "row 15: diagram carries honest halt + cap 3 + three-way verdict" $?

echo ""
echo "=== AC-6: two-tier scan contract ==="

grep -qF 'The scan step runs in two tiers. It does not dispatch all N lenses every round.' "$S"
assert "row 16: two-tier declaration" $?

grep -qF 'Tier 1 runs a deterministic check: grep or bash, zero model cost.' "$S" && grep -qF 'Tier 1 runs every round and decides on its own.' "$S"
assert "row 17: Tier 1 deterministic, every round, decides alone" $?

grep -qF 'Dispatch it only for the criteria Tier 1 cannot reduce' "$S" && grep -qF 'finding-space Tier 1 already cleared.' "$S"
assert "row 18: Tier 2 residual-only + skip cleared lenses" $?

grep -qF 'The stop condition becomes: Tier 1 is all clean, and Tier 2 hits K=0, or its severity drops,' "$S" && grep -qF 'or the round cap hits.' "$S"
assert "row 19: two-tier stop condition, both fragments incl round cap" $?

echo ""
echo "=== AC-7: campaign wraps, never a second engine ==="

grep -qF 'It is not a new engine. It wraps an existing one.' "$S" && grep -qF "This reuses the Goal loop's own shape" "$S" && grep -qF 'Do not build a second convergence' "$S" && grep -qF 'mechanic. Reuse the Goal loop.' "$S"
assert "row 20: campaign reuses the Goal loop, no second convergence mechanic" $?

grep -qF 'docs/patterns/audit-loop.md' "$S"
assert "row 21: audit flavor points at docs/patterns/audit-loop.md" $?

grep -qF 'Shape: build a worklist of untreated items.' "$S" && grep -qF 'Stop when the worklist runs out, or a budget or blocker hits.' "$S"
assert "row 26: worklist shape + its stop condition" $?

echo ""
echo "=== AC-8: search-select preconditions + mandatory adaptations ==="

grep -qF 'All three preconditions must hold, or this shape is wrong:' "$S" && grep -qF 'A cheap, unambiguous numeric metric exists.' "$S" && grep -qF 'Evaluation is fast enough to afford many shots.' "$S" && grep -qF 'minutes per experiment, about 100 overnight.' "$S" && grep -qF 'Losers carry no information the next attempt needs.' "$S"
assert "row 22: all three preconditions + Karpathy budget math" $?

grep -qF 'Two adaptations are mandatory' "$S" && grep -qF 'budget (never "loop forever until interrupted"), and an honest-halt report at the end, what' "$S"
assert "row 23: fixed budget + honest-halt stated as mandatory" $?

echo ""
echo "=== AC-9: lineage claim structure ==="

grep -qF 'Cite Evaluator-Optimizer for the shape. Do not claim the shape itself is new.' "$S" && grep -qF 'kit did not invent it.' "$S" && grep -qF '**Severity-aware convergence.**' "$S" && grep -qF 'A flat finding-count still counts as progress if the worst' "$S" && grep -qF '**Distinct reviser, never a scorer.**' "$S" && grep -qF '**Hard cap with an honest-halt reporting path.**' "$S" && grep -qF 'above are the real contribution.' "$S"
assert "row 24: cite E-O, no novelty claim, three deltas + restatement pinned" $?

echo ""
echo "=== Row 27: in-suite NEGATIVE CONTROL (scratch copy, never the tracked file) ==="

# Mirrors tests/test-memory-tidy-contract.sh row 25: prove the pins discriminate.
# Substring strip, not line delete: row 13's pin and row 14's first fragment
# share one physical line in the SKILL body (SPEC-209 coverage notes), so only
# a substring removal keeps the blast radius at exactly one fragment.
NC_DIR="$(mktemp -d -t loop-engineering-contract-nc.XXXXXX)"
trap 'rm -rf "$NC_DIR"' EXIT
sed 's/A flat K still counts as progress if the worst severity dropped\. //' "$S" > "$NC_DIR/mut.md"

! cmp -s "$S" "$NC_DIR/mut.md"
assert "NC setup: the strip actually changed the scratch copy" $?

! grep -qF 'A flat K still counts as progress if the worst severity dropped.' "$NC_DIR/mut.md"
assert "row 27a: with the flat-K sentence stripped, row 14's second fragment goes RED" $?

grep -qF 'convergence rule tracks severity, not raw' "$NC_DIR/mut.md"
assert "row 27b: row 14's first fragment (previous physical line) still PASSES" $?

grep -qF 'reviser must be distinct from every scanner' "$NC_DIR/mut.md"
assert "row 27c: row 13's pin (adjacent claim, shared line) still PASSES" $?

grep -qF 'A flat finding-count still counts as progress if the worst' "$NC_DIR/mut.md"
assert "row 27d: row 24's differently-worded Lineage restatement still PASSES -- the strip discriminates at sub-wording granularity" $?

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All loop-engineering contract tests passed.${NC}"
  exit 0
fi
