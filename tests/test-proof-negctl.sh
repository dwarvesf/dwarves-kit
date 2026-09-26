#!/usr/bin/env bash
# lib/gate/negctl.sh (and the proof-ledger.sh `negctl` forwarder): the mechanised negative
# control. Asserts on throwaway git repos: a real mutation goes GREEN -> RED -> GREEN and
# prints the block check() reads; a vacuous mutation is FAIL; a dirty tree is REFUSED
# before anything runs; the restore covers staged edits and paths with spaces; untracked
# leftovers are a FAIL; a FAIL block never satisfies check(); the tree is clean after
# every case. Battery findings 2026-09-04 (verifier N2, security 1-2, reviewer H1/M3/M4).
#
# Run: bash tests/test-proof-negctl.sh   Pass: "test-proof-negctl: all N passed", exit 0.
set -uo pipefail
export KIT_CONFIG_OPERATOR="$(cd "$(dirname "$0")/.." && pwd)/tests/fixtures/gates-on"   # quality gates are opt-in; this suite exercises them ON
DIR="$(cd "$(dirname "$0")/.." && pwd)"
NC="$DIR/lib/gate/negctl.sh"
PL="$DIR/lib/gate/proof-ledger.sh"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkrepo() {  # $1 = dir; a lib with add() and a test that needs add 2 2 = 4
  mkdir -p "$1/sub dir"
  printf 'add() { echo $(( $1 + $2 )); }\n' > "$1/lib.sh"
  printf 'mul() { echo $(( $1 * $2 )); }\n' > "$1/sub dir/lib file.sh"
  printf '#!/usr/bin/env bash\nsource ./lib.sh\nsource "./sub dir/lib file.sh"\n[ "$(add 2 2)" = "4" ] && [ "$(mul 2 3)" = "6" ]\n' > "$1/test.sh"
  # fixtures for the restore-set-recompute cases (T4a/T4b/T4c/T4d): a tracked placeholder a
  # test-cmd can overwrite, and four scripts that each write a tracked file only under the
  # condition their case needs (never unconditionally, so the other cases stay unaffected).
  printf 'orig\n' > "$1/fixture.md"
  printf '#!/usr/bin/env bash\nsource ./lib.sh\n[ "$(add 2 2)" = "4" ] && exit 0\necho "captured under mutation" > fixture.md\nexit 1\n' > "$1/test-sidewrite.sh"
  printf '#!/usr/bin/env bash\nsource ./lib.sh\n[ "$(add 2 2)" = "4" ] && exit 0\necho "new" > new-file.txt\ngit add new-file.txt\nexit 1\n' > "$1/test-newfile.sh"
  # Counter-and-fixture driven, deliberately independent of lib.sh/add(): call 1 (the
  # baseline green run) does nothing; call 2 (red-loop attempt 1, under an INERT mutation)
  # is green but writes fixture.md; call 3+ (attempt 2+) goes red ONLY because fixture.md
  # still carries that leftover -- an artifact of attempt 1's own side write, not evidence
  # the mutation did anything (the shape probe A found).
  printf '#!/usr/bin/env bash\nn=$(cat "$RETRY_COUNTER" 2>/dev/null || echo 0); n=$(( n + 1 )); printf %%s "$n" > "$RETRY_COUNTER"\n[ "$n" -eq 1 ] && exit 0\nif [ "$n" -eq 2 ]; then echo "leftover from a green retry attempt" > fixture.md; exit 0; fi\ngrep -q leftover fixture.md 2>/dev/null && exit 1\nexit 0\n' > "$1/test-retrywriter.sh"
  printf '#!/usr/bin/env bash\nsource ./lib.sh\necho "baseline write" > fixture.md\n[ "$(add 2 2)" = "4" ]\n' > "$1/test-basewrite.sh"
  git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -q -m seed
}

# Reconstructs a NAIVE (pre-fix) restore(): one unfiltered `git checkout HEAD --` over the
# mutation's own set AND everything beyond it, no HEAD-existence partition. Used only by T4b's
# negative control, to reproduce the whole-call-abort regression the real fix prevents. Anchors
# on the stable `restore() {` / `trap restore EXIT` lines, not on interior formatting.
mk_naive_negctl() {  # $1 = output path
  open_ln=$(grep -n '^restore() {$' "$NC" | head -1 | cut -d: -f1)
  trap_ln=$(grep -n '^trap restore EXIT$' "$NC" | head -1 | cut -d: -f1)
  head -n $((open_ln - 1)) "$NC" > "$1"
  cat >> "$1" <<'NAIVE'
restore() {
  [ "$restore_done" -eq 1 ] && return 0
  restore_done=1
  _beyond_mutate_set
  full=("${restore_files[@]}")
  if [ "${#beyond[@]}" -gt 0 ]; then full+=("${beyond[@]}"); fi
  if [ "${#full[@]}" -gt 0 ]; then
    git -C "$root" checkout -q HEAD -- "${full[@]}" 2>/dev/null || fail "restore failed: git checkout HEAD -- ${full[*]}"
  fi
}
NAIVE
  tail -n +"$trap_ln" "$NC" >> "$1"
}
clean() { [ -z "$(git -C "$1" status --porcelain --untracked-files=all)" ]; }
REPO="$TMP/r"; mkrepo "$REPO"

echo "[1] real mutation: GREEN -> RED -> GREEN, PASS block, tree clean after"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && grep -qi 'Negative control' <<<"$OUT" \
   && grep -q '^Exit: 0 (green before' <<<"$OUT" && grep -qE '^Exit: [1-9][0-9]* \(under mutation' <<<"$OUT" && clean "$REPO"; then
  ok "PASS block printed, tree clean"
else no "rc=$RC tree=$(git -C "$REPO" status --porcelain) out=$OUT"; fi

echo "[2] the proof-ledger.sh negctl verb forwards to the same script"
OUT="$(bash "$PL" negctl "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && clean "$REPO"; then ok "forwarder works"; else no "rc=$RC out=$OUT"; fi

echo "[3] vacuous mutation (test stays green) is FAIL, exit 1, tree restored"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "printf '\n# comment\n' >> lib.sh" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'Verdict: FAIL: test stayed green' <<<"$OUT" && clean "$REPO"; then ok "vacuous control rejected"; else no "rc=$RC out=$OUT"; fi

echo "[4] dirty tracked file (unstaged AND staged): REFUSED before any step, exit 2, edits survive"
echo "# uncommitted work" >> "$REPO/lib.sh"
OUT1="$(bash "$NC" "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh" 2>&1)"; RC1=$?
git -C "$REPO" add lib.sh
OUT2="$(bash "$NC" "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh" 2>&1)"; RC2=$?
if [ "$RC1" -eq 2 ] && [ "$RC2" -eq 2 ] && grep -q 'REFUSED' <<<"$OUT1$OUT2" && grep -q '# uncommitted work' "$REPO/lib.sh" && ! grep -q 'Command:' <<<"$OUT1$OUT2"; then
  ok "refused both ways, uncommitted line survives"
else no "rc=$RC1/$RC2 out=$OUT1 // $OUT2"; fi
git -C "$REPO" reset -q --hard HEAD

echo "[5] mutation that changes nothing tracked is FAIL with its own reason (first failure wins)"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "true" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'changed no tracked file' <<<"$OUT" && ! grep -q 'Verdict: FAIL: test stayed green' <<<"$OUT"; then ok "no-op mutation named as such"; else no "rc=$RC out=$OUT"; fi

echo "[6] a path with spaces is restored (verifier N2): mutate 'sub dir/lib file.sh'"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "sed -i.bak 's/\*/+/' 'sub dir/lib file.sh' && rm -f 'sub dir/lib file.sh.bak'" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && clean "$REPO"; then ok "space-named path restored, PASS"; else no "rc=$RC tree=$(git -C "$REPO" status --porcelain) out=$OUT"; fi

echo "[7] a STAGED mutation is in the restore set (security 1)"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak && git add lib.sh" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Changed: lib.sh' <<<"$OUT" && clean "$REPO"; then ok "staged edit seen and restored"; else no "rc=$RC tree=$(git -C "$REPO" status --porcelain) out=$OUT"; fi

echo "[8] a mutation that leaves an untracked file behind is FAIL, never PASS (security 2, reviewer M4)"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh" 2>&1)"; RC=$?   # .bak left behind
rm -f "$REPO/lib.sh.bak"
if [ "$RC" -ne 0 ] && grep -q 'tree differs from the pre-run snapshot' <<<"$OUT" && grep -q 'Delta: .*lib.sh.bak' <<<"$OUT" && ! grep -q '^Verdict: PASS' <<<"$OUT"; then
  ok "untracked leftover named in the verdict"
else no "rc=$RC out=$OUT"; fi

echo "[9] a negctl FAIL block does NOT satisfy proof-ledger check() (reviewer H1)"
PR="$TMP/p"; mkrepo "$PR"
# The base ref must be the branch `git init` actually made. Hardcoding `master` here read as
# a passing gate on any machine whose init.defaultBranch is `main`: check() fails open on an
# unresolvable base by contract, so BOTH the FAIL block and the PASS block returned 0 and the
# assertion never reached the gate at all. Ask the repo for its own default branch instead.
BASE="$(git -C "$PR" symbolic-ref --short HEAD)"
git -C "$PR" checkout -q -b feat
printf 'x\n' >> "$PR/lib.sh"; mkdir -p "$PR/docs/verification"
{ echo "# proof"; echo "Command: bash test.sh"; echo "Exit: 0 (green before mutation)"; echo "## Negative control (negctl)"; echo "Verdict: FAIL: test stayed green under the mutation (the check is vacuous)"; } > "$PR/docs/verification/x.md"
git -C "$PR" add -A && git -C "$PR" -c user.name=t -c user.email=t@t commit -q -m "feat: change"
bash "$PL" check "$PR" "$BASE" >/dev/null 2>&1; RC_FAIL=$?
sed -i.bak 's/^Verdict: FAIL.*/Verdict: PASS/' "$PR/docs/verification/x.md" && rm -f "$PR/docs/verification/x.md.bak"
git -C "$PR" -c user.name=t -c user.email=t@t commit -q -am "proof pass"
bash "$PL" check "$PR" "$BASE" >/dev/null 2>&1; RC_PASS=$?
if [ "$RC_FAIL" -ne 0 ] && [ "$RC_PASS" -eq 0 ]; then ok "FAIL block blocked (rc=$RC_FAIL), PASS block accepted"; else no "check rc FAIL-block=$RC_FAIL PASS-block=$RC_PASS"; fi

echo "[9b] an unresolvable base fails OPEN, and that is not a gate pass"
# Pins the behaviour that hid [9] for four commits. check() returns 0 on a base that is not a
# commit (documented fail-open: a gate bug must never block unrelated work). Naming it here
# stops the next reader mistaking a disarmed gate for a satisfied one. hooks/ship-gate.sh
# resolves the base through merge-base and only calls check() with a real commit, so the
# fail-open is unreachable from the shipping path.
bash "$PL" check "$PR" no-such-branch-here >/dev/null 2>&1; RC_OPEN=$?
if [ "$RC_OPEN" -eq 0 ]; then ok "unresolvable base returns 0 by contract, gate never ran"; else no "expected fail-open 0, got $RC_OPEN"; fi

echo "[10] usage on missing args names the verb (non-vacuous: not the unknown-verb 64)"
OUT="$(bash "$NC" "$REPO" 2>&1)"; RC=$?
if [ "$RC" -eq 64 ] && grep -q 'usage: negctl.sh <root>' <<<"$OUT"; then ok "exit 64 with negctl usage"; else no "rc=$RC out=$OUT"; fi

echo
# --- NEGCTL_RED_ATTEMPTS: a PROBABILISTIC test must still be provable ---------------
# `run_test` was treated as deterministic, so a flaky suite could come back green under a
# REAL mutation and negctl called the control vacuous. The fixture below is deterministic,
# not actually flaky: under mutation it is green on the first red-step run and red from the
# second, which is the shape a flake has without the coin flip.
FREPO="$TMP/flaky"; mkrepo "$FREPO"
export FLAKY_COUNTER="$TMP/flaky-counter"
cat > "$FREPO/flaky.sh" <<'FLAKY'
#!/usr/bin/env bash
source ./lib.sh
[ "$(add 2 2)" = "4" ] && exit 0          # unmutated: green on every run
n=$(cat "$FLAKY_COUNTER" 2>/dev/null || echo 0); n=$(( n + 1 )); printf '%s' "$n" > "$FLAKY_COUNTER"
[ "$n" -ge 2 ] && exit 1 || exit 0        # mutated: green once, then red
FLAKY
git -C "$FREPO" add -A && git -C "$FREPO" -c user.name=t -c user.email=t@t commit -q -m flaky
MUT="sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak"

echo "[11] a flaky test defeats the single-attempt control (documents the gap)"
: > "$FLAKY_COUNTER"
OUT="$(bash "$NC" "$FREPO" "bash flaky.sh" "$MUT" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'Verdict: FAIL: test stayed green under the mutation (the check is vacuous)$' <<<"$OUT" && clean "$FREPO"; then
  ok "one attempt calls a real mutation vacuous, and the default wording is unchanged"
else no "rc=$RC out=$OUT"; fi

echo "[12] NEGCTL_RED_ATTEMPTS=3 catches the same real mutation"
: > "$FLAKY_COUNTER"
OUT="$(NEGCTL_RED_ATTEMPTS=3 bash "$NC" "$FREPO" "bash flaky.sh" "$MUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && grep -q 'attempt 2 of 3' <<<"$OUT" && clean "$FREPO"; then
  ok "retry reaches RED and names which attempt bit"
else no "rc=$RC out=$OUT"; fi

echo "[13] retries never manufacture RED: a vacuous mutation stays FAIL at 5 attempts"
OUT="$(NEGCTL_RED_ATTEMPTS=5 bash "$NC" "$REPO" "bash test.sh" "printf '\n# comment\n' >> lib.sh" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'on all 5 attempts' <<<"$OUT" && clean "$REPO"; then
  ok "a genuinely vacuous mutation is still rejected"
else no "rc=$RC out=$OUT"; fi

echo "[14] the default run is byte-identical: no attempt wording at all"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "$MUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Exit: [1-9][0-9]* (under mutation, RED expected)$' <<<"$OUT" && ! grep -qi 'attempt' <<<"$OUT"; then
  ok "unset NEGCTL_RED_ATTEMPTS prints the original lines"
else no "rc=$RC out=$OUT"; fi

echo "[15] a non-numeric or zero NEGCTL_RED_ATTEMPTS is REJECTED, never coerced to 1"
OUT="$(NEGCTL_RED_ATTEMPTS=two bash "$NC" "$REPO" "bash test.sh" "$MUT" 2>&1)"; RC=$?
OUT0="$(NEGCTL_RED_ATTEMPTS=0 bash "$NC" "$REPO" "bash test.sh" "$MUT" 2>&1)"; RC0=$?
if [ "$RC" -eq 64 ] && grep -q 'NEGCTL_RED_ATTEMPTS' <<<"$OUT" && [ "$RC0" -eq 64 ] && grep -q 'NEGCTL_RED_ATTEMPTS' <<<"$OUT0"; then
  ok "both bad values exit 64 naming the variable"
else no "rc=$RC rc0=$RC0 out=$OUT out0=$OUT0"; fi

echo
# --- --base-ref mode: prove the control against a ref, never touch the working tree -----
# test.sh is IDENTICAL across both commits (the real shape: the assertion doesn't change,
# only lib.sh does), so running it against the base ref proves the OLD implementation,
# not a different check.
BREPO="$TMP/baseref"
mkdir -p "$BREPO"
git -C "$BREPO" init -q
printf 'add() { echo $(( $1 * $2 )); }\n' > "$BREPO/lib.sh"   # BUG: multiplies instead of adds
printf '#!/usr/bin/env bash\nsource ./lib.sh\n[ "$(add 3 4)" = "7" ]\n' > "$BREPO/test.sh"
git -C "$BREPO" add -A && git -C "$BREPO" -c user.name=t -c user.email=t@t commit -q -m buggy
BASE_SHA="$(git -C "$BREPO" rev-parse HEAD)"
printf 'add() { echo $(( $1 + $2 )); }\n' > "$BREPO/lib.sh"   # the fix
git -C "$BREPO" -c user.name=t -c user.email=t@t commit -q -am fix
HEAD_SHA="$(git -C "$BREPO" rev-parse HEAD)"

echo "[16] base-ref mode: RED at the base ref is PASS, tree untouched, dirty checkout not refused"
echo "# unrelated foreign dirty file" >> "$BREPO/lib.sh"   # simulates another session's uncommitted work
BEFORE="$(git -C "$BREPO" status --porcelain)"
OUT="$(bash "$NC" --base-ref "$BASE_SHA" "$BREPO" "bash test.sh" 2>&1)"; RC=$?
AFTER="$(git -C "$BREPO" status --porcelain)"
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && grep -qi 'Negative control' <<<"$OUT" \
   && grep -qE '^Exit: [1-9][0-9]* \(base ref, RED expected\)$' <<<"$OUT" && [ "$BEFORE" = "$AFTER" ]; then
  ok "base ref RED accepted, foreign dirty file untouched and never refused"
else no "rc=$RC before=[$BEFORE] after=[$AFTER] out=$OUT"; fi
git -C "$BREPO" checkout -q -- lib.sh   # drop the simulated foreign edit

echo "[17] base-ref mode: GREEN at the given ref is FAIL, proves nothing (a mistaken/no-op base)"
OUT="$(bash "$NC" --base-ref "$HEAD_SHA" "$BREPO" "bash test.sh" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'Verdict: FAIL: the check passed at' <<<"$OUT"; then
  ok "green ref rejected as vacuous"
else no "rc=$RC out=$OUT"; fi

echo "[18] base-ref mode: bad ref exits 64, missing args name the usage"
OUT="$(bash "$NC" --base-ref no-such-ref "$BREPO" "bash test.sh" 2>&1)"; RC=$?
OUT2="$(bash "$NC" --base-ref "$BASE_SHA" "$BREPO" 2>&1)"; RC2=$?
if [ "$RC" -eq 64 ] && grep -q "does not resolve to a commit" <<<"$OUT" \
   && [ "$RC2" -eq 64 ] && grep -q 'usage: negctl.sh --base-ref' <<<"$OUT2"; then
  ok "bad ref and missing args both exit 64"
else no "rc=$RC rc2=$RC2 out=$OUT out2=$OUT2"; fi

echo
# --- restore-set recompute: side effects the RED run itself writes (T4a/b/c/d) -----------
# negctl used to freeze its restore set right after mutate_cmd, before test-cmd's RED run
# executed, so a tracked fixture write during that run (or a green retry attempt's own
# leftover) never got restored. #784 (test-pitch.sh) hit this for real. These four cases and
# their per-mechanism negative controls prove the recompute, the HEAD-existence partition, and
# the retry-loop guard are each independently load-bearing.

echo "[19] T4a: a tracked fixture overwritten only while RED restores cleanly (side effect)"
OUT="$(bash "$NC" "$REPO" "bash test-sidewrite.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && grep -q '^Side effect: fixture.md$' <<<"$OUT" && clean "$REPO"; then
  ok "side-effect fixture restored, Side effect: line printed, tree clean"
else no "rc=$RC tree=$(git -C "$REPO" status --porcelain) out=$OUT"; fi

echo "[20] T4a negative control: disable the side-effect restore -> reverts to tree-differs FAIL"
NC_T4A="$TMP/negctl-t4a.sh"
ln=$(grep -Fn '  if [ "${#beyond[@]}" -gt 0 ]; then' "$NC" | head -1 | cut -d: -f1)
sed "${ln}s/.*/  if false; then/" "$NC" > "$NC_T4A"
OUT="$(bash "$NC_T4A" "$REPO" "bash test-sidewrite.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
git -C "$REPO" checkout -q -- fixture.md 2>/dev/null   # the mutated copy skipped this restore; clean up by hand
if [ "$RC" -ne 0 ] && grep -q 'tree differs from the pre-run snapshot' <<<"$OUT" && ! grep -q '^Verdict: PASS' <<<"$OUT"; then
  ok "without the side-effect restore, the same case reverts to FAIL"
else no "rc=$RC out=$OUT"; fi

echo "[21] T4b: a HEAD-absent side effect fails by name; MUTATE_SET's own file still restores"
OUT="$(bash "$NC" "$REPO" "bash test-newfile.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
LIBCLEAN="$(git -C "$REPO" diff --quiet HEAD -- lib.sh && echo yes || echo no)"
git -C "$REPO" reset -q HEAD -- new-file.txt 2>/dev/null; rm -f "$REPO/new-file.txt"
if [ "$RC" -ne 0 ] && grep -q 'cannot be restored' <<<"$OUT" && grep -q 'new-file.txt' <<<"$OUT" \
   && [ "$LIBCLEAN" = yes ] && ! grep -q '^Verdict: PASS' <<<"$OUT"; then
  ok "new file failed by name, lib.sh (MUTATE_SET) still restored"
else no "rc=$RC libclean=$LIBCLEAN out=$OUT"; fi

echo "[22] T4b negative control: the naive single-call restore aborts -- MUTATE_SET's own file NOT restored"
NC_T4B="$TMP/negctl-t4b.sh"
mk_naive_negctl "$NC_T4B"
OUT="$(bash "$NC_T4B" "$REPO" "bash test-newfile.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" 2>&1)"; RC=$?
LIBCLEAN="$(git -C "$REPO" diff --quiet HEAD -- lib.sh && echo yes || echo no)"
git -C "$REPO" checkout -q -- lib.sh 2>/dev/null
git -C "$REPO" reset -q HEAD -- new-file.txt 2>/dev/null; rm -f "$REPO/new-file.txt"
if [ "$RC" -ne 0 ] && [ "$LIBCLEAN" = no ]; then
  ok "without the HEAD-existence partition, the whole restore aborts and lib.sh stays mutated"
else no "rc=$RC libclean=$LIBCLEAN out=$OUT"; fi

export RETRY_COUNTER="$TMP/retry-counter"
echo "[23] T4c: a green retry attempt's own side write must not mask a vacuous mutation"
: > "$RETRY_COUNTER"
OUT="$(NEGCTL_RED_ATTEMPTS=3 bash "$NC" "$FREPO" "bash test-retrywriter.sh" "printf '\n# comment\n' >> lib.sh" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q 'retries are unsafe against a polluted tree' <<<"$OUT" && grep -q 'attempt 1 of 3' <<<"$OUT" \
   && ! grep -q '^Verdict: PASS$' <<<"$OUT" && clean "$FREPO"; then
  ok "a polluted green attempt stops retries instead of masking the vacuous mutation"
else no "rc=$RC out=$OUT"; fi

echo "[24] T4c negative control: without the retry guard, the vacuous mutation wrongly PASSes"
NC_T4C="$TMP/negctl-t4c.sh"
ln=$(grep -Fn '    if [ "${#beyond[@]}" -gt 0 ]; then' "$NC" | head -1 | cut -d: -f1)
sed "${ln}s/.*/    if false; then/" "$NC" > "$NC_T4C"
: > "$RETRY_COUNTER"
OUT="$(NEGCTL_RED_ATTEMPTS=3 bash "$NC_T4C" "$FREPO" "bash test-retrywriter.sh" "printf '\n# comment\n' >> lib.sh" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^Verdict: PASS$' <<<"$OUT" && clean "$FREPO"; then
  ok "without the guard, the polluted retry sequence wrongly reports PASS for a vacuous mutation"
else no "rc=$RC out=$OUT"; fi

echo "[25] T4d: a baseline side write is excluded from Changed, exact wording pinned"
OUT="$(bash "$NC" "$REPO" "bash test-basewrite.sh" "true" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && grep -q '^Changed: <no tracked file>$' <<<"$OUT" && grep -q 'changed no tracked file' <<<"$OUT" \
   && grep -q '^Baseline side write: fixture.md$' <<<"$OUT" && clean "$REPO"; then
  ok "baseline write excluded from Changed, exact wording preserved"
else no "rc=$RC out=$OUT"; fi

echo "[26] T4d negative control: without the BASELINE_DIFF subtraction, the baseline write is wrongly credited"
NC_T4D="$TMP/negctl-t4d.sh"
ln=$(grep -Fn '    if [ "${#baseline_diff[@]}" -gt 0 ] && _path_in "$f" "${baseline_diff[@]}"; then' "$NC" | head -1 | cut -d: -f1)
sed "${ln}s/.*/    if false; then/" "$NC" > "$NC_T4D"
OUT="$(bash "$NC_T4D" "$REPO" "bash test-basewrite.sh" "true" 2>&1)"; RC=$?
if grep -q '^Changed: fixture.md$' <<<"$OUT" && ! grep -q 'the mutation changed no tracked file' <<<"$OUT" && clean "$REPO"; then
  ok "without the subtraction, the baseline write is wrongly reported as the mutation's own change"
else no "rc=$RC out=$OUT"; fi

echo
# --- round 2: unified partition (MUTATE_SET can itself be HEAD-absent), signal-safe cleanup,
# and closing two coverage gaps a mutation pass found (stripping --no-renames and restoring
# the old early return both left the round-1 suite fully green) --------------------------

echo "[27] a git mv AS the mutation: both halves named, lib.sh restored, lib2.sh failed by name"
OUT="$(bash "$NC" "$REPO" "bash test.sh" "git mv lib.sh lib2.sh" 2>&1)"; RC=$?
git -C "$REPO" reset -q HEAD -- lib2.sh 2>/dev/null; rm -f "$REPO/lib2.sh"
if [ "$RC" -ne 0 ] && grep -q '^Changed: lib.sh, lib2.sh$' <<<"$OUT" && grep -q 'cannot be restored' <<<"$OUT" \
   && grep -q 'lib2.sh' <<<"$OUT" && [ -f "$REPO/lib.sh" ] && ! grep -q '^Verdict: PASS' <<<"$OUT"; then
  ok "both halves of a staged rename visible; lib.sh (MUTATE_SET) restored, lib2.sh failed by name"
else no "rc=$RC out=$OUT"; fi

echo "[28] negative control: without --no-renames, the rename hides lib.sh's deletion entirely"
NC_NORENAME="$TMP/negctl-norenames.sh"
sed 's/--no-renames //g' "$NC" > "$NC_NORENAME"
OUT="$(bash "$NC_NORENAME" "$REPO" "bash test.sh" "git mv lib.sh lib2.sh" 2>&1)"; RC=$?
git -C "$REPO" mv lib2.sh lib.sh 2>/dev/null   # the un-fixed copy never restores lib.sh at all; recover by hand
if grep -q '^Changed: lib2.sh$' <<<"$OUT" && ! grep -q 'lib.sh, lib2.sh' <<<"$OUT" && [ -f "$REPO/lib.sh" ]; then
  ok "without --no-renames, lib.sh's deletion is invisible to Changed (and to the restore set)"
else no "rc=$RC out=$OUT"; fi

echo "[29] an empty MUTATE_SET must not skip the side-effect restore (retry writer, ATTEMPTS=1)"
: > "$RETRY_COUNTER"
OUT="$(bash "$NC" "$REPO" "bash test-retrywriter.sh" "true" 2>&1)"; RC=$?
if grep -q '^Side effect: fixture.md$' <<<"$OUT" && clean "$REPO"; then
  ok "the side-effect restore ran even though the mutation's own set was empty"
else no "rc=$RC out=$OUT"; fi

echo "[30] negative control: restoring the old early return leaves the side effect dirty"
NC_T2REG="$TMP/negctl-t2reg.sh"
ln=$(grep -Fn '  restore_done=1' "$NC" | head -1 | cut -d: -f1)
sed "${ln}s/.*/  restore_done=1; [ \"\${#restore_files[@]}\" -gt 0 ] || return 0/" "$NC" > "$NC_T2REG"
: > "$RETRY_COUNTER"
OUT="$(bash "$NC_T2REG" "$REPO" "bash test-retrywriter.sh" "true" 2>&1)"; RC=$?
DIRTY="$(git -C "$REPO" status --porcelain)"
git -C "$REPO" checkout -q -- fixture.md 2>/dev/null   # the mutated copy skipped this restore; clean up by hand
if [ -n "$DIRTY" ] && grep -q 'fixture.md' <<<"$DIRTY"; then
  ok "with the early return back, an empty MUTATE_SET leaves the side effect dirty"
else no "rc=$RC dirty=[$DIRTY] out=$OUT"; fi

echo "[31] SIGINT mid-checkout does not leave the tree dirty (restore ignores it while cleaning up)"
# A slow-git shim, `checkout` only, so the interrupt has a wide, deterministic window to land
# in without slowing any other git call in the run. Backgrounded under job control (`set -m`)
# so its PID is also its process group, letting one `kill -INT -$PID` reach the whole tree
# the way a real terminal Ctrl-C would (negctl.sh itself and the shimmed git child alike).
GITSHIM="$TMP/gitshim"; mkdir -p "$GITSHIM"
printf '#!/usr/bin/env bash\ncase " $* " in\n  *" checkout "*) sleep 2 ;;\nesac\nexec /usr/bin/git "$@"\n' > "$GITSHIM/git"
chmod +x "$GITSHIM/git"
SIGREPO="$TMP/sigrepo"; mkrepo "$SIGREPO"
(
  set -m
  PATH="$GITSHIM:$PATH" bash "$NC" "$SIGREPO" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" \
    > "$TMP/sigint-out.txt" 2>&1 &
  PID=$!
  sleep 1.0
  kill -INT -$PID 2>/dev/null
  wait $PID
)
OUT="$(cat "$TMP/sigint-out.txt")"
if grep -q '^Verdict: PASS$' <<<"$OUT" && clean "$SIGREPO"; then
  ok "checkout survives a SIGINT mid-restore, tree stays clean"
else no "out=$OUT tree=$(git -C "$SIGREPO" status --porcelain)"; fi

echo "[32] negative control: without the signal block, the same SIGINT leaves lib.sh dirty"
NC_T2SIG="$TMP/negctl-t2sig.sh"
ln=$(grep -Fn "  trap '' INT TERM HUP" "$NC" | head -1 | cut -d: -f1)
sed "${ln}s/.*/  :/" "$NC" > "$NC_T2SIG"
SIGREPO2="$TMP/sigrepo2"; mkrepo "$SIGREPO2"
(
  set -m
  PATH="$GITSHIM:$PATH" bash "$NC_T2SIG" "$SIGREPO2" "bash test.sh" "sed -i.bak 's/+/-/' lib.sh && rm -f lib.sh.bak" \
    > "$TMP/sigint-out2.txt" 2>&1 &
  PID=$!
  sleep 1.0
  kill -INT -$PID 2>/dev/null
  wait $PID
)
DIRTY="$(git -C "$SIGREPO2" status --porcelain)"
git -C "$SIGREPO2" checkout -q -- lib.sh 2>/dev/null   # the mutated copy never finished restoring; clean up by hand
if [ -n "$DIRTY" ] && grep -q 'lib.sh' <<<"$DIRTY"; then
  ok "without the trap, the interrupted checkout leaves lib.sh mutated"
else no "dirty=[$DIRTY]"; fi

if [ "$fail" -gt 0 ]; then echo "test-proof-negctl: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-proof-negctl: all $pass passed"
