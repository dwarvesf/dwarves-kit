#!/usr/bin/env bash
# test-wrap-merge-nopull.sh -- `wrap merge --no-pull` (the step 0 stop): a PR whose head branch
# the main checkout holds is skipped whatever its state; `merge --repo <owner>/<name>` (no checkout). Split from test-wrap-merge.sh so its
# negative controls run in seconds, away from that suite's signal-timing cases.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh lib/wrap/wrap-ship.sh
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
  "$WRAP" merge --apply --no-pull --pr 63 "$NPM" 2>&1)"; rc=$?
chk "merge --no-pull --pr: a PR held by main exits 4, not merged" "$([ "$rc" -eq 4 ]; echo $?)"
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


echo "--- merge --apply: the main checkout is fast-forwarded after a merge, the way land does it"
# `merge` merges server-side, so the checkout it was handed stayed behind origin. The stub's
# `pr merge` pushes feat/pl onto the bare origin's main (GitHub's own landing); the clone's
# main is then one commit behind, and the pull is what brings it level.
build_pull() { # build_pull <name>: bare origin + clone on main one commit behind the PR's landing
  local name="$1" work="$TMPD/pl-work-$1"
  PL_BARE="$TMPD/pl-bare-$name"; PL_CLONE="$TMPD/pl-clone-$name"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf 'base\n' > "$work/a.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$PL_BARE"
  git clone -q "$PL_BARE" "$PL_CLONE"; gitc "$PL_CLONE"
  git -C "$PL_CLONE" remote set-head origin main >/dev/null 2>&1
  PL_BASE="$(git -C "$PL_CLONE" rev-parse main)"
  git -C "$PL_CLONE" checkout -q -b feat/pl
  printf 'pr change\n' > "$PL_CLONE/b.txt"; git -C "$PL_CLONE" add -A; git -C "$PL_CLONE" commit -qm "pr change"
  PL_TIP="$(git -C "$PL_CLONE" rev-parse feat/pl)"
  git -C "$PL_CLONE" checkout -q main
}
pl_json() { # pl_json <number> <tip> [<reviewDecision>]
  printf '{"number":%s,"title":"ff me","headRefName":"feat/pl","headRefOid":"%s","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"%s","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2" "${3:-APPROVED}"
}
pl_open() { printf '[{"number":%s,"title":"ff me","headRefName":"feat/pl"}]' "$1"; }
pl_merge() { # pl_merge <number> [flags]: merge --apply --pr <number> on the fixture, stub landing wired
  local n="$1"; shift
  env GH_STUB_OPEN_PRS="$(pl_open "$n")" "GH_STUB_PR_${n}=$(pl_json "$n" "$PL_TIP")" \
    GH_STUB_LAND_REPO="$PL_CLONE" GH_STUB_LAND_REMOTE="$PL_BARE" GH_STUB_LAND_BRANCH=feat/pl GH_STUB_LAND_DEF=main \
    "$WRAP" merge --apply --pr "$n" "$@" "$PL_CLONE" 2>&1
}

build_pull ok
: > "$GH_STUB_CALLS"
out="$(pl_merge 91)"; rc=$?
chk "merge --apply --pr pulls: exits 0" "$rc"
chk_has "merge --apply --pr pulls: the merge itself is reported" "$out" "tree verified"
chk "merge --apply --pr pulls: the checkout's main equals origin's" \
  "$([ "$(git -C "$PL_CLONE" rev-parse main)" = "$(git -C "$PL_BARE" rev-parse main)" ] && [ "$(git -C "$PL_CLONE" rev-parse main)" != "$PL_BASE" ]; echo $?)"
chk_has "merge --apply --pr pulls: says the checkout was pulled" "$out" "pulled ${PL_CLONE}: "
chk "merge --apply --pr pulls: the checkout stays on main" "$([ "$(git -C "$PL_CLONE" branch --show-current)" = main ]; echo $?)"

build_pull nopull
out="$(pl_merge 92 --no-pull)"; rc=$?
chk "merge --apply --pr --no-pull: exits 0" "$rc"
chk_has "merge --apply --pr --no-pull: merged" "$out" "tree verified"
chk "merge --apply --pr --no-pull: the checkout's main stays behind" \
  "$([ "$(git -C "$PL_CLONE" rev-parse main)" = "$PL_BASE" ]; echo $?)"
chk_has "merge --apply --pr --no-pull: says it did not pull and names the command" "$out" \
  "SKIP pull: --no-pull; ${PL_CLONE} not pulled, run: wrap apply --apply --pull-only ${PL_CLONE}"

build_pull offdef
git -C "$PL_CLONE" checkout -q -b side
out="$(pl_merge 93)"; rc=$?
chk "merge --apply --pr off the default branch: exits 0" "$rc"
chk_has "merge --apply --pr off the default branch: merged" "$out" "tree verified"
chk_has "merge --apply --pr off the default branch: says why and names the command" "$out" \
  "PULL BLOCKED: ${PL_CLONE} is on 'side', not main; run: wrap apply --apply --pull-only ${PL_CLONE}"
chk "merge --apply --pr off the default branch: the checkout and its main are untouched" \
  "$([ "$(git -C "$PL_CLONE" branch --show-current)" = side ] && [ "$(git -C "$PL_CLONE" rev-parse main)" = "$PL_BASE" ]; echo $?)"

build_pull diverged
printf 'local only\n' > "$PL_CLONE/c.txt"; git -C "$PL_CLONE" add -A; git -C "$PL_CLONE" commit -qm "local only"
PL_LOCAL="$(git -C "$PL_CLONE" rev-parse main)"
out="$(pl_merge 94)"; rc=$?
chk "merge --apply --pr, main cannot fast-forward: still exits 0" "$rc"
chk_has "merge --apply --pr, main cannot fast-forward: says the pull was refused and names the command" "$out" \
  "PULL BLOCKED: pull --ff-only refused in ${PL_CLONE}, nothing was stashed or reset; run: wrap apply --apply --pull-only ${PL_CLONE}"
chk "merge --apply --pr, main cannot fast-forward: the local commit is intact" \
  "$([ "$(git -C "$PL_CLONE" rev-parse main)" = "$PL_LOCAL" ]; echo $?)"

build_pull dry
out="$(GH_STUB_OPEN_PRS="$(pl_open 95)" GH_STUB_PR_95="$(pl_json 95 "$PL_TIP")" "$WRAP" merge --pr 95 "$PL_CLONE" 2>&1)"; rc=$?
chk "merge dry run: exits 0" "$rc"
chk_no "merge dry run: never pulls" "$out" "pulled"
chk "merge dry run: the checkout's main is untouched" "$([ "$(git -C "$PL_CLONE" rev-parse main)" = "$PL_BASE" ]; echo $?)"

build_pull skipped
out="$(GH_STUB_OPEN_PRS="$(pl_open 96)" GH_STUB_PR_96="$(pl_json 96 "$PL_TIP" CHANGES_REQUESTED)" \
  GH_STUB_LAND_REPO="$PL_CLONE" GH_STUB_LAND_REMOTE="$PL_BARE" GH_STUB_LAND_BRANCH=feat/pl GH_STUB_LAND_DEF=main \
  "$WRAP" merge --apply --pr 96 "$PL_CLONE" 2>&1)"; rc=$?
chk "merge --apply --pr that merged nothing: exits 4" "$([ "$rc" -eq 4 ]; echo $?)"
chk_no "merge --apply --pr that merged nothing: never pulls" "$out" "pull"
chk "merge --apply --pr that merged nothing: the checkout's main is untouched" "$([ "$(git -C "$PL_CLONE" rev-parse main)" = "$PL_BASE" ]; echo $?)"

# apply's autoland carry lands its carry branch through cmd_merge in-process. It keeps the
# checkout's stray lines as dirty files and pulls on its own stage, so the merge's pull stays
# silent there. The caller is stood in for by a function of the same name.
build_pull carry
out="$(env GH_STUB_OPEN_PRS="$(pl_open 97)" "GH_STUB_PR_97=$(pl_json 97 "$PL_TIP")" \
  GH_STUB_LAND_REPO="$PL_CLONE" GH_STUB_LAND_REMOTE="$PL_BARE" GH_STUB_LAND_BRANCH=feat/pl GH_STUB_LAND_DEF=main \
  bash -c 'source "$1" help >/dev/null; _autoland_carry() { ( cmd_merge --apply --pr 97 "$2" ); }; _autoland_carry x "$2"' _ \
  "$KIT_DIR/lib/wrap/wrap.sh" "$PL_CLONE" 2>&1)"; rc=$?
chk "merge called from apply's carry: exits 0" "$rc"
chk_has "merge called from apply's carry: merged" "$out" "tree verified"
chk_no "merge called from apply's carry: prints no pull line" "$out" "pull"
chk "merge called from apply's carry: the checkout's main is left for apply's own pull" \
  "$([ "$(git -C "$PL_CLONE" rev-parse main)" = "$PL_BASE" ]; echo $?)"

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
chk_no "merge --repo: never pulls (there is no checkout)" "$out" "pulled"
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
