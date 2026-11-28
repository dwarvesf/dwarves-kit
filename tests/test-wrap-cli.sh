#!/usr/bin/env bash
# test-wrap-cli.sh -- the help, usage and resolver cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh lib/wrap/wrap-ship.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== help and usage ==="
# ===========================================================================
out="$("$WRAP" --help 2>&1)"; rc=$?
chk "--help exits 0" "$rc"
for verb in scan session apply sweep merge start log default-branch knowledge-root stage deploy-wait rebase; do
  chk_has "--help names $verb" "$out" "$verb"
done
for verb in scan session apply sweep merge land start ship log default-branch knowledge-root follow-mode deploy-wait stage rebase adopt flick-7b; do
  for hf in --help -h; do
    out="$("$WRAP" "$verb" "$hf" 2>&1 </dev/null)"; rc=$?
    chk "$verb $hf exits 0" "$rc"
    chk_has "$verb $hf prints its usage" "$out" "wrap.sh $verb"
  done
done
out="$("$WRAP" sweep 2>&1)"; rc=$?
chk "sweep with no root and empty wrap.sweep_roots exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "sweep error names wrap.sweep_roots" "$out" "wrap.sweep_roots"
out="$("$WRAP" scan 2>&1)"; rc=$?
chk "scan with no argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" apply 2>&1)"; rc=$?
chk "apply with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" merge 2>&1)"; rc=$?
chk "merge with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
# A usage refusal keeps its usage line and exit 64, then one hint line names the right form.
HR="$TMPD/hint-roots"; mkdir -p "$HR/hintrepo" "$HR/plain"; git -C "$HR/hintrepo" init -q
mkdir -p "$TMPD/hintcfg"; printf '[wrap]\nroots = "%s"\n' "$HR" > "$TMPD/hintcfg/kit.toml"
HRP="$(cd "$HR/hintrepo" && pwd -P)"  # git prints the physical path
out="$(cd "$HR/hintrepo" && "$WRAP" apply --worktrees 2>&1)"
chk_has "apply with no repo keeps the usage line" "$out" "usage: wrap.sh apply"
chk_has "apply with no repo names this checkout's repo" "$out" "never defaults to the current directory. This checkout's repo is $HRP"
git -C "$HR/hintrepo" commit -q --allow-empty -m init
git -C "$HR/hintrepo" worktree add -q -b hint-wt "$HR/hint-wt" 2>/dev/null
mkdir -p "$HR/otherrepo"; git -C "$HR/otherrepo" init -q
out="$(cd "$HR/otherrepo" && "$WRAP" apply --own "$HR/hint-wt" 2>&1)"
chk_has "apply --own with no repo names the worktree's repo, not the cwd's" "$out" "The --own worktree's repo is $HRP"
chk "apply --own with no repo never names the cwd's repo" "$(grep -q 'otherrepo' <<<"$out"; [ $? -eq 1 ]; echo $?)"
out="$(cd "$HR/plain" && "$WRAP" merge 2>&1)"
chk_has "merge with no repo, outside a checkout, still says why" "$out" "wrap.sh merge: no <repo> given; it never defaults to the current directory"
out="$("$WRAP" merge "$HR/hintrepo" "$HR/plain" 2>&1)"
chk "merge with two repos prints no no-repo hint" "$(grep -q 'no <repo> given' <<<"$out"; [ $? -eq 1 ]; echo $?)"
out="$(KIT_CONFIG_OPERATOR="$TMPD/hintcfg" "$WRAP" start hintrepo feat/x 2>&1)"; rc=$?
chk "start with a repo name exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "start with a repo name points at its path" "$out" "did you mean $HR/hintrepo?"
out="$(KIT_CONFIG_OPERATOR="$TMPD/hintcfg" "$WRAP" merge --pr 1 nosuchrepo 2>&1)"
chk_has "merge with an unknown name says <repo> is a path" "$out" "wrap.sh merge: <repo> is a path to a checkout, not a name"
out="$("$WRAP" start feat/x 2>&1)"
chk_has "start with one argument shows the order" "$out" "it takes <repo> then <branch>, as in: wrap start <repo> 'feat/x'"
out="$("$WRAP" land 2>&1)"
chk_has "land with no worktree names wrap start" "$out" "wrap.sh land: no <worktree> given; wrap start <repo> <branch> makes one"
out="$("$WRAP" land "$HR/plain/nope" 2>&1)"
chk_has "land with a non-worktree names the right verbs" "$out" "land takes a worktree path; wrap start <repo> <branch> makes one"
out="$("$WRAP" log 2>&1)"; rc=$?
chk "log with no text exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" knowledge-root 2>&1)"; rc=$?
chk "knowledge-root with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" stage 2>&1)"; rc=$?
chk "stage with no args exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" bogus 2>&1)"; rc=$?
chk "an unknown verb exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

# ------------------------------------------------- main-checkout resolver recipe
# `commands/wrap.md` step 5 prescribes one recipe for turning the session cwd into the
# repo argument `wrap apply` needs: `--git-common-dir` minus the trailing `/.git`. Run from
# a worktree the naive `$PWD` yields the feature branch, `apply` takes its non-default-branch
# path, and the checkout never pulls. This asserts the recipe, not the model following it.
echo
echo "=== main-checkout resolver ==="
RES="$TMPD/resolver"; mkdir -p "$RES"
(
  cd "$RES" || exit 1
  git init -q -b main . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git worktree add -q wt -b feature >/dev/null 2>&1
) >/dev/null 2>&1
main_real="$(cd "$RES" && pwd -P)"
resolved="$(git -C "$RES/wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
resolved="${resolved%/.git}"
resolved="$(cd "$resolved" 2>/dev/null && pwd -P)"
chk "the recipe resolves a worktree to the main checkout" "$([ "$resolved" = "$main_real" ]; echo $?)"
chk "the main checkout is on the default branch, so apply pulls" \
  "$([ "$(git -C "$main_real" branch --show-current)" = "main" ]; echo $?)"
chk "the naive cwd would have been the feature branch" \
  "$([ "$(git -C "$RES/wt" branch --show-current)" = "feature" ]; echo $?)"
chk_has "commands/wrap.md prescribes the recipe" "$(cat "$KIT_DIR/commands/wrap.md")" "--git-common-dir"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-cli: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-cli: all $PASS passed"
