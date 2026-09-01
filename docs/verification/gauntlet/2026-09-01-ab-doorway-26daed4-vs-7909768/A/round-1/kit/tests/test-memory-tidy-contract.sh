#!/usr/bin/env bash
# test-memory-tidy-contract.sh -- ID-452 backfill item 1/6, SPEC-208.
#
# Pins the contract claims of skills/memory-tidy/SKILL.md, a prompt-file skill
# with no prior spec or test coverage. One assertion per SPEC-208 Test plan row
# (rows 1-25; row 26 is the one-time recorded live negative control, see
# docs/verification/backfill-memory-tidy.md). Exact-string pins are the point:
# the tested contract IS the prose, so a reword breaks the row and prompts a
# re-verify (same stance as tests/test-test-writer-contract.sh).
#
# Run: bash tests/test-memory-tidy-contract.sh   (exit 0 = all rows green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
S="$KIT_DIR/skills/memory-tidy/SKILL.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }

echo "=== AC-1: identity + scope-outs ==="

[ -f "$S" ]; assert "skills/memory-tidy/SKILL.md exists" $?

awk '/^---$/{c++; next} c==1' "$S" | grep -qx 'name: memory-tidy'
assert "row 1: frontmatter name is memory-tidy" $?

grep -qF 'NOT for the built-in machine-local auto-memory under ~/.claude/projects' "$S"
assert "row 2: description scopes OUT the machine-local auto-memory" $?

grep -qF 'NOT for editing a single note' "$S"
assert "row 3: description scopes OUT single-note edits" $?

echo ""
echo "=== AC-2: worktree-first ==="

grep -qF 'Branch in a worktree first' "$S"
assert "row 4: process step 1 is worktree-first" $?

grep -qF 'without the worktree branch: stop, branch, start over' "$S"
assert "row 5: red flag repeats the worktree rule" $?

echo ""
echo "=== AC-3: mechanical pre-pass ==="

# Anchored to the process-step region so the Overview's mention of the same
# tool name cannot satisfy this on its own (SPEC-208 critique, MEDIUM 1).
sed -n '/Mechanical pre-pass/,/Fan-out/p' "$S" | grep -qF 'stats memory-sweep'
assert "row 6: the pre-pass STEP names stats memory-sweep (anchored)" $?

grep -qF 'diff both directions' "$S"
assert "row 7: two-direction files-vs-index diff required" $?

echo ""
echo "=== AC-4: four-slot verdict grammar with evidence ==="

grep -qE '^[[:space:]]*\| KEEP \|' "$S" && grep -qE '^[[:space:]]*\| MERGE' "$S" && grep -qE '^[[:space:]]*\| STALE \|' "$S" && grep -qE '^[[:space:]]*\| UNSURE \|' "$S"
assert "row 8: KEEP/MERGE/STALE/UNSURE all present as verdict table cells" $?

grep -qF 'distinct fact, referents spot-checked alive' "$S"
assert "row 9: KEEP evidence rule pinned" $?

grep -qF 'quote the overlapping claim from both notes' "$S"
assert "row 10: MERGE evidence rule pinned" $?

grep -qF 'concrete reason: referenced path tested and gone' "$S"
assert "row 11: STALE evidence rule pinned (one worked example, per spec)" $?

grep -qF 'what only the operator can answer' "$S"
assert "row 12: UNSURE evidence rule pinned" $?

grep -qF 'A verdict with no checkable evidence is not actionable' "$S"
assert "row 13: no-evidence verdicts downgrade to UNSURE" $?

echo ""
echo "=== AC-5: UNSURE is never deleted ==="

grep -qF 'UNSURE notes are never deleted; list them in the report' "$S"
assert "row 14: UNSURE never deleted + operator list" $?

echo ""
echo "=== AC-9/AC-10: fan-out safety + apply safety ==="

grep -qF 'dispatch parallel read-only agents' "$S" && grep -qF '2-4 subsystem clusters' "$S"
assert "row 15: fan-out is clustered and READ-ONLY" $?

grep -qF 'grep the store for references to its name and rewrite them' "$S"
assert "row 16: pre-delete store-wide reference rewrite" $?

grep -qF 'Merges preserve incident detail and dates' "$S"
assert "row 17: merges preserve incident detail and dates" $?

echo ""
echo "=== AC-6: PR gate ==="

grep -qF 'deletions reach main only through a PR merge' "$S"
assert "row 18: deletions reach main only through a PR merge" $?

grep -qF 'PR whose body lists each removal with its reason' "$S"
assert "row 19: PR body lists each removal with its reason" $?

grep -qF 'create no branch and report CLEAN' "$S"
assert "row 20: CLEAN no-op path (no branch when nothing changes)" $?

echo ""
echo "=== AC-7: derived index ==="

grep -qF 'derived from its frontmatter' "$S"
assert "row 21: index lines derived from frontmatter description" $?

grep -qF 'entry count equals note count' "$S" && grep -qF 'returns nothing' "$S"
assert "row 22: index verify clause (count parity + deleted-name grep empty)" $?

grep -qF 'Hand-editing index lines instead of deriving them from frontmatter' "$S"
assert "row 23: hand-editing index lines is a named red flag" $?

echo ""
echo "=== AC-8: danger check ==="

grep -qF 'contradicts current policy' "$S" && grep -qF 'say so in the PR body' "$S"
assert "row 24: contradicts-policy notes are folded, deleted, and named in the PR body" $?

echo ""
echo "=== Row 25: in-suite NEGATIVE CONTROL (scratch copy, never the tracked file) ==="

# Mirrors tests/test-test-writer-contract.sh AC3: prove the pins discriminate.
# Substring strip, not line delete: rows 13 and 14 share one physical line in
# the SKILL body, so a line delete would flip both (SPEC-208 critique, CRITICAL 1).
NC_DIR="$(mktemp -d -t memory-tidy-contract-nc.XXXXXX)"
trap 'rm -rf "$NC_DIR"' EXIT
sed 's/ UNSURE notes are never deleted; list them in the report\.//' "$S" > "$NC_DIR/mut.md"

! cmp -s "$S" "$NC_DIR/mut.md"
assert "NC setup: the strip actually changed the scratch copy" $?

! grep -qF 'UNSURE notes are never deleted; list them in the report' "$NC_DIR/mut.md"
assert "row 25a: with the UNSURE sentence stripped, row 14's pin goes RED" $?

grep -qF 'A verdict with no checkable evidence is not actionable' "$NC_DIR/mut.md"
assert "row 25b: row 13's pin (same physical line) still PASSES -- the strip discriminates" $?

echo ""
echo "=== Results ==="
echo -e "Passed: ${GREEN}${PASS}${NC} / ${TOTAL}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}${FAIL}${NC}"
  exit 1
else
  echo -e "${GREEN}All memory-tidy contract tests passed.${NC}"
  exit 0
fi
