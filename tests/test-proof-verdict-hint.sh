#!/usr/bin/env bash
# test-proof-verdict-hint.sh (SPEC-330)
# Proves proof-ledger.sh check()'s BLOCKED message names the file when a behavioral proof
# has a NEGATIVE CONTROL and a green run but is rejected solely because its own FINAL
# Verdict: line reads FAIL/INCONCLUSIVE (the "near miss" shape), instead of the pre-existing
# generic message that never says a file was found at all. Never changes what passes or
# fails: every case also asserts check()'s exit code is unchanged from before this fix.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"   # this worktree's own copy, never ~/.claude/dwarves-kit
# Pin the operator overlay: a developer's own [gate] negative_control = "full" waives the control these
# fixtures assert is required (the suite then reads green-only as passing). gates-on is the shared fixture.
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# The exact hint literal SPEC-330 pins (path and last_v vary per case; the surrounding prose
# does not).
HINT_PROSE='has a NEGATIVE CONTROL and a green run, but its LAST Verdict line reads FAIL/INCONCLUSIVE'
HINT_FIX='record the negative control'\''s own outcome as `Result: RED as expected`'

F=/tmp/vf-proof-verdict-hint
trap 'rm -rf "$F"' EXIT

make_fixture() {  # $1 = dir; a fresh repo with a behavioral (.sh) diff staged
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/docs/verification" "$d/lib"
  git -C "$d" init -q
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"
  echo "baseline" > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  echo "changed behavior" >> "$d/lib/thing.sh"   # behavioral diff touching a .sh (source) file
  git -C "$d" add -A
}
base() { git -C "$1" rev-parse HEAD; }

# NOTE: proof-ledger.sh's last-verdict-wins scan anchors on `^[[:space:]]*Verdict:` (line
# START, see check()'s `last_v=` line), so every `Verdict:`/`Result:` line below sits at the
# start of its own line, never behind a `- ` bullet (a bulleted Verdict: line is invisible to
# that anchor, same convention every real docs/verification/*.md entry already uses, see e.g.
# docs/verification/advisor.md).

near_miss_block() {  # a full green run + a NEGATIVE CONTROL block whose own line ends FAIL
  cat <<'EOF'
## green run
Command: `bash lib/thing.sh`
Exit: 0
Verdict: PASS

## negative control
Command: `bash lib/thing.sh` (reverted)
Exit: 1
Verdict: FAIL as expected
Note: NEGATIVE CONTROL -- reverting the change turns this RED
EOF
}

pass_block() {  # the fixed shape: the control's own outcome is `Result:`, never `Verdict:`
  cat <<'EOF'
## green run
Command: `bash lib/thing.sh`
Exit: 0
Verdict: PASS

## negative control
Command: `bash lib/thing.sh` (reverted)
Exit: 1
Result: RED as expected
Note: NEGATIVE CONTROL -- reverting the change turns this RED
EOF
}

unrelated_fail_block() {  # a plain failed run: no control ever attempted
  cat <<'EOF'
## run
Command: `bash lib/thing.sh`
Exit: 0
Verdict: FAIL
EOF
}

# --- case 1: near miss, per-file shape -------------------------------------------------
make_fixture "$F"
BASE="$(base "$F")"
near_miss_block > "$F/docs/verification/case1.md"
git -C "$F" add -A
out="$(bash "$LIB" check "$F" "$BASE" case1 2>&1 1>/dev/null)"; rc=$?
if [ "$rc" -eq 1 ]; then pass "case1: still BLOCKED (exit 1)"; else fail "case1: expected exit 1, got $rc"; fi
if printf '%s' "$out" | grep -qF "docs/verification/case1.md" && printf '%s' "$out" | grep -qF "$HINT_PROSE" && printf '%s' "$out" | grep -qF "$HINT_FIX"; then
  pass "case1: Hint names the file and states the fix"
else
  fail "case1: no Hint line naming docs/verification/case1.md -- got: $out"
fi

# --- case 2a: near miss, pure set-wise shape (neither file alone qualifies) ------------
make_fixture "$F"
BASE="$(base "$F")"
mkdir -p "$F/docs/verification/case2a"
cat > "$F/docs/verification/case2a/01-green.md" <<'EOF'
## green run
Command: `bash lib/thing.sh`
Exit: 0
EOF
cat > "$F/docs/verification/case2a/02-control.md" <<'EOF'
## negative control
Command: `bash lib/thing.sh` (reverted)
Exit: 1
Verdict: FAIL as expected
Note: NEGATIVE CONTROL -- reverting the change turns this RED
EOF
git -C "$F" add -A
out="$(bash "$LIB" check "$F" "$BASE" case2a 2>&1 1>/dev/null)"; rc=$?
if [ "$rc" -eq 1 ]; then pass "case2a: still BLOCKED (exit 1)"; else fail "case2a: expected exit 1, got $rc"; fi
hints="$(printf '%s' "$out" | grep -c 'Hint:')"
if [ "$hints" -eq 1 ] && printf '%s' "$out" | grep -qF "docs/verification/case2a/"; then
  pass "case2a: exactly one Hint, identified by the group prefix"
else
  fail "case2a: expected exactly one group-prefixed Hint, got $hints -- $out"
fi

# --- case 2b: set-wise dedupe (a per-file near miss inside a near-miss group) ----------
make_fixture "$F"
BASE="$(base "$F")"
mkdir -p "$F/docs/verification/case2b"
near_miss_block > "$F/docs/verification/case2b/run.md"          # qualifies standalone
echo "nothing to see here" > "$F/docs/verification/case2b/notes.md"  # unrelated sibling
git -C "$F" add -A
out="$(bash "$LIB" check "$F" "$BASE" case2b 2>&1 1>/dev/null)"; rc=$?
if [ "$rc" -eq 1 ]; then pass "case2b: still BLOCKED (exit 1)"; else fail "case2b: expected exit 1, got $rc"; fi
hints="$(printf '%s' "$out" | grep -c 'Hint:')"
if [ "$hints" -eq 1 ] && printf '%s' "$out" | grep -qF "docs/verification/case2b/run.md"; then
  pass "case2b: exactly one Hint (per-file wins, group rollup deduped)"
else
  fail "case2b: expected exactly one Hint naming run.md, got $hints -- $out"
fi

# --- case 3: genuine pass (control) -----------------------------------------------------
make_fixture "$F"
BASE="$(base "$F")"
pass_block > "$F/docs/verification/case3.md"
git -C "$F" add -A
out="$(bash "$LIB" check "$F" "$BASE" case3 2>&1 1>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "case3: genuinely passing file still PASSes, no message"
else
  fail "case3: expected exit 0 and no output, got rc=$rc out=$out"
fi

# --- case 4: no proof file at all (control) ---------------------------------------------
make_fixture "$F"
BASE="$(base "$F")"
out="$(bash "$LIB" check "$F" "$BASE" case4 2>&1 1>/dev/null)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'Need:' && ! printf '%s' "$out" | grep -q 'Hint:'; then
  pass "case4: no proof file -> generic message, no Hint"
else
  fail "case4: expected exit 1, generic Need:, no Hint -- got rc=$rc out=$out"
fi

# --- case 5: unrelated rejection, no NEGATIVE CONTROL at all (control, over-broad guard) -
make_fixture "$F"
BASE="$(base "$F")"
unrelated_fail_block > "$F/docs/verification/case5.md"
git -C "$F" add -A
out="$(bash "$LIB" check "$F" "$BASE" case5 2>&1 1>/dev/null)"; rc=$?
if [ "$rc" -eq 1 ] && ! printf '%s' "$out" | grep -q 'Hint:'; then
  pass "case5: a plain FAIL with no control never gets a Hint"
else
  fail "case5: expected exit 1 with no Hint -- got rc=$rc out=$out"
fi

# --- case 6: mixed branch (edge case 3): a near miss plus an unrelated rejection --------
make_fixture "$F"
BASE="$(base "$F")"
near_miss_block > "$F/docs/verification/near-miss-slug.md"
unrelated_fail_block > "$F/docs/verification/unrelated-slug.md"
git -C "$F" add -A
out="$(bash "$LIB" check "$F" "$BASE" case6 2>&1 1>/dev/null)"; rc=$?
hints="$(printf '%s' "$out" | grep -c 'Hint:')"
if [ "$rc" -eq 1 ] && [ "$hints" -eq 1 ] && printf '%s' "$out" | grep -qF "near-miss-slug.md" && ! printf '%s' "$out" | grep -qF "unrelated-slug.md"; then
  pass "case6: exactly one Hint, naming only the near-miss file"
else
  fail "case6: expected exactly one Hint naming near-miss-slug.md only, got $hints -- $out"
fi

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS (10/10)"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
