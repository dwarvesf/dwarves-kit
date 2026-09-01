#!/usr/bin/env bash
# test-proof-visual-evidence.sh
# Guards the "screenshot/GIF counts as captured run-evidence" path in proof-ledger.sh check()
# AND fix #1 (the embedded image must actually EXIST). Four cases, both directions:
#   - a behavioral proof whose only evidence is a REAL committed image  -> ACCEPT
#   - a dangling ![x](missing.gif) reference (no file)                   -> BLOCK  (fix #1)
#   - a text run-table (Exit: 0)                                        -> ACCEPT (regression)
#   - the NEGATIVE CONTROL marker but no evidence at all               -> BLOCK  (not pass-anything)
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# make_fixture <dir> <evidence in {image-real,image-dangling,text,none}>
make_fixture() {
  local d="$1" ev="$2" proof
  rm -rf "$d"; mkdir -p "$d/docs/verification" "$d/lib"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"   # opt-in marker
  echo baseline > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"                                   # behavioral diff
  proof="$d/docs/verification/vf-vis.md"
  {
    echo "# Verification , vf-vis"
    echo "## NEGATIVE CONTROL"
    echo "reverting the change turns this RED."
    case "$ev" in
      image-real)     echo '![demo](vf-vis-demo.gif)' ;;
      image-dangling) echo '![demo](vf-vis-missing.gif)' ;;   # deliberately create NO file
      text)           echo '- Command: `bash lib/thing.sh`'; echo '- Exit: 0'; echo '- Verdict: PASS' ;;
      none)           echo 'no captured run here.' ;;
    esac
  } > "$proof"
  [ "$ev" = "image-real" ] && printf 'GIF89a' > "$d/docs/verification/vf-vis-demo.gif"
  git -C "$d" add -A
}
base(){ git -C "$1" rev-parse HEAD; }
gate(){ bash "$LIB" check "$1" "$(base "$1")" vf-vis >/dev/null 2>&1; }   # 0 = ACCEPT, non-0 = BLOCK

F=/tmp/vf-vis-gate
make_fixture "$F" image-real;     gate "$F" && pass "real committed image accepted"           || fail "real image should ACCEPT but BLOCKED"
make_fixture "$F" image-dangling; gate "$F" && fail "dangling image should BLOCK but ACCEPTED" || pass "dangling image BLOCKED (fix #1)"
make_fixture "$F" text;           gate "$F" && pass "text run-table still accepted (regression)" || fail "text run-table should ACCEPT but BLOCKED"
make_fixture "$F" none;           gate "$F" && fail "no evidence should BLOCK but ACCEPTED"    || pass "no evidence BLOCKED"
rm -rf "$F"

[ "$fails" -eq 0 ] && { echo "ALL PASS (4/4)"; exit 0; } || { echo "$fails FAILED"; exit 1; }
