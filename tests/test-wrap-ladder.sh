#!/usr/bin/env bash
# test-wrap-ladder.sh -- the merge-proof ladder: one function answers "has this branch reached
# the default branch" with a machine code plus a phrase, and scan, apply, carry and land act on
# the code alone. A kit copy with the phrases reworded proves no caller reads them.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-land.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# lad <wrap.sh> <function> [args...] -- run one function of the sourced wrap library. Sourcing
# runs main with no verb, which prints the usage; that goes to /dev/null.
lad() { local f="$1"; shift; bash -c 'f="$1"; shift; a=("$@"); set --; source "$f" >/dev/null; "${a[@]}"' _ "$f" "$@"; }
LIB="$KIT_DIR/lib/wrap/wrap.sh"

# ===========================================================================
echo "=== ladder: every proof and every refusal has its own code ==="
# ===========================================================================
make_clone lad rmain main unmerged
set_stub rmain main
LAD="$TMPD/clone-lad"

# A branch whose content landed under another commit: the absorbed proof, no PR, no ancestry.
ABW="$TMPD/lad-abs-work"; mkdir -p "$ABW"; git -C "$ABW" init -q -b main; gitc "$ABW"
printf 'base\n' > "$ABW/f.txt"; git -C "$ABW" add -A; git -C "$ABW" commit -qm base
git -C "$ABW" branch absorbed; git -C "$ABW" checkout -q absorbed
printf 'agent line\n' > "$ABW/new.txt"; git -C "$ABW" add -A; git -C "$ABW" commit -qm "agent: new.txt"
git -C "$ABW" checkout -q main
printf 'agent line\n' > "$ABW/new.txt"; printf 'later\n' > "$ABW/g.txt"
git -C "$ABW" add -A; git -C "$ABW" commit -qm "lead: land the agent's work"
git clone -q --bare "$ABW" "$TMPD/lad-abs-bare"
ABC="$TMPD/lad-abs-clone"; git clone -q "$TMPD/lad-abs-bare" "$ABC"; gitc "$ABC"
git -C "$ABC" branch -q absorbed origin/absorbed

out="$(lad "$LIB" _merge_ladder "$LAD" main ok merged-ancestor)"
chk "ancestor: SAFE ancestor plus its phrase" "$([ "$out" = "SAFE ancestor ancestor of origin/main" ]; echo $?)"
out="$(lad "$LIB" _merge_ladder "$ABC" main ok absorbed)"
chk "absorbed: SAFE absorbed plus its phrase" "$([ "$out" = "SAFE absorbed content already on origin/main" ]; echo $?)"
out="$(lad "$LIB" _merge_ladder "$LAD" main ok squash-ok)"
chk "squash: SAFE squash plus its phrase" "$([ "$out" = "SAFE squash squash-merged per gh" ]; echo $?)"
out="$(lad "$LIB" _merge_ladder "$LAD" main ok squash-stale)"
chk "merged from another tip: LEAVE tip plus the PR head sha" \
  "$([ "$out" = "LEAVE tip 1111111111111111111111111111111111111111" ]; echo $?)"
out="$(lad "$LIB" _merge_ladder "$LAD" main ok stacked-child)"
chk "merged into another base: LEAVE base plus its name" "$([ "$out" = "LEAVE base feat/parent" ]; echo $?)"
out="$(lad "$LIB" _merge_ladder "$LAD" main ok wt-dirty)"
chk "no merged PR: LEAVE none" "$([ "${out%% none *}" = "LEAVE" ] && [ "${out#LEAVE none }" != "$out" ]; echo $?)"
out="$(GH_STUB_UNAUTH=1 lad "$LIB" _merge_ladder "$LAD" main unauthenticated wt-dirty)"
chk "gh not ok: LEAVE nogh plus the gh note" "$([ "$out" = "LEAVE nogh (gh unauthenticated)" ]; echo $?)"
out="$(GH_STUB_UNAUTH=1 lad "$LIB" _merge_ladder "$LAD" main unauthenticated merged-ancestor)"
chk "gh not ok: an ancestor is still SAFE" "$([ "${out%% ancestor *}" = "SAFE" ]; echo $?)"
out="$(GH_STUB_UNAUTH=1 lad "$LIB" _merge_ladder "$ABC" main unauthenticated absorbed)"
chk "gh not ok: absorbed content is still SAFE" "$([ "${out%% absorbed *}" = "SAFE" ]; echo $?)"
LAD_TIP="$(git -C "$LAD" rev-parse squash-ok)"
out="$(lad "$LIB" _merge_ladder "$LAD" main ok squash-ok "$LAD_TIP")"
chk "an explicit tip is judged in place of the branch ref" "$([ "${out%% squash *}" = "SAFE" ]; echo $?)"
out="$(lad "$LIB" _merge_ladder "$LAD" main ok squash-ok "$(git -C "$LAD" rev-parse wt-dirty)")"
chk "an explicit tip that no PR merged is not the branch's proof" "$([ "${out%% *}" = "LEAVE" ]; echo $?)"
out="$(lad "$LIB" _squash_verdict "$GH_STUB_MERGED_squash_ok" "$LAD_TIP" main)"
chk "the squash rung speaks the ladder grammar" "$([ "$out" = "SAFE squash squash-merged per gh" ]; echo $?)"
out="$(lad "$LIB" _squash_verdict 'not json' "$LAD_TIP" main)"
chk "the squash rung reads unusable JSON as LEAVE none" "$([ "${out%% none *}" = "LEAVE" ]; echo $?)"

# ===========================================================================
echo "=== callers: a reworded kit acts exactly as the real one ==="
# ===========================================================================
reword_ladder || { echo "FAIL: reword_ladder" >&2; exit 1; }
RLIB="${WRAP_LADDER_REWORDED%/bin/wrap}/lib/wrap/wrap.sh"
out="$(lad "$RLIB" _merge_ladder "$LAD" main ok merged-ancestor)"
chk "the reworded kit changes the phrase" "$([ "$out" = "SAFE ancestor reachable from origin/main" ]; echo $?)"

echo "--- scan labels branches by code, in either kit"
real="$("$WRAP" scan "$LAD" 2>&1)"
reworded="$("$WRAP_LADDER_REWORDED" scan "$LAD" 2>&1)"
chk "scan: the reworded kit prints the same report" "$([ "$real" = "$reworded" ]; echo $?)"
chk_has "scan: the ancestor is still SAFE-d" "$reworded" "merged-ancestor  [SAFE-d: ancestor of origin/main]"
chk_has "scan: the squash is still safe to -D" "$reworded" "squash-ok  [SQUASH-MERGED per gh: safe to -D]"
chk_has "scan: a stale tip is still LEAVE" "$reworded" "squash-stale  [NOT merged / unknown: LEAVE]"
real="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$ABC" 2>&1)"
reworded="$(GH_STUB_UNAUTH=1 "$WRAP_LADDER_REWORDED" scan "$ABC" 2>&1)"
chk "scan without gh: the reworded kit prints the same report" "$([ "$real" = "$reworded" ]; echo $?)"
chk_has "scan without gh: absorbed content is still safe" "$reworded" "absorbed  [ABSORBED: content already on origin/main, safe to -D]"

echo "--- apply deletes the same branches and worktrees, in either kit"
make_clone lad-real rmain main main
make_clone lad-word rmain main main
real="$("$WRAP" apply --apply --worktrees "$TMPD/clone-lad-real" 2>&1)"; rc_real=$?
reworded="$("$WRAP_LADDER_REWORDED" apply --apply --worktrees "$TMPD/clone-lad-word" 2>&1)"; rc_word=$?
chk "apply: both kits exit 0" "$([ "$rc_real" -eq 0 ] && [ "$rc_word" -eq 0 ]; echo $?)"
left_real="$(git -C "$TMPD/clone-lad-real" for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' ')"
left_word="$(git -C "$TMPD/clone-lad-word" for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' ')"
chk "apply: the real kit keeps main, the unproven and the dirty" \
  "$([ "$left_real" = "main squash-stale stacked-child unmerged wt-dirty " ]; echo $?)"
chk "apply: the reworded kit deletes the same branches" "$([ "$left_real" = "$left_word" ]; echo $?)"
chk "apply: the reworded kit removes the same worktrees" \
  "$([ ! -d "$TMPD/wt-lad-word-clean" ] && [ -d "$TMPD/wt-lad-word-dirty" ] && [ -d "$TMPD/wt-lad-word-det" ]; echo $?)"
chk_has "apply: the branch delete prints the ladder's phrase" "$reworded" "delete merged-ancestor (reachable from origin/main)"
chk_has "apply: the worktree removal prints the ladder's phrase" "$reworded" \
  "remove worktree $TMPD_P/wt-lad-word-clean [wt-clean, locked] and delete wt-clean (merged via gh)"
chk_has "apply: a stale tip still names both heads" "$reworded" \
  "SKIP squash-stale: tip $(git -C "$TMPD/clone-lad-word" rev-parse squash-stale | cut -c1-7) != merged PR head 1111111"
chk_has "apply: another base is still named" "$reworded" "SKIP stacked-child: merged into feat/parent, not the default branch"

echo "--- apply removes an absorbed worktree in the reworded kit"
git -C "$ABC" worktree add -q "$TMPD/lad-abs-wt" absorbed
out="$(GH_STUB_UNAUTH=1 "$WRAP_LADDER_REWORDED" apply --apply --worktrees "$ABC" 2>&1)"
chk_has "apply absorbed: the removal prints the ladder's phrase" "$out" \
  "delete absorbed (same bytes already on origin/main, its unlocked worktree is gone)"
chk "apply absorbed: the worktree is gone" "$([ ! -d "$TMPD/lad-abs-wt" ]; echo $?)"
chk "apply absorbed: the branch is gone" "$(git -C "$ABC" show-ref --verify --quiet refs/heads/absorbed && echo 1 || echo 0)"

echo "--- land acts on the code: an ancestor never counts, an absorbed proof does"
build_land ladanc
LWT_A="$(cd "$TMPD/ld-repo-ladanc/wt" && pwd -P)"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=44 GH_STUB_LAND_REPO="$LWT_A" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ladanc" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main bash -c \
  'f="$1"; w="$2"; set --; source "$f"; _merge_ladder() { printf "SAFE ancestor carries no known word\n"; }; cmd_land "$w"' \
  _ "$LIB" "$LWT_A" 2>&1)"
chk_no "land: an ancestor code never prints already landed, whatever its phrase" "$out" "already landed"
chk_has "land: it takes the unchanged path and opens the PR" "$out" "opened PR #44"

build_land ladabs
LWT_B="$(cd "$TMPD/ld-repo-ladabs/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_LAND_REPO="$LWT_B" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ladabs" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main bash -c \
  'f="$1"; w="$2"; set --; source "$f"; _merge_ladder() { printf "SAFE absorbed nothing like the old words\n"; }; cmd_land "$w"' \
  _ "$LIB" "$LWT_B" 2>&1)"; rc=$?
chk "land: an absorbed code exits 0" "$rc"
chk_has "land: it reports the ladder's phrase" "$out" "already landed: nothing like the old words; nothing to push, no PR opened"
chk_no "land: no PR is opened" "$(cat "$GH_STUB_CALLS")" "pr create"
chk "land: the worktree is removed" "$([ ! -e "$LWT_B" ]; echo $?)"

echo "--- land recognizes a squash-merged branch in the reworded kit"
build_land ladsq
LWT_C="$(cd "$TMPD/ld-repo-ladsq/wt" && pwd -P)"
LTIP_C="$(git -C "$LWT_C" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGED_feat_land="[{\"headRefOid\":\"$LTIP_C\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]" \
  GH_STUB_OPEN_PRS='[]' GH_STUB_LAND_REPO="$LWT_C" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ladsq" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP_LADDER_REWORDED" land "$LWT_C" 2>&1)"; rc=$?
chk "land squash: exits 0" "$rc"
chk_has "land squash: reports the reworded phrase" "$out" "already landed: merged via gh"
chk_no "land squash: no PR is opened" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- carry reads the squash rung by code"
build_land ladcarry
CREPO="$TMPD/ld-repo-ladcarry"; CWT="$CREPO/wt"
git -C "$CWT" push -q origin feat/land
CTIP="$(git -C "$CWT" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGED_feat_land="[{\"headRefOid\":\"$CTIP\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]" \
  lad "$RLIB" _autoland_carry "$CREPO" main feat/land "$CTIP" 2>&1)"; rc=$?
chk "carry: a merged branch returns 0" "$rc"
chk_has "carry: it says already merged" "$out" "origin/feat/land already merged"
chk_no "carry: it opens no PR" "$(cat "$GH_STUB_CALLS")" "pr create"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-ladder: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-ladder: all $PASS passed"
