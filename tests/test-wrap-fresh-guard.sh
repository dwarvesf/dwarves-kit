#!/usr/bin/env bash
# test-wrap-fresh-guard.sh -- a fresh worker branch is never an ancestor-proof deletion,
# and the labeled sandbox scores every cleanup class across both `wrap apply` and `wrap sweep`.
# Shares tests/lib/wrap-stub.sh.
# modules under test: lib/gate/branch-merged.sh lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-sweep.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"
export XDG_STATE_HOME="$TMPD/state"
mkdir -p "$XDG_STATE_HOME"

# ===========================================================================
echo "=== wrap labeled set: fresh cases keep, merged cases remove, false deletions zero ==="
# ===========================================================================
FIX="$TMPD_P/labeled"
mkdir -p "$FIX"
fixture_out="$(bash "$KIT_DIR/tests/lib/wrap-labeled-fixture.sh" "$FIX" 2>&1)"; rc=$?
chk "fixture builder exits 0" "$rc"
chk "fixture builder writes labels.tsv" "$([ -s "$FIX/labels.tsv" ]; echo $?)"
chk "labeled set covers 25 cases" \
  "$([ "$(wc -l < "$FIX/labels.tsv" | tr -d ' ')" = 25 ]; echo $?)"

score_before="$(bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode apply "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
cp "$FIX/wrap.out" "$FIX/wrap-before-fetch.out"
chk "scorer (apply) exits 0 before the origin advance" "$rc"
chk_has "scorer (apply) prints zero false deletions" "$score_before" "false_deletions=0"
chk_has "scorer (apply) prints the false-keeps baseline" "$score_before" "false_keeps=0"
chk_has "scorer (apply) scores every labeled case" "$score_before" "missing=0"
chk_has "scorer (apply) verifies all keep reasons" "$score_before" "bad_reason=0"

score_sweep_before="$(bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode sweep "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
chk "scorer (sweep) exits 0 before the origin advance" "$rc"
chk_has "scorer (sweep) prints zero false deletions" "$score_sweep_before" "false_deletions=0"
chk_has "scorer (sweep) prints zero false keeps" "$score_sweep_before" "false_keeps=0"
chk_has "scorer (sweep) scores every labeled case" "$score_sweep_before" "missing=0"
chk_has "scorer (sweep) verifies all keep reasons" "$score_sweep_before" "bad_reason=0"

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
chk_has "fresh ff-sync worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-ff-sync: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh rebase worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-rebase: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh reset worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-reset: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh rename worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-rename: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh origin/HEAD worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-origin-head: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh upstream-alias worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-upstream-alias: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh ff --ff-only @{u} worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-ff-upstream: fresh branch, no own commits and no merged PR (leave it)"
chk_has "fresh ff FETCH_HEAD worktree: exact skip reason" "$raw_before" \
  "SKIP $FIX/wt-fresh-ff-fetchhead: fresh branch, no own commits and no merged PR (leave it)"
chk_has "merged fast-forward worktree still removes" "$score_before" $'merged-ff\tremove\tremove'
chk_has "merged-commit branch still removes" "$score_before" $'merged-commit\tremove\tremove'
chk_has "squash-equivalent worktree still removes" "$score_before" $'squash-equiv\tremove\tremove'
chk_has "exact-head merged PR still removes" "$score_before" $'pr-merged\tremove\tremove'

# Move the sandbox origin's main forward without a push, then fetch: the fresh branch is now
# strictly behind origin/main, the exact hazard shape, and must still be kept.
git -C "$FIX/origin.git" update-ref refs/heads/main refs/heads/next-main
git -C "$FIX/repo" fetch -q origin
score_after="$(bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode apply "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
cp "$FIX/wrap.out" "$FIX/wrap-after-fetch.out"
chk "scorer (apply) exits 0 after the origin advance" "$rc"
chk_has "after fetch (apply): zero false deletions" "$score_after" "false_deletions=0"
chk_has "after fetch (apply): false-keeps baseline stays zero" "$score_after" "false_keeps=0"
chk_has "after fetch (apply): bad_reason=0" "$score_after" "bad_reason=0"

score_sweep_after="$(bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode sweep "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
chk "scorer (sweep) exits 0 after the origin advance" "$rc"
chk_has "after fetch (sweep): zero false deletions" "$score_sweep_after" "false_deletions=0"
chk_has "after fetch (sweep): false-keeps baseline stays zero" "$score_sweep_after" "false_keeps=0"
chk_has "after fetch (sweep): bad_reason=0" "$score_sweep_after" "bad_reason=0"

raw_after="$(cat "$FIX/wrap-after-fetch.out")"
chk_no "after fetch: no WOULD remove for the stale fresh worktree" "$raw_after" \
  "WOULD remove worktree $FIX/wt-fresh-zero"
chk_has "after fetch: exact fresh-worktree skip reason" "$raw_after" \
  "SKIP $FIX/wt-fresh-zero: fresh branch, no own commits and no merged PR (leave it)"

# Negative control: the same fixture through a kit copy whose freshness read is reverted
# must score all 10 fresh cases as deletions across both apply and sweep.
NEG="$TMPD/negative-kit"
mkdir -p "$NEG/bin"
cp -R "$KIT_DIR/lib" "$NEG/lib"
cp "$KIT_DIR/bin/wrap" "$NEG/bin/wrap"
cp "$KIT_DIR/kit.toml" "$NEG/kit.toml"
sed -i.bak 's/^_branch_never_committed() {/_branch_never_committed() { return 1;/' \
  "$NEG/lib/gate/branch-merged.sh"
score_neg="$(WRAP_LABELED_WRAP="$NEG/bin/wrap" bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode apply "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
chk "negative control (apply): scorer exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "negative control (apply): fresh worktree is a false deletion" "$score_neg" $'fresh-zero\tkeep\tremove'
chk_has "negative control (apply): fresh ff-sync is a false deletion" "$score_neg" $'fresh-ff-sync\tkeep\tremove'
chk_has "negative control (apply): fresh rebase is a false deletion" "$score_neg" $'fresh-rebase\tkeep\tremove'
chk_has "negative control (apply): fresh reset is a false deletion" "$score_neg" $'fresh-reset\tkeep\tremove'
chk_has "negative control (apply): fresh rename is a false deletion" "$score_neg" $'fresh-rename\tkeep\tremove'
chk_has "negative control (apply): fresh origin-head is a false deletion" "$score_neg" $'fresh-origin-head\tkeep\tremove'
chk_has "negative control (apply): fresh upstream-alias is a false deletion" "$score_neg" $'fresh-upstream-alias\tkeep\tremove'
chk_has "negative control (apply): fresh ff-upstream is a false deletion" "$score_neg" $'fresh-ff-upstream\tkeep\tremove'
chk_has "negative control (apply): fresh ff-fetchhead is a false deletion" "$score_neg" $'fresh-ff-fetchhead\tkeep\tremove'
chk_has "negative control (apply): all 12 fresh cases are counted" "$score_neg" "false_deletions=12"

score_neg_sweep="$(WRAP_LABELED_WRAP="$NEG/bin/wrap" bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode sweep "$FIX" "$KIT_DIR" 2>&1)"; rc=$?
chk "negative control (sweep): scorer exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "negative control (sweep): all 12 fresh cases are counted" "$score_neg_sweep" "false_deletions=12"

# Scorer rejects missing, empty, or truncated labels sets.
MISS_SB="$TMPD_P/miss-sb"
mkdir -p "$MISS_SB/bin"
cp -R "$FIX/repo" "$MISS_SB/repo"
cp -R "$FIX/bin"/* "$MISS_SB/bin/"
bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode apply "$MISS_SB" "$KIT_DIR" >/dev/null 2>&1; rc=$?
chk "scorer exits non-zero when labels.tsv missing" "$([ "$rc" -ne 0 ]; echo $?)"
: > "$MISS_SB/labels.tsv"
bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode apply "$MISS_SB" "$KIT_DIR" >/dev/null 2>&1; rc=$?
chk "scorer exits non-zero when labels.tsv empty" "$([ "$rc" -ne 0 ]; echo $?)"
printf 'bogus-missing\tkeep\tworktree\t-\n' > "$FIX/labels-short.tsv"
cp "$FIX/labels.tsv" "$FIX/labels.orig"
cat "$FIX/labels.orig" "$FIX/labels-short.tsv" > "$FIX/labels.tsv"
bash "$KIT_DIR/tests/lib/wrap-labeled-score.sh" --mode apply "$FIX" "$KIT_DIR" >/dev/null 2>&1; rc=$?
mv "$FIX/labels.orig" "$FIX/labels.tsv"
chk "scorer exits non-zero when fewer rows scored than labeled" "$([ "$rc" -ne 0 ]; echo $?)"

kill "$(cat "$FIX/holder.pid" 2>/dev/null)" 2>/dev/null

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-fresh-guard: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-fresh-guard: all $PASS passed"
