#!/usr/bin/env bash
# test-wrap-ci.sh -- the merge/land ci-gate cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ------------------------------------------------- seed: the scan section's clones
# plus apply's pusher advance (391-395) and merge's two landings on bare-rmain
# (1629-1638, the MERGE_URL read at 1658, 1671-1680, the OPEN_PRS reset at 1716):
# the ci sections sat below merge's in the monolith and read MERGE_CUR/MERGE_URL.
for pair in "rmain main" "rmaster master" "rdev develop"; do
  set -- $pair
  rname="$1"; def="$2"
  make_clone "scan-$def" "$rname" "$def" unmerged
  set_stub "$rname" "$def"
done
git clone -q "$TMPD/bare-rmain" "$TMPD/pusher"
gitc "$TMPD/pusher"
echo advance >> "$TMPD/pusher/a.txt"
git -C "$TMPD/pusher" commit -qam advance
git -C "$TMPD/pusher" push -q origin main
set_stub rmain main
MERGE_CUR="$(git -C "$TMPD/clone-scan-main" branch --show-current)"
git -C "$TMPD/clone-scan-main" fetch -q origin main
git -C "$TMPD/clone-scan-main" checkout -q -b feat/wrap origin/main
echo "wrap the session" > "$TMPD/clone-scan-main/wrap-note.txt"
git -C "$TMPD/clone-scan-main" add -A
git -C "$TMPD/clone-scan-main" commit -qm "wrap the session"
PR7_OID="$(git -C "$TMPD/clone-scan-main" rev-parse feat/wrap)"
git -C "$TMPD/clone-scan-main" checkout -q "$MERGE_CUR"
export GH_STUB_PR_7="{\"number\":7,\"title\":\"wrap the session\",\"headRefName\":\"feat/wrap\",\"headRefOid\":\"$PR7_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"},{\"conclusion\":\"SKIPPED\"}]}"
git -C "$TMPD/clone-scan-main" push -q "$TMPD/bare-rmain" feat/wrap:refs/heads/main
MERGE_URL="$(git -C "$TMPD/clone-scan-main" remote get-url origin)"
git -C "$TMPD/clone-scan-main" fetch -q origin main
git -C "$TMPD/clone-scan-main" checkout -q -b feat/retry origin/main
echo "retry the merge" > "$TMPD/clone-scan-main/retry-note.txt"
git -C "$TMPD/clone-scan-main" add -A
git -C "$TMPD/clone-scan-main" commit -qm "retry the merge"
PR8_OID="$(git -C "$TMPD/clone-scan-main" rev-parse feat/retry)"
git -C "$TMPD/clone-scan-main" checkout -q "$MERGE_CUR"
export GH_STUB_OPEN_PRS='[{"number":8,"title":"retry the merge","headRefName":"feat/retry"}]'
export GH_STUB_PR_8="{\"number\":8,\"title\":\"retry the merge\",\"headRefName\":\"feat/retry\",\"headRefOid\":\"$PR8_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"}]}"
git -C "$TMPD/clone-scan-main" push -q "$TMPD/bare-rmain" feat/retry:refs/heads/main
export GH_STUB_OPEN_PRS='[{"number":7,"title":"wrap the session","headRefName":"feat/wrap"}]'
# ===========================================================================
echo "=== merge --apply: the ci label gate arms CI before the merge ==="
# ===========================================================================
# A label-gated repo runs no checks on an unlabeled PR, so the eligibility gate reads an
# empty rollup on a CLEAN state as mergeable and would merge the untested head. The stub
# serves the read sequence the sync, the wait, and the post-label re-gate make: view 1 is
# the eligibility read (untested), view 2 the label sync's (unlabeled), views 3-4 the
# check wait's (a run the label started, then green), view 5 the re-gate's. PR numbers
# 50-52 are fresh: the stub counts `pr view` reads per number in files the per-test reset
# never touches.
git -C "$TMPD/clone-scan-main" fetch -q origin main
git -C "$TMPD/clone-scan-main" checkout -q -b feat/ci-gate origin/main
echo "ci gated merge" > "$TMPD/clone-scan-main/ci-gate.txt"
git -C "$TMPD/clone-scan-main" add -A
git -C "$TMPD/clone-scan-main" commit -qm "ci gated merge"
PR50_OID="$(git -C "$TMPD/clone-scan-main" rev-parse feat/ci-gate)"
git -C "$TMPD/clone-scan-main" checkout -q "$MERGE_CUR"
git -C "$TMPD/clone-scan-main" push -q "$TMPD/bare-rmain" feat/ci-gate:refs/heads/main
CI_OPEN='[{"number":50,"title":"ci gated merge","headRefName":"feat/ci-gate"}]'
CI_PR_50="{\"number\":50,\"title\":\"ci gated merge\",\"headRefName\":\"feat/ci-gate\",\"headRefOid\":\"$PR50_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[],\"isDraft\":false}"
CI_PR_50_GREEN="{\"number\":50,\"title\":\"ci gated merge\",\"headRefName\":\"feat/ci-gate\",\"headRefOid\":\"$PR50_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"name\":\"pr-check\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}],\"labels\":[{\"name\":\"ci\"}],\"isDraft\":false}"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" \
  GH_STUB_LABELS='[{"name":"ci-extra"},{"name":"ci"}]' \
  GH_STUB_OPEN_PRS="$CI_OPEN" \
  GH_STUB_PR_50="$CI_PR_50" \
  GH_STUB_PR_50_2='{"number":50,"labels":[],"statusCheckRollup":[]}' \
  GH_STUB_PR_50_3='{"number":50,"statusCheckRollup":[{"name":"pr-check","status":"IN_PROGRESS"}]}' \
  GH_STUB_PR_50_4='{"number":50,"statusCheckRollup":[{"name":"pr-check","status":"COMPLETED","conclusion":"SUCCESS"}]}' \
  GH_STUB_PR_50_5="$CI_PR_50_GREEN" \
  "$WRAP" merge --apply --with-ci "$TMPD/clone-scan-main" 2>&1)"; rc=$?
CI_CALLS="$(cat "$GH_STUB_CALLS")"
chk "ci-gated merge: exits 0" "$rc"
chk_has "ci-gated merge: the empty rollup still gates eligible first" "$out" "eligible #50 ci gated merge [feat/ci-gate]"
chk_has "ci-gated merge: probed the repo labels" "$CI_CALLS" "label list"
chk_has "ci-gated merge: added the ci label" "$CI_CALLS" "pr edit 50 --repo ${MERGE_URL} --add-label ci"
chk_has "ci-gated merge: reports the labeling" "$out" "labeled #50 ci"
chk "ci-gated merge: the label precedes the merge" \
  "$(awk '/^pr edit 50 .*--add-label ci/{a=NR} /^pr merge 50 /{m=NR} END{exit !(a && m && a<m)}' "$GH_STUB_CALLS"; echo $?)"
chk "ci-gated merge: the pending run was waited out and the head re-gated" \
  "$([ "$(cat "$GH_STUB_CALLS.view-50" 2>/dev/null)" -eq 5 ]; echo $?)"
chk_has "ci-gated merge: pinned the gated head" "$CI_CALLS" "--squash --match-head-commit ${PR50_OID}"
chk_has "ci-gated merge: merged once the check read green" "$out" "merged #50 ($(git -C "$TMPD/bare-rmain" rev-parse main)): tree verified"

echo "--- ci-gated merge: a label that will not set refuses the merge"
# The eligibility gate passes the untested head; the sync's failed edit is what stands
# between it and a merge nothing tested.
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 \
  GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_EDIT_RC=1 \
  GH_STUB_OPEN_PRS='[{"number":51,"title":"ci noset","headRefName":"feat/ci-gate"}]' \
  GH_STUB_PR_51="{\"number\":51,\"title\":\"ci noset\",\"headRefName\":\"feat/ci-gate\",\"headRefOid\":\"$PR50_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[],\"isDraft\":false}" \
  GH_STUB_PR_51_2='{"number":51,"labels":[],"statusCheckRollup":[]}' \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-noset merge: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-noset merge: names the refusal" "$out" "FAILED merge #51: the ci label could not be set"
chk_no "ci-noset merge: untested head never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 51"

echo "--- ci-gated merge: a check the label revealed failing refuses the merge"
# The label's run comes back red on the first wait read, and the post-label re-gate is
# what refuses: the empty-rollup eligible verdict it replaces was read on an untested head.
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 \
  GH_STUB_LABELS='[{"name":"ci"}]' \
  GH_STUB_OPEN_PRS='[{"number":52,"title":"ci red","headRefName":"feat/ci-gate"}]' \
  GH_STUB_PR_52="{\"number\":52,\"title\":\"ci red\",\"headRefName\":\"feat/ci-gate\",\"headRefOid\":\"$PR50_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[],\"isDraft\":false}" \
  GH_STUB_PR_52_2='{"number":52,"labels":[],"statusCheckRollup":[]}' \
  GH_STUB_PR_52_3='{"number":52,"statusCheckRollup":[{"name":"pr-check","status":"COMPLETED","conclusion":"FAILURE"}]}' \
  GH_STUB_PR_52_4="{\"number\":52,\"title\":\"ci red\",\"headRefName\":\"feat/ci-gate\",\"headRefOid\":\"$PR50_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"UNSTABLE\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"name\":\"pr-check\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}],\"labels\":[{\"name\":\"ci\"}],\"isDraft\":false}" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-red merge: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-red merge: the re-gate names the failure" "$out" "FAILED merge #52: checks are pending or failing once the ci label's checks ran"
chk_no "ci-red merge: a red head never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 52"

echo "--- ci-gated merge: checks that predate the label do not end the wait"
# A PR can carry completed checks before `ci` goes on (an earlier plain pull_request run,
# or another label's labeled event whose jobs all skipped). Right after the edit none of
# them is pending, and the label's own runs register seconds later; the wait must hold
# until a check outside the pre-label set appears. Pending fixtures are live-shaped: gh
# reports a queued or running check with the zero completedAt and an empty conclusion.
# The harness runs with KIT_WRAP_SETTLE_SECS=0, so the re-gate reads exactly the fixture
# after the wait's last read; the layouts below are chosen so an early-ended wait fails.
CW_T='"completedAt":"2026-09-28T02:44:01Z","startedAt":"2026-09-28T02:44:01Z"'
CW_OLD="[{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SKIPPED\",$CW_T,\"detailsUrl\":\"https://gh/job/1\"},{\"name\":\"preview\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",$CW_T,\"detailsUrl\":\"https://gh/job/2\"}]"
CW_ZERO='"completedAt":"0001-01-01T00:00:00Z"'
CW_RUN="${CW_OLD%]},{\"name\":\"test\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\",$CW_ZERO,\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://gh/job/3\"}]"
CW_GREEN="${CW_OLD%]},{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:24:25Z\",\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://gh/job/3\"}]"
CW_RED="${CW_OLD%]},{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"completedAt\":\"2026-09-29T10:24:25Z\",\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://gh/job/3\"}]"
CW_QUEUED="${CW_OLD%]},{\"name\":\"test\",\"status\":\"QUEUED\",\"conclusion\":\"\",$CW_ZERO,\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://gh/job/3\"}]"
CW_QUEUED0="${CW_OLD%]},{\"name\":\"test\",\"status\":\"QUEUED\",\"conclusion\":\"\",$CW_ZERO,\"startedAt\":\"0001-01-01T00:00:00Z\",\"detailsUrl\":\"https://gh/job/3\"}]"
cw_full() { # cw_full <n> <mergeStateStatus> <rollup> [mergeable]
  printf '{"number":%s,"title":"ci wait","headRefName":"feat/ci-gate","headRefOid":"%s","baseRefName":"main","mergeable":"%s","mergeStateStatus":"%s","reviewDecision":"APPROVED","statusCheckRollup":%s,"labels":[{"name":"ci"}],"isDraft":false}' \
    "$1" "$PR50_OID" "${4:-MERGEABLE}" "$2" "$3"
}
cw_open() { printf '[{"number":%s,"title":"ci wait","headRefName":"feat/ci-gate"}]' "$1"; }
cw_views() { cat "$GH_STUB_CALLS.view-$1" 2>/dev/null || echo 0; }

# T1: the wait holds on the pre-label rollup, waits out the new run, then merges green.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 60)" \
  GH_STUB_PR_60="$(cw_full 60 CLEAN "$CW_OLD")" \
  GH_STUB_PR_60_2="{\"number\":60,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_60_3="{\"number\":60,\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_60_4="$(cw_full 60 CLEAN "$CW_RUN")" \
  GH_STUB_PR_60_5="$(cw_full 60 CLEAN "$CW_GREEN")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T1: exits 0" "$rc"
chk_has "ci-wait T1: labeled the PR" "$out" "labeled #60 ci"
chk "ci-wait T1: waited for the label's run past the pre-label checks (6 reads)" "$([ "$(cw_views 60)" -eq 6 ]; echo $?)"
chk_has "ci-wait T1: merged once the new run read green" "$out" "merged #60 ($(git -C "$TMPD/bare-rmain" rev-parse main)): tree verified"

# T2: the label's run comes back red after a hold, a pending read, and a red read.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 61)" \
  GH_STUB_PR_61="$(cw_full 61 CLEAN "$CW_OLD")" \
  GH_STUB_PR_61_2="{\"number\":61,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_61_3="{\"number\":61,\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_61_4="$(cw_full 61 CLEAN "$CW_OLD")" \
  GH_STUB_PR_61_5="$(cw_full 61 CLEAN "$CW_RUN")" \
  GH_STUB_PR_61_6="$(cw_full 61 CLEAN "$CW_RED")" \
  GH_STUB_PR_61_7="$(cw_full 61 UNSTABLE "$CW_RED")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T2: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-wait T2: the re-gate names the red run" "$out" "FAILED merge #61: checks are pending or failing once the ci label's checks ran"
chk_no "ci-wait T2: a red head never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 61"
chk "ci-wait T2: the wait read until the run completed (7 reads)" "$([ "$(cw_views 61)" -eq 7 ]; echo $?)"

# T3: no new check ever appears (a paths-filtered workflow); the grace bound ends the wait.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 KIT_WRAP_CI_GRACE_SECS=20 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 62)" \
  GH_STUB_PR_62="$(cw_full 62 CLEAN "$CW_OLD")" \
  GH_STUB_PR_62_2="{\"number\":62,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_62_3="$(cw_full 62 CLEAN "$CW_OLD")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T3: exits 0" "$rc"
chk "ci-wait T3: the grace bound held three wait reads (6 reads)" "$([ "$(cw_views 62)" -eq 6 ]; echo $?)"
chk_has "ci-wait T3: merged on the pre-label rollup" "$out" "merged #62 ("

# T4: the label is already on and checks exist: no baseline, one wait read, as before.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 63)" \
  GH_STUB_PR_63="$(cw_full 63 CLEAN "$CW_OLD")" \
  GH_STUB_PR_63_2="{\"number\":63,\"labels\":[{\"name\":\"ci\"}],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_63_3="$(cw_full 63 CLEAN "$CW_OLD")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T4: exits 0" "$rc"
chk_no "ci-wait T4: a label already on is not edited" "$(cat "$GH_STUB_CALLS")" "pr edit 63"
chk "ci-wait T4: one wait read, no extra hold (4 reads)" "$([ "$(cw_views 63)" -eq 4 ]; echo $?)"
chk_has "ci-wait T4: merged" "$out" "merged #63 ("

# T5: the label's run is still queued at the carry bound; the re-gate must not read the
# older SKIPPED of the same name as the verdict for `test`.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 KIT_WRAP_CARRY_CHECKS_SECS=10 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 64)" \
  GH_STUB_PR_64="$(cw_full 64 CLEAN "$CW_OLD")" \
  GH_STUB_PR_64_2="{\"number\":64,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_64_3="$(cw_full 64 CLEAN "$CW_QUEUED")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T5: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-wait T5: a queued run refuses the re-gate" "$out" "FAILED merge #64: checks are pending or failing once the ci label's checks ran"
chk_no "ci-wait T5: a queued head never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 64"

# T8: as T5, with a queued entry that has no real time at all (zero start and completion).
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 KIT_WRAP_CARRY_CHECKS_SECS=10 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 65)" \
  GH_STUB_PR_65="$(cw_full 65 CLEAN "$CW_OLD")" \
  GH_STUB_PR_65_2="{\"number\":65,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_65_3="$(cw_full 65 CLEAN "$CW_QUEUED0")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T8: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-wait T8: a queued run with no real time refuses the re-gate" "$out" "FAILED merge #65: checks are pending or failing once the ci label's checks ran"
chk_no "ci-wait T8: a queued head never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 65"

# T7: the sort-key change sits inside the checks def; the conflict verdict still comes first,
# so the union re-merge and the squash fallback keep matching it.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS="$(cw_open 66)" GH_STUB_PR_66="$(cw_full 66 DIRTY "$CW_QUEUED" CONFLICTING)" \
  "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "ci-wait T7: a conflicting PR with a pending check still verdicts the conflict" "$out" "SKIP #66 ci wait: not mergeable (CONFLICTING)"

# T3b: as T3 on an UNSTABLE merge state. No new check reported inside the grace hold, so the
# verdict would rest on checks that predate the label; those pass only on CLEAN.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 KIT_WRAP_CI_GRACE_SECS=20 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 67)" \
  GH_STUB_PR_67="$(cw_full 67 UNSTABLE "$CW_OLD")" \
  GH_STUB_PR_67_2="{\"number\":67,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_67_3="$(cw_full 67 UNSTABLE "$CW_OLD")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T3b: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-wait T3b: names the non-CLEAN refusal" "$out" "FAILED merge #67: no check reported after the ci label went on, and merge state UNSTABLE is not CLEAN"
chk_no "ci-wait T3b: never merges on pre-label checks alone" "$(cat "$GH_STUB_CALLS")" "pr merge 67"

# T9: the sync's PR read fails on a gating repo. Without it the sync cannot tell which
# checks predate the label, so the merge refuses and the PR stays open.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 68)" \
  GH_STUB_PR_68="$(cw_full 68 CLEAN "$CW_OLD")" \
  GH_STUB_PR_68_2='not json' \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T9: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-wait T9: names the refusal" "$out" "FAILED merge #68: the ci label could not be set"
chk_no "ci-wait T9: no label edit on an unread PR" "$(cat "$GH_STUB_CALLS")" "pr edit 68"
chk_no "ci-wait T9: never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 68"

# T10: a new check that only SKIPPED (another label's labeled event) tests nothing, so the
# hold goes on until the label's own run reports.
CW_LINT="${CW_OLD%]},{\"name\":\"lint\",\"status\":\"COMPLETED\",\"conclusion\":\"SKIPPED\",\"completedAt\":\"2026-09-29T10:21:57Z\",\"startedAt\":\"2026-09-29T10:21:57Z\",\"detailsUrl\":\"https://gh/job/4\"}]"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 69)" \
  GH_STUB_PR_69="$(cw_full 69 CLEAN "$CW_OLD")" \
  GH_STUB_PR_69_2="{\"number\":69,\"labels\":[],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_69_3="$(cw_full 69 CLEAN "$CW_LINT")" \
  GH_STUB_PR_69_4="$(cw_full 69 CLEAN "${CW_LINT%]},{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:24:25Z\",\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://gh/job/3\"}]")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T10: exits 0" "$rc"
chk "ci-wait T10: a new SKIPPED check did not end the hold (5 reads)" "$([ "$(cw_views 69)" -eq 5 ]; echo $?)"
chk_has "ci-wait T10: merged once the label's run reported" "$out" "merged #69 ("

# T11: a check running before the label keeps its key when it completes with a new
# startedAt (the key takes detailsUrl before any time), so it never reads as the label's run.
CW_PRE_RUN="[{\"name\":\"test\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\",\"completedAt\":\"0001-01-01T00:00:00Z\",\"startedAt\":\"2026-09-29T10:00:00Z\",\"detailsUrl\":\"https://gh/job/1\"}]"
CW_PRE_DONE="[{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:05:00Z\",\"startedAt\":\"2026-09-29T10:01:00Z\",\"detailsUrl\":\"https://gh/job/1\"}]"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 KIT_WRAP_CI_GRACE_SECS=20 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 70)" \
  GH_STUB_PR_70="$(cw_full 70 CLEAN "$CW_PRE_DONE")" \
  GH_STUB_PR_70_2="{\"number\":70,\"labels\":[],\"statusCheckRollup\":$CW_PRE_RUN}" \
  GH_STUB_PR_70_3="$(cw_full 70 CLEAN "$CW_PRE_DONE")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T11: exits 0" "$rc"
chk "ci-wait T11: a pre-label check that completed still held the grace wait (6 reads)" "$([ "$(cw_views 70)" -eq 6 ]; echo $?)"

# T12: third-party checks share one detailsUrl; the check name in the key keeps a new
# check apart from a pre-label one on the same URL, so the new ones end the wait at once.
CW_NL_OLD='[{"name":"netlify/deploy-preview","status":"COMPLETED","conclusion":"SUCCESS","completedAt":"2026-09-28T02:44:01Z","startedAt":"2026-09-28T02:44:01Z","detailsUrl":"https://app.netlify.com/sites/x/deploys/1"}]'
CW_NL_NEW="${CW_NL_OLD%]},{\"name\":\"netlify/header-rules\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:22:00Z\",\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://app.netlify.com/sites/x/deploys/1\"},{\"name\":\"netlify/redirect-rules\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:22:00Z\",\"startedAt\":\"2026-09-29T10:21:58Z\",\"detailsUrl\":\"https://app.netlify.com/sites/x/deploys/1\"}]"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS="$(cw_open 71)" \
  GH_STUB_PR_71="$(cw_full 71 CLEAN "$CW_NL_OLD")" \
  GH_STUB_PR_71_2="{\"number\":71,\"labels\":[],\"statusCheckRollup\":$CW_NL_OLD}" \
  GH_STUB_PR_71_3="$(cw_full 71 CLEAN "$CW_NL_NEW")" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-wait T12: exits 0" "$rc"
chk "ci-wait T12: new checks on a shared URL ended the wait at once (4 reads)" "$([ "$(cw_views 71)" -eq 4 ]; echo $?)"

echo "--- ci gate off by default: merge adds no label and waits for nothing"
# The same ci-gated fixture as #50, with no --with-ci and no KIT_WRAP_CI_ON_MERGE: the
# merge runs as before the gate existed. An empty rollup is mergeable again, and the
# label endpoints are never called.
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" \
  GH_STUB_LABELS='[{"name":"ci"}]' \
  GH_STUB_OPEN_PRS='[{"number":72,"title":"ci off merge","headRefName":"feat/ci-gate"}]' \
  GH_STUB_PR_72="{\"number\":72,\"title\":\"ci off merge\",\"headRefName\":\"feat/ci-gate\",\"headRefOid\":\"$PR50_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[],\"isDraft\":false}" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "ci-off merge: exits 0" "$rc"
chk_no "ci-off merge: the repo labels are never probed" "$(cat "$GH_STUB_CALLS")" "label list"
chk_no "ci-off merge: no pr edit runs" "$(cat "$GH_STUB_CALLS")" "pr edit"
chk_has "ci-off merge: the empty rollup is mergeable again" "$out" "merged #72 ($(git -C "$TMPD/bare-rmain" rev-parse main)): tree verified"

echo "=== land: the ci label gate arms CI before the merge ==="
# A label-gated repo runs no checks on an unlabeled PR, so a land that skipped the label
# would merge the pushed head untested. The stub serves the read sequence the sync and
# the wait make: view 1 sees the unlabeled PR, view 2 a run the label just started, view
# 3 the same run green.
build_land cigated
LWT_CI="$(cd "$TMPD/ld-repo-cigated/wt" && pwd -P)"
LTIP_CI="$(git -C "$LWT_CI" rev-parse HEAD)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" \
  GH_STUB_LABELS='[{"name":"ci-extra"},{"name":"ci"}]' \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_PR_42='{"number":42,"labels":[],"statusCheckRollup":[],"mergeStateStatus":"CLEAN"}' \
  GH_STUB_PR_42_2='{"number":42,"labels":[{"name":"ci"}],"statusCheckRollup":[{"name":"pr-check","status":"IN_PROGRESS"}]}' \
  GH_STUB_PR_42_3='{"number":42,"labels":[{"name":"ci"}],"statusCheckRollup":[{"name":"pr-check","status":"COMPLETED","conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$LWT_CI" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cigated" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CI" --with-ci 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "ci-gated land: exits 0" "$rc"
chk_has "ci-gated land: probed the repo labels" "$LAND_CALLS" "label list"
chk_has "ci-gated land: added the ci label" "$LAND_CALLS" "pr edit 42 --repo $TMPD/ld-bare-cigated --add-label ci"
chk_has "ci-gated land: reports the labeling" "$out" "labeled #42 ci"
chk "ci-gated land: the label precedes the merge" \
  "$(awk '/^pr edit 42 .*--add-label ci/{a=NR} /^pr merge 42 /{m=NR} END{exit !(a && m && a<m)}' "$GH_STUB_CALLS"; echo $?)"
chk "ci-gated land: the pending run was waited out, not merged through" \
  "$([ "$(grep -c '^pr view 42 ' "$GH_STUB_CALLS")" -ge 3 ]; echo $?)"
chk_has "ci-gated land: the merge pins the pushed head" "$LAND_CALLS" "--squash --match-head-commit ${LTIP_CI}"
chk_has "ci-gated land: merged once the check read green" "$out" "merged #42 ($(git -C "$TMPD/ld-bare-cigated" rev-parse main)): tree verified"

echo "--- ci-gated land: a fuzzy label hit that is not exactly ci never arms"
# `gh label list --search` matches substrings; a repo whose only hit is "ci-cd" has no
# label gate and must get the ungated path: no edit call, the merge runs as it always did.
build_land cifuzzy
LWT_CF="$(cd "$TMPD/ld-repo-cifuzzy/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci-cd"},{"name":"bug"}]' \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_LAND_REPO="$LWT_CF" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cifuzzy" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CF" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "ci-fuzzy land: exits 0" "$rc"
chk_has "ci-fuzzy land: still probed the labels" "$LAND_CALLS" "label list"
chk_no "ci-fuzzy land: no ci label means no pr edit" "$LAND_CALLS" "pr edit"
chk_has "ci-fuzzy land: merged as before" "$LAND_CALLS" "pr merge 42"

echo "--- ci-gated land: checks that predate the label do not end the wait (T6)"
# land has no settle read and no re-gate, so the order of its reads is the whole proof:
# read 1 is the sync's (unlabeled, pre-label checks), read 2 the wait's (still only those),
# read 3 the label's run pending, read 4 green. The merge must come after the 4th read.
build_land ciwait
LWT_CW="$(cd "$TMPD/ld-repo-ciwait/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 \
  GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_PR_42="{\"number\":42,\"labels\":[],\"statusCheckRollup\":$CW_OLD,\"mergeStateStatus\":\"CLEAN\"}" \
  GH_STUB_PR_42_2="{\"number\":42,\"labels\":[{\"name\":\"ci\"}],\"statusCheckRollup\":$CW_OLD}" \
  GH_STUB_PR_42_3="{\"number\":42,\"labels\":[{\"name\":\"ci\"}],\"statusCheckRollup\":$CW_RUN}" \
  GH_STUB_PR_42_4="{\"number\":42,\"labels\":[{\"name\":\"ci\"}],\"statusCheckRollup\":$CW_GREEN}" \
  GH_STUB_LAND_REPO="$LWT_CW" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ciwait" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CW" 2>&1)"; rc=$?
chk "ci-wait T6 land: exits 0" "$rc"
chk_has "ci-wait T6 land: labeled the PR" "$out" "labeled #42 ci"
chk "ci-wait T6 land: the merge came after the 4th rollup read" \
  "$(awk '/^pr view 42 .*statusCheckRollup/{v++} /^pr merge 42 /{m=v; exit} END{exit !(m == 4)}' "$GH_STUB_CALLS"; echo $?)"
chk_has "ci-wait T6 land: merged" "$out" "merged #42 ("

echo "--- ci-gated land: a label already on with runs on the head is left alone"
build_land ciarmed
LWT_CA="$(cd "$TMPD/ld-repo-ciarmed/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 \
  GH_STUB_LABELS='[{"name":"ci"}]' \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_PR_42='{"number":42,"labels":[{"name":"ci"}],"statusCheckRollup":[{"name":"pr-check","status":"COMPLETED","conclusion":"SUCCESS"}],"mergeStateStatus":"CLEAN"}' \
  GH_STUB_LAND_REPO="$LWT_CA" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ciarmed" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CA" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "ci-armed land: exits 0" "$rc"
chk_no "ci-armed land: an armed label is never re-added" "$LAND_CALLS" "pr edit"
chk_has "ci-armed land: merged" "$LAND_CALLS" "pr merge 42"

echo "--- ci-gated land: a label that predates the head is removed and re-added"
# The PR carries ci but the rollup is empty: the labeled event fired before the pushed
# commits, so the head was never tested. Remove+re-add re-fires the event on it.
build_land cistale
LWT_CS="$(cd "$TMPD/ld-repo-cistale/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_CI_ON_MERGE=1 \
  GH_STUB_LABELS='[{"name":"ci"}]' \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_PR_42='{"number":42,"labels":[{"name":"ci"}],"statusCheckRollup":[],"mergeStateStatus":"CLEAN"}' \
  GH_STUB_PR_42_2='{"number":42,"labels":[{"name":"ci"}],"statusCheckRollup":[{"name":"pr-check","status":"COMPLETED","conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$LWT_CS" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cistale" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CS" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "ci-stale land: exits 0" "$rc"
chk_has "ci-stale land: reports the re-label" "$out" "re-labeled #42 ci"
chk "ci-stale land: remove precedes re-add precedes merge" \
  "$(awk '/^pr edit 42 .*--remove-label ci/{r=NR} /^pr edit 42 .*--add-label ci/{a=NR} /^pr merge 42 /{m=NR} END{exit !(r && a && m && r<a && a<m)}' "$GH_STUB_CALLS"; echo $?)"

echo "--- ci-gated land: a label that will not set refuses the merge"
build_land cinoset
LWT_CN="$(cd "$TMPD/ld-repo-cinoset/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(KIT_WRAP_CI_ON_MERGE=1 GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_EDIT_RC=1 \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_PR_42='{"number":42,"labels":[],"statusCheckRollup":[],"mergeStateStatus":"CLEAN"}' \
  GH_STUB_LAND_REPO="$LWT_CN" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cinoset" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CN" 2>&1)"; rc=$?
chk "ci-noset land: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "ci-noset land: names the refusal" "$out" "MERGE FAILED #42: the ci label could not be set"
chk_no "ci-noset land: untested head never merges" "$(cat "$GH_STUB_CALLS")" "pr merge 42"

echo "--- ci gate off by default: land adds no label and waits for nothing"
# The same ci-gated fixture as the gated land above, with no --with-ci and no env: the
# repo labels are never probed, the wait never runs, and the merge lands as before the
# gate existed.
build_land cioff
LWT_CO="$(cd "$TMPD/ld-repo-cioff/wt" && pwd -P)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_LABELS='[{"name":"ci"}]' \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_LAND_REPO="$LWT_CO" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cioff" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_CO" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "ci-off land: exits 0" "$rc"
chk_no "ci-off land: the repo labels are never probed" "$LAND_CALLS" "label list"
chk_no "ci-off land: no pr edit runs" "$LAND_CALLS" "pr edit"
chk_has "ci-off land: merged as before" "$LAND_CALLS" "pr merge 42"

echo "--- autoland on a ci-gated repo labels the carry PR before the merge"
build_union_repo alci; al_orphan alci
ALI="$TMPD/uclone-alci"; ALIB="$TMPD/ubare-alci"
printf '%s' "$LAB_STRAY" > "$ALI/_meta/LAB_LOG.md"
AL_PR_CI_2='{"number":42,"title":"carry","headRefName":"wrap/stray","headRefOid":"%CARRY_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"","statusCheckRollup":[{"name":"pr-check","status":"COMPLETED","conclusion":"SUCCESS"}],"labels":[{"name":"ci"}],"isDraft":false}'
out="$(PATH="$TMPD/nosleep:$PATH" AL_WAIT=30 KIT_WRAP_CI_ON_MERGE=1 \
  GH_STUB_LABELS='[{"name":"ci"}]' GH_STUB_PR_42_2="$AL_PR_CI_2" \
  al_run "$ALIB" "$ALI" --apply)"; rc=$?
chk "autoland ci-gated: apply exits 0" "$rc"
chk_has "autoland ci-gated: the label went on the orphan's PR" "$(cat "$GH_STUB_CALLS")" "pr edit 42 --repo $ALIB --add-label ci"
chk "autoland ci-gated: the label precedes the merge" \
  "$(awk '/^pr edit 42 .*--add-label ci/{a=NR} /^pr merge 42 /{m=NR} END{exit !(a && m && a<m)}' "$GH_STUB_CALLS"; echo $?)"
chk_has "autoland ci-gated: merge --pr verifies the tree" "$out" "tree verified"

echo "--- autoland on a ci-gated repo: one grace hold, not two (T13)"
# The carry PR holds only pre-label checks and the label starts nothing new, so the carry
# wait holds for the grace window once. `cmd_merge --pr` then runs its own sync in a subshell
# that inherits the carry's globals; the label is on by then, and the sync's reset of
# CI_PRELABEL_KEYS on entry is what keeps that second wait from holding again.
build_union_repo alcw; al_orphan alcw
ALW="$TMPD/uclone-alcw"; ALWB="$TMPD/ubare-alcw"
printf '%s' "$LAB_STRAY" > "$ALW/_meta/LAB_LOG.md"
AL_CW_PR="{\"number\":42,\"title\":\"carry\",\"headRefName\":\"wrap/stray\",\"headRefOid\":\"%CARRY_TIP%\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"\",\"statusCheckRollup\":$CW_OLD,\"labels\":[],\"isDraft\":false}"
out="$(PATH="$TMPD/nosleep:$PATH" AL_WAIT=30 KIT_WRAP_CI_ON_MERGE=1 KIT_WRAP_CI_GRACE_SECS=20 \
  GH_STUB_LABELS='[{"name":"ci"}]' AL_PR_OVERRIDE="$AL_CW_PR" \
  GH_STUB_PR_42_2="${AL_CW_PR/\"labels\":[]/\"labels\":[{\"name\":\"ci\"}]}" \
  al_run "$ALWB" "$ALW" --apply)"; rc=$?
chk "autoland ci-wait T13: apply exits 0" "$rc"
chk_has "autoland ci-wait T13: merge --pr verifies the tree" "$out" "tree verified"
# 18 reads of #42 with one hold, measured; a second hold in the merge's own wait adds reads.
chk "autoland ci-wait T13: the grace hold ran once (18 reads)" "$([ "$(cw_views 42)" -eq 18 ]; echo $?)"

echo "--- knob false leaves the merged branch on origin"
build_land knobkeep
LWT_KK="$(cd "$TMPD/ld-repo-knobkeep/wt" && pwd -P)"
KK_OP="$TMPD/ld-knob-op"; mkdir -p "$KK_OP"
printf '[wrap]\ndelete_merged_remote_branches = false\n' > "$KK_OP/kit.toml"
: > "$GH_STUB_CALLS"
out="$(KIT_CONFIG_OPERATOR="$KK_OP" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=45 \
  GH_STUB_LAND_REPO="$LWT_KK" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-knobkeep" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_KK" 2>&1)"; rc=$?
chk "land with the knob off still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "land reports the branch left on origin" "$out" \
  "feat/land left on origin (wrap.delete_merged_remote_branches=false)"
chk "the origin branch survives the knob-off case" \
  "$(git -C "$TMPD/ld-bare-knobkeep" rev-parse --verify feat/land >/dev/null 2>&1; echo $?)"

echo "--- an open PR based on the branch keeps it on origin"
build_land basekeep
LWT_BK="$(cd "$TMPD/ld-repo-basekeep/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[{"number":50,"title":"stacked","headRefName":"feat/stacked","baseRefName":"feat/land"}]' \
  GH_STUB_CREATE_NUM=46 GH_STUB_LAND_REPO="$LWT_BK" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-basekeep" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_BK" 2>&1)"; rc=$?
chk "land with an open base-PR still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "land reports the base-PR hold" "$out" "feat/land left on origin: an open PR bases off it"
chk "the origin branch survives when an open PR bases off it" \
  "$(git -C "$TMPD/ld-bare-basekeep" rev-parse --verify feat/land >/dev/null 2>&1; echo $?)"

echo "--- a dirty worktree refuses before any write"
build_land dirty
LWT_D="$(cd "$TMPD/ld-repo-dirty/wt" && pwd -P)"
echo dirt > "$LWT_D/dirt.txt"
: > "$GH_STUB_CALLS"
out="$("$WRAP" land "$LWT_D" 2>&1)"; rc=$?
chk "land refuses a dirty worktree with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the dirt" "$out" "is dirty, so the branch is not what a PR would carry"
chk "a dirty refusal called no gh" "$([ ! -s "$GH_STUB_CALLS" ]; echo $?)"
chk "a dirty refusal pushed nothing" \
  "$(git -C "$TMPD/ld-bare-dirty" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"
chk "a dirty refusal left the worktree in place" "$([ -e "$LWT_D" ]; echo $?)"

echo "--- HEAD on the default branch refuses"
build_land ondef
git -C "$TMPD/ld-repo-ondef" checkout -q -b side
git -C "$TMPD/ld-repo-ondef" worktree add -q "$TMPD/ld-repo-ondef/wt-def" main >/dev/null 2>&1
LWT_M="$(cd "$TMPD/ld-repo-ondef/wt-def" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$("$WRAP" land "$LWT_M" 2>&1)"; rc=$?
chk "land refuses a worktree on the default branch with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the branch" "$out" "HEAD is main, the default or a protected branch name"
chk "a default-branch refusal called no gh" "$([ ! -s "$GH_STUB_CALLS" ]; echo $?)"
chk "a default-branch refusal left the worktree in place" "$([ -e "$LWT_M" ]; echo $?)"

echo "--- PULL BLOCKED: a dirty tracked file in the main checkout never stops the tidy"
build_land blocked --modify-base
LREPO_B="$TMPD/ld-repo-blocked"; LREPO_BP="$(cd "$LREPO_B" && pwd -P)"; LWT_B="$(cd "$LREPO_B/wt" && pwd -P)"
LTIP_B="$(git -C "$LWT_B" rev-parse HEAD)"
LHEAD_B="$(git -C "$LREPO_B" rev-parse HEAD)"
echo "a sibling session's line" >> "$LREPO_B/base.txt"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_CREATE_NUM=43 GH_STUB_LAND_REPO="$LWT_B" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-blocked" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_B" 2>&1)"; rc=$?
chk "a blocked pull exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "the blocked pull says PULL BLOCKED" "$out" "PULL BLOCKED: pull --ff-only refused in ${LREPO_BP}"
chk_has "the blocked pull says nothing was stashed or reset" "$out" "nothing was stashed or reset"
chk "the blocked pull left the main checkout where it was" \
  "$([ "$(git -C "$LREPO_B" rev-parse HEAD)" = "$LHEAD_B" ]; echo $?)"
chk "the blocked pull left the sibling's dirty file alone" \
  "$(grep -qx "a sibling session's line" "$LREPO_B/base.txt"; echo $?)"
chk "the merge still landed" \
  "$([ "$(git -C "$TMPD/ld-bare-blocked" rev-parse main)" = "$LTIP_B" ]; echo $?)"
chk "the worktree was still removed" "$([ ! -e "$LWT_B" ]; echo $?)"
chk_has "the removal is still reported" "$out" "removed worktree ${LWT_B}"
chk "the branch was still deleted" \
  "$(git -C "$LREPO_B" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"

echo "--- a dirty merge=union file in the main checkout is carried across the fast-forward (SPEC-321)"
build_land unionlog --union-log
LREPO_U="$TMPD/ld-repo-unionlog"; LREPO_UP="$(cd "$LREPO_U" && pwd -P)"; LWT_U="$(cd "$LREPO_U/wt" && pwd -P)"
LTIP_U="$(git -C "$LWT_U" rev-parse HEAD)"
printf 'local entry\nbase entry\n' > "$LREPO_U/_meta/LAB_LOG.md"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_CREATE_NUM=44 GH_STUB_LAND_REPO="$LWT_U" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-unionlog" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_U" 2>&1)"; rc=$?
chk "a union-carried pull exits 0" "$rc"
chk_has "the carry reports the save" "$out" "saved 1 union-marked file(s) aside so the pull can fast-forward"
chk_has "the carry reports the carry-back" "$out" "carried 1 local line(s) back into _meta/LAB_LOG.md"
chk_has "the fast-forward is still reported as pulled" "$out" "pulled ${LREPO_UP}"
chk_no "no PULL BLOCKED on a union-only dirty file" "$out" "PULL BLOCKED"
chk "the main checkout fast-forwarded to the landed tip" \
  "$([ "$(git -C "$LREPO_U" rev-parse HEAD)" = "$LTIP_U" ]; echo $?)"
chk "the incoming log line landed" \
  "$(grep -qxF 'remote entry' "$LREPO_U/_meta/LAB_LOG.md"; echo $?)"
chk "the sibling's local log line survived" \
  "$(grep -qxF 'local entry' "$LREPO_U/_meta/LAB_LOG.md"; echo $?)"
chk "the local log line is still uncommitted" \
  "$(git -C "$LREPO_U" diff --name-only | grep -qx '_meta/LAB_LOG.md'; echo $?)"
chk "the pr-file.txt content also landed" \
  "$([ "$(cat "$LREPO_U/pr-file.txt")" = "pr change" ]; echo $?)"
chk "the worktree was removed" "$([ ! -e "$LWT_U" ]; echo $?)"
chk "the branch was deleted" \
  "$(git -C "$LREPO_U" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-ci: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-ci: all $PASS passed"
