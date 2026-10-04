#!/usr/bin/env bash
# test-wrap-merge-nopull.sh -- `wrap merge --no-pull` (the step 0 stop): a PR whose head branch
# the main checkout holds is skipped whatever its state. Split from test-wrap-merge.sh so its
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


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-merge-nopull: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-merge-nopull: all $PASS passed"
