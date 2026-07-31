#!/usr/bin/env bash
# test-research-pair-contract.sh -- ID-452 backfill items 4+5/6, SPEC-211.
#
# Pins the contract claims of agents/research-pitfalls.md and
# agents/research-stack.md (two read-only research subagents with no prior
# spec or test coverage) AND their per-agent dispatch deltas in
# commands/spec.md Step 2, from both sides. One assertion per SPEC-211 Test
# plan row (rows 1-34; rows 35-36 are the one-time recorded live negative
# controls, see docs/verification/backfill-research-pair.md). Shared
# dispatcher rows (Step 2 heading, parallel-4 sentence, Mode A/B gate) are
# SPEC-210's and deliberately NOT re-pinned here.
# Exact-string pins are the point: the tested contract IS the prose, so a
# reword breaks the row and prompts a re-verify (same stance as SPEC-208/209/210).
#
# Run: bash tests/test-research-pair-contract.sh   (exit 0 = all rows green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
P="$KIT_DIR/agents/research-pitfalls.md"
S="$KIT_DIR/agents/research-stack.md"
C="$KIT_DIR/commands/spec.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }

echo "=== AC-1/AC-2: research-pitfalls identity + grant ==="

[ -f "$P" ] && [ -f "$S" ] && [ -f "$C" ]; assert "agent files + dispatcher file exist" $?

awk '/^---$/{c++; next} c==1' "$P" | grep -qx 'name: research-pitfalls' && awk '/^---$/{c++; next} c==1' "$P" | grep -qx 'model: sonnet'
assert "row 1: pitfalls frontmatter name + model sonnet (cheap-worker choice)" $?

grep -qF 'Finds landmines and risks in a codebase area before new work begins.' "$P" && grep -qF 'Dispatched by /spec for brownfield projects. Read-only.' "$P"
assert "row 2: pitfalls description carries both clauses" $?

grep -qF 'Your single job: find landmines that will blow up during implementation.' "$P"
assert "row 3: pitfalls single-job mission statement present" $?

diff <(awk '/^---$/{c++; next} c==1' "$P" | grep '^  - ') <(printf '  - Read\n  - Grep\n  - Glob\n  - Bash(git log *)\n  - Bash(find *)\n  - Bash(wc *)\n') >/dev/null \
  && ! awk '/^---$/{c++; next} c==1' "$P" | grep -qE '^[[:space:]]*-[[:space:]]*(Write|Edit|NotebookEdit)'
assert "row 4: pitfalls tool roster byte-for-byte (6 read-only entries, in order) + no write grant" $?

echo ""
echo "=== AC-4/AC-5: research-pitfalls scope + output ==="

grep -qF '**Deprecated code still referenced**' "$P" && grep -qF '**TODO/FIXME/HACK in the area**' "$P" && grep -qF '**Test gaps**' "$P" && grep -qF '**Large files**' "$P" && grep -qF '**Circular dependencies**' "$P" && grep -qF '**Missing config/env values**' "$P" && grep -qF '**Stale dependencies**' "$P"
assert "row 5: all seven pitfalls category labels present" $?

grep -qF 'If codebase-memory-mcp is available, use `find_dead_code()` and `trace_call_path()`.' "$P"
assert "row 6: pitfalls codebase-memory conditional (guard + both calls co-located)" $?

grep -qF '# Pitfall Report' "$P" && grep -qF '## Critical (will block implementation)' "$P" && grep -qF '## Warnings (will cause problems if ignored)' "$P" && grep -qF '## Noted (cosmetic, low risk)' "$P" && grep -qF '## Missing prerequisites' "$P" && grep -qF '## Files over 500 lines (split candidates)' "$P"
assert "row 7: pitfalls report title + all five template section headings" $?

echo ""
echo "=== AC-6: research-pitfalls rules ==="

grep -qF 'Max 40 lines.' "$P"
assert "row 8: pitfalls 40-line budget" $?

grep -qF 'Only report real risks, not style preferences.' "$P"
assert "row 9: real-risks-not-style rule" $?

grep -qF "Critical means \"implementation will fail or produce bugs if this isn't addressed first.\"" "$P"
assert "row 10: critical-definition sentence" $?

grep -qF "If you find nothing, say \"No significant pitfalls found.\" Don't pad the report." "$P"
assert "row 11: no-padding honesty rule" $?

grep -qF 'Check `git blame` on suspicious code to see when it last changed. Code untouched for 6+ months in an active repo is a smell.' "$P"
assert "row 12: git-blame smell rule (both sentences)" $?

grep -qF '## Return contract (distilled return, SPEC-087 Mechanism C)' "$P" && grep -qF '**verdict**' "$P" && grep -qF '**key findings**' "$P" && grep -qF '**artifacts**' "$P" && grep -qF '**read-next**' "$P" && grep -qF 'BOUNDED summary, not a dump' "$P" && grep -qF 'not as a re-paste of diffs, full test logs, or whole files' "$P" && grep -qF 'hundreds of tokens per dispatch instead of tens of thousands' "$P"
assert "row 13: pitfalls distilled return contract (heading + fields + bounds)" $?

echo ""
echo "=== AC-1/AC-2: research-stack identity + grant ==="

awk '/^---$/{c++; next} c==1' "$S" | grep -qx 'name: research-stack' && awk '/^---$/{c++; next} c==1' "$S" | grep -qx 'model: haiku'
assert "row 14: stack frontmatter name + model haiku (the only haiku-tier research agent)" $?

grep -qF 'Maps the technology stack of an existing codebase.' "$S" && grep -qF 'Dispatched by /spec for brownfield projects. Read-only.' "$S"
assert "row 15: stack description carries both clauses" $?

grep -qF 'Your single job: map the technology stack.' "$S"
assert "row 16: stack single-job mission statement present" $?

diff <(awk '/^---$/{c++; next} c==1' "$S" | grep '^  - ') <(printf '  - Read\n  - Grep\n  - Glob\n  - Bash(cat *)\n  - Bash(head *)\n  - Bash(wc *)\n') >/dev/null \
  && ! awk '/^---$/{c++; next} c==1' "$S" | grep -qE '^[[:space:]]*-[[:space:]]*(Write|Edit|NotebookEdit)'
assert "row 17: stack tool roster byte-for-byte (cat/head replace find/git log; no git access) + no write grant" $?

echo ""
echo "=== AC-4/AC-5: research-stack scope + output ==="

grep -qF '**Languages**' "$S" && grep -qF '**Frameworks**' "$S" && grep -qF '**Key dependencies**' "$S" && grep -qF '**Infrastructure**' "$S" && grep -qF '**Build/deploy**' "$S"
assert "row 18: all five stack category labels present" $?

grep -qF 'If codebase-memory-mcp is available, use `get_structure()` instead of reading files one by one.' "$S"
assert "row 19: stack codebase-memory conditional (body side of divergence c)" $?

grep -qF '# Stack Report' "$S" && grep -qF '## Languages' "$S" && grep -qF '## Frameworks' "$S" && grep -qF '## Key dependencies' "$S" && grep -qF '## Infrastructure' "$S" && grep -qF '## Build & deploy' "$S"
assert "row 20: stack report title + all five template section headings" $?

echo ""
echo "=== AC-6: research-stack rules ==="

grep -qF 'Max 50 lines of output. Be concise.' "$S"
assert "row 21: stack 50-line budget + be-concise (full line)" $?

grep -qF 'Only report what you can verify from files.' "$S"
assert "row 22: verify-from-files rule (first sentence)" $?

grep -qF "Don't guess." "$S"
assert "row 23: don't-guess rule" $?

grep -qF "If a config file doesn't exist, say \"not found\" instead of assuming." "$S"
assert "row 24: not-found honesty rule" $?

grep -qF '## Return contract (distilled return, SPEC-087 Mechanism C)' "$S" && grep -qF '**verdict**' "$S" && grep -qF '**key findings**' "$S" && grep -qF '**artifacts**' "$S" && grep -qF '**read-next**' "$S" && grep -qF 'BOUNDED summary, not a dump' "$S" && grep -qF 'not as a re-paste of diffs, full test logs, or whole files' "$S" && grep -qF 'hundreds of tokens per dispatch instead of tens of thousands' "$S"
assert "row 25: stack distilled return contract (heading + fields + bounds)" $?

echo ""
echo "=== AC-3: dispatch deltas, both sides ==="

grep -qF '**research-pitfalls** agent: "Find landmines in [target area / target files]. Write to `docs/research/pitfalls.md`."' "$C"
assert "row 26: Mode A pitfalls dispatch line names agent + exact write target" $?

grep -qF '**research-stack** agent: "Map the technology stack. Write to `docs/research/stack.md`."' "$C" && grep -qF '`.claude/agents/research-stack.md`' "$C"
assert "row 27: Mode A stack dispatch line + gate example filename" $?

grep -qF 'Find landmines in [target area]. Look for: deprecated code still referenced, TODO/FIXME comments, test gaps, circular dependencies, files over 500 lines, missing env/config values the new feature will need. Max 40 lines. Write to docs/research/pitfalls.md.' "$C"
assert "row 28: Mode B pitfalls prompt pinned verbatim (6-of-7 divergence as-is)" $?

grep -qF 'Map the technology stack. Read package.json / go.mod / Cargo.toml / pyproject.toml and config files. Report: languages, frameworks, versions, key dependencies (top 5-10), build/test/deploy commands. If codebase-memory-mcp is available, use get_architecture(). Max 50 lines. Write to docs/research/stack.md.' "$C"
assert "row 29: Mode B stack prompt pinned verbatim (get_architecture divergence as-is)" $?

test "$(sed -n '/^### Step 2: Research/,/^### Step 3/p' "$C" | grep -cF 'docs/research/pitfalls.md')" -eq 2 && grep -qF 'Write to `docs/research/pitfalls.md`:' "$P"
assert "row 30: pitfalls write target agrees (Step 2 region count 2 + agent body)" $?

test "$(sed -n '/^### Step 2: Research/,/^### Step 3/p' "$C" | grep -cF 'docs/research/stack.md')" -eq 2 && grep -qF 'Write to `docs/research/stack.md`:' "$S"
assert "row 31: stack write target agrees (Step 2 region count 2 + agent body)" $?

echo ""
echo "=== Row 32: read-only claim consistency (regression pair, both agents) ==="

grep -qF 'Read-only.' "$P" && grep -qF 'Read-only.' "$S" \
  && ! awk '/^---$/{c++; next} c==1' "$P" | grep -qE '^[[:space:]]*-[[:space:]]*(Write|Edit|NotebookEdit)' \
  && ! awk '/^---$/{c++; next} c==1' "$S" | grep -qE '^[[:space:]]*-[[:space:]]*(Write|Edit|NotebookEdit)'
assert "row 32: Read-only description claims + no write grants hold together" $?

echo ""
echo "=== Rows 33-34: in-suite NEGATIVE CONTROLS (scratch copies, never a tracked file) ==="

# Mirrors tests/test-research-arch-contract.sh: prove the pins discriminate.
# Substring strip, not line delete: each NC target shares its physical line
# with a survivor pin (SPEC-211 coverage notes), so only a substring removal
# keeps the blast radius at exactly one pin. The ! cmp -s setup guard is the
# assertion rows 35/36 predict RED under the live mutation (sed is a silent
# no-op when the substring is already gone).
NC_DIR="$(mktemp -d -t research-pair-contract-nc.XXXXXX)"
trap 'rm -rf "$NC_DIR"' EXIT

sed 's/ Only report real risks, not style preferences\.//' "$P" > "$NC_DIR/mut-p.md"

! cmp -s "$P" "$NC_DIR/mut-p.md"
assert "NC setup (pitfalls): the strip actually changed the scratch copy" $?

! grep -qF 'Only report real risks, not style preferences.' "$NC_DIR/mut-p.md"
assert "row 33a: with the sentence stripped, row 9's pin goes RED" $?

grep -qF 'Max 40 lines.' "$NC_DIR/mut-p.md"
assert "row 33b: row 8's pin (same physical line) still PASSES -- substring-strip, not line-delete, granularity" $?

grep -qF "Critical means \"implementation will fail or produce bugs if this isn't addressed first.\"" "$NC_DIR/mut-p.md"
assert "row 33c: row 10's pin (adjacent physical line) still PASSES -- the strip does not over-reach the line boundary" $?

sed "s/ Don't guess\.//" "$S" > "$NC_DIR/mut-s.md"

! cmp -s "$S" "$NC_DIR/mut-s.md"
assert "NC setup (stack): the strip actually changed the scratch copy" $?

! grep -qF "Don't guess." "$NC_DIR/mut-s.md"
assert "row 34a: with the sentence stripped, row 23's pin goes RED" $?

grep -qF 'Only report what you can verify from files.' "$NC_DIR/mut-s.md"
assert "row 34b: row 22's pin (same physical line) still PASSES" $?

grep -qF 'Max 50 lines of output. Be concise.' "$NC_DIR/mut-s.md"
assert "row 34c: row 21's pin (adjacent physical line) still PASSES" $?

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All research-pair contract tests passed.${NC}"
  exit 0
fi
