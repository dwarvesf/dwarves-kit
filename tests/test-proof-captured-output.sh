#!/usr/bin/env bash
# test-proof-captured-output.sh
# A proof of done must CARRY the output of its run, not only words about it, and that output
# must reach the PR. Guards, both directions:
#   gate      a typed `Exit: 0` / `Verdict: PASS` with no captured output      -> BLOCK
#             an `Output:` slot holding real lines (inline, bare, or fenced)   -> ACCEPT
#             an `Output:` slot left empty or holding only a <placeholder>     -> BLOCK
#             a committed image embed                                          -> ACCEPT
#             a dangling image reference                                       -> BLOCK
#             the same rule for a stateful proof's recorded run
#   producers `proof-gate.sh skeleton` and `negctl.sh` emit the `Output:` slot
#   land      the PR body built from the proof file carries the proof section, with image
#             links pinned to the head sha, and is cut under GitHub's body limit
# modules under test: lib/gate/proof-ledger.sh lib/gate/proof-gate.sh lib/gate/negctl.sh lib/wrap/wrap-land.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0; total=0
pass(){ total=$((total+1)); echo "PASS $*"; }
fail(){ total=$((total+1)); echo "FAIL $*"; fails=$((fails+1)); }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-proof-out.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
export KIT_LEDGER_DIR="$TMPD/ledger" KIT_CONFIG_OPERATOR="$TMPD/no-operator-config"
export GIT_TEMPLATE_DIR="$TMPD/no-git-template"; mkdir -p "$GIT_TEMPLATE_DIR"

# new_repo <name> -- a repo with one base commit; prints its path
new_repo() {
  local d="$TMPD/$1"
  mkdir -p "$d/docs/verification" "$d/lib"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"
  echo baseline > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  printf '%s\n' "$d"
}
# behavioral <name> <proof body...> -- a behavioral diff plus a proof file holding stdin
behavioral() {
  local d; d="$(new_repo "$1")"
  echo "changed behavior" >> "$d/lib/thing.sh"
  { echo "# Verification"; echo "## NEGATIVE CONTROL"; echo "reverting the change turns this RED."; cat; } \
    > "$d/docs/verification/vf.md"
  printf '%s\n' "$d"
}
gate(){ bash "$LIB" check "$1" "$(git -C "$1" rev-parse HEAD)" vf 2>&1; }
accepts(){ if gate "$2" >/dev/null; then pass "$1"; else fail "$1 (BLOCKED, want ACCEPT)"; fi; }
blocks(){ if gate "$2" >/dev/null; then fail "$1 (ACCEPTED, want BLOCK)"; else pass "$1"; fi; }

echo "=== gate: a green run needs captured output ==="
D="$(behavioral typed <<'EOF'
## Green run
Command: `bash lib/thing.sh`
Exit: 0
Verdict: PASS
EOF
)"
blocks "typed Exit: 0 / Verdict: PASS with no output is BLOCKED" "$D"
MSG="$(gate "$D")"
case "$MSG" in *"docs/verification/vf.md"*"Output:"*) pass "the BLOCKED message names the file and the Output: slot" ;;
  *) fail "the BLOCKED message does not say what to add: $MSG" ;; esac

D="$(behavioral bare <<'EOF'
## Green run
Command: `bash lib/thing.sh`
Exit: 0
Output:
test-thing: all 12 passed
Verdict: PASS
EOF
)"
accepts "an Output: slot with a real line is accepted" "$D"

D="$(behavioral inline <<'EOF'
Command: `bash lib/thing.sh`
Exit: 0
Output (tail): `test-thing: all 12 passed`
Verdict: PASS
EOF
)"
accepts "output on the Output: line itself is accepted" "$D"

D="$(behavioral fenced <<'EOF'
- Command: `bash lib/thing.sh`
- Exit: 0
- Output (excerpt):
  ```
  Passed: 12 / 12
  ```
- Verdict: PASS
EOF
)"
accepts "the documented '- Output (excerpt):' fenced shape is accepted" "$D"

D="$(behavioral empty <<'EOF'
Command: `bash lib/thing.sh`
Exit: 0
Output:
Verdict: PASS
EOF
)"
blocks "an empty Output: slot is BLOCKED" "$D"

D="$(behavioral placeholder <<'EOF'
- Command: `bash lib/thing.sh`
- Exit: 0
- Output (excerpt):
  ```
  <the decisive lines>
  ```
- Verdict: PASS
- Note: nothing was pasted
EOF
)"
blocks "an Output: slot holding only a <placeholder> is BLOCKED" "$D"

D="$(behavioral fence-close <<'EOF'
```
Command: `bash lib/thing.sh`
Exit: 0
Output:
```
The run passed, trust me.
Verdict: PASS
EOF
)"
blocks "prose after the fence a slot sat in is not output" "$D"

D="$(behavioral image <<'EOF'
![demo](vf-demo.gif)
EOF
)"
printf 'GIF89a' > "$D/docs/verification/vf-demo.gif"
accepts "a committed image embed is accepted" "$D"

D="$(behavioral dangling <<'EOF'
Exit: 0
Verdict: PASS
![demo](vf-missing.gif)
EOF
)"
blocks "a dangling image reference is still BLOCKED" "$D"

echo "=== gate: the slot parser on shapes real proofs use ==="
# slot <label> <want: yes|no> <printf format> -- the proof text; yes = captured output found.
# Never piped into: a pipeline runs it in a subshell and its pass/fail counts would be lost.
slot() {
  local got; printf "$3" >| "$TMPD/slot.md"; got="$(bash "$LIB" captured-output "$TMPD/slot.md")"
  if { [ "$2" = yes ] && [ -n "$got" ]; } || { [ "$2" = no ] && [ -z "$got" ]; }; then pass "$1"
  else fail "$1 (want $2, captured: $(printf '%s' "$got" | tr '\n' '|'))"; fi
}
slot "indented output lines that look like fields stay output" yes 'Output:\n  Results: 12 passed, 0 failed\n  Verdict: PASS (printed by the test)\nExit: 0\n'
slot "a '### Output' heading slot is read" yes '### Output\n\nt: all 3 passed\n\n## Next\n'
slot "any parenthetical and any case is a slot" yes 'output (last 20 lines):\nt: all 3 passed\n'
slot "an empty slot then a prose paragraph is not output" no 'Output:\n\nThe run passed, trust me.\n'
slot "a blank line before the slot's own fence is fine" yes 'Output:\n\n```\nt: all 3 passed\n```\n'
for v in none n/a ... '(see above)' 'see the run log'; do
  slot "filler '$v' is not output" no "Output: $v\n"
done
slot "a fenced run block with raw output after Exit: counts" yes '```\nCommand: bash t.sh\nExit: 0\n[1] case one\n  ok: it held\nt: all 1 passed\n```\n'
slot "a fenced run block of fields alone holds nothing" no '```\nCommand: bash t.sh\nExit: 0\nVerdict: PASS\n```\n'
slot "a blank line ends a filled slot" yes 'Output:\nt: all 3 passed\n\nunrelated prose\n'
printf 'Output:\nt: all 3 passed\n```\nnot output\n```\n' >| "$TMPD/slot.md"; OUT="$(bash "$LIB" captured-output "$TMPD/slot.md")"
[ "$OUT" = "t: all 3 passed" ] && pass "a later unrelated fence ends the slot" || fail "a later fence joined the slot: $OUT"

echo "=== gate: a stateful proof's recorded run needs captured output too ==="
stateful() { # stateful <name> -- proof body on stdin
  local d; d="$(new_repo "$1")"
  mkdir -p "$d/deploy"; echo "rollout" > "$d/deploy/rollout.sh"
  { echo "# Verification"; cat; echo "- rollback: git revert HEAD"; } > "$d/docs/verification/vf.md"
  printf '%s\n' "$d"
}
D="$(stateful st-typed <<'EOF'
- Command: `bash deploy/rollout.sh --dry-run`
- Exit: 0
EOF
)"
blocks "stateful: a typed Command:/Exit: with no output is BLOCKED" "$D"
D="$(stateful st-output <<'EOF'
- Command: `bash deploy/rollout.sh --dry-run`
- Exit: 0
- Output (excerpt):
  ```
  dry-run: 3 hosts would roll
  ```
EOF
)"
accepts "stateful: a recorded run with captured output is accepted" "$D"

echo "=== verbs the land step reads ==="
D="$(behavioral verbs <<'EOF'
Exit: 0
Output:
line one
line two
Verdict: PASS
EOF
)"
OUT="$(bash "$LIB" captured-output "$D/docs/verification/vf.md")"
[ "$OUT" = $'line one\nline two' ] && pass "captured-output prints the Output: lines" || fail "captured-output printed: $OUT"
OUT="$(bash "$LIB" proof-files "$D" "$(git -C "$D" rev-parse HEAD)")"
[ "$OUT" = "docs/verification/vf.md" ] && pass "proof-files lists the branch's proof file" || fail "proof-files printed: $OUT"

echo "=== producers emit the Output: slot ==="
SK="$(bash "$KIT/lib/gate/proof-gate.sh" skeleton vf "add a retry to the fetch client")"
case "$SK" in *$'\nOutput:'*) pass "skeleton carries an Output: slot" ;; *) fail "skeleton has no Output: slot" ;; esac
printf '%s\n' "$SK" | grep -qiE 'screenshot|GIF' && pass "skeleton names the screenshot or GIF alternative" || fail "skeleton does not name the image alternative"
D="$(new_repo skel)"; echo "changed" >> "$D/lib/thing.sh"
{ printf '%s\n' "$SK"; echo "NEGATIVE CONTROL"; echo "Exit: 0"; echo "Verdict: PASS"; } > "$D/docs/verification/vf.md"
blocks "an unfilled skeleton does not pass the gate" "$D"

D="$(new_repo negctl)"
printf 'echo "greeting: hello"\n' > "$D/lib/thing.sh"
printf 'bash lib/thing.sh | grep hello && echo "test-thing: all 1 passed"\n' > "$D/test.sh"
git -C "$D" add -A; git -C "$D" commit -qm "feat: greet"
NOUT="$(bash "$KIT/lib/gate/negctl.sh" "$D" "bash test.sh" "sed -i.bak s/hello/bye/ lib/thing.sh && rm -f lib/thing.sh.bak" 2>&1)"; NRC=$?
if [ "$NRC" -eq 0 ] && printf '%s\n' "$NOUT" | grep -q '^Output:$' && printf '%s\n' "$NOUT" | grep -q 'test-thing: all 1 passed'; then
  pass "negctl prints an Output: slot holding the run's own output"
else fail "negctl rc=$NRC out=$NOUT"; fi
echo "more behavior" >> "$D/lib/thing.sh"
printf '# Verification\n%s\n' "$NOUT" > "$D/docs/verification/vf.md"
accepts "a proof made of negctl's own block passes the gate" "$D"
printf 'true\n' > "$D/test.sh"; printf 'exit 1\n' > "$D/lib/thing.sh"; git -C "$D" add -A; git -C "$D" commit -qm "test: silent"
printf 'grep -q hello lib/thing.sh\n' > "$D/test.sh"; printf 'hello\n' > "$D/lib/thing.sh"; git -C "$D" commit -qam "test: silent check"
NOUT="$(bash "$KIT/lib/gate/negctl.sh" "$D" "bash test.sh" "printf 'bye\\n' > lib/thing.sh" 2>&1)"
echo "more" >> "$D/lib/thing.sh"
printf '# Verification\n%s\n' "$NOUT" > "$D/docs/verification/vf.md"
blocks "negctl on a silent test: its own lines are not read as output" "$D"

echo "=== land: the PR body is built from the proof file ==="
PROOF_LEDGER_SH="$LIB"
# shellcheck source=lib/wrap/wrap-land.sh
source "$KIT/lib/wrap/wrap-land.sh"
D="$(new_repo body)"; BASE="$(git -C "$D" rev-parse HEAD)"
echo "changed behavior" >> "$D/lib/thing.sh"
printf 'PNG' > "$D/docs/verification/shot.png"
cat > "$D/docs/verification/vf.md" <<'EOF'
# Verification
NEGATIVE CONTROL
Command: `bash lib/thing.sh`
Exit: 0
Output:
test-thing: all 12 passed
Verdict: PASS
![after](shot.png)
![gone](missing.png)
EOF
git -C "$D" add -A; git -C "$D" commit -qm "feat: the change"
SHA="$(git -C "$D" rev-parse HEAD)"
BODY="$(_land_proof_body "$D" "$BASE" "feat: the change" "$SHA" "git@github.com:acme/widget.git")"
[ "$(printf '%s\n' "$BODY" | sed -n 1p)" = "feat: the change" ] && pass "body opens with the one-line summary" || fail "body first line: $(printf '%s\n' "$BODY" | sed -n 1p)"
printf '%s\n' "$BODY" | grep -qx '## Proof of done' && pass "body carries the '## Proof of done' section" || fail "body has no proof section"
printf '%s\n' "$BODY" | grep -qx 'test-thing: all 12 passed' && pass "body carries the captured output" || fail "body lost the captured output"
printf '%s\n' "$BODY" | grep -qF "![after](https://github.com/acme/widget/blob/$SHA/docs/verification/shot.png?raw=true)" \
  && pass "a relative image link is pinned to the head sha" || fail "image link not rewritten: $(printf '%s\n' "$BODY" | grep after)"
printf '%s\n' "$BODY" | grep -qF '![gone](missing.png)' && pass "a dangling image link is left as written" || fail "dangling link was rewritten"
BLOCK="$(_land_proof_block "$D" "$BASE" "https://github.com/acme/widget/pull/7")"
case "$BLOCK" in "PROOF OF DONE"*"docs/verification/vf.md"*"https://github.com/acme/widget/pull/7"*"test-thing: all 12 passed"*) pass "the PROOF OF DONE block names the file, the PR and the output" ;;
  *) fail "PROOF OF DONE block: $BLOCK" ;; esac

{ echo "NEGATIVE CONTROL"; echo "Exit: 0"; echo "Output:"; echo '```'; i=0; while [ "$i" -lt 3000 ]; do echo "line $i of a very long captured run"; i=$((i+1)); done; echo "Verdict: PASS"; } \
  > "$D/docs/verification/vf.md"
git -C "$D" commit -qam "docs: long proof"
BODY="$(_land_proof_body "$D" "$BASE" "feat: the change" "$SHA" "https://github.com/acme/widget")"
if [ "${#BODY}" -lt 50000 ] && printf '%s\n' "$BODY" | tail -1 | grep -qF "https://github.com/acme/widget/blob/$SHA/docs/verification/vf.md"; then
  pass "a long proof is cut under the body limit with a pointer to the file (${#BODY} chars)"
else fail "long body is ${#BODY} chars, tail: $(printf '%s\n' "$BODY" | tail -1)"; fi
[ $(( $(printf '%s\n' "$BODY" | grep -c '^```') % 2 )) -eq 0 ] && pass "a cut inside a fence closes the fence before the pointer" || fail "the cut left a fence open"

D="$(new_repo nobody)"; BASE="$(git -C "$D" rev-parse HEAD)"
echo "changed" >> "$D/lib/thing.sh"; git -C "$D" commit -qam "feat: no proof"
[ -z "$(_land_proof_body "$D" "$BASE" "feat: no proof" "$(git -C "$D" rev-parse HEAD)" "https://github.com/acme/widget")" ] \
  && pass "no proof file on the branch builds no body" || fail "a body was built with no proof file"
[ -z "$(_land_proof_block "$D" "$BASE" "https://github.com/acme/widget/pull/8")" ] \
  && pass "no proof file on the branch prints no block" || fail "a block was printed with no proof file"

echo
[ "$fails" -eq 0 ] && { echo "test-proof-captured-output: all $total passed"; exit 0; } || { echo "test-proof-captured-output: $fails FAILED of $total"; exit 1; }
