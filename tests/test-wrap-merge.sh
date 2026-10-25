#!/usr/bin/env bash
# test-wrap-merge.sh -- the merge cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ------------------------------------------------- seed: the scan section's clones
# clone-scan-main is merge's repo and bare-rmain its remote: the monolith builds the
# clones in the scan loop (291-295) and advances bare-rmain in apply's pusher block
# (391-395); the last set_stub the merge cases ran under was rmain/main (line 686).
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
# ===========================================================================
echo "=== gh absent: every non-ancestor is LEAVE, merge refuses ==="
# ===========================================================================
mkdir -p "$TMPD/nogh"
for t in bash env git jq sed awk grep date stat mktemp readlink mv rm cat tr sort head cut basename dirname chmod; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$TMPD/nogh/$t"
done
chk "the gh-free PATH really has no gh" "$(PATH="$TMPD/nogh" command -v gh >/dev/null 2>&1 && echo 1 || echo 0)"
out="$(PATH="$TMPD/nogh" "$WRAP" scan "$TMPD/clone-scan-main" 2>&1)"
chk_has "scan without gh: squash-ok falls back to LEAVE" "$out" "squash-ok  [NOT merged / unknown: LEAVE]"
chk_has "scan without gh: the PR line says so" "$out" "(gh unavailable)"
out="$(PATH="$TMPD/nogh" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge without gh exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "merge without gh names the reason" "$out" "(gh unavailable)"

echo "=== gh unauthenticated: the same verdicts, merge still refuses ==="
out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$TMPD/clone-scan-main" 2>&1)"
chk_has "scan unauthenticated: squash-ok falls back to LEAVE" "$out" "squash-ok  [NOT merged / unknown: LEAVE]"
chk_has "scan unauthenticated: the PR line says so" "$out" "(gh unauthenticated)"
out="$(GH_STUB_UNAUTH=1 "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge unauthenticated exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "merge unauthenticated names the reason" "$out" "(gh unauthenticated)"

# feat/wrap stops being a fake OID here: `merge --apply`'s tree-verify needs a real local
# commit to check, so give the branch one and land its exact content on the remote's main,
# standing in for the squash `gh pr merge` performs on GitHub's own side (this stub never
# pushes anything for real).
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

# ===========================================================================
echo "=== merge: dry-run lists the eligible PR, --apply merges exactly one ==="
# ===========================================================================
: > "$GH_STUB_CALLS"
out="$("$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge dry-run exits 0" "$rc"
chk_has "merge dry-run lists the PR as eligible" "$out" "eligible #7 wrap the session [feat/wrap]"
chk "merge dry-run calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

: > "$GH_STUB_CALLS"
out="$("$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --apply exits 0" "$rc"
chk_has "merge --apply reports the merge, tree verified" "$out" "merged #7 ($(git -C "$TMPD/bare-rmain" rev-parse main)): tree verified"
chk "merge --apply called pr merge exactly once" "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "merge --apply passed --squash" "$(grep -q '^pr merge 7 .*--squash' "$GH_STUB_CALLS"; echo $?)"
chk "merge --apply passed no --delete-branch" "$(grep -q -- '--delete-branch' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge --apply passed no --auto" "$(grep -q -- '--auto' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge --apply verified through pr view" "$(grep -q '^pr view 7 .*state,mergeCommit' "$GH_STUB_CALLS"; echo $?)"
MERGE_URL="$(git -C "$TMPD/clone-scan-main" remote get-url origin)"
MERGE_CALLS="$(cat "$GH_STUB_CALLS")"
chk_has "merge --apply pinned the head it gated on" "$MERGE_CALLS" \
  "pr merge 7 --repo ${MERGE_URL} --squash --match-head-commit ${PR7_OID}"
chk_has "merge: the detail read names --repo" "$MERGE_CALLS" "pr view 7 --repo ${MERGE_URL}"
chk "merge reads each PR detail exactly once" \
  "$([ "$(grep -c "^pr view 7 --repo ${MERGE_URL} --json number,title" "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

# ===========================================================================
# SPEC-300: merge retries a transient GitHub failure, never a real refusal
# ===========================================================================
# A second branch+PR for the retry cases, landed on the remote's main up front
# the same way feat/wrap was, so tree-verify has the squash tree to compare.
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

rm -f "$GH_STUB_CALLS.merge"; : > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGE_FAILS=2 GH_STUB_MERGE_ERR='HTTP 502 Bad Gateway' \
  WRAP_MERGE_RETRY_SLEEP=0 "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "SPEC-300: a transient 502 retries and merges" "$rc"
chk "SPEC-300: the retry took three merge calls" \
  "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 3 ]; echo $?)"
chk_has "SPEC-300: the retry says why it waits" "$out" "transient GitHub error (attempt 1/3)"
chk_has "SPEC-300: the retried merge still verifies" "$out" "merged #8 ($(git -C "$TMPD/bare-rmain" rev-parse main)): tree verified"

rm -f "$GH_STUB_CALLS.merge"; : > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGE_FAILS=9 GH_STUB_MERGE_ERR='HTTP 503 Service Unavailable' \
  WRAP_MERGE_RETRY_SLEEP=0 "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "SPEC-300: a transient that outlasts the bound exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk "SPEC-300: the bound held at three merge calls" \
  "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 3 ]; echo $?)"
chk_has "SPEC-300: the last failure still reports" "$out" "FAILED merge #8: exit 1"

rm -f "$GH_STUB_CALLS.merge"; : > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGE_RC=1 GH_STUB_MERGE_ERR='405 Method Not Allowed' \
  WRAP_MERGE_RETRY_SLEEP=0 "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "SPEC-300: a real refusal exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk "SPEC-300: a real refusal is not retried" \
  "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "SPEC-300: no transient retry line on a refusal" \
  "$(printf '%s' "$out" | grep -q 'transient GitHub error' && echo 1 || echo 0)"

rm -f "$GH_STUB_CALLS.merge"; : > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGE_RC=1 \
  GH_STUB_MERGE_ERR='the head commit oid does not match the pull request head' \
  WRAP_MERGE_RETRY_SLEEP=0 "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "SPEC-300: a match-head mismatch exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk "SPEC-300: a match-head mismatch is not retried" \
  "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

export GH_STUB_OPEN_PRS='[{"number":7,"title":"wrap the session","headRefName":"feat/wrap"}]'

echo "=== merge: the checks gate refuses pending, failing, empty-and-unstable, and changes requested ==="
gate_verdict() { # gate_verdict <pr json>
  GH_STUB_OPEN_PRS='[{"number":9,"title":"gate case","headRefName":"feat/gate"}]' \
  GH_STUB_PR_9="$1" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1
}
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"},{"status":"PENDING"}]}')"
chk_has "merge: a pending check skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"FAILURE"}]}')"
chk_has "merge: a failing check skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"UNSTABLE","reviewDecision":"APPROVED","statusCheckRollup":[]}')"
chk_has "merge: an empty rollup on a non-CLEAN state skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":null}')"
chk_has "merge: a null rollup on a CLEAN state stays eligible" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}')"
chk_has "merge: an empty rollup on a CLEAN state stays eligible" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}')"
chk_has "merge: changes requested skips" "$out" "SKIP #9 gate case: changes requested"

echo "=== merge: the checks gate reads only the latest run per check name, not every stale run ==="
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"evidence","conclusion":"FAILURE","completedAt":"2026-09-24T17:44:08Z"},{"name":"evidence","conclusion":"SUCCESS","completedAt":"2026-09-24T17:45:49Z"}]}')"
chk_has "merge: a re-run that later passed is eligible, not blocked by its stale failure" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"evidence","conclusion":"SUCCESS","completedAt":"2026-09-24T17:44:08Z"},{"name":"evidence","conclusion":"FAILURE","completedAt":"2026-09-24T17:45:49Z"}]}')"
chk_has "merge: a re-run whose latest attempt failed after an earlier pass still skips" "$out" "SKIP #9 gate case: checks are pending or failing"

echo "=== merge: a pending check is the latest of its name, whatever its time ==="
# gh reports a queued or running check with the zero completedAt and an empty conclusion.
# Every pending entry sorts last in its name group, so an older or later completed entry
# of that name never stands in as the verdict for a run still going.
GV_HEAD='"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED"'
out="$(gate_verdict "{$GV_HEAD,\"statusCheckRollup\":[{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SKIPPED\",\"completedAt\":\"2026-09-29T10:22:05Z\",\"startedAt\":\"2026-09-29T10:22:05Z\"},{\"name\":\"test\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\",\"completedAt\":\"0001-01-01T00:00:00Z\",\"startedAt\":\"2026-09-29T10:21:55Z\"}]}")"
chk_has "gate pending-last: a later SKIPPED does not stand in for a running check" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict "{$GV_HEAD,\"statusCheckRollup\":[{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SKIPPED\",\"completedAt\":\"2026-09-28T02:44:01Z\",\"startedAt\":\"2026-09-28T02:44:01Z\"},{\"name\":\"test\",\"status\":\"QUEUED\",\"conclusion\":\"\",\"completedAt\":\"0001-01-01T00:00:00Z\",\"startedAt\":\"2026-09-29T10:21:58Z\"}]}")"
chk_has "gate pending-last: an older SKIPPED does not stand in for a queued check" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict "{$GV_HEAD,\"statusCheckRollup\":[{\"name\":\"test\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\",\"completedAt\":\"0001-01-01T00:00:00Z\",\"startedAt\":\"2026-09-29T10:00:00Z\"},{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:30:00Z\",\"startedAt\":\"2026-09-29T10:20:00Z\"}]}")"
chk_has "gate pending-last: a stuck running entry blocks even behind a newer SUCCESS" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict "{$GV_HEAD,\"statusCheckRollup\":[{\"name\":\"test\",\"status\":\"QUEUED\",\"conclusion\":\"\",\"completedAt\":\"0001-01-01T00:00:00Z\",\"startedAt\":\"0001-01-01T00:00:00Z\"},{\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\",\"completedAt\":\"2026-09-29T10:30:00Z\",\"startedAt\":\"2026-09-29T10:20:00Z\"}]}")"
chk_has "gate pending-last: a stuck entry with no real time blocks behind a newer SUCCESS" "$out" "SKIP #9 gate case: checks are pending or failing"

echo "=== merge: statusCheckRollup mixes CheckRun and StatusContext entries; both dedupe correctly ==="
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"context":"pages-a","state":"FAILURE","createdAt":"2026-09-24T17:00:00Z"},{"context":"pages-b","state":"SUCCESS","createdAt":"2026-09-24T17:01:00Z"}]}')"
chk_has "merge: two distinct StatusContext entries, one FAILURE, still skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"context":"pages-a","state":"ERROR","createdAt":"2026-09-24T17:00:00Z"},{"context":"pages-a","state":"SUCCESS","createdAt":"2026-09-24T17:01:00Z"}]}')"
chk_has "merge: a same-context re-post (older error, newer success) is eligible" "$out" "eligible #9 gate case [feat/gate]"

echo "=== merge: a draft PR skips even when GitHub reports it mergeable and clean ==="
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":true}')"
chk_has "merge: a draft skips" "$out" "SKIP #9 gate case: draft"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":false}')"
chk_has "merge: isDraft=false stays eligible" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}')"
chk_has "merge: a missing isDraft field (older fixture) stays eligible" "$out" "eligible #9 gate case [feat/gate]"

echo "=== merge: a newer draft does not block an older ready PR ==="
DRAFT_OPEN='[{"number":19,"title":"wip","headRefName":"feat/wip"},{"number":18,"title":"ready","headRefName":"feat/ready"}]'
DRAFT_PR_19='{"number":19,"title":"wip","headRefName":"feat/wip","headRefOid":"dd","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[],"isDraft":true}'
DRAFT_PR_18='{"number":18,"title":"ready","headRefName":"feat/ready","headRefOid":"ee","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[],"isDraft":false}'
out="$(GH_STUB_OPEN_PRS="$DRAFT_OPEN" GH_STUB_PR_19="$DRAFT_PR_19" GH_STUB_PR_18="$DRAFT_PR_18" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge: the newer draft is skipped" "$out" "SKIP #19 wip: draft"
chk_has "merge: the older ready PR is picked" "$out" "eligible #18 ready [feat/ready]"

echo "=== merge: a PR the search index has not indexed yet is still found ==="
# The reported shape: an own green PR opened minutes earlier is absent from the
# author-filtered answer and present in the repository's own open-PR list.
LAG_OPEN='[{"number":31,"title":"fresh work","headRefName":"chore/fresh","author":{"login":"me"}}]'
LAG_PR_31='{"number":31,"title":"fresh work","headRefName":"chore/fresh","headRefOid":"ff","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":false}'
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$LAG_OPEN" GH_STUB_OPEN_PRS_SEARCH='[]' GH_STUB_PR_31="$LAG_PR_31" \
  "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge: a PR missing from the search index is still eligible" "$out" "eligible #31 fresh work [chore/fresh]"
chk "merge: the open-PR list carries no --author filter" \
  "$(grep -q '^pr list .*--author' "$GH_STUB_CALLS" && echo 1 || echo 0)"

echo "=== merge: a PR someone else authored is never listed ==="
FOREIGN_OPEN='[{"number":32,"title":"not mine","headRefName":"chore/theirs","author":{"login":"someone-else"}}]'
FOREIGN_PR_32='{"number":32,"title":"not mine","headRefName":"chore/theirs","headRefOid":"ff","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":false}'
out="$(GH_STUB_OPEN_PRS="$FOREIGN_OPEN" GH_STUB_PR_32="$FOREIGN_PR_32" \
  "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_no "merge: a PR authored by someone else is not eligible" "$out" "eligible #32"
chk_has "merge: a foreign-only list reports no own PRs" "$out" "no open PRs authored by the operator"

echo "=== merge: a repo with no open PRs is not a failed query ==="
out="$(GH_STUB_OPEN_PRS='[]' "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge: an empty board exits 0" "$rc"
chk_has "merge: an empty board says so" "$out" "no open PRs authored by the operator"
chk_no "merge: an empty board is not reported as a failed query" "$out" "the open-PR query on"

echo "=== merge: a failed identity read is reported, never read as an empty board ==="
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$LAG_OPEN" GH_STUB_API_RC=1 GH_STUB_PR_31="$LAG_PR_31" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge: a failed identity read exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "merge: a failed identity read names the query" "$out" "the open-PR query on"
chk_no "merge: a failed identity read is not reported as no own PRs" "$out" "no open PRs authored by the operator"
chk "merge: a failed identity read calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

echo "=== merge: unparseable PR JSON skips instead of passing the gate ==="
out="$(gate_verdict 'not json at all')"
chk_has "merge: unreadable JSON skips" "$out" "SKIP #9: unreadable PR JSON"

echo "=== merge: a stacked parent with an open dependent skips, naming the retarget rule ==="
STACK_OPEN='[{"number":7,"title":"parent","headRefName":"feat/wrap"},{"number":8,"title":"child","headRefName":"feat/child"}]'
STACK_8='{"number":8,"title":"child","headRefName":"feat/child","baseRefName":"feat/wrap","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}'
STACK_7='{"number":7,"title":"parent","headRefName":"feat/wrap","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}'
out="$(GH_STUB_OPEN_PRS="$STACK_OPEN" GH_STUB_PR_7="$STACK_7" GH_STUB_PR_8="$STACK_8" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge skips the stacked parent" "$out" "SKIP #7 parent: dependents open, retarget them first"
chk_has "merge skips the child whose base is not the default branch" "$out" "SKIP #8 child: base is feat/wrap, not the default branch main"

echo "=== merge: the post-merge state check fails closed ==="
: > "$GH_STUB_CALLS"
out="$(GH_STUB_VIEW_STATE='{"state":"OPEN","mergeCommit":null}' "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --apply exits 2 when the PR is not MERGED after the call" "$([ "$rc" -eq 2 ]; echo $?)"


# ------------- seed: the ci section's ci-gate landing on bare-rmain ----------
# The ci-gate cases (moved to test-wrap-ci.sh) pushed feat/ci-gate onto main in the
# monolith between this suite's two merge blocks (lines 1840-1847 verbatim).
git -C "$TMPD/clone-scan-main" fetch -q origin main
git -C "$TMPD/clone-scan-main" checkout -q -b feat/ci-gate origin/main
echo "ci gated merge" > "$TMPD/clone-scan-main/ci-gate.txt"
git -C "$TMPD/clone-scan-main" add -A
git -C "$TMPD/clone-scan-main" commit -qm "ci gated merge"
PR50_OID="$(git -C "$TMPD/clone-scan-main" rev-parse feat/ci-gate)"
git -C "$TMPD/clone-scan-main" checkout -q "$MERGE_CUR"
git -C "$TMPD/clone-scan-main" push -q "$TMPD/bare-rmain" feat/ci-gate:refs/heads/main
# ===========================================================================
echo "=== merge --pr: a named draft is marked ready, then gated and merged ==="
# ===========================================================================
# Same real-commit-plus-push shape as the PR7 fixture above: the branch's tip is pushed
# straight onto the bare remote's default branch, standing in for the squash GitHub would
# perform, so tree-verify has something real to match once --apply lands.
PRFLAG_CUR="$(git -C "$TMPD/clone-scan-main" branch --show-current)"
git -C "$TMPD/clone-scan-main" fetch -q origin main
git -C "$TMPD/clone-scan-main" checkout -q -b feat/draft-flag origin/main
echo "draft flag pr" > "$TMPD/clone-scan-main/draft-flag.txt"
git -C "$TMPD/clone-scan-main" add -A
git -C "$TMPD/clone-scan-main" commit -qm "draft flag pr"
PR40_OID="$(git -C "$TMPD/clone-scan-main" rev-parse feat/draft-flag)"
git -C "$TMPD/clone-scan-main" checkout -q "$PRFLAG_CUR"
git -C "$TMPD/clone-scan-main" push -q "$TMPD/bare-rmain" feat/draft-flag:refs/heads/main
PRFLAG_URL="$(git -C "$TMPD/clone-scan-main" remote get-url origin)"

# PR numbers here (40, 41) are never reused anywhere else in this file: the stub counts
# `pr view` reads per number in a file the per-test `: > "$GH_STUB_CALLS"` reset never
# touches, and a --pr run always reads a PR's detail twice (the isDraft precheck, then the
# eligibility loop), so any number shared with a later fixture would inherit a stale count.
PRFLAG_OPEN='[{"number":40,"title":"draft flag pr","headRefName":"feat/draft-flag"}]'
PRFLAG_PR_40="{\"number\":40,\"title\":\"draft flag pr\",\"headRefName\":\"feat/draft-flag\",\"headRefOid\":\"$PR40_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"}],\"isDraft\":true}"
# The second `pr view` read (the eligibility loop's, after `gh pr ready` ran) stands in for
# what a real ready call flips server-side: isDraft false, everything else unchanged.
PRFLAG_PR_40_2="{\"number\":40,\"title\":\"draft flag pr\",\"headRefName\":\"feat/draft-flag\",\"headRefOid\":\"$PR40_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"}],\"isDraft\":false}"

# (a) --pr N on a draft calls ready then merge, pinned to the full sha.
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$PRFLAG_OPEN" GH_STUB_PR_40="$PRFLAG_PR_40" GH_STUB_PR_40_2="$PRFLAG_PR_40_2" \
  "$WRAP" merge --apply --pr 40 "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --pr on a draft exits 0" "$rc"
chk_has "merge --pr marks the draft ready" "$out" "marking #40 ready (was draft)"
chk_has "merge --pr re-gates the PR after readying it" "$out" "eligible #40 draft flag pr [feat/draft-flag]"
chk_has "merge --pr reports the merge, tree verified" "$out" "merged #40"
PRFLAG_CALLS="$(cat "$GH_STUB_CALLS")"
chk_has "merge --pr called gh pr ready" "$PRFLAG_CALLS" "pr ready 40 --repo ${PRFLAG_URL}"
READY_LINE="$(grep -n '^pr ready 40' "$GH_STUB_CALLS" | head -1 | cut -d: -f1)"
MERGE_LINE="$(grep -n '^pr merge 40' "$GH_STUB_CALLS" | head -1 | cut -d: -f1)"
chk "merge --pr calls ready before merge" "$([ -n "$READY_LINE" ] && [ -n "$MERGE_LINE" ] && [ "$READY_LINE" -lt "$MERGE_LINE" ]; echo $?)"
chk_has "merge --pr pinned the full head sha" "$PRFLAG_CALLS" \
  "pr merge 40 --repo ${PRFLAG_URL} --squash --match-head-commit ${PR40_OID}"

# (b) no --pr still skips the same draft; behavior for the plain verb is unchanged.
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$PRFLAG_OPEN" GH_STUB_PR_40="$PRFLAG_PR_40" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge without --pr on the same draft exits 0" "$rc"
chk_has "merge without --pr still skips the draft" "$out" "SKIP #40 draft flag pr: draft"
chk_no "merge without --pr calls gh pr ready" "$(cat "$GH_STUB_CALLS")" "pr ready"
chk "merge without --pr calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# (c) --pr N for a PR not authored by the operator refuses and writes nothing. Reuses the
# FOREIGN_OPEN / FOREIGN_PR_32 fixture from the "authored by someone else" case above.
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$FOREIGN_OPEN" GH_STUB_PR_32="$FOREIGN_PR_32" \
  "$WRAP" merge --apply --pr 32 "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --pr on a foreign PR exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "merge --pr on a foreign PR names the refusal" "$out" "PR #32 is not an open PR authored by you"
chk_no "merge --pr on a foreign PR calls gh pr ready" "$(cat "$GH_STUB_CALLS")" "pr ready"
chk "merge --pr on a foreign PR calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# (d) dry run (no --apply) reports the draft note and marks nothing ready. A fresh PR
# number with no `_2` fixture: the eligibility loop's second read serves the SAME (still
# draft) body, because a real `gh pr ready` never ran to flip it.
PRFLAG_OPEN_41='[{"number":41,"title":"another draft","headRefName":"feat/draft-dry"}]'
PRFLAG_PR_41='{"number":41,"title":"another draft","headRefName":"feat/draft-dry","headRefOid":"4141414141414141414141414141414141414141","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":true}'
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$PRFLAG_OPEN_41" GH_STUB_PR_41="$PRFLAG_PR_41" \
  "$WRAP" merge --pr 41 "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --pr dry run exits 0" "$rc"
chk_has "merge --pr dry run notes the draft without applying" "$out" \
  "note: #41 is a draft; --apply would run \`gh pr ready\` before merging"
chk_has "merge --pr dry run still gates the draft as a draft" "$out" "SKIP #41 another draft: draft"
chk_no "merge --pr dry run calls gh pr ready" "$(cat "$GH_STUB_CALLS")" "pr ready"
chk "merge --pr dry run calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# ===========================================================================
echo "=== merge: one bounded re-merge when GitHub conflicts on a union-marked log ==="
# ===========================================================================
# GitHub squash-merges without reading .gitattributes, so a log both sides appended to
# conflicts on the PR while `git merge` resolves it by union. Each case gets its own remote
# and its own PR number, because the stub counts detail reads per number.
build_remerge() { # build_remerge <name> [--also-conflict]
  local name="$1" also="${2:-}" work="$TMPD/rm-work-$1" clone="$TMPD/rm-clone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  mkdir -p "$work/_meta"
  printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
  printf 'base line\n' > "$work/_meta/LAB_LOG.md"
  printf 'shared\n' > "$work/a.txt"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/union
  printf 'branch line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  [ "$also" = "--also-conflict" ] && printf 'branch side\n' > "$work/a.txt"
  git -C "$work" commit -qam "branch entry"
  git -C "$work" checkout -q main
  printf 'main line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  [ "$also" = "--also-conflict" ] && printf 'main side\n' > "$work/a.txt"
  git -C "$work" commit -qam "main entry"
  git clone -q --bare "$work" "$TMPD/rm-bare-$name"
  git clone -q "$TMPD/rm-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/union origin/feat/union
}
conflict_json() { # conflict_json <number>
  printf '{"number":%s,"title":"log entry","headRefName":"feat/union","headRefOid":"%s","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2"
}
open_one() { printf '[{"number":%s,"title":"log entry","headRefName":"feat/union"}]' "$1"; }

# --- dry run: the retry is announced, never run
build_remerge dry
RM_DRY="$TMPD/rm-clone-dry"; RM_DRY_TIP="$(git -C "$RM_DRY" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 11)" GH_STUB_PR_11="$(conflict_json 11 "$RM_DRY_TIP")" \
  "$WRAP" merge "$RM_DRY" 2>&1)"
chk_has "re-merge dry run names the branch it would re-merge" "$out" \
  "note: #11 conflicts; --apply would try one re-merge of main into feat/union"
chk_has "re-merge dry run also names the squash fallback" "$out" \
  "--apply falls back to a squash-equivalent feat/union-squash PR"
chk "re-merge dry run left the branch tip alone" \
  "$([ "$(git -C "$RM_DRY" rev-parse feat/union)" = "$RM_DRY_TIP" ]; echo $?)"
chk "re-merge dry run called no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- apply: the union log resolves, the push lands, the re-gate passes, one merge follows
# headRefOid is a %REMERGE_TIP% marker: the recovered commit's real SHA does not exist
# until wrap creates it mid-run, so the stub resolves the marker against the live branch
# tip, and its `pr merge` lands that same tip on main so tree-verify has a real match.
build_remerge ok
RM_OK="$TMPD/rm-clone-ok"; RM_OK_TIP="$(git -C "$RM_OK" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 12)" GH_STUB_PR_12="$(conflict_json 12 "$RM_OK_TIP")" \
  GH_STUB_PR_12_2='{"number":12,"title":"log entry","headRefName":"feat/union","headRefOid":"%REMERGE_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$RM_OK" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-ok" GH_STUB_LAND_BRANCH="feat/union" GH_STUB_LAND_DEF="main" \
  "$WRAP" merge --apply "$RM_OK" 2>&1)"; rc=$?
RM_OK_RECOVERED="$(git -C "$RM_OK" rev-parse feat/union)"
chk "re-merge --apply exits 0" "$rc"
chk_has "re-merge --apply reports the push" "$out" "re-merged origin/main into feat/union, pushed"
chk_has "re-merge --apply re-gates the PR" "$out" "eligible #12 after the re-merge"
chk_has "re-merge --apply merges the recovered PR" "$out" "merged #12 ($(git -C "$TMPD/rm-bare-ok" rev-parse main)): tree verified"
chk "re-merge --apply called pr merge exactly once" \
  "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "re-merge --apply pinned the head the re-gate read, not the stale one" \
  "$(grep -q -- "--match-head-commit ${RM_OK_RECOVERED}" "$GH_STUB_CALLS"; echo $?)"
chk "re-merge --apply advanced the remote branch" \
  "$([ "$(git -C "$TMPD/rm-bare-ok" rev-parse feat/union)" != "$RM_OK_TIP" ]; echo $?)"
chk "re-merge --apply kept both log lines" \
  "$(grep -q 'branch line' "$RM_OK/_meta/LAB_LOG.md" && grep -q 'main line' "$RM_OK/_meta/LAB_LOG.md"; echo $?)"
chk_no "re-merge --apply reports no dedupe (LAB_LOG is not a kanban table)" "$out" "deduped union-merged rows"

# --- apply: a conflict outside the union-marked files aborts and changes nothing
build_remerge bad --also-conflict
RM_BAD="$TMPD/rm-clone-bad"; RM_BAD_TIP="$(git -C "$RM_BAD" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 13)" GH_STUB_PR_13="$(conflict_json 13 "$RM_BAD_TIP")" \
  "$WRAP" merge --apply "$RM_BAD" 2>&1)"; rc=$?
chk "re-merge with a real conflict exits 0 without merging" "$rc"
chk_has "re-merge with a real conflict names the refused path" "$out" \
  "REFUSED feat/union: conflict in a.txt"
chk_has "re-merge with a real conflict says it aborted" "$out" \
  "conflicts beyond the union-marked files, aborted"
chk "re-merge with a real conflict left the branch tip alone" \
  "$([ "$(git -C "$RM_BAD" rev-parse feat/union)" = "$RM_BAD_TIP" ]; echo $?)"
chk "re-merge with a real conflict left no half-merged tree" \
  "$([ -z "$(git -C "$RM_BAD" status --porcelain)" ]; echo $?)"
chk "re-merge with a real conflict called no pr merge" \
  "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- apply: a tip that is not the gated head is never pushed
build_remerge tip
RM_TIP="$TMPD/rm-clone-tip"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 14)" \
  GH_STUB_PR_14="$(conflict_json 14 3333333333333333333333333333333333333333)" \
  "$WRAP" merge --apply "$RM_TIP" 2>&1)"
chk_has "re-merge refuses a branch whose tip is not the PR head" "$out" "is not the PR head"
chk "re-merge tip mismatch called no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- apply: two conflicting PRs leave the branch ambiguous, so nothing is retried
build_remerge two
RM_TWO="$TMPD/rm-clone-two"; RM_TWO_TIP="$(git -C "$RM_TWO" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[{"number":15,"title":"log entry","headRefName":"feat/union"},{"number":16,"title":"other","headRefName":"feat/other"}]' \
  GH_STUB_PR_15="$(conflict_json 15 "$RM_TWO_TIP")" \
  GH_STUB_PR_16='{"number":16,"title":"other","headRefName":"feat/other","headRefOid":"bb","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  "$WRAP" merge --apply "$RM_TWO" 2>&1)"
chk_no "two conflicting PRs retry neither" "$out" "one re-merge of main"
chk "two conflicting PRs left the branch tip alone" \
  "$([ "$(git -C "$RM_TWO" rev-parse feat/union)" = "$RM_TWO_TIP" ]; echo $?)"

# --- apply: the re-gate after the push is the authority, not the merge that succeeded
build_remerge gate
RM_GATE="$TMPD/rm-clone-gate"; RM_GATE_TIP="$(git -C "$RM_GATE" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 17)" GH_STUB_PR_17="$(conflict_json 17 "$RM_GATE_TIP")" \
  GH_STUB_PR_17_2='{"number":17,"title":"log entry","headRefName":"feat/union","headRefOid":"%REMERGE_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$RM_GATE" \
  "$WRAP" merge --apply "$RM_GATE" 2>&1)"
chk_has "a re-gate that refuses after the push names the reason" "$out" \
  "SKIP #17 after the re-merge: changes requested"
chk "a refused re-gate calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# ===========================================================================
echo "=== merge: the re-merge dedupes a union-merged kanban row before pushing ==="
# ===========================================================================
# Two adjacent kanban rows edited on each side sit inside ONE conflicting hunk on a short
# file (git's merge context, not the row content, is what overlaps), so the union driver
# resolves it by keeping ours-then-theirs whole and duplicates BOTH ids. This is the exact
# defect measured by hand 12 times on 2026-09-12; `_union_dedupe_rows` fixes it.
build_remerge_board() { # build_remerge_board <name>
  local name="$1" work="$TMPD/rb-work-$1" clone="$TMPD/rb-clone-$1"
  mkdir -p "$work/_meta"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf '_meta/BACKLOG.md merge=union\n' > "$work/.gitattributes"
  printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-401 | row a | src | queued |\n| ID-402 | row b | src | queued |\n' \
    > "$work/_meta/BACKLOG.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/union
  sed -i.bak 's/ID-401 | row a | src | queued/ID-401 | row a | src | shipped/' "$work/_meta/BACKLOG.md"
  rm -f "$work/_meta/BACKLOG.md.bak"
  git -C "$work" commit -qam "branch flips 401"
  git -C "$work" checkout -q main
  sed -i.bak 's/ID-402 | row b | src | queued/ID-402 | row b | src | executing/' "$work/_meta/BACKLOG.md"
  rm -f "$work/_meta/BACKLOG.md.bak"
  git -C "$work" commit -qam "main flips 402"
  git clone -q --bare "$work" "$TMPD/rb-bare-$name"
  git clone -q "$TMPD/rb-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/union origin/feat/union
}

build_remerge_board board
RB="$TMPD/rb-clone-board"; RB_TIP="$(git -C "$RB" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 20)" GH_STUB_PR_20="$(conflict_json 20 "$RB_TIP")" \
  GH_STUB_PR_20_2='{"number":20,"title":"log entry","headRefName":"feat/union","headRefOid":"%REMERGE_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$RB" GH_STUB_LAND_REMOTE="$TMPD/rb-bare-board" GH_STUB_LAND_BRANCH="feat/union" GH_STUB_LAND_DEF="main" \
  "$WRAP" merge --apply "$RB" 2>&1)"; rc=$?
chk "board re-merge --apply exits 0" "$rc"
chk_has "board re-merge reports the dedupe" "$out" "deduped union-merged rows"
chk "board re-merge left exactly one ID-401 row" \
  "$([ "$(grep -c '^| ID-401 ' "$RB/_meta/BACKLOG.md")" -eq 1 ]; echo $?)"
chk "board re-merge left exactly one ID-402 row" \
  "$([ "$(grep -c '^| ID-402 ' "$RB/_meta/BACKLOG.md")" -eq 1 ]; echo $?)"
chk "board re-merge kept the flipped ID-401 status, dropped the queued copy" \
  "$(grep -q '^| ID-401 | row a | src | shipped |$' "$RB/_meta/BACKLOG.md"; echo $?)"
chk "board re-merge kept the flipped ID-402 status, dropped the queued copy" \
  "$(grep -q '^| ID-402 | row b | src | executing |$' "$RB/_meta/BACKLOG.md"; echo $?)"
# git's own process (not a builtin) can take a SIGPIPE from a `grep -q` that stops reading
# after its match, so the subjects are captured into a variable FIRST and grepped from there
# (a builtin write), never piped straight from a live `git log`.
board_subjects="$(git -C "$RB" log --format=%s -3)"
chk "the dedupe landed as its own commit, the merge commit stays untouched" \
  "$(printf '%s\n' "$board_subjects" | grep -qx 'fix(board): dedupe union-merged rows'; echo $?)"
chk "the re-merge still pushed and merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 0 || echo 1)"

# ===========================================================================
echo "=== merge: a head already carrying the base falls back to a squash-equivalent PR ==="
# ===========================================================================
# The conflict GitHub still reports after the pushed head already contains
# origin/<default>: git resolved the union-marked files locally and the push landed, so
# the re-merge has nothing left to merge and only GitHub's attribute-blind merge keeps
# saying CONFLICTING. The recovery is the squash commit GitHub would have computed: one
# commit of the merged tree onto origin/<default>, pushed to a <branch>-squash branch and
# merged through a replacement PR carrying the original title and body. Real git
# throughout; gh stubbed, with %SQUASH_TIP% resolving the commit wrap makes mid-run.
build_carried() { # build_carried <name> -- feat/union already holds main, yet conflicts
  local name="$1" work="$TMPD/cb-work-$1" clone="$TMPD/cb-clone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  mkdir -p "$work/_meta"
  printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
  printf 'base line\n' > "$work/_meta/LAB_LOG.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/union
  printf 'branch line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  git -C "$work" commit -qam "branch entry"
  git -C "$work" checkout -q main
  printf 'main line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  git -C "$work" commit -qam "main entry"
  # The hand-worked recovery the fallback replaces: the union merge lands locally and
  # pushes, and only GitHub keeps reporting the PR conflicting.
  git -C "$work" checkout -q feat/union
  git -C "$work" merge -q --no-edit main
  git -C "$work" checkout -q main
  git clone -q --bare "$work" "$TMPD/cb-bare-$name"
  git clone -q "$TMPD/cb-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/union origin/feat/union
}
# The stub's `pr merge` pushes GH_STUB_LAND_BRANCH onto the default branch. For every
# case below that is feat/union, not feat/union-squash: the squash commit's tree IS the
# head's tree once the head contains the base, so pushing either ref hands tree-verify
# the same tree GitHub's squash would have produced.

# --- happy path: commit-tree, push, replacement PR, same merge+verify, superseded report
build_carried ok
CB_OK="$TMPD/cb-clone-ok"
CB_OK_TIP="$(git -C "$CB_OK" rev-parse feat/union)"
CB_OK_MAIN="$(git -C "$CB_OK" rev-parse origin/main)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 50)" \
  GH_STUB_PR_50="{\"number\":50,\"title\":\"log entry\",\"body\":\"the carried body\",\"headRefName\":\"feat/union\",\"headRefOid\":\"$CB_OK_TIP\",\"baseRefName\":\"main\",\"mergeable\":\"CONFLICTING\",\"mergeStateStatus\":\"DIRTY\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"}]}" \
  GH_STUB_CREATE_NUM=51 \
  GH_STUB_PR_51='{"number":51,"title":"log entry","headRefName":"feat/union-squash","headRefOid":"%SQUASH_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$CB_OK" GH_STUB_LAND_REMOTE="$TMPD/cb-bare-ok" GH_STUB_LAND_BRANCH=feat/union \
  "$WRAP" merge --apply "$CB_OK" 2>&1)"; rc=$?
SQ_OK="$(git -C "$CB_OK" rev-parse feat/union-squash 2>/dev/null)"
SQ_CALLS="$(cat "$GH_STUB_CALLS")"
chk "squash fallback exits 0" "$rc"
chk_has "squash fallback names why the re-merge could not run" "$out" \
  "already contains origin/main, so a re-merge cannot clear the conflict"
chk_has "squash fallback reports the pushed scratch branch" "$out" \
  "committed the squash-equivalent tree on feat/union-squash, pushed"
chk_has "squash fallback reports the replacement PR" "$out" \
  "opened replacement PR #51 on feat/union-squash (supersedes #50)"
chk_has "squash fallback gates the replacement" "$out" "eligible #51 after the squash fallback"
chk_has "squash fallback merges the replacement, tree verified" "$out" \
  "merged #51 ($(git -C "$TMPD/cb-bare-ok" rev-parse main)): tree verified"
chk_has "squash fallback names the superseded PR" "$out" \
  "superseded #50: its tree landed via #51 on feat/union-squash"
chk_has "squash fallback created the PR on the -squash branch" "$SQ_CALLS" \
  "--head feat/union-squash"
chk_has "squash fallback carried the original title" "$SQ_CALLS" "--title log entry"
chk_has "squash fallback carried the original body" "$SQ_CALLS" "--body the carried body"
chk "squash fallback merged #51, never #50" \
  "$([ "$(grep -c '^pr merge 51 ' "$GH_STUB_CALLS")" -eq 1 ] && ! grep -q '^pr merge 50 ' "$GH_STUB_CALLS"; echo $?)"
chk_has "squash fallback pinned the squash commit it built" "$SQ_CALLS" \
  "--squash --match-head-commit ${SQ_OK}"
chk "the squash commit's tree is the stuck head's tree" \
  "$([ "$(git -C "$CB_OK" rev-parse 'feat/union-squash^{tree}')" = "$(git -C "$CB_OK" rev-parse 'feat/union^{tree}')" ]; echo $?)"
chk "the squash commit's parent is the origin/main tip it fetched" \
  "$([ "$(git -C "$CB_OK" rev-parse 'feat/union-squash^')" = "$CB_OK_MAIN" ]; echo $?)"
chk "the -squash branch reached the remote" \
  "$([ "$(git -C "$TMPD/cb-bare-ok" rev-parse feat/union-squash)" = "$SQ_OK" ]; echo $?)"
chk "the stuck branch was left alone" \
  "$([ "$(git -C "$CB_OK" rev-parse feat/union)" = "$CB_OK_TIP" ]; echo $?)"
chk "the checkout stayed clean" \
  "$([ -z "$(git -C "$CB_OK" status --porcelain)" ]; echo $?)"

# --- a stuck PR that is also red elsewhere refuses before any git write
build_carried red
CB_RED="$TMPD/cb-clone-red"; CB_RED_TIP="$(git -C "$CB_RED" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 52)" \
  GH_STUB_PR_52="{\"number\":52,\"title\":\"red entry\",\"headRefName\":\"feat/union\",\"headRefOid\":\"$CB_RED_TIP\",\"baseRefName\":\"main\",\"mergeable\":\"CONFLICTING\",\"mergeStateStatus\":\"DIRTY\",\"reviewDecision\":\"CHANGES_REQUESTED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"}]}" \
  "$WRAP" merge --apply "$CB_RED" 2>&1)"; rc=$?
chk "a red conflict exits 0 without merging" "$rc"
chk_has "a red conflict names why the fallback refused" "$out" \
  "#52 is not one squash away from green: changes requested"
chk "a red conflict wrote no local -squash ref" \
  "$(git -C "$CB_RED" show-ref --verify --quiet refs/heads/feat/union-squash && echo 1 || echo 0)"
chk "a red conflict pushed no -squash branch" \
  "$(git -C "$TMPD/cb-bare-red" rev-parse --verify feat/union-squash >/dev/null 2>&1 && echo 1 || echo 0)"
chk "a red conflict called no pr create" "$(grep -q '^pr create' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "a red conflict called no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- a head that does NOT carry the base is not the carried-base case, and is left alone
# An untracked file dirties the checkout holding feat/union, so the re-merge refuses to
# run; the fallback still must refuse, because the head lacks origin/main.
build_remerge behind
CB_BEH="$TMPD/rm-clone-behind"
echo scratch > "$CB_BEH/untracked.txt"
CB_BEH_TIP="$(git -C "$TMPD/rm-bare-behind" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 55)" GH_STUB_PR_55="$(conflict_json 55 "$CB_BEH_TIP")" \
  "$WRAP" merge --apply "$CB_BEH" 2>&1)"; rc=$?
chk "a not-carried conflict exits 0 without merging" "$rc"
chk_has "a not-carried conflict names the missing ancestor" "$out" \
  "does not contain origin/main; the conflict is not the carried-base case"
chk "a not-carried conflict called no pr create" \
  "$(grep -q '^pr create' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "a not-carried conflict pushed no -squash branch" \
  "$(git -C "$TMPD/rm-bare-behind" rev-parse --verify feat/union-squash >/dev/null 2>&1 && echo 1 || echo 0)"

# --- the replacement PR's own gate refusing stops the merge, leaving both PRs for a human
build_carried gated
CB_G="$TMPD/cb-clone-gated"; CB_G_TIP="$(git -C "$CB_G" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 56)" GH_STUB_PR_56="$(conflict_json 56 "$CB_G_TIP")" \
  GH_STUB_CREATE_NUM=57 \
  GH_STUB_PR_57='{"number":57,"title":"log entry","headRefName":"feat/union-squash","headRefOid":"%SQUASH_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$CB_G" GH_STUB_LAND_REMOTE="$TMPD/cb-bare-gated" GH_STUB_LAND_BRANCH=feat/union \
  "$WRAP" merge --apply "$CB_G" 2>&1)"; rc=$?
chk "a gated replacement exits 0 without merging" "$rc"
chk_has "a gated replacement names the merge state" "$out" \
  "SKIP #57 after the squash fallback: merge state BLOCKED"
chk "a gated replacement called no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "a gated replacement leaves the -squash branch on origin for a human" \
  "$(git -C "$TMPD/cb-bare-gated" rev-parse --verify feat/union-squash >/dev/null 2>&1; echo $?)"

# --- the same anomaly one merge later: the re-merge pushes, GitHub still says CONFLICTING
build_remerge chain
RM_CH="$TMPD/rm-clone-chain"; RM_CH_TIP="$(git -C "$RM_CH" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 58)" GH_STUB_PR_58="$(conflict_json 58 "$RM_CH_TIP")" \
  GH_STUB_PR_58_2='{"number":58,"title":"log entry","headRefName":"feat/union","headRefOid":"%REMERGE_TIP%","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_CREATE_NUM=59 \
  GH_STUB_PR_59='{"number":59,"title":"log entry","headRefName":"feat/union-squash","headRefOid":"%SQUASH_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$RM_CH" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-chain" GH_STUB_LAND_BRANCH=feat/union \
  "$WRAP" merge --apply "$RM_CH" 2>&1)"; rc=$?
chk "a still-conflicting re-merge falls back and exits 0" "$rc"
chk_has "chain: the re-merge push is reported" "$out" "re-merged origin/main into feat/union"
chk_has "chain: the re-gate's refusal is reported" "$out" \
  "SKIP #58 after the re-merge: not mergeable (CONFLICTING)"
chk_has "chain: the fallback opens the replacement" "$out" \
  "opened replacement PR #59 on feat/union-squash (supersedes #58)"
chk_has "chain: the replacement merges" "$out" "merged #59 ($(git -C "$TMPD/rm-bare-chain" rev-parse main)): tree verified"
chk_has "chain: the superseded PR is named" "$out" "superseded #58"
chk "chain: one pr merge call, on #59 never #58" \
  "$([ "$(grep -c '^pr merge 59 ' "$GH_STUB_CALLS")" -eq 1 ] && ! grep -q '^pr merge 58 ' "$GH_STUB_CALLS"; echo $?)"

# --- a dependent PR on the conflicting branch refuses the fallback the same way it
# refuses the plain merge: merging the squash-equivalent would strand the dependent
# exactly as merging the original would have.
build_carried dep
CB_DEP="$TMPD/cb-clone-dep"; CB_DEP_TIP="$(git -C "$CB_DEP" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[{"number":60,"title":"log entry","headRefName":"feat/union"},{"number":61,"title":"stacked on it","headRefName":"feat/child"}]' \
  GH_STUB_PR_60="$(conflict_json 60 "$CB_DEP_TIP")" \
  GH_STUB_PR_61='{"number":61,"title":"stacked on it","headRefName":"feat/child","headRefOid":"aa","baseRefName":"feat/union","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  "$WRAP" merge --apply "$CB_DEP" 2>&1)"; rc=$?
chk "a conflict with a dependent exits 0 without merging" "$rc"
chk_has "a conflict with a dependent names the stranded dependent" "$out" \
  "fallback refused for #60: dependents open on feat/union, retarget them first"
chk "a conflict with a dependent called no pr create" \
  "$(grep -q '^pr create' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "a conflict with a dependent pushed no -squash branch" \
  "$(git -C "$TMPD/cb-bare-dep" rev-parse --verify feat/union-squash >/dev/null 2>&1 && echo 1 || echo 0)"

# --- a live PR already riding <branch>-squash is never closed by the delete+repush:
# the leftover-branch recovery checks for an open PR on that head first.
build_carried live
CB_LIVE="$TMPD/cb-clone-live"; CB_LIVE_TIP="$(git -C "$CB_LIVE" rev-parse feat/union)"
# Seed a divergent feat/union-squash on the remote so wrap's push comes back non-FF.
git -C "$CB_LIVE" checkout -q -b feat/union-squash
git -C "$CB_LIVE" commit -qm "stale squash attempt" --allow-empty
git -C "$CB_LIVE" push -q origin feat/union-squash
git -C "$CB_LIVE" checkout -q feat/union
git -C "$CB_LIVE" branch -qD feat/union-squash
CB_LIVE_SQ="$(git -C "$TMPD/cb-bare-live" rev-parse feat/union-squash)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 62)" \
  GH_STUB_PR_62="$(conflict_json 62 "$CB_LIVE_TIP")" \
  GH_STUB_OPEN_HEAD_feat_union_squash='[{"number":70}]' \
  "$WRAP" merge --apply "$CB_LIVE" 2>&1)"; rc=$?
chk "a live -squash PR exits 0 without merging" "$rc"
chk_has "a live -squash PR names the refusal" "$out" \
  "feat/union-squash has an open PR already; refusing to delete it"
chk "a live -squash PR kept the remote branch" \
  "$([ "$(git -C "$TMPD/cb-bare-live" rev-parse feat/union-squash)" = "$CB_LIVE_SQ" ]; echo $?)"
chk "a live -squash PR called no pr create" \
  "$(grep -q '^pr create' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "a live -squash PR called no pr merge" \
  "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# ===========================================================================
echo "=== merge: the re-gate waits for GitHub to settle on the pushed head ==="
# ===========================================================================
# GitHub computes mergeability asynchronously after a push: for a while it serves UNKNOWN,
# or the old head with its old CONFLICTING verdict. The re-gate polls until the head is the
# one wrap pushed and the verdict left UNKNOWN/CONFLICTING, bounded by KIT_WRAP_SETTLE_SECS.
# A no-op `sleep` keeps the bounded waits instant.
mergeable_json() { # mergeable_json <number> <head oid> <mergeable> <mergeStateStatus>
  printf '{"number":%s,"title":"log entry","headRefName":"feat/union","headRefOid":"%s","baseRefName":"main","mergeable":"%s","mergeStateStatus":"%s","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2" "$3" "$4"
}
views() { grep -c "^pr view $1 .*headRefOid" "$GH_STUB_CALLS"; }

# --- the observed race: UNKNOWN on the old head, then CONFLICTING on the pushed head, then MERGEABLE
build_remerge settle
ST="$TMPD/rm-clone-settle"; ST_TIP="$(git -C "$ST" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=60 \
  GH_STUB_OPEN_PRS="$(open_one 80)" GH_STUB_PR_80="$(conflict_json 80 "$ST_TIP")" \
  GH_STUB_PR_80_2="$(mergeable_json 80 "$ST_TIP" UNKNOWN UNKNOWN)" \
  GH_STUB_PR_80_3="$(mergeable_json 80 %REMERGE_TIP% CONFLICTING DIRTY)" \
  GH_STUB_PR_80_4="$(mergeable_json 80 %REMERGE_TIP% MERGEABLE CLEAN)" \
  GH_STUB_LAND_REPO="$ST" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-settle" GH_STUB_LAND_BRANCH=feat/union \
  "$WRAP" merge --apply "$ST" 2>&1)"; rc=$?
ST_PUSHED="$(git -C "$ST" rev-parse feat/union)"
chk "settle: a late-settling PR exits 0" "$rc"
chk_has "settle: the PR is eligible once GitHub settles" "$out" "eligible #80 after the re-merge"
chk_has "settle: the PR merges, tree verified" "$out" "merged #80 ($(git -C "$TMPD/rm-bare-settle" rev-parse main)): tree verified"
chk "settle: polled past UNKNOWN and the stale CONFLICTING (4 detail reads)" \
  "$([ "$(views 80)" -eq 4 ]; echo $?)"
chk "settle: pinned the merge to the pushed head" \
  "$(grep -q -- "^pr merge 80 .*--match-head-commit ${ST_PUSHED}" "$GH_STUB_CALLS"; echo $?)"
chk "settle: a late settle never closes the PR" "$(grep -q '^pr close' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- a verdict that stays CONFLICTING past the bound still skips with the existing message
build_remerge stuck
SK="$TMPD/rm-clone-stuck"; SK_TIP="$(git -C "$SK" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=6 \
  GH_STUB_OPEN_PRS="$(open_one 82)" GH_STUB_PR_82="$(conflict_json 82 "$SK_TIP")" \
  GH_STUB_PR_82_2="$(mergeable_json 82 %REMERGE_TIP% CONFLICTING DIRTY)" \
  GH_STUB_LAND_REPO="$SK" GH_STUB_CREATE_RC=1 \
  "$WRAP" merge --apply "$SK" 2>&1)"; rc=$?
chk "settle: a stuck CONFLICTING exits 0 without merging #82" "$rc"
chk_has "settle: a stuck CONFLICTING skips with the existing message" "$out" \
  "SKIP #82 after the re-merge: not mergeable (CONFLICTING)"
chk "settle: the wait is bounded (initial read plus 4 reads over 6s)" \
  "$([ "$(views 82)" -eq 5 ]; echo $?)"
chk "settle: a stuck CONFLICTING never merges #82" \
  "$(grep -q '^pr merge 82 ' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "settle: a stuck CONFLICTING on the pushed head never closes the PR" "$(grep -q '^pr close' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- a head someone else pushed during the wait is refused at once, never merged
build_remerge moved
MV="$TMPD/rm-clone-moved"; MV_TIP="$(git -C "$MV" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=60 \
  GH_STUB_OPEN_PRS="$(open_one 84)" GH_STUB_PR_84="$(conflict_json 84 "$MV_TIP")" \
  GH_STUB_PR_84_2="$(mergeable_json 84 "$MV_TIP" UNKNOWN UNKNOWN)" \
  GH_STUB_PR_84_3="$(mergeable_json 84 4444444444444444444444444444444444444444 MERGEABLE CLEAN)" \
  "$WRAP" merge --apply "$MV" 2>&1)"; rc=$?
chk "settle: a moved head exits 0 without merging" "$rc"
chk_has "settle: a moved head is named" "$out" "SKIP #84 after the re-merge: head is 4444444, not the pushed"
chk "settle: a moved head stops the wait at once (3 detail reads)" \
  "$([ "$(views 84)" -eq 3 ]; echo $?)"
chk "settle: a moved head is never merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "settle: a moved head never closes the PR" "$(grep -q '^pr close' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- a push GitHub never registers is refused once the bound runs out
build_remerge lost
LS="$TMPD/rm-clone-lost"; LS_TIP="$(git -C "$LS" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=4 \
  GH_STUB_OPEN_PRS="$(open_one 86)" GH_STUB_PR_86="$(conflict_json 86 "$LS_TIP")" \
  "$WRAP" merge --apply "$LS" 2>&1)"; rc=$?
chk "settle: an unregistered push exits 0 without merging" "$rc"
chk_has "settle: an unregistered push names the stale head" "$out" \
  "SKIP #86 after the re-merge: head is $(printf '%s' "$LS_TIP" | cut -c1-7), not the pushed"
chk "settle: an unregistered push is never merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "settle: a stale head with no state field never closes the PR" "$(grep -q '^pr close' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- a first read of UNKNOWN is re-read, never a SKIP on its own
build_remerge first
FR="$TMPD/rm-clone-first"; FR_TIP="$(git -C "$FR" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=60 \
  GH_STUB_OPEN_PRS="$(open_one 88)" GH_STUB_PR_88="$(mergeable_json 88 "$FR_TIP" UNKNOWN UNKNOWN)" \
  GH_STUB_PR_88_2="$(mergeable_json 88 "$FR_TIP" MERGEABLE CLEAN)" \
  "$WRAP" merge "$FR" 2>&1)"
chk_has "settle: a first UNKNOWN read settles to eligible" "$out" "eligible #88 log entry"
chk_no "settle: a first UNKNOWN read is not skipped" "$out" "not mergeable (UNKNOWN)"

# ===========================================================================
echo "=== merge: a branch no checkout holds re-merges in a scratch worktree ==="
# ===========================================================================
# The worktree that pushed the branch is gone, so no checkout holds it. The re-merge runs
# in a scratch detached worktree at the PR head, pushes, and removes the scratch worktree.
build_remerge nockout
NK="$TMPD/rm-clone-nockout"
git -C "$NK" checkout -q main
git -C "$NK" branch -qD feat/union
NK_TIP="$(git -C "$TMPD/rm-bare-nockout" rev-parse feat/union)"
NK_WT_BEFORE="$(git -C "$NK" worktree list --porcelain | grep -c '^worktree ')"
NK_MAIN="$(git -C "$TMPD/rm-bare-nockout" rev-parse main)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 90)" GH_STUB_PR_90="$(conflict_json 90 "$NK_TIP")" \
  GH_STUB_PR_90_2="$(mergeable_json 90 %REMERGE_TIP% MERGEABLE CLEAN)" \
  GH_STUB_LAND_REPO="$NK" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-nockout" GH_STUB_LAND_BRANCH=origin/feat/union \
  "$WRAP" merge --apply "$NK" 2>&1)"; rc=$?
NK_PUSHED="$(git -C "$TMPD/rm-bare-nockout" rev-parse feat/union)"
chk "no-checkout: exits 0" "$rc"
chk_has "no-checkout: names the scratch worktree" "$out" "no local checkout holds feat/union; re-merging in a scratch worktree"
chk_has "no-checkout: re-merged and pushed" "$out" "re-merged origin/main into feat/union, pushed"
chk_has "no-checkout: merged, tree verified" "$out" "merged #90 ($(git -C "$TMPD/rm-bare-nockout" rev-parse main)): tree verified"
chk "no-checkout: the pushed head carries the old origin/main" \
  "$(git -C "$NK" merge-base --is-ancestor "$NK_MAIN" "$NK_PUSHED"; echo $?)"
chk "no-checkout: pinned the merge to the pushed head" \
  "$(grep -q -- "--match-head-commit ${NK_PUSHED}" "$GH_STUB_CALLS"; echo $?)"
chk "no-checkout: the scratch worktree is gone" \
  "$([ "$(git -C "$NK" worktree list --porcelain | grep -c '^worktree ')" -eq "$NK_WT_BEFORE" ]; echo $?)"
chk "no-checkout: the operator checkout stayed clean on main" \
  "$([ -z "$(git -C "$NK" status --porcelain)" ] && [ "$(git -C "$NK" symbolic-ref --short HEAD)" = main ]; echo $?)"

# ===========================================================================
echo "=== merge: gh saying MERGED is not proof the default branch holds the PR head ==="
# ===========================================================================
# Real git repos throughout: what a tree actually holds after a squash is the whole
# subject, so nothing about the tree state is stubbed. `gh` stays stubbed (it always
# reports MERGED via GH_STUB_VIEW_STATE's default), which is the point: the mismatch
# and unverifiable cases below are exactly what gh's own word cannot catch.
tv_pr_json() { # tv_pr_json <number> <head branch> <head oid>
  printf '{"number":%s,"title":"tv case","headRefName":"%s","headRefOid":"%s","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2" "$3"
}
tv_open_one() { printf '[{"number":%s,"title":"tv case","headRefName":"%s"}]' "$1" "$2"; }
build_tv_repo() { # build_tv_repo <name> -- bare + clone, base.txt on main, feat/tv adds pr-file.txt
  local name="$1" work="$TMPD/tv-work-$1" clone="$TMPD/tv-clone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/base.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/tv-bare-$name"
  git clone -q "$TMPD/tv-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/tv main
  echo "pr change" > "$clone/pr-file.txt"
  git -C "$clone" add -A; git -C "$clone" commit -qm "pr change"
}

# tv_land <name> <message> <cmd...> -- one commit on the bare remote's main, made in a scratch
# clone: a concurrent PR, or the squash GitHub performs. The stub names the remote's HEAD as
# the merge commit, so the last tv_land before a merge is the squash under test.
tv_land() {
  local name="$1" msg="$2" land="$TMPD/tv-land-$1"; shift 2
  [ -d "$land" ] || { git clone -q "$TMPD/tv-bare-$name" "$land" >/dev/null 2>&1; gitc "$land"; }
  git -C "$land" pull -q origin main >/dev/null 2>&1
  (cd "$land" && "$@")
  git -C "$land" add -A; git -C "$land" commit -qm "$msg"; git -C "$land" push -q origin main
}

echo "--- a real mismatch: the squash carried a stale head's content, exits 3, branch untouched"
build_tv_repo mismatch
TVM="$TMPD/tv-clone-mismatch"; TVM_OID="$(git -C "$TVM" rev-parse feat/tv)"
tv_land mismatch "squash: stale head" sh -c 'echo "stale change" > pr-file.txt'
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 21 feat/tv)" GH_STUB_PR_21="$(tv_pr_json 21 feat/tv "$TVM_OID")" \
  "$WRAP" merge --apply "$TVM" 2>&1)"; rc=$?
chk "tree-verify: a real mismatch exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: mismatch names the count and that main lacks the head" "$out" \
  "TREE MISMATCH, 1 paths differ; main does not hold the PR head"
chk "tree-verify: mismatch leaves the branch in place" \
  "$(git -C "$TVM" rev-parse --verify feat/tv >/dev/null 2>&1; echo $?)"

echo "--- main never got the PR's change: the named commit is someone else's, exits 3"
build_tv_repo missing
TVX="$TMPD/tv-clone-missing"; TVX_OID="$(git -C "$TVX" rev-parse feat/tv)"
tv_land missing "someone else's change" sh -c 'echo other > other-file.txt'
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 24 feat/tv)" GH_STUB_PR_24="$(tv_pr_json 24 feat/tv "$TVX_OID")" \
  "$WRAP" merge --apply "$TVX" 2>&1)"; rc=$?
chk "tree-verify: a missing change exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: a missing change counts the extra and the absent path" "$out" \
  "TREE MISMATCH, 2 paths differ; main does not hold the PR head"

echo "--- gh names a merge commit that is not on main: unverifiable, exits 3"
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 25 feat/tv)" GH_STUB_PR_25="$(tv_pr_json 25 feat/tv "$TVX_OID")" \
  GH_STUB_VIEW_STATE="{\"state\":\"MERGED\",\"mergeCommit\":{\"oid\":\"$TVX_OID\"}}" \
  "$WRAP" merge --apply "$TVX" 2>&1)"; rc=$?
chk "tree-verify: a merge commit off main exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: names the merge commit off main" "$out" "is not on origin/main"

echo "--- an unreachable head object: never a false pass, exits 3"
BOGUS_OID="0000000000000000000000000000000000000f"
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 22 feat/tv)" GH_STUB_PR_22="$(tv_pr_json 22 feat/tv "$BOGUS_OID")" \
  "$WRAP" merge --apply "$TVM" 2>&1)"; rc=$?
chk "tree-verify: an unreachable head object exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: names it unverifiable rather than passing silently" "$out" \
  "tree UNVERIFIABLE the PR head is not a local object"

echo "--- scoped match: another PR landed on main meanwhile, only the touched path must agree"
build_tv_repo scoped
TVS="$TMPD/tv-clone-scoped"; TVS_OID="$(git -C "$TVS" rev-parse feat/tv)"
git clone -q "$TMPD/tv-bare-scoped" "$TMPD/tv-land-scoped" >/dev/null 2>&1
gitc "$TMPD/tv-land-scoped"
echo "someone else's change" > "$TMPD/tv-land-scoped/other-file.txt"
git -C "$TMPD/tv-land-scoped" add -A; git -C "$TMPD/tv-land-scoped" commit -qm "other change"
cp "$TVS/pr-file.txt" "$TMPD/tv-land-scoped/pr-file.txt"
git -C "$TMPD/tv-land-scoped" add -A; git -C "$TMPD/tv-land-scoped" commit -qm "squash: pr change"
git -C "$TMPD/tv-land-scoped" push -q origin main
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 23 feat/tv)" GH_STUB_PR_23="$(tv_pr_json 23 feat/tv "$TVS_OID")" \
  "$WRAP" merge --apply "$TVS" 2>&1)"; rc=$?
chk "tree-verify: a scoped match (another PR landed meanwhile) exits 0" "$rc"
chk_has "tree-verify: scoped match reports verified" "$out" "tree verified"

echo "--- a concurrent PR edited the same file: judged on this PR's own change, verified"
# The ops-toolkit case: both PRs add a line to one log, so main's copy holds both lines and
# never equals the PR head's copy, yet the squash applied exactly the PR's change.
build_tv_repo shared
TVH="$TMPD/tv-clone-shared"
tv_land shared "log seed" sh -c 'printf "l1\nl2\nl3\nl4\nl5\n" > log.md'
git -C "$TVH" checkout -q main; git -C "$TVH" pull -q origin main
git -C "$TVH" checkout -q -b feat/shared main
printf 'pr line\nl1\nl2\nl3\nl4\nl5\n' > "$TVH/log.md"
git -C "$TVH" commit -qam "pr: log line"; TVH_OID="$(git -C "$TVH" rev-parse feat/shared)"
tv_land shared "other PR: log line" sh -c 'echo "other line" >> log.md'
tv_land shared "squash: pr log line" sh -c '{ echo "pr line"; cat log.md; } > log.tmp && mv log.tmp log.md'
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 26 feat/shared)" GH_STUB_PR_26="$(tv_pr_json 26 feat/shared "$TVH_OID")" \
  "$WRAP" merge --apply "$TVH" 2>&1)"; rc=$?
chk "tree-verify: a concurrent edit to a shared file exits 0" "$rc"
chk_has "tree-verify: a concurrent edit to a shared file reports verified" "$out" "tree verified"

echo "--- the squash altered the PR's own line in a shared file: still a mismatch"
build_tv_repo sharedbad
TVB="$TMPD/tv-clone-sharedbad"
tv_land sharedbad "log seed" sh -c 'printf "l1\nl2\n" > log.md'
git -C "$TVB" checkout -q main; git -C "$TVB" pull -q origin main
git -C "$TVB" checkout -q -b feat/shared main
printf 'pr line\nl1\nl2\n' > "$TVB/log.md"
git -C "$TVB" commit -qam "pr: log line"; TVB_OID="$(git -C "$TVB" rev-parse feat/shared)"
tv_land sharedbad "other PR: log line" sh -c 'echo "other line" >> log.md'
tv_land sharedbad "squash: a resolution that rewrote the PR line" \
  sh -c '{ echo "pr line, resolved"; cat log.md; } > log.tmp && mv log.tmp log.md'
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 27 feat/shared)" GH_STUB_PR_27="$(tv_pr_json 27 feat/shared "$TVB_OID")" \
  "$WRAP" merge --apply "$TVB" 2>&1)"; rc=$?
chk "tree-verify: an altered shared-file line exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: an altered shared-file line is a one-path mismatch" "$out" "TREE MISMATCH, 1 paths differ"

echo "--- a PR that deletes and renames files lands after a concurrent PR: verified"
build_tv_repo delete
TVD="$TMPD/tv-clone-delete"
tv_land delete "seed" sh -c 'echo gone > gone.txt; echo moved > old-name.txt'
git -C "$TVD" checkout -q main; git -C "$TVD" pull -q origin main
git -C "$TVD" checkout -q -b feat/delete main
git -C "$TVD" rm -q gone.txt; git -C "$TVD" mv old-name.txt new-name.txt
git -C "$TVD" commit -qm "pr: delete and rename"; TVD_OID="$(git -C "$TVD" rev-parse feat/delete)"
tv_land delete "other PR" sh -c 'echo other > other-file.txt'
tv_land delete "squash: delete and rename" sh -c 'git rm -q gone.txt && git mv old-name.txt new-name.txt'
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 28 feat/delete)" GH_STUB_PR_28="$(tv_pr_json 28 feat/delete "$TVD_OID")" \
  "$WRAP" merge --apply "$TVD" 2>&1)"; rc=$?
chk "tree-verify: a landed deletion and rename exits 0" "$rc"
chk_has "tree-verify: a landed deletion and rename reports verified" "$out" "tree verified"

echo "--- the deletion never landed: the squash kept the file, a mismatch"
build_tv_repo delbad
TVE="$TMPD/tv-clone-delbad"
tv_land delbad "seed" sh -c 'echo gone > gone.txt'
git -C "$TVE" checkout -q main; git -C "$TVE" pull -q origin main
git -C "$TVE" checkout -q -b feat/delete main
git -C "$TVE" rm -q gone.txt; git -C "$TVE" commit -qm "pr: delete"; TVE_OID="$(git -C "$TVE" rev-parse feat/delete)"
tv_land delbad "squash: kept the file" sh -c 'echo "pr change" > pr-file.txt'
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 29 feat/delete)" GH_STUB_PR_29="$(tv_pr_json 29 feat/delete "$TVE_OID")" \
  "$WRAP" merge --apply "$TVE" 2>&1)"; rc=$?
chk "tree-verify: an unlanded deletion exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: an unlanded deletion is a mismatch" "$out" "TREE MISMATCH"

echo "=== merge: flags packed into one positional are refused ==="
out="$("$WRAP" merge " --apply" 2>&1)"; rc=$?
chk "packed arg to merge exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "packed arg to merge names the packed-flags refusal" "$out" "wrap.sh merge: argument '"

REAL_GIT_BIN="$(command -v git)"

# build_remerge_reg <name> [--branch-gen] -- the registry layout on the merge fixture's
# shape: a bare origin, a clone holding feat/union in its main worktree, both sides having
# regenerated docs/reference/FEATURES.md (a conflict the union driver cannot touch). The stub
# generator also touches gen-ran.marker, an ignored path, so a cycle that ran it leaves the
# marker behind even after a restore: its absence proves the generator never ran.
# --branch-gen edits the generator on feat/union only, which must withhold it from the
# cycle (the two sides disagree on it).
build_remerge_reg() {
  local name="$1" bgen="${2:-}" work="$TMPD/rr-work-$1" clone="$TMPD/rr-clone-$1"
  mkdir -p "$work/lib/registry" "$work/specs" "$work/docs"
  git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  { printf '#!/usr/bin/env bash\nroot="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf 'ls "$root/specs" | LC_ALL=C sort > "$root/docs/reference/FEATURES.md"\n'
    printf 'touch "$root/gen-ran.marker"\n'
  } > "$work/lib/registry/feature-registry.sh"
  chmod +x "$work/lib/registry/feature-registry.sh"
  echo base > "$work/base.txt"
  printf 'gen-ran.marker\n' > "$work/.gitignore"
  echo a > "$work/specs/a.md"
  ( cd "$work" && bash lib/registry/feature-registry.sh generate )
  rm -f "$work/gen-ran.marker"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/union
  echo b > "$work/specs/b.md"
  ( cd "$work" && bash lib/registry/feature-registry.sh generate )
  rm -f "$work/gen-ran.marker"
  if [ "$bgen" = "--branch-gen" ]; then
    printf 'echo branch >> "$root/gen-ran.marker"\n' >> "$work/lib/registry/feature-registry.sh"
  fi
  git -C "$work" add -A; git -C "$work" commit -qm "branch change"
  git -C "$work" checkout -q main
  echo o > "$work/specs/o.md"
  ( cd "$work" && bash lib/registry/feature-registry.sh generate )
  rm -f "$work/gen-ran.marker"
  git -C "$work" add -A; git -C "$work" commit -qm "main change"
  git clone -q --bare "$work" "$TMPD/rr-bare-$name"
  git clone -q "$TMPD/rr-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/union origin/feat/union
}

echo "--- merge-cycle: a FEATURES conflict re-merges, pushes and the PR merges"
# The same cycle land runs, reached through `wrap merge --apply`: today this aborted on
# the first non-union path. The resolved tree lands a real merge commit on feat/union and
# the recovered PR then squash-merges as before.
build_remerge_reg rfeat
RR="$TMPD/rr-clone-rfeat"; RR_TIP="$(git -C "$RR" rev-parse feat/union)"
RR_MAIN="$(git -C "$TMPD/rr-bare-rfeat" rev-parse main)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS="$(open_one 100)" GH_STUB_PR_100="$(conflict_json 100 "$RR_TIP")" \
  GH_STUB_PR_100_2="$(mergeable_json 100 %REMERGE_TIP% MERGEABLE CLEAN)" \
  GH_STUB_LAND_REPO="$RR" GH_STUB_LAND_REMOTE="$TMPD/rr-bare-rfeat" \
  GH_STUB_LAND_BRANCH=feat/union GH_STUB_LAND_DEF=main \
  "$WRAP" merge --apply "$RR" 2>&1)"; rc=$?
chk "merge-cycle: FEATURES re-merge exits 0" "$rc"
chk_has "merge-cycle: FEATURES re-merge reports the push" "$out" \
  "re-merged origin/main into feat/union, pushed"
chk_has "merge-cycle: FEATURES re-merge merges the recovered PR" "$out" \
  "merged #100 ($(git -C "$TMPD/rr-bare-rfeat" rev-parse main)): tree verified"
chk "merge-cycle: the merge commit has both parents" \
  "$([ "$(git -C "$RR" rev-parse 'feat/union^1')" = "$RR_TIP" ] \
    && [ "$(git -C "$RR" rev-parse 'feat/union^2')" = "$RR_MAIN" ]; echo $?)"
chk_has "merge-cycle: the merge commit carries the conventional subject" \
  "$(git -C "$RR" log --format=%s -1 feat/union)" "chore(merge): merge origin/main"
chk "merge-cycle: FEATURES in the pushed head equals a fresh generate" \
  "$([ "$(git -C "$RR" show feat/union:docs/reference/FEATURES.md)" = "$(printf 'a.md\nb.md\no.md\n')" ]; echo $?)"
chk "merge-cycle: the generator ran (its ignored marker exists)" \
  "$([ -f "$RR/gen-ran.marker" ]; echo $?)"

echo "--- merge-cycle: a generator the branch changed is never run"
build_remerge_reg rgen --branch-gen
RRG="$TMPD/rr-clone-rgen"; RRG_TIP="$(git -C "$RRG" rev-parse feat/union)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS="$(open_one 101)" GH_STUB_PR_101="$(conflict_json 101 "$RRG_TIP")" \
  "$WRAP" merge --apply "$RRG" 2>&1)"; rc=$?
chk "merge-cycle: a branch-changed generator exits 0 without merging" "$rc"
chk_has "merge-cycle: FEATURES is refused by name" "$out" \
  "REFUSED feat/union: conflict in docs/reference/FEATURES.md"
chk "merge-cycle: the generator never ran (marker absent)" \
  "$([ ! -e "$RRG/gen-ran.marker" ]; echo $?)"
chk "merge-cycle: the branch tip is untouched" \
  "$([ "$(git -C "$RRG" rev-parse feat/union)" = "$RRG_TIP" ]; echo $?)"
chk "merge-cycle: origin holds only the pre-merge tip" \
  "$([ "$(git -C "$TMPD/rr-bare-rgen" rev-parse feat/union)" = "$RRG_TIP" ]; echo $?)"
chk "merge-cycle: a branch-changed generator called no pr merge" \
  "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

echo "--- merge-cycle: a restore that cannot finish needs a human"
build_remerge_reg rhuman
RRH="$TMPD/rr-clone-rhuman"; RRH_TIP="$(git -C "$RRH" rev-parse feat/union)"
printf 'conflict\n' >> "$RRH/base.txt"; git -C "$RRH" commit -qam "branch edits base.txt"
git -C "$RRH" push -q origin feat/union
RRH_TIP="$(git -C "$RRH" rev-parse feat/union)"
RH_ADV="$TMPD/rr-adv-rhuman"; git clone -q "$TMPD/rr-bare-rhuman" "$RH_ADV"; gitc "$RH_ADV"
printf 'conflict-other\n' >> "$RH_ADV/base.txt"
git -C "$RH_ADV" commit -qam "main edits base.txt"; git -C "$RH_ADV" push -q origin main
git -C "$RRH" fetch -q origin main
mkdir -p "$TMPD/gshim-noabort"
cat > "$TMPD/gshim-noabort/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "--abort" ] && exit 1; done
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-noabort/git"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-noabort:$PATH" \
  GH_STUB_OPEN_PRS="$(open_one 102)" GH_STUB_PR_102="$(conflict_json 102 "$RRH_TIP")" \
  "$WRAP" merge --apply "$RRH" 2>&1)"; rc=$?
chk "merge-cycle: an unrestored re-merge exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "merge-cycle: ABORT FAILED is named" "$out" "ABORT FAILED feat/union"
chk_has "merge-cycle: the human-needing checkout is named" "$out" \
  "FAILED merge #102: the re-merge left $(cd "$RRH" && pwd -P) needing a human"
chk "merge-cycle: no squash-fallback PR was created" \
  "$(grep -q '^pr create' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge-cycle: the merge is still in progress for the human" \
  "$([ -e "$RRH/.git/MERGE_HEAD" ]; echo $?)"

echo "--- merge-cycle: --verify red pushes nothing and the PR stays open"
build_remerge rver
RRV="$TMPD/rm-clone-rver"; RRV_TIP="$(git -C "$RRV" rev-parse feat/union)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS="$(open_one 103)" GH_STUB_PR_103="$(conflict_json 103 "$RRV_TIP")" \
  "$WRAP" merge --apply --verify false "$RRV" 2>&1)"; rc=$?
chk "merge-cycle: verify red exits 0 without merging" "$rc"
chk_has "merge-cycle: VERIFY FAILED names the checkout" "$out" \
  "VERIFY FAILED feat/union: false exited 1 in $(cd "$RRV" && pwd -P)"
chk "merge-cycle: verify red pushed nothing" \
  "$([ "$(git -C "$TMPD/rm-bare-rver" rev-parse feat/union)" = "$RRV_TIP" ]; echo $?)"
chk "merge-cycle: verify red called no pr merge" \
  "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge-cycle: verify red restored the tip" \
  "$([ "$(git -C "$RRV" rev-parse feat/union)" = "$RRV_TIP" ]; echo $?)"

echo "--- merge-cycle: TERM inside a scratch-worktree cycle exits 130 and drops it"
build_remerge rint
RRI="$TMPD/rm-clone-rint"
git -C "$RRI" checkout -q main; git -C "$RRI" branch -qD feat/union
RRI_TIP="$(git -C "$TMPD/rm-bare-rint" rev-parse feat/union)"
RRI_WT_BEFORE="$(git -C "$RRI" worktree list --porcelain | grep -c '^worktree ')"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS="$(open_one 104)" GH_STUB_PR_104="$(conflict_json 104 "$RRI_TIP")" \
  GH_STUB_LAND_REPO="$RRI" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-rint" GH_STUB_LAND_BRANCH=origin/feat/union \
  "$WRAP" merge --apply --verify 'kill -TERM $PPID' "$RRI" 2>&1)"; rc=$?
chk "merge-cycle: an interrupted scratch cycle exits 130" "$([ "$rc" -eq 130 ]; echo $?)"
chk "merge-cycle: the scratch worktree and its temp dir are gone" \
  "$([ "$(git -C "$RRI" worktree list --porcelain | grep -c '^worktree ')" -eq "$RRI_WT_BEFORE" ]; echo $?)"
chk "merge-cycle: the interrupt pushed nothing" \
  "$([ "$(git -C "$TMPD/rm-bare-rint" rev-parse feat/union)" = "$RRI_TIP" ]; echo $?)"

echo "--- merge-cycle: --verify with no value exits 64, and --help names the flag"
out="$("$WRAP" merge --verify 2>&1)"; rc=$?
chk "merge-cycle: bare --verify exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "merge-cycle: bare --verify names the missing value" "$out" "--verify needs a value"
out="$("$WRAP" merge "$TMPD" --verify 2>&1)"; rc=$?
chk "merge-cycle: trailing --verify exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk "merge-cycle: wrap --help names --verify" \
  "$("$WRAP" --help 2>/dev/null | grep -q -- '--verify'; echo $?)"
chk "merge-cycle: bin/wrap usage names --verify on both verbs" \
  "$([ "$(grep -c -- '--verify' "$WRAP")" -ge 2 ]; echo $?)"

# ===========================================================================
echo "=== merge: a stale head after wrap's own push resyncs with one close and reopen ==="
# ===========================================================================
# GitHub can keep serving the pre-push head after wrap's re-merge push. When the settle
# wait ends on it and origin holds exactly the pushed commit, wrap closes and reopens its
# own PR once. Every case runs the bare form. Reads of the PR: 1 the cache loop, 2 to 4 the
# settle window (bound 4s, no-op sleep), 5 the resync's own read, 6 on the state reads.
rs_json() { # rs_json <number> <head oid> <mergeable> <mergeStateStatus> [jq edit]
  printf '{"number":%s,"title":"log entry","headRefName":"feat/union","headRefOid":"%s","baseRefName":"main","mergeable":"%s","mergeStateStatus":"%s","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"state":"OPEN","isDraft":false,"isCrossRepository":false,"autoMergeRequest":null}' \
    "$1" "$2" "$3" "$4" | jq -c "${5:-.}"
}
rs_tip() { git -C "$TMPD/rm-bare-$1" rev-parse feat/union; }
rs_count() { grep -c -- "$1" "$GH_STUB_CALLS" || true; }
rs_reads() { cat "$GH_STUB_CALLS.view-$1" 2>/dev/null || echo 0; }
RS_PIDF="$TMPD/rs-wrap.pid"; RS_ERRF="$TMPD/rs-wrap.err"
RS_FLAGS=""  # extra merge flags for one case, e.g. "--pr 116"; reset after every run
rs_merge() { # rs_merge <n> <name> [VAR=value ...] -- later VAR=value pairs win
  local n="$1" name="$2" stale; shift 2
  stale="$(rs_json "$n" "$(rs_tip "$name")" CONFLICTING DIRTY)"
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  # stdout and stderr are kept apart so a case can check which stream a line went to.
  # shellcheck disable=SC2086
  RS_STDOUT="$(env PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=4 \
    GH_STUB_OPEN_PRS="$(open_one "$n")" "GH_STUB_PR_${n}=${stale}" "GH_STUB_PR_${n}_2=${stale}" \
    GH_STUB_LAND_REPO="$TMPD/rm-clone-$name" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-$name" \
    GH_STUB_LAND_BRANCH=feat/union GH_STUB_KILL_PIDFILE="$RS_PIDF" "$@" \
    sh -c 'echo $$ > "$0"; exec "$@"' "$RS_PIDF" "$WRAP" merge --apply $RS_FLAGS "$TMPD/rm-clone-$name" 2>"$RS_ERRF")"
  RS_RC=$?
  RS_ERR="$(cat "$RS_ERRF")"
  RS_OUT="${RS_STDOUT}
${RS_ERR}"
  RS_FLAGS=""
}
rs_merged() { # rs_merged <n> <name> -- merged, tree verified, pinned to the pushed head
  local pushed; pushed="$(git -C "$TMPD/rm-clone-$2" rev-parse feat/union)"
  chk "resync #$1: exits 0" "$RS_RC"
  chk_has "resync #$1: merged, tree verified" "$RS_OUT" "merged #$1 ($(git -C "$TMPD/rm-bare-$2" rev-parse main)): tree verified"
  chk "resync #$1: merge pinned to the pushed head" \
    "$(grep -q -- "^pr merge $1 .*--match-head-commit ${pushed}" "$GH_STUB_CALLS"; echo $?)"
}
rs_untouched() { # rs_untouched <n> [expected exit, default 0] -- no close, no reopen, no merge
  chk "resync #$1: exits ${2:-0}" "$([ "$RS_RC" -eq "${2:-0}" ]; echo $?)"
  chk "resync #$1: no pr close" "$([ "$(rs_count "^pr close $1")" -eq 0 ]; echo $?)"
  chk "resync #$1: no pr reopen" "$([ "$(rs_count "^pr reopen $1")" -eq 0 ]; echo $?)"
  chk "resync #$1: no pr merge" "$([ "$(rs_count "^pr merge")" -eq 0 ]; echo $?)"
}

echo "--- resync: a stale head is closed and reopened once, then merged"
build_remerge rs90; T="$(rs_tip rs90)"
rs_merge 90 rs90 GH_STUB_PR_90_REOPENED="$(rs_json 90 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 90 rs90
chk_has "resync #90: names the resync" "$RS_OUT" "#90 still shows head $(printf '%s' "$T" | cut -c1-7) after the push of"
chk_has "resync #90: reports it" "$RS_OUT" "resynced #90: closed and reopened"
chk_has "resync #90: eligible after the re-merge" "$RS_OUT" "eligible #90 after the re-merge"
chk "resync #90: one close" "$([ "$(rs_count '^pr close 90')" -eq 1 ]; echo $?)"
chk "resync #90: one reopen" "$([ "$(rs_count '^pr reopen 90')" -eq 1 ]; echo $?)"
chk "resync #90: one comment" "$([ "$(rs_count '^pr comment 90')" -eq 1 ]; echo $?)"
chk "resync #90: the close comes before the reopen" \
  "$([ "$(grep -n '^pr close 90' "$GH_STUB_CALLS" | cut -d: -f1)" -lt "$(grep -n '^pr reopen 90' "$GH_STUB_CALLS" | cut -d: -f1)" ]; echo $?)"
chk "resync #90: the close carries no --comment, -d or --delete-branch" \
  "$(grep '^pr close 90' "$GH_STUB_CALLS" | grep -qE -- '--comment|--delete-branch|(^| )-d( |$)' && echo 1 || echo 0)"
chk_no "resync #90: the comment carries no branch name" "$(grep '^pr comment 90' "$GH_STUB_CALLS")" "feat/union"

echo "--- resync: GitHub caught up before the close, so no close runs"
build_remerge rs96
rs_merge 96 rs96 GH_STUB_PR_96_5="$(rs_json 96 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 96 rs96
chk_has "resync #96: caught up on its own" "$RS_OUT" "#96 caught up on its own; no resync needed"
chk "resync #96: no pr close" "$([ "$(rs_count '^pr close 96')" -eq 0 ]; echo $?)"
chk_no "resync #96: no still-stale text" "$RS_OUT" "still stale"

echo "--- resync: a refusing step 1 read never closes"
build_remerge rs92; T="$(rs_tip rs92)"
rs_merge 92 rs92 GH_STUB_PR_92_5="$(rs_json 92 "$T" CONFLICTING DIRTY '.isDraft = true')"
rs_untouched 92
chk_has "resync #92: a draft is named" "$RS_OUT" "no resync for #92: isDraft is not false"
chk_has "resync #92: the existing SKIP stands" "$RS_OUT" "SKIP #92 after the re-merge: head is"
build_remerge rs93; T="$(rs_tip rs93)"
rs_merge 93 rs93 GH_STUB_PR_93_5="$(rs_json 93 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
rs_untouched 93
chk_has "resync #93: a closed PR is named" "$RS_OUT" "no resync for #93: state CLOSED"
build_remerge rs102; T="$(rs_tip rs102)"
rs_merge 102 rs102 GH_STUB_PR_102_5="$(rs_json 102 "$T" CONFLICTING DIRTY '.autoMergeRequest = {"mergeMethod":"SQUASH"}')"
rs_untouched 102
chk_has "resync #102: armed auto-merge is named" "$RS_OUT" "no resync for #102: auto-merge armed or unreadable"
build_remerge rs105; T="$(rs_tip rs105)"
rs_merge 105 rs105 GH_STUB_PR_105_5="$(rs_json 105 "$T" CONFLICTING DIRTY 'del(.state)')"
rs_untouched 105
chk_has "resync #105: a missing state fails closed" "$RS_OUT" "no resync for #105: state unreadable"
build_remerge rs106; T="$(rs_tip rs106)"
rs_merge 106 rs106 GH_STUB_PR_106_5="$(rs_json 106 "$T" CONFLICTING DIRTY 'del(.isDraft)')"
rs_untouched 106
chk_has "resync #106: a missing isDraft fails closed" "$RS_OUT" "no resync for #106: isDraft is not false"
build_remerge rs107; T="$(rs_tip rs107)"
rs_merge 107 rs107 GH_STUB_PR_107_5="$(rs_json 107 "$T" CONFLICTING DIRTY 'del(.autoMergeRequest)')"
rs_untouched 107
chk_has "resync #107: a missing autoMergeRequest fails closed" "$RS_OUT" "no resync for #107: auto-merge armed or unreadable"

echo "--- resync: origin moved past the pushed commit, so no close"
build_remerge rs91
mkdir -p "$TMPD/rm-bare-rs91/hooks"
cat > "$TMPD/rm-bare-rs91/hooks/post-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
  [ "$ref" = refs/heads/feat/union ] || continue
  c="$(GIT_AUTHOR_NAME=f GIT_AUTHOR_EMAIL=f@f GIT_COMMITTER_NAME=f GIT_COMMITTER_EMAIL=f@f \
    git commit-tree "${new}^{tree}" -p "$new" -m foreign)"
  git update-ref refs/heads/feat/union "$c"
done
HOOK
chmod +x "$TMPD/rm-bare-rs91/hooks/post-receive"
rs_merge 91 rs91
rs_untouched 91
chk_has "resync #91: a foreign origin tip is named" "$RS_OUT" "no resync for #91: origin tip is"

echo "--- resync: open dependents skip the resync (bare form only)"
build_remerge rs98
rs_merge 98 rs98 \
  GH_STUB_OPEN_PRS='[{"number":98,"title":"log entry","headRefName":"feat/union"},{"number":99,"title":"stacked","headRefName":"feat/child"}]' \
  GH_STUB_PR_99='{"number":99,"title":"stacked","headRefName":"feat/child","headRefOid":"aa","baseRefName":"feat/union","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}'
rs_untouched 98
chk_has "resync #98: dependents are named" "$RS_OUT" "no resync for #98: dependents open"
chk_has "resync #98: the dependent itself is not eligible" "$RS_OUT" "SKIP #99 stacked: base is feat/union"

echo "--- resync: a decoy ref that tail-matches the branch does not fool the origin check"
build_remerge rs103
git -C "$TMPD/rm-bare-rs103" update-ref refs/heads/a/refs/heads/feat/union "$(rs_tip rs103)"
rs_merge 103 rs103 GH_STUB_PR_103_REOPENED="$(rs_json 103 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 103 rs103
chk "resync #103: one close" "$([ "$(rs_count '^pr close 103')" -eq 1 ]; echo $?)"

echo "--- resync: two failed reopens exit 2 and name the reopen command"
build_remerge rs94
rs_merge 94 rs94 GH_STUB_REOPEN_RC=1
chk "resync #94: exits 2" "$([ "$RS_RC" -eq 2 ]; echo $?)"
chk_has "resync #94: names the reopen command" "$RS_OUT" \
  "FAILED merge #94: closed #94 to resync its head, and the reopen failed; reopen it: gh pr reopen 94 --repo"
chk_has "resync #94: names the re-push step" "$RS_OUT" "(if origin lost feat/union, push it at"
chk "resync #94: two reopens" "$([ "$(rs_count '^pr reopen 94')" -eq 2 ]; echo $?)"
chk "resync #94: one comment saying the reopen failed" \
  "$([ "$(grep '^pr comment 94' "$GH_STUB_CALLS" | grep -c 'the reopen failed')" -eq 1 ]; echo $?)"
chk_no "resync #94: the comment carries no branch name" "$(grep '^pr comment 94' "$GH_STUB_CALLS")" "feat/union"
chk "resync #94: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"

echo "--- resync: one failed reopen, then the retry succeeds"
build_remerge rs95
rs_merge 95 rs95 GH_STUB_REOPEN_FAILS=1 GH_STUB_PR_95_REOPENED="$(rs_json 95 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 95 rs95
chk "resync #95: two reopens" "$([ "$(rs_count '^pr reopen 95')" -eq 2 ]; echo $?)"

echo "--- resync: a failed close is judged by state, fail closed"
build_remerge rs100; T="$(rs_tip rs100)"
rs_merge 100 rs100 GH_STUB_CLOSE_RC=1 GH_STUB_PR_100_6="$(rs_json 100 "$T" CONFLICTING DIRTY)"
chk "resync #100: exits 0" "$RS_RC"
chk "resync #100: no reopen" "$([ "$(rs_count '^pr reopen 100')" -eq 0 ]; echo $?)"
chk_has "resync #100: an open PR after a failed close is named" "$RS_OUT" "no resync for #100: close failed and #100 is still open"
chk_has "resync #100: the existing SKIP stands" "$RS_OUT" "SKIP #100 after the re-merge: head is"
build_remerge rs101
rs_merge 101 rs101 GH_STUB_CLOSE_RC=1 GH_STUB_PR_101_6='{}'
chk "resync #101: exits 2" "$([ "$RS_RC" -eq 2 ]; echo $?)"
chk_has "resync #101: names the unreadable close on stderr" "$RS_ERR" \
  "FAILED merge #101: close #101 errored and its state is unreadable; if it is closed: gh pr reopen 101 --repo"
chk_no "resync #101: the FAILED line is not on stdout" "$RS_STDOUT" "FAILED merge #101"
chk "resync #101: three state reads, no more" "$([ "$(rs_reads 101)" -eq 8 ]; echo $?)"
chk "resync #101: no reopen" "$([ "$(rs_count '^pr reopen 101')" -eq 0 ]; echo $?)"
chk "resync #101: no comment" "$([ "$(rs_count '^pr comment 101')" -eq 0 ]; echo $?)"
chk "resync #101: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"
build_remerge rs108; T="$(rs_tip rs108)"
rs_merge 108 rs108 GH_STUB_CLOSE_RC=1 GH_STUB_PR_108_6='{}' \
  GH_STUB_PR_108_7="$(rs_json 108 "$T" CONFLICTING DIRTY '.state = "CLOSED"')" \
  GH_STUB_PR_108_REOPENED="$(rs_json 108 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 108 rs108
chk "resync #108: one reopen after the CLOSED read" "$([ "$(rs_count '^pr reopen 108')" -eq 1 ]; echo $?)"

echo "--- resync: still stale after the reopen, one pair only and the next steps named"
build_remerge rs97
rs_merge 97 rs97
chk "resync #97: exits 0" "$RS_RC"
chk "resync #97: one close" "$([ "$(rs_count '^pr close 97')" -eq 1 ]; echo $?)"
chk "resync #97: one reopen" "$([ "$(rs_count '^pr reopen 97')" -eq 1 ]; echo $?)"
chk_has "resync #97: names the wait" "$RS_OUT" \
  "still stale after a close and reopen; wait until gh pr view 97 --json headRefOid shows"
chk_has "resync #97: names the manual close and reopen" "$RS_OUT" "gh pr close 97 && gh pr reopen 97"
chk "resync #97: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"

echo "--- resync: an interrupt inside the close window reopens and exits 130"
build_remerge rs104; T="$(rs_tip rs104)"
rs_merge 104 rs104 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_104_6="$(rs_json 104 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #104: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #104: prints the recovery command on stderr" "$RS_ERR" \
  "INTERRUPTED inside the resync of #104; if #104 is closed, reopen it: gh pr reopen 104 --repo"
chk_has "resync #104: reports the reopen" "$RS_OUT" "reopened #104 after the interrupt"
chk "resync #104: one reopen" "$([ "$(rs_count '^pr reopen 104')" -eq 1 ]; echo $?)"
chk "resync #104: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"
build_remerge rs109; T="$(rs_tip rs109)"
rs_merge 109 rs109 GH_STUB_CLOSE_KILL=1 GH_STUB_CLOSE_RC=1 \
  GH_STUB_PR_109_6="$(rs_json 109 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #109: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #109: reports the reopen" "$RS_OUT" "reopened #109 after the interrupt"
chk "resync #109: one reopen" "$([ "$(rs_count '^pr reopen 109')" -eq 1 ]; echo $?)"
chk "resync #109: the handler's read is the last one (6 reads)" "$([ "$(rs_reads 109)" -eq 6 ]; echo $?)"

echo "--- resync: an interrupt before the close stops the run with the PR untouched"
build_remerge rs110
rs_merge 110 rs110 GH_STUB_VIEW_KILL_110_5=1
chk_has "resync #110: says nothing changed" "$RS_OUT" \
  "INTERRUPTED inside the resync of #110 before the close; nothing changed on GitHub"
rs_untouched 110 130

echo "--- resync: the handler acts only on exactly CLOSED"
build_remerge rs111; T="$(rs_tip rs111)"
rs_merge 111 rs111 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_111_6="$(rs_json 111 "$T" CONFLICTING DIRTY)"
chk "resync #111: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #111: an open PR is left alone" "$RS_ERR" "#111 is still open after the interrupt; nothing to undo"
chk "resync #111: no reopen" "$([ "$(rs_count '^pr reopen 111')" -eq 0 ]; echo $?)"
build_remerge rs112
rs_merge 112 rs112 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_112_6='{}'
chk "resync #112: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #112: an unreadable state is reported" "$RS_ERR" \
  "#112 state reads 'unreadable' after the interrupt, so no reopen was tried; check it: gh pr view 112 --repo"
chk "resync #112: no reopen" "$([ "$(rs_count '^pr reopen 112')" -eq 0 ]; echo $?)"
build_remerge rs113; T="$(rs_tip rs113)"
rs_merge 113 rs113 GH_STUB_CLOSE_KILL=1 GH_STUB_REOPEN_RC=1 \
  GH_STUB_PR_113_6="$(rs_json 113 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #113: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #113: a failed reopen names the command" "$RS_ERR" \
  "could not reopen #113 after the interrupt; reopen it: gh pr reopen 113 --repo"
chk "resync #113: the handler and the wrapper each try once (2 reopens)" \
  "$([ "$(rs_count '^pr reopen 113')" -eq 2 ]; echo $?)"

echo "--- resync: the handler read OPEN before the close landed; one more read reopens it"
build_remerge rs117; T="$(rs_tip rs117)"
rs_merge 117 rs117 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_117_6="$(rs_json 117 "$T" CONFLICTING DIRTY)" \
  GH_STUB_PR_117_7="$(rs_json 117 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #117: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #117: the late read reopens" "$RS_ERR" "reopened #117 after the interrupt"
chk "resync #117: one reopen" "$([ "$(rs_count '^pr reopen 117')" -eq 1 ]; echo $?)"

echo "--- resync: an interrupt during a failed close's state reads"
build_remerge rs115; T="$(rs_tip rs115)"
rs_merge 115 rs115 GH_STUB_CLOSE_RC=1 GH_STUB_VIEW_KILL_115_6=1 GH_STUB_PR_115_6='{}' \
  GH_STUB_PR_115_7="$(rs_json 115 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #115: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #115: the handler reopens" "$RS_ERR" "reopened #115 after the interrupt"
chk "resync #115: one reopen" "$([ "$(rs_count '^pr reopen 115')" -eq 1 ]; echo $?)"

echo "--- resync: a failed comment never fails the merge"
build_remerge rs114
rs_merge 114 rs114 GH_STUB_COMMENT_RC=1 GH_STUB_PR_114_REOPENED="$(rs_json 114 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 114 rs114
chk_has "resync #114: names the failed comment" "$RS_OUT" "comment on #114 failed; the resync itself is unaffected"

echo "--- resync: the --pr form resyncs the same way"
build_remerge rs116
RS_FLAGS="--pr 116"
rs_merge 116 rs116 GH_STUB_PR_116_REOPENED="$(rs_json 116 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 116 rs116
chk "resync #116: one close" "$([ "$(rs_count '^pr close 116')" -eq 1 ]; echo $?)"

echo "--- resync: a moved, unreadable or fork head at step 1 never closes"
build_remerge rs118
rs_merge 118 rs118 GH_STUB_PR_118_5="$(rs_json 118 4444444444444444444444444444444444444444 CONFLICTING DIRTY)"
rs_untouched 118
chk_has "resync #118: a moved head is named" "$RS_OUT" "no resync for #118: head moved to 4444444"
build_remerge rs119
rs_merge 119 rs119 GH_STUB_FAIL_VIEW_119_5=1
rs_untouched 119
chk_has "resync #119: a failed read is named" "$RS_OUT" "no resync for #119: unreadable PR state"
build_remerge rs121; T="$(rs_tip rs121)"
rs_merge 121 rs121 GH_STUB_PR_121_5="$(rs_json 121 "$T" CONFLICTING DIRTY '.isCrossRepository = true')"
rs_untouched 121
chk_has "resync #121: a fork PR is named" "$RS_OUT" "no resync for #121: a fork PR or unreadable"

echo "--- resync: origin lost the branch after the push"
build_remerge rs122
mkdir -p "$TMPD/rm-bare-rs122/hooks"
cat > "$TMPD/rm-bare-rs122/hooks/post-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
  [ "$ref" = refs/heads/feat/union ] && git update-ref -d refs/heads/feat/union
done
HOOK
chmod +x "$TMPD/rm-bare-rs122/hooks/post-receive"
rs_merge 122 rs122
rs_untouched 122
chk_has "resync #122: a missing origin ref is named" "$RS_OUT" "no resync for #122: origin ref is ambiguous or missing"

echo "--- resync: the helper restores the caller's traps, resets its flag, and strips userinfo"
cat > "$TMPD/rs-unit.sh" <<'UNIT'
source "$1/lib/wrap/wrap-common.sh"
source "$1/lib/wrap/wrap-merge.sh"
trap 'echo caller-term' TERM
int_before="$(trap -p INT)"
_RS_HIT=1
_pr_head_resync /nonexistent https://example.invalid/o/r 120 feat/x \
  1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 >/dev/null
echo "rc=$?"
echo "term=$(trap -p TERM)"
[ "$(trap -p INT)" = "$int_before" ] && echo "int=unchanged" || echo "int=changed"
echo "pub1=$(_url_public 'https://u:p@ss@host.example/o/r.git')"
echo "pub2=$(_url_public 'git@github.com:o/r.git')"
echo "pub3=$(_url_public 'https://github.com/o/r')"
UNIT
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_PR_120="$(rs_json 120 2222222222222222222222222222222222222222 MERGEABLE CLEAN)" \
  bash "$TMPD/rs-unit.sh" "$KIT_DIR" 2>&1)"
chk_has "resync unit: a stale flag from an earlier run is reset (caught up, rc 3)" "$out" "rc=3"
chk_has "resync unit: the caller's TERM trap is back" "$out" "term=trap -- 'echo caller-term'"
chk_has "resync unit: the caller's INT disposition is back" "$out" "int=unchanged"
chk_no "resync unit: no INT trap remains" "$out" "_resync_trap"
chk_has "resync unit: userinfo is stripped, a raw @ in the password too" "$out" "pub1=https://host.example/o/r.git"
chk_has "resync unit: an scp-style URL is unchanged" "$out" "pub2=git@github.com:o/r.git"
chk_has "resync unit: a plain URL is unchanged" "$out" "pub3=https://github.com/o/r"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-merge: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-merge: all $PASS passed"
