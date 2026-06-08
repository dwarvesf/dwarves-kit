#!/usr/bin/env bash
# test-proof-dir-layout.sh
# Proves proof-ledger.sh check() validates the docs/verification/<slug>/ directory layout
# SET-WISE: a green run in one runs/ file + a negative control in another runs/ file under
# the same <slug>/ dir satisfies the gate. Two negative controls guard it:
#   A. a fixture missing the negative-control run BLOCKS (the gate is not trivially green);
#   B. the pre-change lib (HEAD:lib/proof-ledger.sh) BLOCKS the same split fixture (the
#      set-wise code is load-bearing, not decorative).
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/proof-ledger.sh"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

make_fixture() {  # $1 = dir ; $2 = include negative-control run (1/0)
  local d="$1" negctl="$2"
  rm -rf "$d"; mkdir -p "$d/docs/verification" "$d/lib"
  git -C "$d" init -q
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"  # opt-in marker
  echo "baseline" > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"                                  # behavioral diff
  mkdir -p "$d/docs/verification/vf-fix/runs"
  cat > "$d/docs/verification/vf-fix/runs/2026-06-09-1000.md" <<'EOF'
## 2026-06-09 10:00 PASS -- vf-fix [green]
- Command: `bash lib/thing.sh`
- Exit: 0
- Verdict: PASS
EOF
  if [ "$negctl" = "1" ]; then
    cat > "$d/docs/verification/vf-fix/runs/2026-06-09-1001.md" <<'EOF'
## 2026-06-09 10:01 RED-as-expected -- vf-fix [negative-control]
- Command: `bash lib/thing.sh`
- Exit: 1
- Verdict: RED-as-expected
- Note: NEGATIVE CONTROL -- reverting the change turns this RED
EOF
  fi
  git -C "$d" add -A   # staged but uncommitted: the gate counts --cached + working tree
}
base() { git -C "$1" rev-parse HEAD; }

# 1. GREEN: green + negative control split across two runs/ files, current lib -> PASS
F=/tmp/vf-gate-split; make_fixture "$F" 1
if bash "$LIB" check "$F" "$(base "$F")" vf-fix >/dev/null 2>&1; then
  pass "split green+negctl under one <slug>/ dir satisfies the gate"
else
  fail "split proof should satisfy but the gate BLOCKED"
fi

# 2. NEGATIVE CONTROL A: same fixture without the negative-control run -> BLOCK
F=/tmp/vf-gate-noneg; make_fixture "$F" 0
if bash "$LIB" check "$F" "$(base "$F")" vf-fix >/dev/null 2>&1; then
  fail "green-only should BLOCK but the gate passed (trivially green)"
else
  pass "green-only correctly BLOCKED (negative control is required)"
fi

# 3. NEGATIVE CONTROL B: pre-change lib on the split fixture -> BLOCK (set-wise is load-bearing).
# Take the lib as it was at the fork point (merge-base with master), so this stays valid no
# matter how many commits land on the branch after the set-wise change. HEAD would be wrong
# once the change is committed (HEAD then HAS set-wise).
F=/tmp/vf-gate-split   # reuse the split fixture (has both runs/ files)
OLD=/tmp/vf-oldlib.sh
BASEREF=$(git -C "$KIT" merge-base HEAD master 2>/dev/null \
  || git -C "$KIT" merge-base HEAD origin/master 2>/dev/null \
  || git -C "$KIT" rev-parse master 2>/dev/null)
git -C "$KIT" show "${BASEREF:-HEAD}:lib/proof-ledger.sh" > "$OLD" 2>/dev/null
if [ -s "$OLD" ] && ! grep -q 'set-wise' "$OLD"; then
  if bash "$OLD" check "$F" "$(base "$F")" vf-fix >/dev/null 2>&1; then
    fail "pre-change lib should BLOCK the split layout but it passed"
  else
    pass "pre-change lib BLOCKS the split layout (the set-wise code is load-bearing)"
  fi
else
  echo "[NO EXECUTABLE CHECK: cannot read HEAD:lib/proof-ledger.sh]"; fails=$((fails+1))
fi

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS (3/3)"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
