#!/usr/bin/env bash
# test-wrap-cli.sh -- the help, usage and resolver cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== help and usage ==="
# ===========================================================================
out="$("$WRAP" --help 2>&1)"; rc=$?
chk "--help exits 0" "$rc"
for verb in scan apply merge start log default-branch knowledge-root stage deploy-wait rebase; do
  chk_has "--help names $verb" "$out" "$verb"
done
out="$("$WRAP" scan 2>&1)"; rc=$?
chk "scan with no argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" apply 2>&1)"; rc=$?
chk "apply with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" merge 2>&1)"; rc=$?
chk "merge with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
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
