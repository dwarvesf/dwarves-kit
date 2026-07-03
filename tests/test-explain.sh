#!/usr/bin/env bash
# test-explain.sh -- SPEC-122, understanding-gate SG-03.
# Proves /kit:explain's grounding engine (lib/explain.sh) emits a LITERATE-DIFF explainer:
#   AC1  the 4 sections appear in reading order (background -> goal+intuition -> diff -> diagram)
#   AC2  the diff is in PROSE order, NOT git/alphabetical order
#   AC3  the diagram renders (a syntactically valid mermaid block)
#   AC4  GROUNDED-IN-DIFF negative control (the load-bearing one): when a false narrative contradicts
#        the diff, the explainer describes the DIFF, not the narrative. This is the reason SG-03 exists.
#
# Run: bash tests/test-explain.sh   (exit 0 = all AC green)
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$KIT_DIR/lib/explain.sh"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi; }

gitq() { git -C "$1" "${@:2}"; }
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git init -q -b master "$d"
  gitq "$d" config user.email t@t; gitq "$d" config user.name t
}

# ---------------------------------------------------------------------------
# Fixture A: a multi-rank change (background doc + new file + modified files + test), so reading
# order and alphabetical order genuinely differ. Two commits: a base, then the change under explanation.
# ---------------------------------------------------------------------------
DA="$(mktemp -d)"; mkrepo "$DA"
printf 'let a = 1;\n' > "$DA/alpha.js"
printf 'let z = 1;\n' > "$DA/zebra.js"
gitq "$DA" add -A; gitq "$DA" commit -qm "init base files"

mkdir -p "$DA/docs" "$DA/tests"
printf '# Guide\nBackground for the reader.\n'    > "$DA/docs/guide.md"      # rank 0 background (A)
printf 'function beta(){ return 2; }\n'           > "$DA/beta.js"            # rank 1 new concept (A)
printf 'let a = 1;\nlet a2 = 2; // wired in\n'     > "$DA/alpha.js"          # rank 2 integration (M)
printf 'let z = 1;\nlet z2 = 2; // wired in\n'     > "$DA/zebra.js"          # rank 2 integration (M)
printf 'echo beta test\n'                          > "$DA/tests/test-beta.sh" # rank 3 verification (A)
gitq "$DA" add -A; gitq "$DA" commit -qm "wire beta helper into alpha and zebra"
REFA="$(gitq "$DA" rev-parse HEAD)"

ART="$(mktemp)"
( cd "$DA" && bash "$LIB" render "$REFA" ) > "$ART"

echo "=== AC1: four sections in reading order ==="
# The section headings must appear, and in this order.
ORDER=$(grep -nE '^## (Background|Goal and intuition|The change, in reading order|Diagram)$' "$ART" | sed -E 's/^([0-9]+):## //' | tr '\n' '|')
assert "AC1 sections present + ordered (got: ${ORDER%|})" \
  "$([ "$ORDER" = "Background|Goal and intuition|The change, in reading order|Diagram|" ] && echo 0 || echo 1)"

echo "=== AC2: prose order != git alphabetical order ==="
# The engine's reading order:
READ_ORDER=$( cd "$DA" && bash "$LIB" order "$REFA" | tr '\n' '|' )
# git's own (alphabetical) order for the same change:
ALPHA_ORDER=$( gitq "$DA" diff --name-only "${REFA}^1" "$REFA" | tr '\n' '|' )
echo "  reading:      ${READ_ORDER%|}"
echo "  alphabetical: ${ALPHA_ORDER%|}"
assert "AC2 the two orders differ (prose ordering, not a raw diff)" \
  "$([ "$READ_ORDER" != "$ALPHA_ORDER" ] && echo 0 || echo 1)"
# and prove it is not a random shuffle: background leads, verification trails.
FIRST="${READ_ORDER%%|*}"; LAST_TRIM="${READ_ORDER%|}"; LAST="${LAST_TRIM##*|}"
assert "AC2 background (docs/) leads the reading order" \
  "$([ "$FIRST" = "docs/guide.md" ] && echo 0 || echo 1)"
assert "AC2 verification (tests/) trails the reading order" \
  "$([ "$LAST" = "tests/test-beta.sh" ] && echo 0 || echo 1)"

echo "=== AC3: the diagram renders (valid mermaid) ==="
MER=$( cd "$DA" && bash "$LIB" mermaid "$REFA" )
FENCES=$(printf '%s\n' "$MER" | grep -c '^```')
HAS_DIRECTIVE=$(printf '%s\n' "$MER" | grep -cE '^(flowchart|graph) ')
HAS_EDGE=$(printf '%s\n' "$MER" | grep -c -- '-->')
assert "AC3 mermaid fence is balanced (open+close)" "$([ "$FENCES" -eq 2 ] && echo 0 || echo 1)"
assert "AC3 mermaid has a flowchart/graph directive" "$([ "$HAS_DIRECTIVE" -ge 1 ] && echo 0 || echo 1)"
assert "AC3 mermaid has >=1 edge" "$([ "$HAS_EDGE" -ge 1 ] && echo 0 || echo 1)"
# the same fenced diagram is embedded in the rendered artifact
FENCE='```mermaid'
if grep -qF "$FENCE" "$ART"; then EMBED=0; else EMBED=1; fi
assert "AC3 the artifact embeds a mermaid block" "$EMBED"

echo "=== AC4: GROUNDED-IN-DIFF negative control (load-bearing) ==="
# Fixture B: the change adds `subtract`. A FALSE narrative (commit body + an external narrative file)
# claims it adds `multiply`. The engine's only input is the git ref -- there is no channel for the
# narrative -- so the explainer must describe the DIFF (subtract), never the false narrative (multiply).
DB="$(mktemp -d)"; mkrepo "$DB"
printf '// calc\n' > "$DB/calc.js"
gitq "$DB" add -A; gitq "$DB" commit -qm "init calc"
printf '// calc\nfunction subtract(a, b) { return a - b; }\n' > "$DB/calc.js"   # DIFF truth: subtract
# The agent's stated intent, deliberately WRONG, in two channels the tool must ignore:
printf 'This change adds a multiply function for products.\n' > "$DB/AGENT_NARRATIVE.txt"  # not committed to the ref
gitq "$DB" add calc.js
# commit BODY carries the false narrative; the subject stays neutral (engine reads %s only).
gitq "$DB" commit -qm "update calc helper" -m "Adds a multiply operation as requested."
REFB="$(gitq "$DB" rev-parse HEAD)"

ARTB="$(mktemp)"
( cd "$DB" && bash "$LIB" render "$REFB" ) > "$ARTB"

assert "AC4 explainer describes the DIFF (names 'subtract')" \
  "$(grep -q 'subtract' "$ARTB" && echo 0 || echo 1)"
assert "AC4 explainer does NOT parrot the false narrative ('multiply')" \
  "$(grep -qi 'multiply' "$ARTB" && echo 1 || echo 0)"

# Capture the fixture-A explainer as the proof artifact.
PROOF_DIR="$KIT_DIR/docs/verification/explain-command"
mkdir -p "$PROOF_DIR"
cp "$ART" "$PROOF_DIR/sample-explainer.md"

echo ""
echo "  ---------------------------------------------"
echo "  TOTAL: $TOTAL   PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
