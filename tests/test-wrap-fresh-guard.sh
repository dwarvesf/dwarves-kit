#!/usr/bin/env bash
# test-wrap-fresh-guard.sh -- a fresh worker branch is never an ancestor-proof deletion,
# and the labeled sandbox scores every cleanup class. Shares tests/lib/wrap-stub.sh.
# modules under test: lib/gate/branch-merged.sh lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-apply.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== wrap labeled set: fresh cases keep, merged cases remove, false deletions zero ==="
# ===========================================================================
FIX="$TMPD_P/labeled"
mkdir -p "$FIX"
fixture_out="$(bash "$KIT_DIR/tests/lib/wrap-labeled-fixture.sh" "$FIX" 2>&1)"; rc=$?
chk "fixture builder exits 0" "$rc"
chk "fixture builder writes labels.tsv" "$([ -s "$FIX/labels.tsv" ]; echo $?)"
chk "labeled set covers 17 cases" \
  "$([ "$(wc -l < "$FIX/labels.tsv" | tr -d ' ')" = 17 ]; echo $?)"

score_before="$(bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
cp "$FIX/wrap.out" "$FIX/wrap-before-fetch.out"
chk "scorer exits 0 before the origin advance" "$rc"
chk_has "scorer prints zero false deletions" "$score_before" "false_deletions=0"
chk_has "scorer prints the false-keeps baseline" "$score_before" "false_keeps=0"
chk_has "scorer scores every labeled case" "$score_before" "missing=0"
raw_before="$(cat "$FIX/wrap-before-fetch.out")"
chk_no "fresh worktree at origin/main: no WOULD remove" "$raw_before" \
  "WOULD remove worktree $FIX/wt-fresh-zero"
chk_has "fresh worktree at origin/main: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-zero: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh branch-only ref: exact skip reason" "$raw_before" \
  "SKIP case-fresh-branch: fresh branch, no own commits and no merged PR (leave it)"
chk_no "fresh worktree created by SHA: no WOULD remove" "$raw_before" \
  "WOULD remove worktree $FIX/wt-fresh-sha"
chk_has "fresh worktree created by SHA: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-sha: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh branch created by revision expression: exact skip reason" "$raw_before" \
  "SKIP case-fresh-revision: fresh branch, no own commits and no merged PR (leave it)"
chk_has "merged fast-forward worktree still removes" "$score_before" $'merged-ff\tremove\tremove'
chk_has "merged-commit branch still removes" "$score_before" $'merged-commit\tremove\tremove'
chk_has "squash-equivalent worktree still removes" "$score_before" $'squash-equiv\tremove\tremove'
chk_has "exact-head merged PR still removes" "$score_before" $'pr-merged\tremove\tremove'

# Move the sandbox origin's main forward without a push, then fetch: the fresh branch is now
# strictly behind origin/main, the exact hazard shape, and must still be kept.
git -C "$FIX/origin.git" update-ref refs/heads/main refs/heads/next-main
git -C "$FIX/repo" fetch -q origin
score_after="$(bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
cp "$FIX/wrap.out" "$FIX/wrap-after-fetch.out"
chk "scorer exits 0 after the origin advance" "$rc"
chk_has "after fetch: zero false deletions" "$score_after" "false_deletions=0"
chk_has "after fetch: false-keeps baseline stays zero" "$score_after" "false_keeps=0"
raw_after="$(cat "$FIX/wrap-after-fetch.out")"
chk_no "after fetch: no WOULD remove for the stale fresh worktree" "$raw_after" \
  "WOULD remove worktree $FIX/wt-fresh-zero"
chk_has "after fetch: exact fresh-worktree skip reason" "$raw_after" \
  "SKIP $FIX/wt-fresh-zero: fresh branch, no own commits and no merged PR (leave it)"

# Negative control: the same fixture through a kit copy whose freshness read is reverted
# must score the fresh cases as deletions, proving the labels and scorer bite.
NEG="$TMPD/negative-kit"
mkdir -p "$NEG/bin"
cp -R "$KIT_DIR/lib" "$NEG/lib"
cp "$KIT_DIR/bin/wrap" "$NEG/bin/wrap"
sed -i.bak 's/^_branch_never_committed() {/_branch_never_committed() { return 1;/' \
  "$NEG/lib/gate/branch-merged.sh"
score_neg="$(WRAP_LABELED_WRAP="$NEG/bin/wrap" bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
chk "negative control: scorer exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "negative control: fresh worktree is a false deletion" "$score_neg" $'fresh-zero\tkeep\tremove'
chk_has "negative control: fresh branch is a false deletion" "$score_neg" $'fresh-branch\tkeep\tremove'
chk_has "negative control: fresh SHA worktree is a false deletion" "$score_neg" $'fresh-sha\tkeep\tremove'
chk_has "negative control: fresh revision branch is a false deletion" "$score_neg" $'fresh-revision\tkeep\tremove'
chk_has "negative control: all fresh cases are counted" "$score_neg" "false_deletions=4"

kill "$(cat "$FIX/holder.pid" 2>/dev/null)" 2>/dev/null

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-fresh-guard: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-fresh-guard: all $PASS passed"
