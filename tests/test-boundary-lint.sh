#!/usr/bin/env bash
# test-boundary-lint.sh -- SG-01 (learning-boundary, SPEC-285): the engine names no
# consumer, by path or by skill.
#
# AC1 is the live-tree smoke: green on this branch.
# AC2/AC3 are the negative control, planted in a mktemp fixture -- self-contained (no git
# checkout, no dirty-tree refusal, no dependency on negctl.sh's real-repo mutate/restore
# dance), so it runs every time run-all.sh globs tests/test-*.sh instead of needing a
# separate manual invocation. Before this, the ONLY negative control for this lint lived in
# a script run-all.sh never discovers (it globs tests/test-*.sh only), so a typo in path_re
# or name_re/name_files -- or an emptied name_files -- left the whole suite green. (The
# battery found this same defect class, an assert-only-PASS lint test with its negative
# control elsewhere and unrun, in two other repos.)
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$KIT_DIR/lib/gate/boundary-lint.sh"
PASS=0; FAIL=0; TOTAL=0
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1 ${3:-}" >&2; FAIL=$((FAIL+1)); fi; }

echo "=== AC1: live tree PASSes ==="
OUT="$(bash "$LINT" "$KIT_DIR" 2>&1)"; RC=$?
assert "boundary-lint PASSes on the live tree (rc=$RC): $OUT" "$([ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'boundary-lint: PASS' && echo 0 || echo 1)"

echo ""
echo "=== AC2: negative control -- a mktemp fixture with a planted hardcoded path is caught ==="
FX="$(mktemp -d)"
mkdir -p "$FX/lib" "$FX/hooks" "$FX/commands" "$FX/tests"
: > "$FX/kit.toml"
# Built from two halves so the pattern this fixture plants never appears literally in this
# test's own source (tests/ is itself in boundary-lint's PATH-check scan set).
d="dotfiles"; h="home"
{
  echo '# reaches into the operator dotfiles by absolute path'
  echo "SRC=\"\$HOME/workspace/<owner>/$d/$h/dot_claude/skills/whatever\""
} > "$FX/lib/evil-path.sh"
OUT="$(bash "$LINT" "$FX" 2>&1)"; RC=$?
assert "planted path violation exits non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
assert "planted path violation names itself in the message" "$(printf '%s' "$OUT" | grep -q 'consumer path hardcoded' && echo 0 || echo 1)" "$OUT"

echo ""
echo "=== AC3: negative control -- a planted retired-skill name in a NEW commands/*.md is caught ==="
# Fresh fixture dir, not AC2's $FX: a shared dir left AC2's path violation live here too, so
# AC3's "exits non-zero" assertion passed on that violation instead of on the name check --
# only the message-content assertion caught the break. A fresh dir makes the exit code prove
# what it claims.
rm -rf "$FX"
FX="$(mktemp -d)"
mkdir -p "$FX/commands"
# Not one of the three files the old hand list carried before this fix (wrap.md/explain.md/
# quiz-gate.md): proves name_files now globs every commands/*.md, the finding-3 fix.
echo 'Compose narrate-log to write the session summary.' > "$FX/commands/brand-new-cmd.md"
OUT="$(bash "$LINT" "$FX" 2>&1)"; RC=$?
assert "planted name violation (new commands/*.md file) exits non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
assert "planted name violation names itself in the message" "$(printf '%s' "$OUT" | grep -q 'consumer skill named directly' && echo 0 || echo 1)" "$OUT"

rm -rf "$FX"

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
