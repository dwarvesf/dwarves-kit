#!/usr/bin/env bash
# test-rules.sh -- the kit's stateful rules (lib/rules) are proven, their broken variants refused, and the
# commands that run them (bin/verify-loop) behave as the proven rule decides.
#
# Proof: `node lib/rules/prove.ts` exits 0 only when every law is proven AND kernel-checked from any state, and
# every kept broken variant is refuted. Skips (exit 0, one line) when node or the gdp-wired install is missing,
# so a bash-only host is not failed for a tool it does not have; CI installs both.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
no() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

if ! command -v node >/dev/null 2>&1; then echo "test-rules: SKIP (node not installed)"; exit 0; fi
if [ ! -d "$ROOT/lib/rules/node_modules/gdp-wired" ]; then
  if command -v npm >/dev/null 2>&1; then npm ci --silent --prefix "$ROOT/lib/rules" >/dev/null 2>&1 || true; fi
  [ -d "$ROOT/lib/rules/node_modules/gdp-wired" ] || { echo "test-rules: SKIP (gdp-wired not installed: npm ci --prefix lib/rules)"; exit 0; }
fi

echo "== proofs"
if out=$(cd "$ROOT/lib/rules" && node prove.ts 2>&1); then ok "every rule's laws proven and checked; every broken variant refused"
else no "lib/rules/prove.ts"; echo "$out" | sed 's/^/    /'; fi

echo "== bin/verify-loop"
VL="$ROOT/bin/verify-loop"
export VERIFY_LOOP_DIR; VERIFY_LOOP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kit-vl.XXXXXX")" || exit 1; trap 'rm -rf "$VERIFY_LOOP_DIR"' EXIT
step() { bash "$VL" event "$1" "$2" 2>&1; }
expect() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1: got '$2'" ;; esac; }

expect "first FAIL:fixable dispatches fix cycle 1" "$(step a FAIL:fixable)" "fix cycle 1 of 2"
expect "a known failure spends no cycle" "$(step a known)" "retries=1"
expect "second FAIL:fixable dispatches fix cycle 2" "$(step a FAIL:fixable)" "fix cycle 2 of 2"
expect "a third FAIL:fixable ends PARTIAL, no third fix" "$(step a FAIL:fixable)" "phase=partial retries=2"
expect "a finished run never reopens" "$(step a PASS)" "already ended partial"
expect "FAIL:escalate is never retried" "$(step b FAIL:escalate)" "phase=escalated retries=0"
expect "a fix-agent that cannot fix escalates at once" "$(step c cannot-fix)" "phase=escalated"
expect "a silent builder resumes without spending a cycle" "$(step d silent-grace)" "phase=open retries=0"
expect "PASS passes" "$(step d PASS)" "phase=passed"
echo '{"scalars":{"phase":0,"retries":7}}' > "$VERIFY_LOOP_DIR/e.json"
bash "$VL" event e PASS >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "a state outside the proven domain is refused (exit 3)" || no "out-of-domain state: exit $rc, want 3"
bash "$VL" event f bogus >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "an unknown verdict is a usage error" || no "unknown verdict: exit $rc, want 64"

echo "test-rules: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
