#!/usr/bin/env bash
# test-verbatim-rows.sh -- lib/gate/verbatim-rows.sh: every row in a rewritten structured
# index must appear verbatim in the pre-edit original (see the script's own header for the
# incident this catches: a truncated MEMORY.md row that still ended in a legal character).
#
# AC1  all-verbatim: new file's rows all exist unchanged in the original -> exit 0.
# AC2  one truncated row -> exit 1, and the bad row is named in the output.
# AC3  --pattern override: a non-default row marker is picked up correctly.
# AC4  bad ref -> exit 2.
#
# Fixture: a throwaway git repo in mktemp, one commit holding the "original" index file.
# "New" files are plain files on disk (as the real usage is: committed original vs. a
# working-tree rewrite), never committed themselves.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$KIT_DIR/lib/gate/verbatim-rows.sh"
PASS=0; FAIL=0; TOTAL=0
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo "  PASS $1"; PASS=$((PASS+1)); else echo "  FAIL $1 ${3:-}" >&2; FAIL=$((FAIL+1)); fi; }

FX="$(mktemp -d)"
cleanup() { rm -rf "$FX"; }
trap cleanup EXIT

git -C "$FX" init -q
git -C "$FX" config user.email "test@example.com"
git -C "$FX" config user.name "test"
cat > "$FX/MEMORY.md" <<'EOF'
- [Title one](slug-one.md): a hook that ends cleanly
- [Title two](slug-two.md): another hook, also intact
- [Title three](slug-three.md): so a later git stash pop pops a clean line
EOF
git -C "$FX" add MEMORY.md
git -C "$FX" commit -q -m "original"

echo "=== AC1: all rows verbatim -> exit 0 ==="
cp "$FX/MEMORY.md" "$FX/new-ok.md"
# git show needs to run from inside the fixture repo (it reads <ref>:<original-path>
# relative to cwd)
OUT="$(cd "$FX" && bash "$SCRIPT" HEAD MEMORY.md "$FX/new-ok.md" 2>&1)"; RC=$?
assert "all-verbatim exits 0 (rc=$RC): $OUT" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
assert "all-verbatim reports 0 not-verbatim" "$(printf '%s' "$OUT" | grep -q 'not verbatim: 0' && echo 0 || echo 1)" "$OUT"

echo ""
echo "=== AC2: one truncated row -> exit 1, names the row ==="
cat > "$FX/new-bad.md" <<'EOF'
- [Title one](slug-one.md): a hook that ends cleanly
- [Title two](slug-two.md): another hook, also intact
- [Title three](slug-three.md): so a later git stash pop pops a
EOF
OUT="$(cd "$FX" && bash "$SCRIPT" HEAD MEMORY.md "$FX/new-bad.md" 2>&1)"; RC=$?
assert "truncated row exits 1 (rc=$RC)" "$([ "$RC" -eq 1 ] && echo 0 || echo 1)" "$OUT"
assert "output names the truncated row" "$(printf '%s' "$OUT" | grep -q 'stash pop pops a' && echo 0 || echo 1)" "$OUT"
assert "summary reports 1 not-verbatim" "$(printf '%s' "$OUT" | grep -q 'not verbatim: 1' && echo 0 || echo 1)" "$OUT"

echo ""
echo "=== AC3: --pattern override picks up a non-default row marker ==="
cat > "$FX/kanban.md" <<'EOF'
| ID-001 | Do the thing | queued |
| ID-002 | Do another thing | shipped |
EOF
git -C "$FX" add kanban.md
git -C "$FX" commit -q -m "kanban original"
cp "$FX/kanban.md" "$FX/kanban-ok.md"
OUT="$(cd "$FX" && bash "$SCRIPT" HEAD kanban.md "$FX/kanban-ok.md" --pattern '^\| ID-' 2>&1)"; RC=$?
assert "--pattern override matches kanban rows and exits 0 (rc=$RC)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "$OUT"
assert "--pattern override checked 2 rows" "$(printf '%s' "$OUT" | grep -q 'rows checked: 2' && echo 0 || echo 1)" "$OUT"

# Same fixture with the DEFAULT pattern (^- \[) should find zero kanban rows to check --
# proves the override actually changed what counted as a row, not that everything passes
# regardless of pattern.
OUT="$(cd "$FX" && bash "$SCRIPT" HEAD kanban.md "$FX/kanban-ok.md" 2>&1)"; RC=$?
assert "default pattern finds 0 rows in a kanban file (rc=$RC)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "$OUT"
assert "default pattern checked 0 rows" "$(printf '%s' "$OUT" | grep -q 'rows checked: 0' && echo 0 || echo 1)" "$OUT"

echo ""
echo "=== AC4: bad ref -> exit 2 ==="
OUT="$(cd "$FX" && bash "$SCRIPT" not-a-real-ref MEMORY.md "$FX/new-ok.md" 2>&1)"; RC=$?
assert "bad ref exits 2 (rc=$RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)" "$OUT"

echo ""
echo "=== usage error -> exit 2 ==="
OUT="$(bash "$SCRIPT" 2>&1)"; RC=$?
assert "no args exits 2 (rc=$RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)" "$OUT"

echo ""
echo "=== $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ]
