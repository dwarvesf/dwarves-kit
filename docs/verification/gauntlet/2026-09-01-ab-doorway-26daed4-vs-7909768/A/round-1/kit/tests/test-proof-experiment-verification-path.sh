#!/usr/bin/env bash
# test-proof-experiment-verification-path.sh
# Guards the co-located verification path for owners OTHER than tools/ (ID-553): a fresh
# proof at experiments/<slug>/docs/verification/<feature>.md must satisfy check(), the same
# as the repo-root and tools/<name>/ conventions.
#
# This is the second time the same bug landed. ID-478 fixed it for tools/ by adding one more
# alternative to the grep; enumerating owner directories left every other co-location home
# still invisible, and the failure is silent (the gate reports "no proof of done" for a
# branch that has one). The fix matches docs/verification/ at ANY depth, so case 3 below is
# the one that stops the next recurrence.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# $1 = dir, $2 = path of the proof file relative to the repo root
make_fixture() {
  local d="$1" rel="$2" proof
  rm -rf "$d"; mkdir -p "$d/$(dirname "$rel")" "$d/lib"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo baseline > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"                                  # behavioral diff
  proof="$d/$rel"
  {
    echo "# Verification"
    echo "## NEGATIVE CONTROL"
    echo "reverting the change turns this RED."
    echo '- Command: `bash lib/thing.sh`'
    echo '- Exit: 0'
    echo '- Verdict: PASS'
  } > "$proof"
  git -C "$d" add -A
}
base(){ git -C "$1" rev-parse HEAD; }

check_accepts() {  # $1 = label, $2 = proof path relative to repo root
  local d=/tmp/vf-exp-path-gate
  make_fixture "$d" "$2"
  if bash "$LIB" check "$d" "$(base "$d")" vf-exp >/dev/null 2>&1; then
    pass "$1"
  else
    fail "$1 , proof exists but the gate BLOCKED"
  fi
  rm -rf "$d"
}

check_accepts "experiments/<slug>/docs/verification/<feature>.md accepted" \
  "experiments/webnovel-dl/docs/verification/repair-outliers.md"

# set-wise layout: the green run and the negative control may live in separate files under
# a per-feature directory. Grouping must key on the nested prefix too, not only a root one.
check_accepts "experiments/<slug>/docs/verification/<feature>/run.md accepted" \
  "experiments/webnovel-dl/docs/verification/repair-outliers/run.md"

# The generalization's real payload: an owner directory nobody has enumerated yet.
check_accepts "an unenumerated owner dir under docs/verification/ accepted" \
  "learning/social-stratification/docs/verification/claim-teardown.md"

# Guard the other direction: a README under docs/verification/ is documentation about
# proofs, not a proof, and must stay excluded or every repo self-satisfies the gate.
D=/tmp/vf-exp-path-gate-neg
make_fixture "$D" "experiments/e/docs/verification/README.md"
if bash "$LIB" check "$D" "$(base "$D")" vf-exp >/dev/null 2>&1; then
  fail "a docs/verification/README.md must NOT satisfy the gate, but it did"
else
  pass "docs/verification/README.md still excluded"
fi
rm -rf "$D"

[ "$fails" -eq 0 ] && { echo "ALL PASS (4/4)"; exit 0; } || { echo "$fails FAILED"; exit 1; }
