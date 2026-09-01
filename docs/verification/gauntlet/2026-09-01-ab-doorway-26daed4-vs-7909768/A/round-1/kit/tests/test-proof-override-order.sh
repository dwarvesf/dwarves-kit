#!/usr/bin/env bash
# test-proof-override-order.sh
# Proves proof-ledger.sh check() lets a REAL proof-of-done win outright even when an
# override was ALSO logged for the same slug. Before the fix, is_overridden() being true
# short-circuited check() straight into the override branch, which always REJECTS a slug
# that touches a source (.sh/.py/...) file, no matter what proof docs exist. Because the
# override log is append-only, that meant: log an override early (a reasonable thing to
# do before writing the proof), then add a real proof-of-done later in the same branch,
# and the slug was blocked FOREVER, since the override was always checked first. Found
# 2026-08-06 on a docs+one-line-.sh-fix branch that could never pass again once it had a
# real NEGATIVE CONTROL proof, because an earlier override call for the same slug kept
# winning.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

make_fixture() {  # $1 = dir
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/docs/verification" "$d/lib"
  git -C "$d" init -q
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"  # opt-in marker
  echo "baseline" > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"   # behavioral diff touching a .sh (source) file
  git -C "$d" add -A   # staged but uncommitted: the gate counts --cached + working tree
}
base() { git -C "$1" rev-parse HEAD; }

F=/tmp/vf-gate-override-order
make_fixture "$F"
SLUG=vf-override-fix
BASE="$(base "$F")"

# 1. No proof yet, no override yet -> BLOCK (baseline: an unproven behavioral change gates).
if bash "$LIB" check "$F" "$BASE" "$SLUG" >/dev/null 2>&1; then
  fail "unproven behavioral change should BLOCK but the gate passed"
else
  pass "unproven behavioral change correctly BLOCKED"
fi

# 2. Log an override for this slug (as an operator might, before writing the proof doc).
#    override() scopes to cwd (git -C .), so it must run FROM the fixture repo, same as a
#    real operator cd'd into their own repo before logging one.
if ( cd "$F" && bash "$LIB" override "$SLUG" "test: exercising the override-then-proof ordering" >/dev/null 2>&1 ); then
  pass "override logged"
else
  fail "override call itself failed"
fi

# 3. Override exists, .sh file has no proof -> still REJECTED (unchanged: an override can
#    never excuse a source-code file, cc-hyg-04 / rtk-611).
if bash "$LIB" check "$F" "$BASE" "$SLUG" >/dev/null 2>&1; then
  fail "override alone should not excuse a .sh source change, but the gate passed"
else
  pass "override alone correctly still REJECTED for the .sh source file"
fi

# 4. Add a real proof-of-done (green run + NEGATIVE CONTROL) for this slug's file.
cat > "$F/docs/verification/$SLUG.md" <<'EOF'
## 2026-08-06 10:00 PASS -- vf-override-fix [green]
- Command: `bash lib/thing.sh`
- Exit: 0
- Verdict: PASS

## 2026-08-06 10:01 RED-as-expected -- vf-override-fix [negative control]
- Command: `bash lib/thing.sh` (change reverted)
- Exit: 1
- Verdict: RED-as-expected
- Note: NEGATIVE CONTROL -- reverting the change turns this RED
EOF
git -C "$F" add -A

# 5. CURRENT (fixed) lib: a real proof now exists for the same slug that also has a logged
#    override -> the real proof must win outright -> PASS.
if bash "$LIB" check "$F" "$BASE" "$SLUG" >/dev/null 2>&1; then
  pass "fixed lib: real proof-of-done wins even though an override was also logged"
else
  fail "fixed lib: a real proof-of-done should PASS regardless of an earlier override, but the gate still BLOCKED"
fi

# 6. NEGATIVE CONTROL: revert the fix (stash the working-tree edit to lib/gate/proof-ledger.sh
#    itself), re-run the SAME check against the SAME fixture -> must go RED (the bug reproduces
#    without the fix), then restore.
if git -C "$KIT" diff --quiet -- lib/gate/proof-ledger.sh; then
  echo "[NO EXECUTABLE CHECK: lib/gate/proof-ledger.sh has no uncommitted diff to revert for the negative control -- run this from the fix branch before committing]"
  fails=$((fails+1))
else
  STASH_TAG="test-proof-override-order-negctl-$$"
  git -C "$KIT" stash push -u -m "$STASH_TAG" -- lib/gate/proof-ledger.sh >/dev/null 2>&1
  if bash "$LIB" check "$F" "$BASE" "$SLUG" >/dev/null 2>&1; then
    fail "negative control: reverting the fix should turn this RED (old override-first order should still block) but it stayed PASS"
  else
    pass "negative control: reverting the fix correctly goes RED (old order re-blocks a real proof)"
  fi
  # stash@{0} is this push (nothing else touches the stash stack in between): pop restores
  # the fix and drops the entry in one step, no bare-SHA stash-drop (that form does not work).
  git -C "$KIT" stash pop >/dev/null 2>&1
fi

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS (5/5)"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
