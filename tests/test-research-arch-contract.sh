#!/usr/bin/env bash
# test-research-arch-contract.sh -- ID-452 backfill item 3/6, SPEC-210.
#
# Pins the contract claims of agents/research-architecture.md (a read-only
# research subagent with no prior spec or test coverage) AND its dispatch
# contract in commands/spec.md Step 2, from both sides. One assertion per
# SPEC-210 Test plan row (rows 1-24; row 25 is the one-time recorded live
# negative control, see docs/verification/backfill-research-arch.md).
# Exact-string pins are the point: the tested contract IS the prose, so a
# reword breaks the row and prompts a re-verify (same stance as SPEC-208/209).
#
# Run: bash tests/test-research-arch-contract.sh   (exit 0 = all rows green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
A="$KIT_DIR/agents/research-architecture.md"
C="$KIT_DIR/commands/spec.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }

echo "=== AC-1: identity ==="

[ -f "$A" ] && [ -f "$C" ]; assert "agent file + dispatcher file exist" $?

awk '/^---$/{c++; next} c==1' "$A" | grep -qx 'name: research-architecture'
assert "row 1: frontmatter name is research-architecture" $?

grep -qF 'Maps architecture patterns and conventions in an existing codebase.' "$A" && grep -qF 'Dispatched by /spec for brownfield projects. Read-only.' "$A"
assert "row 2: description carries both clauses (auto-delegation + dispatch trigger)" $?

awk '/^---$/{c++; next} c==1' "$A" | grep -qx 'model: sonnet'
assert "row 3: model tier is sonnet (cheap-worker choice)" $?

grep -qF 'Your single job: map the architecture patterns so new code follows existing conventions.' "$A"
assert "row 4: single-job mission statement present" $?

echo ""
echo "=== AC-2: read-only tool grant ==="

diff <(awk '/^---$/{c++; next} c==1' "$A" | grep '^  - ') <(printf '  - Read\n  - Grep\n  - Glob\n  - Bash(find *)\n  - Bash(git log *)\n') >/dev/null
assert "row 5: tool roster is byte-for-byte the 5 read-only entries, in order" $?

! awk '/^---$/{c++; next} c==1' "$A" | grep -qE '^[[:space:]]*-[[:space:]]*(Write|Edit|NotebookEdit)'
assert "row 6: no write-capable tool in the frontmatter grant" $?

echo ""
echo "=== AC-3: dispatch contract, both sides ==="

grep -qF '### Step 2: Research (if brownfield)' "$C"
assert "row 7: dispatcher Step 2 is brownfield-gated" $?

grep -qF '**research-architecture** agent: "Map architecture patterns and conventions. Write to `docs/research/architecture.md`."' "$C"
assert "row 8: Mode A dispatch line names agent + exact write target" $?

grep -qF 'dispatch all 4 via the Task tool in parallel' "$C"
assert "row 9: all 4 research agents dispatched in parallel via Task tool" $?

grep -qF 'Map architecture patterns. Find: directory structure conventions, error handling patterns, naming conventions, how the 2-3 most recent features were built (check git log). Show concrete examples. Max 60 lines. Write to docs/research/architecture.md.' "$C"
assert "row 10: Mode B inline fallback prompt pinned verbatim" $?

test "$(sed -n '/^### Step 2: Research/,/^### Step 3/p' "$C" | grep -cF 'docs/research/architecture.md')" -eq 2 && grep -qF 'Write to `docs/research/architecture.md`:' "$A"
assert "row 11: write target agrees across files (Step 2 region count 2 + agent body)" $?

echo ""
echo "=== AC-4: research scope ==="

grep -qF '**Directory structure**' "$A" && grep -qF '**Error handling pattern**' "$A" && grep -qF '**Naming conventions**' "$A"
assert "row 12: question labels 1-3 present" $?

grep -qF '**How similar features were built**' "$A" && grep -qF '**Shared utilities**' "$A" && grep -qF '**Config pattern**' "$A"
assert "row 13: question labels 4-6 present" $?

grep -qF 'If codebase-memory-mcp is available, use `get_structure()` for directory layout and `search_symbols()` for patterns.' "$A"
assert "row 14: full codebase-memory conditional sentence (guard + both calls co-located)" $?

echo ""
echo "=== AC-5: output contract ==="

grep -qF '## Directory structure' "$A" && grep -qF '## Error handling' "$A" && grep -qF '## Naming conventions' "$A" && grep -qF '## How recent features were built' "$A" && grep -qF '## Shared utilities to reuse' "$A" && grep -qF '## Config pattern' "$A"
assert "row 15: all six output template section headings present" $?

echo ""
echo "=== AC-6: rules ==="

grep -qF 'Max 60 lines.' "$A"
assert "row 16: 60-line output budget" $?

grep -qF 'Patterns, not exhaustive listings.' "$A"
assert "row 17: patterns-not-listings rule" $?

grep -qF 'Show concrete examples (actual file paths, actual function signatures) not abstract descriptions.' "$A"
assert "row 18: concrete-examples rule (full sentence)" $?

grep -qF "If the codebase has no consistent pattern (different features use different approaches), say so. That's useful information." "$A"
assert "row 19: no-consistent-pattern honesty (full sentence)" $?

echo ""
echo "=== AC-7: distilled return contract ==="

grep -qF '## Return contract (distilled return, SPEC-087 Mechanism C)' "$A"
assert "row 20: return-contract heading" $?

grep -qF '**verdict**' "$A" && grep -qF '**key findings**' "$A" && grep -qF '**artifacts**' "$A" && grep -qF '**read-next**' "$A"
assert "row 21: all four bounded return fields" $?

grep -qF 'BOUNDED summary, not a dump' "$A" && grep -qF 'not as a re-paste of diffs, full test logs, or whole files' "$A" && grep -qF 'hundreds of tokens per dispatch instead of tens of thousands' "$A"
assert "row 22: bounded summary + no-re-paste rule + token bound" $?

echo ""
echo "=== Row 23: read-only claim consistency (regression pair) ==="

grep -qF 'Read-only.' "$A" && ! awk '/^---$/{c++; next} c==1' "$A" | grep -qE '^[[:space:]]*-[[:space:]]*(Write|Edit|NotebookEdit)'
assert "row 23: Read-only description claim + no write grant hold together" $?

echo ""
echo "=== Row 24: in-suite NEGATIVE CONTROL (scratch copy, never the tracked file) ==="

# Mirrors tests/test-{memory-tidy,loop-engineering}-contract.sh: prove the pins
# discriminate. Substring strip, not line delete: row 16's pin and row 17's pin
# share one physical line of the agent body (SPEC-210 coverage notes), so only
# a substring removal keeps the blast radius at exactly one pin.
NC_DIR="$(mktemp -d -t research-arch-contract-nc.XXXXXX)"
trap 'rm -rf "$NC_DIR"' EXIT
sed 's/ Patterns, not exhaustive listings\.//' "$A" > "$NC_DIR/mut.md"

! cmp -s "$A" "$NC_DIR/mut.md"
assert "NC setup: the strip actually changed the scratch copy" $?

! grep -qF 'Patterns, not exhaustive listings.' "$NC_DIR/mut.md"
assert "row 24a: with the sentence stripped, row 17's pin goes RED" $?

grep -qF 'Max 60 lines.' "$NC_DIR/mut.md"
assert "row 24b: row 16's pin (same physical line) still PASSES -- substring-strip, not line-delete, granularity" $?

grep -qF 'Show concrete examples (actual file paths, actual function signatures) not abstract descriptions.' "$NC_DIR/mut.md"
assert "row 24c: row 18's pin (adjacent physical line) still PASSES -- the strip does not over-reach the line boundary" $?

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All research-architecture contract tests passed.${NC}"
  exit 0
fi
