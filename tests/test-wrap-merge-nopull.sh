#!/usr/bin/env bash
# test-wrap-merge-nopull.sh -- `wrap merge --no-pull` (the step 0 stop): a PR whose head branch
# the main checkout holds is skipped whatever its state; `merge --repo <owner>/<name>` (no checkout). Split from test-wrap-merge.sh so its
# negative controls run in seconds, away from that suite's signal-timing cases.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# build_remerge: a bare origin whose feat/union and main both appended to a union-marked log,
# plus a clone with feat/union checked out in its MAIN checkout.
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

echo "--- merge --no-pull: a PR whose head the main checkout holds is skipped, whatever its state"
# Under a step 0 stop the main checkout belongs to a live session, and its checked-out branch is
# that session's mid-iteration work. build_remerge leaves feat/union checked out in the clone.
build_remerge np
NPM="$TMPD/rm-clone-np"; NPM_TIP="$(git -C "$NPM" rev-parse feat/union)"
clean_json() { # clean_json <number> <tip>
  printf '{"number":%s,"title":"log entry","headRefName":"feat/union","headRefOid":"%s","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2"
}
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 61)" GH_STUB_PR_61="$(conflict_json 61 "$NPM_TIP")" \
  "$WRAP" merge --apply --no-pull "$NPM" 2>&1)"; rc=$?
chk "merge --no-pull, CONFLICTING held by main: exits 0" "$rc"
chk_has "merge --no-pull, CONFLICTING held by main: skips by name" "$out" \
  "SKIP #61: head feat/union is checked out in the main checkout (--no-pull)"
chk_no "merge --no-pull, CONFLICTING held by main: no re-merge attempted" "$out" "re-merge"
chk "merge --no-pull, CONFLICTING held by main: the branch tip and checkout are untouched" \
  "$([ "$(git -C "$NPM" rev-parse feat/union)" = "$NPM_TIP" ] && [ "$(git -C "$NPM" rev-parse HEAD)" = "$NPM_TIP" ]; echo $?)"
chk "merge --no-pull, CONFLICTING held by main: no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
out="$(GH_STUB_OPEN_PRS="$(open_one 62)" GH_STUB_PR_62="$(clean_json 62 "$NPM_TIP")" \
  "$WRAP" merge --apply --no-pull "$NPM" 2>&1)"
chk_has "merge --no-pull, a CLEAN PR held by main is skipped too" "$out" \
  "SKIP #62: head feat/union is checked out in the main checkout (--no-pull)"
chk_no "merge --no-pull, a CLEAN PR held by main: not eligible" "$out" "eligible #62"
chk "merge --no-pull, a CLEAN PR held by main: no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
out="$(GH_STUB_OPEN_PRS="$(open_one 63)" GH_STUB_PR_63="$(clean_json 63 "$NPM_TIP")" \
  "$WRAP" merge --apply --no-pull --pr 63 "$NPM" 2>&1)"
chk_has "merge --no-pull --pr: the named PR is skipped by name" "$out" \
  "SKIP #63: head feat/union is checked out in the main checkout (--no-pull)"
chk "merge --no-pull --pr: no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
: > "$GH_STUB_CALLS"
DRAFT_JSON="$(clean_json 66 "$NPM_TIP" | sed 's/"statusCheckRollup"/"isDraft":true,"statusCheckRollup"/')"
out="$(GH_STUB_OPEN_PRS="$(open_one 66)" GH_STUB_PR_66="$DRAFT_JSON" \
  "$WRAP" merge --apply --no-pull --pr 66 "$NPM" 2>&1)"
chk_has "merge --no-pull --pr: a draft held by main is skipped by name" "$out" \
  "SKIP #66: head feat/union is checked out in the main checkout (--no-pull)"
chk "merge --no-pull --pr: a draft held by main is never marked ready" "$(grep -q '^pr ready' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge --no-pull --pr: a draft held by main is never merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
out="$(GH_STUB_OPEN_PRS="$(open_one 64)" GH_STUB_PR_64="$(clean_json 64 "$NPM_TIP")" \
  "$WRAP" merge "$NPM" 2>&1)"
chk_has "control, without --no-pull: the same held PR is eligible" "$out" "eligible #64"
chk_no "control, without --no-pull: no main-checkout skip" "$out" "checked out in the main checkout"

echo "--- merge --no-pull: a branch held by a LINKED worktree is not skipped"
build_remerge npw
NPW="$TMPD/rm-clone-npw"; NPW_TIP="$(git -C "$NPW" rev-parse feat/union)"
git -C "$NPW" checkout -q main
git -C "$NPW" worktree add -q "$TMPD/rm-wt-npw" feat/union
out="$(GH_STUB_OPEN_PRS="$(open_one 65)" GH_STUB_PR_65="$(clean_json 65 "$NPW_TIP")" \
  "$WRAP" merge --no-pull "$NPW" 2>&1)"
chk_has "merge --no-pull: a PR held by a linked worktree stays eligible" "$out" "eligible #65"
chk_no "merge --no-pull: a PR held by a linked worktree gets no skip" "$out" "checked out in the main checkout"


echo "--- merge --repo <owner>/<name>: no local checkout, gh-only gate, merge and verify"
# No path, no clone: the stub answers by slug. Every local step is skipped and the run says so.
RM_JSON() { # RM_JSON <number> <mergeable> <extra json fields, trailing comma>
  printf '{"number":%s,"title":"remote pr","headRefName":"feat/r","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","baseRefName":"main",%s"mergeable":"%s","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "${3:-}" "$2"
}
RM_MERGED='{"state":"MERGED","mergeCommit":{"oid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}'
: > "$GH_STUB_CALLS"
out="$(cd "$TMPD" && GH_STUB_OPEN_PRS="$(open_one 71)" GH_STUB_PR_71="$(RM_JSON 71 MERGEABLE)"   GH_STUB_VIEW_STATE="$RM_MERGED" "$WRAP" merge --apply --pr 71 --repo o/r 2>&1)"; rc=$?
chk "merge --repo: exits 0" "$rc"
chk_has "merge --repo: says the local steps are skipped" "$out" "no local checkout, so the re-merge push, tree verify and pull are skipped"
chk_has "merge --repo: reports the merge verified through gh api" "$out" \
  "merged #71 (bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb): verified on main via gh api"
chk "merge --repo: squash-merged once, pinned to the gated head, against the slug" \
  "$(grep -c '^pr merge 71 --repo o/r --squash --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$GH_STUB_CALLS" | grep -qx 1; echo $?)"
chk "merge --repo: read the default branch and the compare through gh api" \
  "$(grep -q '^api repos/o/r --jq .default_branch' "$GH_STUB_CALLS" && grep -q '^api repos/o/r/compare/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\.\.\.main' "$GH_STUB_CALLS"; echo $?)"
chk "merge --repo: never marks anything ready" "$(grep -q '^pr ready' "$GH_STUB_CALLS" && echo 1 || echo 0)"

out="$(GH_STUB_OPEN_PRS="$(open_one 72)" GH_STUB_PR_72="$(RM_JSON 72 MERGEABLE)" "$WRAP" merge --repo o/r 2>&1)"; rc=$?
chk "merge --repo dry run: exits 0" "$rc"
chk_has "merge --repo dry run: lists the PR as eligible" "$out" "eligible #72 remote pr [feat/r]"
chk_has "merge --repo dry run: stops at the dry-run line" "$out" "dry run; pass --apply"

: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 73)" GH_STUB_PR_73="$(RM_JSON 73 MERGEABLE)" \
  GH_STUB_VIEW_STATE="$RM_MERGED" GH_STUB_COMPARE_BASE=cccccccccccccccccccccccccccccccccccccccc \
  "$WRAP" merge --apply --repo o/r 2>&1)"; rc=$?
chk "merge --repo: a merge commit absent from the default branch exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "merge --repo: names the failed verification" "$out" "merge commit is not on main"
out="$(GH_STUB_OPEN_PRS="$(open_one 73)" GH_STUB_PR_73="$(RM_JSON 73 MERGEABLE)" \
  GH_STUB_VIEW_STATE="$RM_MERGED" GH_STUB_COMPARE_RC=1 "$WRAP" merge --apply --repo o/r 2>&1)"; rc=$?
chk "merge --repo: an unreadable compare exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
out="$(GH_STUB_OPEN_PRS="$(open_one 73)" GH_STUB_PR_73="$(RM_JSON 73 MERGEABLE)" \
  GH_STUB_VIEW_STATE='{"state":"OPEN","mergeCommit":null}' "$WRAP" merge --apply --repo o/r 2>&1)"; rc=$?
chk "merge --repo: a PR gh does not report MERGED exits 2" "$([ "$rc" -eq 2 ]; echo $?)"

echo "--- merge --repo: the gate and the authorship rule hold"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 74)" GH_STUB_PR_74="$(RM_JSON 74 MERGEABLE '"isDraft":true,')" \
  "$WRAP" merge --apply --pr 74 --repo o/r 2>&1)"; rc=$?
chk_has "merge --repo --pr: a draft is refused" "$out" "SKIP #74 remote pr: draft"
chk "merge --repo --pr: a draft is never marked ready" "$(grep -q '^pr ready' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge --repo --pr: a draft is never merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
out="$(GH_STUB_OPEN_PRS="$(open_one 75)" GH_STUB_PR_75="$(RM_JSON 75 MERGEABLE | sed 's/"APPROVED"/"CHANGES_REQUESTED"/')" \
  "$WRAP" merge --apply --pr 75 --repo o/r 2>&1)"
chk_has "merge --repo: changes requested is refused" "$out" "SKIP #75 remote pr: changes requested"
out="$(GH_STUB_OPEN_PRS="$(open_one 76)" GH_STUB_PR_76="$(RM_JSON 76 MERGEABLE | sed 's/"SUCCESS"/"FAILURE"/')" \
  "$WRAP" merge --apply --pr 76 --repo o/r 2>&1)"
chk_has "merge --repo: a failing check is refused" "$out" "SKIP #76 remote pr: checks are pending or failing"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 77)" GH_STUB_PR_77="$(RM_JSON 77 CONFLICTING)" \
  "$WRAP" merge --apply --pr 77 --repo o/r 2>&1)"; rc=$?
chk_has "merge --repo: a conflicting PR is refused" "$out" "SKIP #77 remote pr: not mergeable (CONFLICTING)"
chk_has "merge --repo: a conflicting PR says the re-merge is skipped" "$out" "which --repo skips (no local checkout)"
chk "merge --repo: a conflicting PR is never merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 78 | jq -c '.[0].author={login:"someone-else"}')" GH_STUB_PR_78="$(RM_JSON 78 MERGEABLE)" \
  "$WRAP" merge --apply --pr 78 --repo o/r 2>&1)"; rc=$?
chk "merge --repo --pr: another author's PR exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "merge --repo --pr: another author's PR refuses by name" "$out" "PR #78 is not an open PR authored by you"
chk "merge --repo --pr: another author's PR is never merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

echo "--- merge --repo: argument errors"
out="$("$WRAP" merge --repo o/r "$NPM" 2>&1)"; rc=$?
chk "merge --repo plus a path: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
for bad in notaslug a/b/c /abs/path o/ -x/y; do
  out="$("$WRAP" merge --repo "$bad" 2>&1)"; rc=$?
  chk "merge --repo $bad: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
done
out="$("$WRAP" merge --repo 2>&1)"; rc=$?
chk "merge --repo with no value: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$(GH_STUB_REMOTE_DEFAULT= "$WRAP" merge --repo o/r 2>&1)"; rc=$?
chk "merge --repo: an unreadable default branch exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "merge --repo: an unreadable default branch names the slug" "$out" "no default branch resolved for o/r"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-merge-nopull: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-merge-nopull: all $PASS passed"
