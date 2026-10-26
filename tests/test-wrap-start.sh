#!/usr/bin/env bash
# test-wrap-start.sh -- the start cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== start: a fresh branch in a new worktree off origin/<default> ==="
# ===========================================================================
# Real git throughout, no gh: start never calls gh. The clones ride the same bare
# remotes the scan/apply cases use; the origin tip is advanced after the clone so
# the worktree's base proves the fetch ran, not the clone-time snapshot.
build_start() { # build_start <name> <remote name> <default branch>
  local name="$1" rname="$2" def="$3" repo="$TMPD/st-repo-$1"
  git clone -q "$TMPD/bare-$rname" "$repo"; gitc "$repo"
  git -C "$repo" remote set-head origin "$def" >/dev/null 2>&1
}

build_start ok rmain main
SREPO="$TMPD/st-repo-ok"
# Advance origin/main past the clone's view: the worktree's base is the fetched tip.
git clone -q "$TMPD/bare-rmain" "$TMPD/st-pusher"; gitc "$TMPD/st-pusher"
echo newer > "$TMPD/st-pusher/newer.txt"
git -C "$TMPD/st-pusher" add -A; git -C "$TMPD/st-pusher" commit -qm newer
git -C "$TMPD/st-pusher" push -q origin main
STIP="$(git -C "$TMPD/bare-rmain" rev-parse main)"
SWT_P="$(cd "$SREPO" && pwd -P)/.claude/worktrees/start"

out="$("$WRAP" start "$SREPO" feat/start 2>"$TMPD/st.err")"; rc=$?
chk "start exits 0 on the happy path" "$rc"
chk "start prints only the worktree path on stdout" "$([ "$out" = "$SWT_P" ]; echo $?)"
chk "start created the worktree at the fetched origin tip" \
  "$([ "$(git -C "$SWT_P" rev-parse HEAD)" = "$STIP" ]; echo $?)"
chk "start put the worktree on the new branch" \
  "$([ "$(git -C "$SWT_P" branch --show-current)" = "feat/start" ]; echo $?)"
chk "start created the local branch" \
  "$(git -C "$SREPO" show-ref --verify --quiet refs/heads/feat/start && echo 0 || echo 1)"
chk "start registered the worktree" \
  "$(git -C "$SREPO" worktree list --porcelain | grep -qxF "worktree $SWT_P" && echo 0 || echo 1)"

echo "--- a master-default repo resolves its own default branch"
build_start master rmaster master
out="$("$WRAP" start "$TMPD/st-repo-master" fix/master-side 2>/dev/null)"; rc=$?
chk "start exits 0 on a master-default repo" "$rc"
chk "the worktree sits at origin/master" \
  "$([ "$(git -C "$TMPD/st-repo-master/.claude/worktrees/master-side" rev-parse HEAD)" \
      = "$(git -C "$TMPD/bare-rmaster" rev-parse master)" ]; echo $?)"

echo "--- the refusals, each before any write"
out="$("$WRAP" start "$SREPO" feat/start 2>&1)"; rc=$?
chk "start refuses an existing local branch with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the branch" "$out" "branch feat/start already exists in"

# A same-named branch on origin only: the local name is free, but the push would
# collide, so the verb refuses. The clone predates the push and `fetch origin
# <def>` refreshes no other tracking ref, so this exercises the live check.
git -C "$TMPD/st-pusher" checkout -qb feat/pushed
git -C "$TMPD/st-pusher" push -q origin feat/pushed
out="$("$WRAP" start "$SREPO" feat/pushed 2>&1)"; rc=$?
chk "start refuses a name already on origin with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names origin" "$out" "branch feat/pushed already exists on origin"
chk "an origin-collision refusal created no branch" \
  "$(git -C "$SREPO" show-ref --verify --quiet refs/heads/feat/pushed && echo 1 || echo 0)"

mkdir -p "$SREPO/.claude/worktrees/collide"
out="$("$WRAP" start "$SREPO" feat/collide 2>&1)"; rc=$?
chk "start refuses an existing path with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the path" "$out" ".claude/worktrees/collide already exists"
chk "a path refusal created no branch" \
  "$(git -C "$SREPO" show-ref --verify --quiet refs/heads/feat/collide && echo 1 || echo 0)"

out="$("$WRAP" start "$SREPO" main 2>&1)"; rc=$?
chk "start refuses the default branch name with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the protected reason" "$out" "main is the default or a protected branch name"

out="$("$WRAP" start "$SREPO" "feat/../x" 2>&1)"; rc=$?
chk "start refuses an invalid branch name with exit 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "the refusal says the name is invalid" "$out" "is not a valid branch name"

out="$("$WRAP" start 2>&1)"; rc=$?
chk "start with no args exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" start "$TMPD/not-a-repo" feat/x 2>&1)"; rc=$?
chk "start exits 64 on a non-repo" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "the refusal says not a git repo" "$out" "is not a git repo"

mkdir -p "$TMPD/st-remoteless"
git -C "$TMPD/st-remoteless" init -q; gitc "$TMPD/st-remoteless"
echo x > "$TMPD/st-remoteless/x.txt"; git -C "$TMPD/st-remoteless" add -A; git -C "$TMPD/st-remoteless" commit -qm x
out="$("$WRAP" start "$TMPD/st-remoteless" feat/x 2>&1)"; rc=$?
chk "start exits 1 on a repo with no remote" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the unresolved default" "$out" "no default branch resolved"

build_start broken rmain main
git -C "$TMPD/st-repo-broken" remote set-url origin /nonexistent
out="$("$WRAP" start "$TMPD/st-repo-broken" feat/x 2>&1)"; rc=$?
chk "start exits 1 when the fetch fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the failed fetch" "$out" "fetch origin main failed"
chk "a failed fetch left no worktree dir behind" \
  "$([ ! -e "$TMPD/st-repo-broken/.claude/worktrees/x" ]; echo $?)"

echo "--- a dirty main checkout is not a refusal, it is the point"
build_start dirty rmain main
echo sibling-dirt >> "$TMPD/st-repo-dirty/a.txt"
out="$("$WRAP" start "$TMPD/st-repo-dirty" feat/dirty 2>/dev/null)"; rc=$?
chk "start exits 0 on a dirty main checkout" "$rc"
chk "the worktree landed under .claude/worktrees" \
  "$([ -d "$TMPD/st-repo-dirty/.claude/worktrees/dirty" ]; echo $?)"
chk "the sibling's dirty line is still there" \
  "$(grep -qx sibling-dirt "$TMPD/st-repo-dirty/a.txt"; echo $?)"

chk_has "wrap --help names start" "$("$WRAP" --help 2>&1)" "wrap.sh start <repo> <branch>"
chk_has "commands/wrap.md names start for the hand-made-worktree shape" \
  "$(cat "$KIT_DIR/commands/wrap.md")" "bin/wrap start <repo> <branch>"

# ===========================================================================
echo "=== start --carry: moves the main checkout's own edits into the worktree ==="
# ===========================================================================
# Reuses build_start's clone-of-bare-rmain fixture; a.txt is the tracked file every
# clone starts with (build_remote's base commit), so dirtying it exercises the tracked
# half of a carry and a fresh *.txt exercises the untracked half.

echo "--- (a) everything: a modified tracked file and a new untracked file, main left clean"
build_start carry-a rmain main
CREPO="$TMPD/st-repo-carry-a"
echo dirty-a >> "$CREPO/a.txt"
echo untracked-a > "$CREPO/new-a.txt"
CWT="$(cd "$CREPO" && pwd -P)/.claude/worktrees/carry-a"
out="$("$WRAP" start "$CREPO" feat/carry-a --carry 2>"$TMPD/carry-a.err")"; rc=$?
chk "carry: exits 0 on a clean carry" "$rc"
chk "carry: still prints only the worktree path on stdout" "$([ "$out" = "$CWT" ]; echo $?)"
chk "carry: the tracked edit landed in the worktree" \
  "$(grep -qx dirty-a "$CWT/a.txt"; echo $?)"
chk "carry: the untracked file landed in the worktree" \
  "$(grep -qx untracked-a "$CWT/new-a.txt"; echo $?)"
chk "carry: the main checkout's tracked file is clean" \
  "$(git -C "$CREPO" diff --quiet -- a.txt; echo $?)"
chk "carry: the main checkout dropped the untracked file" \
  "$([ ! -e "$CREPO/new-a.txt" ]; echo $?)"
chk "carry: no leftover stash entry" \
  "$([ -z "$(git -C "$CREPO" stash list)" ]; echo $?)"
chk_has "carry: reports what it carried" "$(cat "$TMPD/carry-a.err")" "carried:"

echo "--- (b) --carry <path> takes only that path, the other dirty file stays in main"
build_start carry-b rmain main
CREPO="$TMPD/st-repo-carry-b"
echo dirty-b >> "$CREPO/a.txt"
echo other-dirt > "$CREPO/other.txt"
CWT="$(cd "$CREPO" && pwd -P)/.claude/worktrees/carry-b"
out="$("$WRAP" start "$CREPO" feat/carry-b --carry a.txt 2>/dev/null)"; rc=$?
chk "carry <path>: exits 0" "$rc"
chk "carry <path>: the named path landed in the worktree" \
  "$(grep -qx dirty-b "$CWT/a.txt"; echo $?)"
chk "carry <path>: the other dirty file stayed in main" \
  "$(grep -qx other-dirt "$CREPO/other.txt"; echo $?)"
chk "carry <path>: the other file never reached the worktree" \
  "$([ ! -e "$CWT/other.txt" ]; echo $?)"

echo "--- (c) nothing dirty prints the marker, the worktree is still made"
build_start carry-c rmain main
CREPO="$TMPD/st-repo-carry-c"
CWT="$(cd "$CREPO" && pwd -P)/.claude/worktrees/carry-c"
out="$("$WRAP" start "$CREPO" feat/carry-c --carry 2>"$TMPD/carry-c.err")"; rc=$?
chk "carry: nothing dirty exits 0" "$rc"
chk_has "carry: nothing dirty prints the marker" "$(cat "$TMPD/carry-c.err")" "nothing to carry"
chk "carry: the worktree still exists" "$([ -d "$CWT" ]; echo $?)"

echo "--- (d) an index.lock held by another writer refuses by name, worktree stays"
build_start carry-d rmain main
CREPO="$TMPD/st-repo-carry-d"
echo dirty-d >> "$CREPO/a.txt"
CWT="$(cd "$CREPO" && pwd -P)/.claude/worktrees/carry-d"
# `git worktree add` runs post-checkout synchronously, after the worktree exists and
# before start's own carry-time write-guard check: planting the stale lock there times
# the refusal deterministically, no race with git's own (unrelated) internal locking.
mkdir -p "$CREPO/.git/hooks"
cat > "$CREPO/.git/hooks/post-checkout" <<HOOK
#!/bin/sh
touch -t 202601010000 "$CREPO/.git/index.lock"
HOOK
chmod +x "$CREPO/.git/hooks/post-checkout"
out="$("$WRAP" start "$CREPO" feat/carry-d --carry 2>&1 >/dev/null)"; rc=$?
rm -f "$CREPO/.git/hooks/post-checkout" "$CREPO/.git/index.lock"
chk "carry: an index.lock refusal exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "carry: the refusal names index.lock" "$out" "index.lock held by another writer"
chk_has "carry: the refusal says the worktree exists" "$out" "the worktree exists at ${CWT}"
chk "carry: the worktree was still created" "$([ -d "$CWT" ]; echo $?)"
chk "carry: an index.lock refusal took no stash" \
  "$([ -z "$(git -C "$CREPO" stash list)" ]; echo $?)"
chk "carry: the refusal left the main checkout's edit in place" \
  "$(grep -qx dirty-d "$CREPO/a.txt"; echo $?)"

echo "--- (e) a pre-existing foreign stash entry is untouched"
build_start carry-e rmain main
CREPO="$TMPD/st-repo-carry-e"
echo foreign-dirt >> "$CREPO/a.txt"
git -C "$CREPO" stash push -q -m "someone-elses-stash"
FOREIGN_SHA="$(git -C "$CREPO" stash list --format='%H' | head -1)"
echo dirty-e >> "$CREPO/a.txt"
"$WRAP" start "$CREPO" feat/carry-e --carry >/dev/null 2>&1
chk "carry: a foreign stash entry is still there" \
  "$(git -C "$CREPO" stash list --format='%H' | grep -qx "$FOREIGN_SHA"; echo $?)"
chk "carry: the foreign entry's message is unchanged" \
  "$(git -C "$CREPO" stash list --format='%gs' | grep -qF ': someone-elses-stash'; echo $?)"

echo "--- plain start (no --carry) is unaffected"
build_start carry-f rmain main
CREPO="$TMPD/st-repo-carry-f"
echo untouched >> "$CREPO/a.txt"
out="$("$WRAP" start "$CREPO" feat/carry-f 2>&1)"; rc=$?
chk "no --carry: exits 0" "$rc"
chk "no --carry: the main checkout's edit is untouched" \
  "$(grep -qx untouched "$CREPO/a.txt"; echo $?)"
chk "no --carry: no stash was taken" \
  "$([ -z "$(git -C "$CREPO" stash list)" ]; echo $?)"

# ===========================================================================
echo "=== start --pick: folds worker branches into the new worktree ==="
# ===========================================================================
# mk_worker <repo> <branch> <file> <line>... : a local branch off origin/main with one commit
# per line, each appending <line> to <file>. The checkout returns to main, so the main
# checkout stays clean.
mk_worker() {
  local repo="$1" b="$2" f="$3"; shift 3
  git -C "$repo" switch -q -c "$b" origin/main
  for l in "$@"; do echo "$l" >> "$repo/$f"; git -C "$repo" add -A; git -C "$repo" commit -qm "$b: $l"; done
  git -C "$repo" switch -q main
}

build_start pick rmain main
PREPO="$TMPD/st-repo-pick"
mk_worker "$PREPO" w/one one.txt a1 a2
mk_worker "$PREPO" w/two two.txt b1
git -C "$PREPO" branch w/empty origin/main
out="$("$WRAP" start "$PREPO" feat/fold --pick w/one --pick w/two --pick w/empty 2>"$TMPD/pick.err")"; rc=$?
PWT="$(cd "$PREPO" && pwd -P)/.claude/worktrees/fold"
chk "pick: exits 0 on two branches and an empty one" "$rc"
chk "pick: stdout is the worktree path only" "$([ "$out" = "$PWT" ]; echo $?)"
chk_has "pick: reports the first branch" "$(cat "$TMPD/pick.err")" "picked w/one: 2 commits"
chk_has "pick: reports the second branch" "$(cat "$TMPD/pick.err")" "picked w/two: 1 commits"
chk_has "pick: an empty branch prints nothing to pick" "$(cat "$TMPD/pick.err")" "pick w/empty: nothing to pick"
chk "pick: the first branch's files landed" "$([ "$(cat "$PWT/one.txt" 2>/dev/null)" = "$(printf 'a1\na2')" ]; echo $?)"
chk "pick: the second branch's file landed" "$(grep -qx b1 "$PWT/two.txt"; echo $?)"
chk "pick: three commits sit past origin/main" \
  "$([ "$(git -C "$PWT" rev-list --count origin/main..HEAD)" = 3 ]; echo $?)"
chk "pick: commits are in argument order" \
  "$([ "$(git -C "$PWT" log --reverse --format=%s origin/main..HEAD | tr '\n' ',')" = "w/one: a1,w/one: a2,w/two: b1," ]; echo $?)"
chk "pick: the worktree is clean" "$([ -z "$(git -C "$PWT" status --porcelain)" ]; echo $?)"
chk "pick: the worker branch is untouched" \
  "$([ "$(git -C "$PREPO" rev-list --count origin/main..w/one)" = 2 ]; echo $?)"

echo "--- a missing branch refuses by name before any pick"
mk_worker "$PREPO" w/three three.txt c1
out="$("$WRAP" start "$PREPO" feat/missing --pick w/three --pick w/ghost 2>&1)"; rc=$?
MWT="$(cd "$PREPO" && pwd -P)/.claude/worktrees/missing"
chk "pick: a missing branch exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pick: the refusal names the missing branch" "$out" "--pick branch w/ghost does not exist locally or on origin"
chk "pick: the worktree is still created" "$([ -d "$MWT" ]; echo $?)"
chk "pick: nothing was picked before the refusal" \
  "$([ "$(git -C "$MWT" rev-list --count origin/main..HEAD)" = 0 ]; echo $?)"

echo "--- a branch known only on origin resolves"
git -C "$TMPD/st-pusher" switch -q -c w/remote-only origin/main
echo r1 > "$TMPD/st-pusher/remote.txt"; git -C "$TMPD/st-pusher" add -A; git -C "$TMPD/st-pusher" commit -qm remote-only
git -C "$TMPD/st-pusher" push -q origin w/remote-only
git -C "$TMPD/st-pusher" switch -q main
out="$("$WRAP" start "$PREPO" feat/remote --pick w/remote-only 2>&1)"; rc=$?
chk "pick: an origin-only branch exits 0" "$rc"
chk "pick: the origin-only commit landed" \
  "$(grep -qx r1 "$PREPO/.claude/worktrees/remote/remote.txt"; echo $?)"

echo "--- a conflict aborts, keeps the earlier picks, never resolves"
mk_worker "$PREPO" w/ok ok.txt k1
mk_worker "$PREPO" w/clash-a clash.txt from-a
mk_worker "$PREPO" w/clash-b clash.txt from-b
out="$("$WRAP" start "$PREPO" feat/clash --pick w/ok --pick w/clash-a --pick w/clash-b 2>&1)"; rc=$?
CWT="$(cd "$PREPO" && pwd -P)/.claude/worktrees/clash"
chk "pick: a conflict exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pick: names the conflicting branch and file" "$out" "PICK CONFLICT w/clash-b: clash.txt"
chk_has "pick: names the commits already picked" "$out" "already picked in ${CWT}:"
chk "pick: the cherry-pick was aborted" \
  "$([ ! -f "$(git -C "$CWT" rev-parse --git-path CHERRY_PICK_HEAD)" ]; echo $?)"
chk "pick: the earlier picks are kept" \
  "$([ "$(git -C "$CWT" rev-list --count origin/main..HEAD)" = 2 ]; echo $?)"
chk "pick: the tree is clean after the abort" "$([ -z "$(git -C "$CWT" status --porcelain)" ]; echo $?)"
chk "pick: the conflicting side did not leak" \
  "$(grep -qx from-a "$CWT/clash.txt" && ! grep -q from-b "$CWT/clash.txt"; echo $?)"

echo "--- --pick with --carry: picks first, then the carried edits"
mk_worker "$PREPO" w/car car.txt p1
echo carried-edit >> "$PREPO/a.txt"
out="$("$WRAP" start "$PREPO" feat/both --carry --pick w/car 2>&1)"; rc=$?
BWT="$(cd "$PREPO" && pwd -P)/.claude/worktrees/both"
chk "pick+carry: exits 0 with --pick after --carry" "$rc"
chk "pick+carry: the pick landed as a commit" \
  "$(git -C "$BWT" log --format=%s origin/main..HEAD | grep -qx 'w/car: p1'; echo $?)"
chk "pick+carry: the carried edit is uncommitted in the worktree" \
  "$(git -C "$BWT" diff --name-only | grep -qx a.txt; echo $?)"
git -C "$PREPO" checkout -q -- a.txt

echo "--- --pick usage"
out="$("$WRAP" start "$PREPO" feat/nopick --pick 2>&1)"; rc=$?
chk "pick: --pick with no branch exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pick: the usage error names --pick" "$out" "--pick needs a branch name"
chk "pick: a usage error created no worktree" "$([ ! -e "$PREPO/.claude/worktrees/nopick" ]; echo $?)"
chk_has "wrap --help names --pick" "$("$WRAP" --help 2>&1)" "--pick <branch>"
chk_has "commands/wrap.md names --pick" "$(cat "$KIT_DIR/commands/wrap.md")" '`--pick <branch>`'

echo "=== start: flags packed into one positional are refused ==="
out="$("$WRAP" start " --carry" br 2>&1)"; rc=$?
chk "packed arg to start exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "packed arg to start names the packed-flags refusal" "$out" "wrap.sh start: argument '"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-start: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-start: all $PASS passed"
