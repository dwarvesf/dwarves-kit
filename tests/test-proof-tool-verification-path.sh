#!/usr/bin/env bash
# test-proof-tool-verification-path.sh
# Guards the monorepo tool-co-located verification path (ID-478): a fresh proof at
# tools/<name>/docs/verification/<slug>.md must satisfy check(), the same as the
# repo-root docs/verification/<slug>.md convention. Before the fix, _fresh_proof_files()
# anchored its grep at the repo root and this file was invisible to the gate.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

make_fixture() {  # $1 = dir
  local d="$1" proof
  rm -rf "$d"; mkdir -p "$d/tools/x/docs/verification" "$d/lib"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo baseline > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"                                  # behavioral diff
  proof="$d/tools/x/docs/verification/vf-tool.md"
  {
    echo "# Verification , vf-tool"
    echo "## NEGATIVE CONTROL"
    echo "reverting the change turns this RED."
    echo '- Command: `bash lib/thing.sh`'
    echo '- Exit: 0'
    echo '- Verdict: PASS'
  } > "$proof"
  git -C "$d" add -A
}
base(){ git -C "$1" rev-parse HEAD; }

F=/tmp/vf-tool-path-gate
make_fixture "$F"
if bash "$LIB" check "$F" "$(base "$F")" vf-tool >/dev/null 2>&1; then
  pass "tools/<name>/docs/verification/<slug>.md proof satisfies the gate"
else
  fail "co-located tool verification proof should ACCEPT but the gate BLOCKED"
fi
rm -rf "$F"

[ "$fails" -eq 0 ] && { echo "ALL PASS (1/1)"; exit 0; } || { echo "$fails FAILED"; exit 1; }
