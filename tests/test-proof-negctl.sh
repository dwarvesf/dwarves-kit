#!/usr/bin/env bash
# proof-ledger negctl: the mechanised negative control. Asserts on a throwaway git repo:
# a real mutation goes GREEN -> RED -> GREEN and prints the block check() reads; a vacuous
# mutation (test stays green) is FAIL; a dirty tree is REFUSED before anything runs; the
# tree is restored on every path.
#
# Run: bash tests/test-proof-negctl.sh   Pass: "test-proof-negctl: all N passed", exit 0.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PL="$DIR/lib/gate/proof-ledger.sh"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

REPO="$(mktemp -d)"
git -C "$REPO" init -q
cat > "$REPO/lib.sh" <<'EOF'
add() { echo $(( $1 + $2 )); }
EOF
cat > "$REPO/test.sh" <<'EOF'
#!/usr/bin/env bash
source ./lib.sh
[ "$(add 2 2)" = "4" ]
EOF
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m seed

echo "[1] real mutation: GREEN -> RED -> GREEN, PASS block, tree restored"
OUT="$(bash "$PL" negctl "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && grep -q 'NEGATIVE CONTROL\|Negative control' <<<"$OUT" \
   && grep -q '^Exit: 0 (green before' <<<"$OUT" && grep -qE '^Exit: [1-9][0-9]* \(under mutation' <<<"$OUT" \
   && [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
  ok "PASS block printed, tree clean after"
else
  no "rc=$RC tree=$(git -C "$REPO" status --porcelain) out=$OUT"
fi

echo "[2] vacuous mutation (test stays green) is FAIL, exit 1, tree restored"
OUT="$(bash "$PL" negctl "$REPO" "bash test.sh" "printf '\n# comment\n' >> lib.sh" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'Verdict: FAIL: test stayed green' <<<"$OUT" \
   && [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
  ok "vacuous control rejected, tree restored"
else
  no "rc=$RC out=$OUT"
fi

echo "[3] dirty tracked file: REFUSED before any step, exit 2, file untouched"
echo "# uncommitted work" >> "$REPO/lib.sh"
OUT="$(bash "$PL" negctl "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh" 2>&1)"; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'REFUSED' <<<"$OUT" && grep -q '# uncommitted work' "$REPO/lib.sh" && ! grep -q 'Command:' <<<"$OUT"; then
  ok "refused, uncommitted line survives"
else
  no "rc=$RC out=$OUT"
fi
git -C "$REPO" checkout -q -- lib.sh

echo "[4] mutation that changes nothing tracked is FAIL"
OUT="$(bash "$PL" negctl "$REPO" "bash test.sh" "true" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'changed no tracked file' <<<"$OUT"; then ok "no-op mutation rejected"; else no "rc=$RC out=$OUT"; fi

echo "[5] usage on missing args"
bash "$PL" negctl "$REPO" >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 64 ]; then ok "exit 64"; else no "rc=$RC"; fi

echo
if [ "$fail" -gt 0 ]; then echo "test-proof-negctl: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-proof-negctl: all $pass passed"
