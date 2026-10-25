#!/usr/bin/env bash
# test-wrap-merge-stacked.sh -- `wrap merge --pr N --rebase-stacked`: a child PR whose parent
# squash-merged is rebased onto the default branch past the parent's last pushed head, pushed
# with a lease to its own branch alone; every guard refuses by name and touches nothing. Split
# from test-wrap-merge.sh so the suite stays short. The zero-check ci label cases live in
# test-wrap-ci.sh beside the other label-gate cases.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# build_stack <name> [--conflict] -- a bare origin and a clone on main. stack/a (commits a1,
# a2) squash-merged into main as one commit; stack/b (commit b1) was built on stack/a, so it
# still holds a1 and a2. --conflict adds a main commit that writes b.txt too, so replaying b1
# conflicts. Sets SK_A1, SK_A2 (stack/a's pushed commits), SK_B (stack/b's head), SK_MAIN.
build_stack() {
  local name="$1" mode="${2:-}" w="$TMPD/sk-work-$1"
  mkdir -p "$w"; git -C "$w" init -q; gitc "$w"
  git -C "$w" symbolic-ref HEAD refs/heads/main
  printf 'line1\n' > "$w/a.txt"; git -C "$w" add -A; git -C "$w" commit -qm base
  git -C "$w" checkout -q -b stack/a
  printf 'line1\na1\n' > "$w/a.txt"; git -C "$w" commit -qam a1
  SK_A1="$(git -C "$w" rev-parse HEAD)"
  printf 'a2\n' > "$w/a2.txt"; git -C "$w" add -A; git -C "$w" commit -qm a2
  SK_A2="$(git -C "$w" rev-parse HEAD)"
  git -C "$w" checkout -q -b stack/b
  printf 'b1\n' > "$w/b.txt"; git -C "$w" add -A; git -C "$w" commit -qm b1
  git -C "$w" checkout -q main
  printf 'line1\na1\n' > "$w/a.txt"; printf 'a2\n' > "$w/a2.txt"
  git -C "$w" add -A; git -C "$w" commit -qm "squash a"
  if [ "$mode" = "--conflict" ]; then
    printf 'main b\n' > "$w/b.txt"; git -C "$w" add -A; git -C "$w" commit -qm "main adds b"
  fi
  git clone -q --bare "$w" "$TMPD/sk-bare-$name"
  git clone -q "$TMPD/sk-bare-$name" "$TMPD/sk-clone-$name"; gitc "$TMPD/sk-clone-$name"
  git -C "$TMPD/sk-clone-$name" remote set-head origin main >/dev/null 2>&1
  SK_B="$(git -C "$TMPD/sk-bare-$name" rev-parse stack/b)"
  SK_MAIN="$(git -C "$TMPD/sk-bare-$name" rev-parse main)"
}

# The retargeted child: base main, CONFLICTING, the gate's other fields green.
sk_json() { # sk_json <n> <head-oid>
  printf '{"number":%s,"title":"child b","headRefName":"stack/b","headRefOid":"%s","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"t","status":"COMPLETED","conclusion":"SUCCESS"}],"isDraft":false,"isCrossRepository":false,"autoMergeRequest":null}' "$1" "$2"
}
# The same PR once GitHub reads the rebased head. %REMERGE_TIP% resolves against the bare
# remote's stack/b, which only exists after wrap pushes it.
sk_green() { # sk_green <n>
  printf '{"number":%s,"title":"child b","headRefName":"stack/b","headRefOid":"%%REMERGE_TIP%%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"name":"t","status":"COMPLETED","conclusion":"SUCCESS"}],"isDraft":false,"isCrossRepository":false,"autoMergeRequest":null}' "$1"
}
sk_open() { printf '[{"number":%s,"title":"child b","headRefName":"stack/b"}]' "$1"; }
sk_merged() { # two stacked parents, a1's PR and a2's PR: the tip-most must win
  printf '[{"number":19,"headRefOid":"%s","baseRefName":"main","mergedAt":"2026-01-01T00:00:00Z"},{"number":20,"headRefOid":"%s","baseRefName":"main","mergedAt":"2026-01-02T00:00:00Z"}]' "$SK_A1" "$SK_A2"
}

# sk_run <n> <name> [wrap args...] -- one wrap merge on the <name> fixture, all output merged.
# Read order for `--pr N`: view 1 the draft check, view 2 the eligibility read (the base
# fixture), view 3 on the settled re-read of the rebased head (the green fixture).
# SK_OPEN, SK_MERGED_ALL and SK_PR1 override the open list, the merged list and the base read.
sk_run() {
  local n="$1" name="$2" bare="$TMPD/sk-bare-$2"; shift 2
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".* "$TMPD/sk-trace.log"
  (
    export PATH="$TMPD/nosleep:$PATH" GIT_TRACE="$TMPD/sk-trace.log"
    export GH_STUB_OPEN_PRS="${SK_OPEN:-$(sk_open "$n")}" GH_STUB_MERGED_ALL="${SK_MERGED_ALL:-$(sk_merged)}"
    export "GH_STUB_PR_${n}=${SK_PR1:-$(sk_json "$n" "$SK_B")}"
    export "GH_STUB_PR_${n}_3=$(sk_green "$n")"
    export GH_STUB_LAND_REPO="$bare" GH_STUB_LAND_REMOTE="$bare" GH_STUB_LAND_BRANCH=stack/b GH_STUB_LAND_DEF=main
    "$WRAP" merge "$@" "$TMPD/sk-clone-$name" 2>&1
  )
}
sk_force_pushes() { # sk_force_pushes -- how many leased pushes the run made
  grep -c 'built-in: git push.*force-with-lease' "$TMPD/sk-trace.log" 2>/dev/null || true
}
sk_remote_b() { git -C "$TMPD/sk-bare-$1" rev-parse stack/b; }
sk_no_merge() { grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0; }

echo "=== merge --rebase-stacked: flag shape ==="
build_stack flags
out="$("$WRAP" merge --apply --rebase-stacked "$TMPD/sk-clone-flags" 2>&1)"; rc=$?
chk "--rebase-stacked without --pr: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "--rebase-stacked without --pr: names the rule" "$out" "--rebase-stacked needs --pr N"
out="$("$WRAP" merge --apply --pr 21 --rebase-stacked --repo o/r 2>&1)"; rc=$?
chk "--rebase-stacked with --repo: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "--rebase-stacked with --repo: names the rule" "$out" "needs a local checkout"

echo "=== merge --rebase-stacked: a dry run names the rebase and pushes nothing ==="
build_stack dry
out="$(sk_run 21 dry --pr 21 --rebase-stacked)"; rc=$?
chk "dry run: exits 0" "$rc"
chk_has "dry run: announces the rebase" "$out" "note: #21 conflicts; --apply would rebase its branch onto origin/main if its parent PR squash-merged (--rebase-stacked)"
chk "dry run: origin stack/b untouched" "$([ "$(sk_remote_b dry)" = "$SK_B" ]; echo $?)"
chk "dry run: no leased push" "$([ "$(sk_force_pushes)" -eq 0 ]; echo $?)"

echo "=== merge --rebase-stacked: the squash-merged parent is cut out and the child merges ==="
# No checkout holds stack/b, so the rebase runs in a scratch worktree. Two merged PRs sit under
# the child (a1's and a2's): the chain's tip, #20, is the cut point.
build_stack happy
out="$(sk_run 21 happy --apply --pr 21 --rebase-stacked)"; rc=$?
NEWB="$(sk_remote_b happy)"
chk "happy: exits 0" "$rc"
chk_has "happy: names the parent it cut at" "$out" "#21 was stacked on #20"
chk_has "happy: says it used a scratch worktree" "$out" "no local checkout holds stack/b; rebasing in a scratch worktree"
chk_has "happy: reports the leased push" "$out" "force-with-lease pushed"
chk "happy: origin stack/b moved" "$([ "$NEWB" != "$SK_B" ]; echo $?)"
chk "happy: only the child's own commit sits above main" \
  "$([ "$(git -C "$TMPD/sk-bare-happy" rev-list --count "${SK_MAIN}..${NEWB}")" -eq 1 ]; echo $?)"
chk "happy: the parent's original commits are gone" \
  "$(git -C "$TMPD/sk-bare-happy" merge-base --is-ancestor "$SK_A1" "$NEWB" && echo 1 || echo 0)"
chk "happy: the rebased branch holds main" "$(git -C "$TMPD/sk-bare-happy" merge-base --is-ancestor "$SK_MAIN" "$NEWB"; echo $?)"
chk "happy: exactly one leased push" "$([ "$(sk_force_pushes)" -eq 1 ]; echo $?)"
chk "happy: the lease names the head the gates read" \
  "$(grep 'built-in: git push' "$TMPD/sk-trace.log" | grep -q -- "--force-with-lease=refs/heads/stack/b:${SK_B}"; echo $?)"
chk "happy: the leased push targets the PR branch, never main" \
  "$(grep 'built-in: git push' "$TMPD/sk-trace.log" | grep -- 'force-with-lease' | grep -q 'refs/heads/main' && echo 1 || echo 0)"
chk "happy: no plain --force and no + refspec" \
  "$(grep 'built-in: git push' "$TMPD/sk-trace.log" | grep -Eq -- "(^| )'?--force'?( |$)|'?\+[A-Za-z]" && echo 1 || echo 0)"
chk "happy: the merge pins the rebased head" "$(grep -q -- "--match-head-commit ${NEWB}" "$GH_STUB_CALLS"; echo $?)"
chk_has "happy: merges once gated" "$out" "merged #21 ("
chk "happy: the scratch worktree was dropped" "$([ "$(git -C "$TMPD/sk-clone-happy" worktree list | wc -l | tr -d ' ')" -eq 1 ]; echo $?)"

echo "=== merge --rebase-stacked: a checkout that holds the branch rebases in place and verifies ==="
build_stack held
HELD_WT="$TMPD/sk-wt-held"
git -C "$TMPD/sk-clone-held" worktree add -q -b stack/b "$HELD_WT" origin/stack/b >/dev/null 2>&1
out="$(sk_run 22 held --apply --pr 22 --rebase-stacked --verify 'test -f b.txt')"; rc=$?
NEWB="$(sk_remote_b held)"
chk "held: exits 0" "$rc"
chk_no "held: no scratch worktree" "$out" "scratch worktree"
chk_has "held: ran the verify command in the checkout" "$out" "test -f b.txt"
chk "held: origin stack/b moved" "$([ "$NEWB" != "$SK_B" ]; echo $?)"
chk "held: the checkout's branch is the pushed head" "$([ "$(git -C "$HELD_WT" rev-parse HEAD)" = "$NEWB" ]; echo $?)"
chk "held: the checkout is clean" "$([ -z "$(git -C "$HELD_WT" status --porcelain)" ]; echo $?)"
chk_has "held: merges once gated" "$out" "merged #22 ("

echo "=== merge --rebase-stacked: a rebase conflict refuses by name and touches nothing ==="
build_stack conf --conflict
out="$(sk_run 23 conf --apply --pr 23 --rebase-stacked)"; rc=$?
chk "conflict: exits 0 without merging" "$rc"
chk_has "conflict: names the conflicting file" "$out" "REFUSED #23: rebasing stack/b onto origin/main conflicts in: b.txt; aborted, nothing pushed"
chk "conflict: origin stack/b untouched" "$([ "$(sk_remote_b conf)" = "$SK_B" ]; echo $?)"
chk "conflict: no leased push" "$([ "$(sk_force_pushes)" -eq 0 ]; echo $?)"
chk "conflict: no pr merge" "$(sk_no_merge)"
chk_no "conflict: the union re-merge never touched the branch" "$out" "re-merge"
chk "conflict: the scratch worktree was dropped" "$([ "$(git -C "$TMPD/sk-clone-conf" worktree list | wc -l | tr -d ' ')" -eq 1 ]; echo $?)"

build_stack confheld --conflict
CH_WT="$TMPD/sk-wt-confheld"
git -C "$TMPD/sk-clone-confheld" worktree add -q -b stack/b "$CH_WT" origin/stack/b >/dev/null 2>&1
out="$(sk_run 24 confheld --apply --pr 24 --rebase-stacked)"; rc=$?
chk_has "conflict, held: names the conflicting file" "$out" "conflicts in: b.txt; aborted, nothing pushed"
chk "conflict, held: the checkout is back at the PR head" "$([ "$(git -C "$CH_WT" rev-parse HEAD)" = "$SK_B" ]; echo $?)"
chk "conflict, held: the checkout is clean, no rebase in progress" \
  "$([ -z "$(git -C "$CH_WT" status --porcelain)" ] && ! git -C "$CH_WT" status | grep -q 'rebase in progress'; echo $?)"
chk "conflict, held: still on the branch" "$([ "$(git -C "$CH_WT" symbolic-ref --short HEAD)" = "stack/b" ]; echo $?)"
chk "conflict, held: origin stack/b untouched" "$([ "$(sk_remote_b confheld)" = "$SK_B" ]; echo $?)"

echo "=== merge --rebase-stacked: opt-in, the same conflict without the flag is not rewritten ==="
build_stack noflag --conflict
out="$(sk_run 25 noflag --apply --pr 25)"; rc=$?
chk_no "no flag: no rebase is announced" "$out" "rebasing stack/b"
chk "no flag: origin stack/b untouched" "$([ "$(sk_remote_b noflag)" = "$SK_B" ]; echo $?)"
chk "no flag: no leased push" "$([ "$(sk_force_pushes)" -eq 0 ]; echo $?)"

echo "=== merge --rebase-stacked: guards refuse before anything is touched ==="
build_stack guards
GU_OPEN='[{"number":26,"title":"child b","headRefName":"stack/b"},{"number":27,"title":"grandchild","headRefName":"stack/c","baseRefName":"stack/b"}]'
out="$(SK_OPEN="$GU_OPEN" sk_run 26 guards --apply --pr 26 --rebase-stacked)"
chk_has "dependents: refused by name" "$out" "REFUSED #26: #27 still target stack/b, retarget them first; nothing pushed"
chk "dependents: origin stack/b untouched" "$([ "$(sk_remote_b guards)" = "$SK_B" ]; echo $?)"

out="$(SK_PR1="$(sk_json 28 "$SK_B" | sed 's/"isCrossRepository":false/"isCrossRepository":true/')" sk_run 28 guards --apply --pr 28 --rebase-stacked)"
chk_has "fork PR: refused by name" "$out" "REFUSED #28: a fork PR, one with auto-merge armed, or an unreadable PR is never force-pushed"

out="$(SK_PR1="$(sk_json 29 "$SK_B" | sed 's/"autoMergeRequest":null/"autoMergeRequest":{"mergeMethod":"SQUASH"}/')" sk_run 29 guards --apply --pr 29 --rebase-stacked)"
chk_has "auto-merge armed: refused by name" "$out" "REFUSED #29: a fork PR, one with auto-merge armed"

out="$(SK_PR1="$(sk_json 30 3333333333333333333333333333333333333333)" sk_run 30 guards --apply --pr 30 --rebase-stacked)"
chk_has "stale head: refused by name" "$out" "REFUSED #30: stack/b is not at the head the gates read"
chk "guards: origin stack/b untouched by every refusal" "$([ "$(sk_remote_b guards)" = "$SK_B" ]; echo $?)"
chk "guards: no leased push in any refusal" "$([ "$(sk_force_pushes)" -eq 0 ]; echo $?)"

echo "=== merge --rebase-stacked: no squash-merged parent means not the stacked case ==="
build_stack noparent --conflict
out="$(SK_MERGED_ALL='[]' sk_run 31 noparent --apply --pr 31 --rebase-stacked)"
chk_has "no parent: says so" "$out" "no squash-merged parent PR sits under stack/b; not the stacked case"
chk "no parent: origin stack/b untouched" "$([ "$(sk_remote_b noparent)" = "$SK_B" ]; echo $?)"
chk "no parent: no leased push" "$([ "$(sk_force_pushes)" -eq 0 ]; echo $?)"
chk "no parent: no pr merge" "$(sk_no_merge)"

echo "=== merge --rebase-stacked: a failing verify undoes the rebase before any push ==="
build_stack verify
out="$(sk_run 32 verify --apply --pr 32 --rebase-stacked --verify false)"
chk_has "verify red: names the failure" "$out" "VERIFY FAILED #32: false (exit 1)"
chk "verify red: origin stack/b untouched" "$([ "$(sk_remote_b verify)" = "$SK_B" ]; echo $?)"
chk "verify red: no leased push" "$([ "$(sk_force_pushes)" -eq 0 ]; echo $?)"
chk "verify red: no pr merge" "$(sk_no_merge)"

echo "=== merge --rebase-stacked: the lease refuses when another writer pushed in between ==="
# The verify command runs after the rebase and before the push, so it stands in for a foreign
# push landing in that window. The lease names the head the gates read; the moved branch must
# survive.
build_stack lease
git clone -q "$TMPD/sk-bare-lease" "$TMPD/sk-pusher"; gitc "$TMPD/sk-pusher"
git -C "$TMPD/sk-pusher" checkout -q -b stack/b origin/stack/b
out="$(sk_run 33 lease --apply --pr 33 --rebase-stacked \
  --verify "git -C $TMPD/sk-pusher commit -q --allow-empty -m foreign && git -C $TMPD/sk-pusher push -q origin HEAD:refs/heads/stack/b")"
chk_has "lease: the push is refused by name" "$out" "PUSH REFUSED #33: the lease on stack/b"
chk "lease: the foreign push survived" "$([ "$(sk_remote_b lease)" = "$(git -C "$TMPD/sk-pusher" rev-parse HEAD)" ]; echo $?)"
chk "lease: no pr merge" "$(sk_no_merge)"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-merge-stacked: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-merge-stacked: all $PASS passed"
