#!/usr/bin/env bash
# test-wrap-apply.sh -- the apply cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ------------------------------------------------- seed: the scan section's clones
# clone-scan-main is this suite's dry-run repo: the monolith builds it in the scan
# loop (lines 291-295); the loop's own scan asserts stay in test-wrap-scan.sh.
for pair in "rmain main" "rmaster master" "rdev develop"; do
  set -- $pair
  rname="$1"; def="$2"
  make_clone "scan-$def" "$rname" "$def" unmerged
  set_stub "$rname" "$def"
done
# ===========================================================================
echo "=== apply dry-run: every SKIP reason, and no write ==="
# ===========================================================================
set_stub rmain main
DRY="$TMPD/clone-scan-main"
before_b="$(git -C "$DRY" branch --list)"
before_w="$(git -C "$DRY" worktree list)"
out="$("$WRAP" apply "$DRY" 2>&1)"; rc=$?
chk "apply dry-run exits 0" "$rc"
chk_has "apply dry-run: wt-clean skipped without --worktrees" "$out" "--worktrees not given"
chk_has "apply dry-run: the checked-out branch is skipped" "$out" "SKIP unmerged: currently checked out"
chk_has "apply dry-run: squash-stale names both short SHAs" "$out" "SKIP squash-stale: tip $(git -C "$DRY" rev-parse squash-stale | cut -c1-7) != merged PR head 1111111"
chk_has "apply dry-run: stacked-child names the other base" "$out" "SKIP stacked-child: merged into feat/parent, not the default branch"
chk_has "apply dry-run: pull skipped off the default branch" "$out" "SKIP pull: checkout on 'unmerged', not the default branch main"
chk_has "apply dry-run: the deletes are announced, not run" "$out" "[DRY-RUN] delete merged-ancestor"

out="$("$WRAP" apply --worktrees "$DRY" 2>&1)"; rc=$?
chk "apply dry-run --worktrees exits 0" "$rc"
chk_has "apply dry-run: the dirty worktree is skipped" "$out" "dirty (another session's work stays)"
chk_has "apply dry-run: the detached worktree is skipped" "$out" "detached HEAD (removal could orphan the commit)"
chk_has "apply dry-run: the proven locked worktree prints WOULD with path, branch and locked" "$out" \
  "WOULD remove worktree $TMPD_P/wt-scan-main-clean [wt-clean, locked] and delete wt-clean (squash-merged per gh)"
after_b="$(git -C "$DRY" branch --list)"
after_w="$(git -C "$DRY" worktree list)"
chk "apply without --apply changes no branch (byte-equal)" "$([ "$before_b" = "$after_b" ]; echo $?)"
chk "apply without --apply changes no worktree (byte-equal)" "$([ "$before_w" = "$after_w" ]; echo $?)"

# ===========================================================================
echo "=== apply --apply --worktrees: only the proven deletes, and a ff pull ==="
# ===========================================================================
make_clone apply-main rmain main main
# Advance the remote default branch so the pull has something to fast-forward to.
git clone -q "$TMPD/bare-rmain" "$TMPD/pusher"
gitc "$TMPD/pusher"
echo advance >> "$TMPD/pusher/a.txt"
git -C "$TMPD/pusher" commit -qam advance
git -C "$TMPD/pusher" push -q origin main
NEW_TIP="$(git -C "$TMPD/bare-rmain" rev-parse main)"

set_stub rmain main
APPLYREPO="$TMPD/clone-apply-main"
out="$("$WRAP" apply --apply --worktrees "$APPLYREPO" 2>&1)"; rc=$?
chk "apply --apply exits 0 on a healthy repo" "$rc"
branches="$(git -C "$APPLYREPO" for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' ')"
chk "apply --apply deleted merged-ancestor, squash-ok and the removed worktree's wt-clean" \
  "$([ "$branches" = "main squash-stale stacked-child unmerged wt-dirty " ]; echo $?)"
chk_no "apply --apply never touched the default branch" "$out" "delete main"
chk "apply --apply removed the clean worktree only" \
  "$([ ! -d "$TMPD/wt-apply-main-clean" ] && [ -d "$TMPD/wt-apply-main-dirty" ] && [ -d "$TMPD/wt-apply-main-det" ]; echo $?)"
chk_has "apply --apply names the removed worktree's path, branch and lock" "$out" \
  "remove worktree $TMPD_P/wt-apply-main-clean [wt-clean, locked] and delete wt-clean"
chk "apply --apply fast-forwarded the default branch" \
  "$([ "$(git -C "$APPLYREPO" rev-parse HEAD)" = "$NEW_TIP" ]; echo $?)"

# ===========================================================================
echo "=== apply --worktrees: the locked-worktree matrix (proven, dirty, unproven) ==="
# ===========================================================================
# One clone, three locked worktrees: the Agent tool locks every worktree it creates, so a lock is
# the normal state here and the merge proof, not the lock, decides.
git clone -q "$TMPD/bare-rmain" "$TMPD/clone-wtmatrix"
MTX="$TMPD/clone-wtmatrix"
gitc "$MTX"
git -C "$MTX" remote set-head origin main >/dev/null 2>&1
for b in merged-ancestor squash-stale wt-clean wt-dirty; do
  git -C "$MTX" branch "$b" "origin/$b" >/dev/null 2>&1
done
for pair in "proven wt-clean" "dirty wt-dirty" "unproven squash-stale"; do
  set -- $pair
  git -C "$MTX" worktree add "$TMPD/mtx-$1" "$2" >/dev/null 2>&1
  git -C "$MTX" worktree lock "$TMPD/mtx-$1" >/dev/null 2>&1
done
# Unlocked and proven: the report reads the real lock state rather than assuming one.
git -C "$MTX" worktree add "$TMPD/mtx-unlocked" merged-ancestor >/dev/null 2>&1
echo dirt > "$TMPD/mtx-dirty/dirt.txt"
set_stub rmain main

out="$("$WRAP" apply --worktrees "$MTX" 2>&1)"
chk_has "matrix dry-run: the proven locked worktree is a WOULD line" "$out" \
  "WOULD remove worktree $TMPD_P/mtx-proven [wt-clean, locked] and delete wt-clean"
chk_has "matrix dry-run: the locked dirty worktree still skips as dirty" "$out" \
  "SKIP $TMPD_P/mtx-dirty: dirty (another session's work stays)"
chk_has "matrix dry-run: the locked unproven worktree skips unproven" "$out" \
  "SKIP $TMPD_P/mtx-unproven: squash-stale is not proven merged into main (leave it)"
chk_has "matrix dry-run: an unlocked proven worktree reads as unlocked" "$out" \
  "WOULD remove worktree $TMPD_P/mtx-unlocked [merged-ancestor, unlocked] and delete merged-ancestor (ancestor of origin/main)"
chk "matrix dry-run removed nothing" \
  "$([ -d "$TMPD/mtx-proven" ] && [ -d "$TMPD/mtx-dirty" ] && [ -d "$TMPD/mtx-unproven" ]; echo $?)"

out="$("$WRAP" apply --apply --worktrees "$MTX" 2>&1)"; rc=$?
chk "matrix apply exits 0" "$rc"
chk "matrix apply removed the proven locked worktree" "$([ ! -e "$TMPD/mtx-proven" ]; echo $?)"
chk "matrix apply deleted the removed worktree's branch" \
  "$(git -C "$MTX" show-ref --verify --quiet refs/heads/wt-clean && echo 1 || echo 0)"
chk_has "matrix apply names the branch delete with its proof" "$out" \
  "delete wt-clean (squash-merged per gh, its locked worktree is gone)"
chk "matrix apply kept the dirty and unproven worktrees" \
  "$([ -d "$TMPD/mtx-dirty" ] && [ -d "$TMPD/mtx-unproven" ]; echo $?)"
chk "matrix apply kept the unproven worktree's branch" \
  "$(git -C "$MTX" show-ref --verify --quiet refs/heads/squash-stale; echo $?)"

# ===========================================================================
echo "=== apply --own: only the named worktrees are candidates (SPEC-302) ==="
# ===========================================================================
# A shared repo cannot use --worktrees without endangering other sessions' worktrees,
# so --own names the session's own set and everything else is out of scope.
make_clone own rmain main unmerged
set_stub rmain main
OWNREPO="$TMPD/clone-own"

out="$("$WRAP" apply --own "$TMPD/wt-own-clean" "$OWNREPO" 2>&1)"; rc=$?
chk "--own dry-run exits 0 without --worktrees (own implies the opt-in)" "$rc"
chk_has "--own dry-run: the scope line" "$out" \
  "scope --own: only the named worktrees are candidates"
chk_has "--own dry-run: the named proven worktree is a WOULD line" "$out" \
  "WOULD remove worktree $TMPD_P/wt-own-clean [wt-clean, locked] and delete wt-clean"
chk_no "--own dry-run: the unnamed dirty worktree gets no line at all" "$out" "wt-own-dirty"
chk_no "--own dry-run: the unnamed detached worktree gets no line at all" "$out" "wt-own-det"
chk_has "--own dry-run: the branch sweep is scoped off" "$out" \
  "SKIP branch sweep: --own scopes cleanup to the named worktrees"
chk_no "--own dry-run: the proven merged branch is no delete candidate" "$out" \
  "delete merged-ancestor"
chk "--own dry-run removed nothing" \
  "$([ -d "$TMPD/wt-own-clean" ] && [ -d "$TMPD/wt-own-dirty" ]; echo $?)"

out="$("$WRAP" apply --apply --own "$TMPD/wt-own-clean" "$OWNREPO" 2>&1)"; rc=$?
chk "--own apply exits 0" "$rc"
chk "--own apply removed only the named worktree" \
  "$([ ! -e "$TMPD/wt-own-clean" ] && [ -d "$TMPD/wt-own-dirty" ] && [ -d "$TMPD/wt-own-det" ]; echo $?)"
chk "--own apply deleted the named worktree's branch" \
  "$(git -C "$OWNREPO" show-ref --verify --quiet refs/heads/wt-clean && echo 1 || echo 0)"
chk "--own apply kept the unnamed merged branch (sweep scoped off)" \
  "$(git -C "$OWNREPO" show-ref --verify --quiet refs/heads/merged-ancestor; echo $?)"
chk "--own apply kept the unnamed worktrees' branches" \
  "$(git -C "$OWNREPO" show-ref --verify --quiet refs/heads/wt-dirty; echo $?)"

# A named dirty worktree refuses like any swept one; a bogus path is reported, not silent.
out="$("$WRAP" apply --own "$TMPD/wt-own-dirty" --own "$TMPD/wt-notthere" "$OWNREPO" 2>&1)"; rc=$?
chk "--own on a dirty plus a bogus path exits 0" "$rc"
chk_has "--own: a named dirty worktree still refuses" "$out" \
  "SKIP $TMPD_P/wt-own-dirty: dirty (another session's work stays)"
chk_has "--own: a named path that is no worktree says so" "$out" \
  "SKIP $TMPD/wt-notthere: not a registered worktree"
chk "--own: the dirty worktree stays" "$([ -d "$TMPD/wt-own-dirty" ]; echo $?)"

# Canonicalisation: a trailing-slash path names the same registered worktree, and
# --worktrees + --own together still honour the own set.
out="$("$WRAP" apply --worktrees --own "$TMPD/wt-own-det/" "$OWNREPO" 2>&1)"; rc=$?
chk "--own canonicalised a trailing-slash path, exits 0" "$rc"
chk_has "--own: the named detached worktree refuses as detached" "$out" \
  "SKIP $TMPD_P/wt-own-det: detached HEAD (removal could orphan the commit)"
chk_no "--own + --worktrees: the unnamed proven worktree stays out of scope" "$out" \
  "wt-own-clean"

out="$("$WRAP" apply --own 2>&1)"; rc=$?
chk "--own with no value exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "--own with no value names the missing arg" "$out" "--own needs a worktree path"

# Flags packed into one word (a zsh unsplit `$args`) refuse with 64 and touch nothing, so a
# lost --own can never widen into a sweep of every merged worktree.
PACKED=" --own $TMPD/wt-own-dirty"
out="$("$WRAP" apply --apply --worktrees "$PACKED" "$OWNREPO" 2>&1)"; rc=$?
chk "packed ' --own <path>' to apply exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "packed arg: the one-line refusal" "$out" \
  "wrap.sh apply: argument '$PACKED' looks like flags packed into one word (an unsplit variable?); pass each flag and path as its own argument"
chk_no "packed arg: it is never treated as a repo" "$out" "not a git repo"
chk "packed arg: nothing removed" "$([ -d "$TMPD/wt-own-dirty" ] && [ -d "$TMPD/wt-own-det" ]; echo $?)"

# A real path with a space (and no ' --') is still a repo.
SPACEREPO="$TMPD/dir with space"
git init -q "$SPACEREPO" && git -C "$SPACEREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
out="$("$WRAP" apply "$SPACEREPO" 2>&1)"; rc=$?
chk "a repo path containing a space still works, exits 0" "$rc"
chk_no "space path: not flagged as packed" "$out" "packed into one word"
chk_no "space path: seen as a git repo" "$out" "not a git repo"

# ===========================================================================
echo "=== apply --worktrees: a lock naming a live pid is skipped, a dead pid is removed ==="
# ===========================================================================
# A worktree the Agent tool just created for a still-running subagent is also locked and its
# fresh branch can be a trivial ancestor of origin/main: the lock alone must not authorize
# removal when the pid it names is still alive.
git -C "$MTX" branch mtx-live-branch origin/merged-ancestor >/dev/null 2>&1
git -C "$MTX" branch mtx-dead-branch origin/merged-ancestor >/dev/null 2>&1
git -C "$MTX" worktree add "$TMPD/mtx-livepid" mtx-live-branch >/dev/null 2>&1
git -C "$MTX" worktree lock "$TMPD/mtx-livepid" --reason "claude agent test (pid $$ started now)" >/dev/null 2>&1
git -C "$MTX" worktree add "$TMPD/mtx-deadpid" mtx-dead-branch >/dev/null 2>&1
( sleep 0 ) & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null
git -C "$MTX" worktree lock "$TMPD/mtx-deadpid" --reason "claude agent test (pid $DEAD_PID started now)" >/dev/null 2>&1

out="$("$WRAP" apply --worktrees "$MTX" 2>&1)"
chk_has "livepid dry-run: the live-pid worktree is skipped, not removed" "$out" \
  "SKIP $TMPD_P/mtx-livepid: locked by live pid $$ (an agent is still running)"
chk_has "livepid dry-run: the dead-pid worktree still reads as a WOULD remove" "$out" \
  "WOULD remove worktree $TMPD_P/mtx-deadpid [mtx-dead-branch, locked] and delete mtx-dead-branch (ancestor of origin/main)"

out="$("$WRAP" apply --apply --worktrees "$MTX" 2>&1)"; rc=$?
chk "livepid apply exits 0" "$rc"
chk "livepid apply removed the dead-pid worktree" "$([ ! -e "$TMPD/mtx-deadpid" ]; echo $?)"
chk "livepid apply kept the live-pid worktree" "$([ -d "$TMPD/mtx-livepid" ]; echo $?)"
chk "livepid apply kept the live-pid worktree's branch" \
  "$(git -C "$MTX" show-ref --verify --quiet refs/heads/mtx-live-branch; echo $?)"

# ===========================================================================
echo "=== apply --worktrees: the default branch and the main checkout's branch are off limits ==="
# ===========================================================================
# git allows a second worktree on an already-checked-out branch under --force, which is the only
# way either guard can be reached. Both would otherwise pass the merge proof: the default branch is
# an ancestor of itself, and a session's own branch may well be merged already.
make_clone guards rmain main unmerged
GUARDS="$TMPD/clone-guards"
git -C "$GUARDS" worktree add --force "$TMPD/wt-guards-default" main >/dev/null 2>&1
git -C "$GUARDS" worktree lock "$TMPD/wt-guards-default" >/dev/null 2>&1
git -C "$GUARDS" worktree add --force "$TMPD/wt-guards-cur" unmerged >/dev/null 2>&1
git -C "$GUARDS" worktree lock "$TMPD/wt-guards-cur" >/dev/null 2>&1
set_stub rmain main
out="$("$WRAP" apply --apply --worktrees "$GUARDS" 2>&1)"
chk_has "apply --worktrees: a worktree on the default branch is skipped" "$out" \
  "SKIP $TMPD_P/wt-guards-default: main is the default or a protected branch name"
chk_has "apply --worktrees: a worktree on the main checkout's branch is skipped" "$out" \
  "SKIP $TMPD_P/wt-guards-cur: unmerged is the main checkout's branch"
chk "apply --worktrees: both guarded worktrees and their branches survive" \
  "$([ -d "$TMPD/wt-guards-default" ] && [ -d "$TMPD/wt-guards-cur" ] \
     && git -C "$GUARDS" show-ref --verify --quiet refs/heads/main \
     && git -C "$GUARDS" show-ref --verify --quiet refs/heads/unmerged; echo $?)"

# ===========================================================================
echo "=== apply --apply --worktrees: a removal that leaves the path is FAILED, exit 2 ==="
# ===========================================================================
# The postcondition is the point: git prunes the admin entry even when it cannot delete the
# directory, so a report that trusted the exit code alone would call this worktree removed.
git clone -q "$TMPD/bare-rmain" "$TMPD/clone-wtpost"
POST="$TMPD/clone-wtpost"
gitc "$POST"
git -C "$POST" remote set-head origin main >/dev/null 2>&1
git -C "$POST" branch wt-clean origin/wt-clean >/dev/null 2>&1
mkdir -p "$TMPD/ro-parent"
git -C "$POST" worktree add "$TMPD/ro-parent/stuck" wt-clean >/dev/null 2>&1
git -C "$POST" worktree lock "$TMPD/ro-parent/stuck" >/dev/null 2>&1
set_stub rmain main
chmod 500 "$TMPD/ro-parent"
out="$("$WRAP" apply --apply --worktrees "$POST" 2>&1)"; rc=$?
chmod 700 "$TMPD/ro-parent"
chk "apply exits 2 when the postcondition fails" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "the failed postcondition is reported, not silent" "$out" \
  "FAILED remove worktree $TMPD_P/ro-parent/stuck [wt-clean, locked] and delete wt-clean (squash-merged per gh): $TMPD_P/ro-parent/stuck survived the removal, wt-clean not deleted"
chk "the stuck worktree path is still there" "$([ -d "$TMPD/ro-parent/stuck" ]; echo $?)"
# The branch delete is the half a silent postcondition would cost, so the worktree step must not
# reach it. The later branch pass may still delete the same proven branch under its own gate,
# which is why the assertion reads the step's own line rather than the ref.
chk_no "a failed postcondition never reaches the worktree step's branch delete" "$out" \
  "delete wt-clean (squash-merged per gh, its locked worktree is gone)"

# ===========================================================================
echo "=== apply --apply: a non-ff default branch is FAILED, exit 2, never forced ==="
# ===========================================================================
make_clone apply-nonff rmaster master master
OLD_MASTER="$(git -C "$TMPD/clone-apply-nonff" rev-parse master)"
git clone -q "$TMPD/bare-rmaster" "$TMPD/rewriter"
gitc "$TMPD/rewriter"
git -C "$TMPD/rewriter" reset -q --hard HEAD~1
echo divergent > "$TMPD/rewriter/divergent.txt"
git -C "$TMPD/rewriter" add -A; git -C "$TMPD/rewriter" commit -qm divergent
git -C "$TMPD/rewriter" push -q --force origin HEAD:refs/heads/master
set_stub rmaster master
# The local master now holds a commit origin lost, which the stray-commit carry would take
# to a branch and move off master. With its knob off the pull meets the divergence as is.
mkdir -p "$TMPD/nonff-carry-off"; printf '[wrap]\ncarry_stray_lines = false\n' > "$TMPD/nonff-carry-off/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$TMPD/nonff-carry-off" "$WRAP" apply --apply "$TMPD/clone-apply-nonff" 2>&1)"; rc=$?
chk "apply --apply exits 2 when a write fails" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "apply --apply reports the failed pull" "$out" "FAILED pull --ff-only"
chk "apply --apply never reset the local default branch" \
  "$([ "$(git -C "$TMPD/clone-apply-nonff" rev-parse master)" = "$OLD_MASTER" ]; echo $?)"

# ===========================================================================
echo "=== apply: a tip that moved during the run is skipped, not deleted ==="
# ===========================================================================
make_clone tips rmain main unmerged
set_stub rmain main
TIPSREPO="$TMPD/clone-tips"
STALE_TIPS="$TMPD/stale-tips.txt"
git -C "$TIPSREPO" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/ > "$STALE_TIPS"
# Rewrite merged-ancestor's recorded tip so the pre-delete re-check sees a moved branch.
sed 's/^merged-ancestor .*/merged-ancestor 2222222222222222222222222222222222222222/' \
  "$STALE_TIPS" > "$STALE_TIPS.new" && mv -f "$STALE_TIPS.new" "$STALE_TIPS"
out="$("$WRAP" apply --apply --tips-file "$STALE_TIPS" "$TIPSREPO" 2>&1)"
chk_has "apply: a moved tip is skipped" "$out" "SKIP merged-ancestor: tip moved during this run"
chk "apply: the moved-tip branch survives" \
  "$(git -C "$TIPSREPO" show-ref --verify --quiet refs/heads/merged-ancestor; echo $?)"
chk "apply: the unmoved squash-ok branch still went" \
  "$(git -C "$TIPSREPO" show-ref --verify --quiet refs/heads/squash-ok && echo 1 || echo 0)"

# The worktree gate re-reads the tip after the merge proof, because the proof can cost a network
# round trip and `-D` discards a commit made inside that window.
sed 's/^wt-clean .*/wt-clean 3333333333333333333333333333333333333333/' \
  "$STALE_TIPS" > "$STALE_TIPS.new" && mv -f "$STALE_TIPS.new" "$STALE_TIPS"
out="$("$WRAP" apply --apply --worktrees --tips-file "$STALE_TIPS" "$TIPSREPO" 2>&1)"
chk_has "apply --worktrees: a worktree whose branch tip moved is skipped" "$out" \
  "SKIP $TMPD_P/wt-tips-clean: wt-clean tip moved during this run (3333333"
chk "apply --worktrees: the moved-tip worktree and branch survive" \
  "$([ -d "$TMPD/wt-tips-clean" ] && git -C "$TIPSREPO" show-ref --verify --quiet refs/heads/wt-clean; echo $?)"

# ===========================================================================
echo "=== apply: index.lock age decides, and a non-repo never reaches a write ==="
# ===========================================================================
make_clone lock rmain main unmerged
set_stub rmain main
LOCKREPO="$TMPD/clone-lock"
touch -t 202601010000 "$LOCKREPO/.git/index.lock"
out="$("$WRAP" apply --apply "$LOCKREPO" 2>&1)"
chk_has "apply: a stale index.lock refuses every write" "$out" "index.lock held by another writer"
LOCK_BRANCHES="$(git -C "$LOCKREPO" for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' ')"
chk "apply: a stale index.lock deleted nothing" \
  "$([ "$LOCK_BRANCHES" = "main merged-ancestor squash-ok squash-stale stacked-child unmerged wt-clean wt-dirty " ]; echo $?)"

# A young lock that clears within the window is ordinary traffic: release it after 2 s from
# the background and the write proceeds. A young lock that persists is a writer (next case).
rm -f "$LOCKREPO/.git/index.lock"; touch "$LOCKREPO/.git/index.lock"
( sleep 2; rm -f "$LOCKREPO/.git/index.lock" ) &
out="$("$WRAP" apply --apply "$LOCKREPO" 2>&1)"
wait
chk_no "apply: a fresh index.lock that clears does not refuse the write" "$out" "index.lock held by another writer"
chk "apply: a fresh index.lock that clears still deleted the proven branches" \
  "$(git -C "$LOCKREPO" show-ref --verify --quiet refs/heads/merged-ancestor && echo 1 || echo 0)"
touch "$LOCKREPO/.git/index.lock"
out="$("$WRAP" apply --apply "$LOCKREPO" 2>&1)"
chk_has "apply: a fresh index.lock that persists past the window refuses the write" "$out" "index.lock held by another writer"
rm -f "$LOCKREPO/.git/index.lock"

# The same guard, at the worktree write site: the clean locked worktree is proven, so only the
# lock stands between it and a removal.
touch -t 202601010000 "$LOCKREPO/.git/index.lock"
out="$("$WRAP" apply --apply --worktrees "$LOCKREPO" 2>&1)"
rm -f "$LOCKREPO/.git/index.lock"
chk_has "apply --worktrees: a stale index.lock refuses the worktree removal" "$out" \
  "SKIP $TMPD_P/wt-lock-clean: index.lock held by another writer"
chk "apply --worktrees: the refused worktree is still there" "$([ -d "$TMPD/wt-lock-clean" ]; echo $?)"

out="$("$WRAP" apply --apply "$TMPD/not-a-repo" "$LOCKREPO" 2>&1)"
chk_has "apply: a non-repo argument is skipped before any write" "$out" "not a git repo, skipped"
chk_has "apply: the repo after the non-repo still runs" "$out" "-- branches:"

# ===========================================================================
echo "=== apply: a broken origin URL fails the fetch and deletes nothing ==="
# ===========================================================================
make_clone brokenremote rmain main unmerged
set_stub rmain main
BROKEN="$TMPD/clone-brokenremote"
BROKEN_BEFORE="$(git -C "$BROKEN" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
git -C "$BROKEN" remote set-url origin /nonexistent
out="$("$WRAP" apply --apply "$BROKEN" 2>&1)"
chk_has "apply: the failed fetch is reported" "$out" "(fetch failed; every delete is skipped)"
chk_has "apply: the ancestor branch names the stale-data reason" "$out" \
  "SKIP merged-ancestor: fetch failed, stale ancestor data"
out="$("$WRAP" apply --apply --worktrees "$BROKEN" 2>&1)"
chk_has "apply --worktrees: a failed fetch skips the worktree with the stale-proof reason" "$out" \
  "SKIP $TMPD_P/wt-brokenremote-clean: fetch failed, stale merge proof for wt-clean"
chk "apply --worktrees: the broken-remote repo lost no worktree" \
  "$([ -d "$TMPD/wt-brokenremote-clean" ]; echo $?)"
chk "apply: the broken-remote repo lost no branch" \
  "$([ "$BROKEN_BEFORE" = "$(git -C "$BROKEN" for-each-ref --format='%(refname:short)' refs/heads/ | sort)" ]; echo $?)"

# ===========================================================================
echo "=== apply --apply: an ancestor of origin/<default> goes whatever its upstream says ==="
# ===========================================================================
# `git branch -d` judges against the branch's own upstream, or HEAD when it has none. Local
# main sits behind origin/main here, so both branches fail git's check while wrap's proof
# (ancestor of origin/main) holds: one has no upstream, one tracks a ref that lacks its tip.
build_union_repo noup; advance_union_repo noup
NU="$TMPD/uclone-noup"
git -C "$NU" fetch -q origin
git -C "$NU" branch --no-track no-upstream origin/main
git -C "$NU" branch --no-track old-base main
git -C "$NU" branch --no-track other-upstream origin/main
git -C "$NU" branch -q -u old-base other-upstream
out="$("$WRAP" apply --apply "$NU" 2>&1)"; rc=$?
chk "no upstream: apply exits 0" "$rc"
chk_has "no upstream: the delete is reported" "$out" "[APPLY] delete no-upstream (ancestor of origin/main)"
chk_no "no upstream: no delete failed" "$out" "FAILED delete"
chk "no upstream: the branch with no upstream is gone" \
  "$(git -C "$NU" show-ref --verify --quiet refs/heads/no-upstream && echo 1 || echo 0)"
chk "no upstream: the branch tracking another ref is gone" \
  "$(git -C "$NU" show-ref --verify --quiet refs/heads/other-upstream && echo 1 || echo 0)"

# ===========================================================================
echo "=== apply: the origin sweep deletes only merged branches at their exact tip ==="
# ===========================================================================
# A real bare origin behind a github.com URL: `url.<bare>.insteadOf` sends every fetch and
# push to the bare, while remote.origin.url still reads as GitHub, which is what the sweep keys
# on. Each case builds a fresh pair, because --apply deletes on the bare.
OS_URL="https://github.com/o/sweep.git"
os_pr() { # os_pr <bare> <branch> <isCrossRepository> -- one merged-PR record at the branch tip
  printf '{"headRefName":"%s","headRefOid":"%s","isCrossRepository":%s}' "$2" "$(git -C "$1" rev-parse "$2")" "$3"
}
build_os_repo() { # build_os_repo <name> -- bare origin plus a clone on main, gh stubs exported
  local name="$1" work="$TMPD/oswork-$1" bare="$TMPD/osbare-$1" clone="$TMPD/osclone-$1" b
  mkdir -p "$work"
  git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/a.txt"; git -C "$work" add -A; git -C "$work" commit -q -m base
  for b in gone gone2 gone3 moved stack-base open-head fork-head; do
    git -C "$work" checkout -q -b "$b" main
    echo "$b" > "$work/$b.txt"; git -C "$work" add -A; git -C "$work" commit -q -m "$b"
  done
  git -C "$work" checkout -q main
  git clone -q --bare "$work" "$bare"
  GH_STUB_MERGED_ALL="[$(os_pr "$bare" gone false),$(os_pr "$bare" gone2 false),$(os_pr "$bare" gone3 false),$(os_pr "$bare" moved false),$(os_pr "$bare" stack-base false),$(os_pr "$bare" open-head false),$(os_pr "$bare" fork-head true),$(os_pr "$bare" main false)]"
  export GH_STUB_MERGED_ALL
  # open-head targets develop, a branch origin lacks, so each kept branch has exactly one guard.
  export GH_STUB_OPEN_PRS='[{"number":9,"title":"child","headRefName":"child","baseRefName":"stack-base"},{"number":10,"title":"open","headRefName":"open-head","baseRefName":"develop"}]'
  # moved gains a commit after its PR merged, so its origin tip is past the PR head.
  git -C "$work" checkout -q moved
  echo more >> "$work/moved.txt"; git -C "$work" commit -q -a -m more
  git -C "$work" checkout -q main
  git -C "$work" push -q "$bare" moved
  git clone -q "$bare" "$clone"; gitc "$clone"
  git -C "$clone" remote set-url origin "$OS_URL"
  git -C "$clone" config "url.$bare.insteadOf" "$OS_URL"
}
os_has() { git -C "$TMPD/osbare-$1" show-ref --verify --quiet "refs/heads/$2"; }
os_run() { KIT_CONFIG_ROOT="$KIT_DIR" "$WRAP" "$@" 2>&1; }

echo "--- dry run: names the eligible branches, deletes nothing"
build_os_repo dry
out="$(os_run apply "$TMPD/osclone-dry")"; rc=$?
chk "origin dry run exits 0" "$rc"
chk_has "origin dry run counts the eligible branches" "$out" "WOULD delete 3 merged branches on origin:"
chk_has "origin dry run names it" "$out" "       gone"
chk "origin dry run deleted nothing" "$(os_has dry gone; echo $?)"

echo "--- --apply: only merged branches at their PR head go"
build_os_repo app
out="$(os_run apply --apply "$TMPD/osclone-app")"; rc=$?
chk "origin --apply exits 0" "$rc"
chk_has "origin --apply reports the count" "$out" "deleted 3 of 3 merged branches on origin"
chk "origin --apply deleted gone, gone2 and gone3" "$(os_has app gone || os_has app gone2 || os_has app gone3 && echo 1 || echo 0)"
chk "origin --apply kept moved, its tip is past the PR head" "$(os_has app moved; echo $?)"
chk "origin --apply kept stack-base, an open PR targets it" "$(os_has app stack-base; echo $?)"
chk "origin --apply kept open-head, an open PR uses it" "$(os_has app open-head; echo $?)"
chk "origin --apply kept fork-head, its PR came from a fork" "$(os_has app fork-head; echo $?)"
chk "origin --apply kept the default branch" "$(os_has app main; echo $?)"
chk_no "origin --apply lists no kept branch" "$out" "moved"
chk_has "origin --apply went on to the pull" "$out" "-- pull:"
out="$(os_run apply --apply "$TMPD/osclone-app")"
chk_has "origin second --apply finds nothing left" "$out" "no merged branches left on origin"


echo "--- --own: the origin sweep still runs (it touches no local state)"
build_os_repo own
out="$(os_run apply --apply --own "$TMPD/no-such-wt" "$TMPD/osclone-own")"; rc=$?
chk "origin --own exits 0" "$rc"
chk_has "origin --own still reports the count" "$out" "deleted 3 of 3 merged branches on origin"
chk "origin --own deleted gone" "$(os_has own gone && echo 1 || echo 0)"
chk "origin --own kept moved" "$(os_has own moved; echo $?)"
echo "--- a failed PR read skips the sweep and deletes nothing"
build_os_repo nolist
out="$(GH_STUB_MERGED_ALL_RC=1 os_run apply --apply "$TMPD/osclone-nolist")"; rc=$?
chk "origin failed PR read exits 0" "$rc"
chk_has "origin failed PR read names the skip" "$out" "SKIP origin sweep: origin's branches or PRs could not be read"
chk "origin failed PR read deleted nothing" "$(os_has nolist gone; echo $?)"

echo "--- knob false: a report line, no delete"
OS_OFF="$TMPD/os-knob-off"; mkdir -p "$OS_OFF"
printf '[wrap]\ndelete_merged_remote_branches = false\n' > "$OS_OFF/kit.toml"
build_os_repo off
out="$(KIT_CONFIG_OPERATOR="$OS_OFF" os_run apply --apply "$TMPD/osclone-off")"; rc=$?
chk "origin knob false exits 0" "$rc"
chk_has "origin knob false prints the report line" "$out" \
  "3 merged branches left on origin (wrap.delete_merged_remote_branches=false)"
chk "origin knob false deleted nothing" "$(os_has off gone; echo $?)"

echo "--- a project .kit.toml cannot turn the knob off"
build_os_repo proj
printf '[wrap]\ndelete_merged_remote_branches = false\n' > "$TMPD/osclone-proj/.kit.toml"
out="$(cd "$TMPD/osclone-proj" && KIT_PROJECT_ROOT="$TMPD/osclone-proj" os_run apply --apply "$TMPD/osclone-proj")"
chk_no "origin project .kit.toml is ignored" "$out" "delete_merged_remote_branches=false"
chk "origin project .kit.toml did not stop the delete" "$(os_has proj gone && echo 1 || echo 0)"

echo "--- a refused push is FAILED, exit 2, and apply still finishes"
build_os_repo deny
git -C "$TMPD/osbare-deny" config receive.denyDeletes true
out="$(os_run apply --apply "$TMPD/osclone-deny")"; rc=$?
chk "origin refused push exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "origin refused push is FAILED" "$out" "FAILED delete 3 origin branches"
chk_has "origin refused push counts zero deleted" "$out" "deleted 0 of 3 merged branches on origin"
chk_has "origin refused push still ran the pull" "$out" "-- pull:"
chk "origin refused push left the branch" "$(os_has deny gone; echo $?)"

echo "--- a branch pushed to after the read is refused by the lease, the rest still go"
# pushInsteadOf sends the delete to a second bare whose gone moved on, which is what origin
# looks like when someone pushes between the ls-remote read and the delete.
build_os_repo lease
git clone -q --bare "$TMPD/osbare-lease" "$TMPD/osbare-lease-push"
git clone -q "$TMPD/osbare-lease-push" "$TMPD/oslease-pusher"; gitc "$TMPD/oslease-pusher"
git -C "$TMPD/oslease-pusher" checkout -q gone
echo late >> "$TMPD/oslease-pusher/gone.txt"; git -C "$TMPD/oslease-pusher" commit -q -a -m late
git -C "$TMPD/oslease-pusher" push -q origin gone
git -C "$TMPD/osclone-lease" config "url.$TMPD/osbare-lease-push.pushInsteadOf" "$OS_URL"
out="$(os_run apply --apply "$TMPD/osclone-lease")"; rc=$?
chk "origin lease refusal exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "origin lease refusal is FAILED" "$out" "FAILED delete 3 origin branches"
chk "origin lease kept the branch that moved" \
  "$(git -C "$TMPD/osbare-lease-push" show-ref --verify --quiet refs/heads/gone; echo $?)"
chk "origin lease still deleted the unmoved ones" \
  "$(git -C "$TMPD/osbare-lease-push" show-ref --verify --quiet refs/heads/gone2 && echo 1 || echo 0)"

echo "--- a chunk smaller than the list splits the delete into several pushes"
build_os_repo chunk
out="$(WRAP_ORIGIN_DELETE_CHUNK=2 os_run apply --apply "$TMPD/osclone-chunk")"; rc=$?
chk "origin chunked delete exits 0" "$rc"
chk_has "origin chunked delete removed all three" "$out" "deleted 3 of 3 merged branches on origin"
chk "origin chunked delete left none of them" "$(os_has chunk gone || os_has chunk gone2 || os_has chunk gone3 && echo 1 || echo 0)"
chk "origin chunked delete kept the default branch" "$(os_has chunk main; echo $?)"

echo "--- a non-GitHub origin is skipped by name"
out="$(os_run apply "$TMPD/clone-scan-main")"
chk_has "origin sweep skips a non-GitHub remote" "$out" "SKIP origin sweep: origin is not a GitHub remote"
unset GH_STUB_MERGED_ALL
export GH_STUB_OPEN_PRS='[{"number":7,"title":"wrap the session","headRefName":"feat/wrap"}]'

# ===========================================================================
echo "=== apply --archive-unmerged: opt-in push-to-origin archive of unmerged branches ==="
# ===========================================================================
# A fresh bare origin + clone per case (--apply writes on the bare). Three branches:
# nothing-unique (an ancestor of main, zero unique patches), unique-work and held-work
# (each one commit origin/main lacks). No gh stub needed: the sweep never calls gh.
AU_DATE="$(date +%Y%m%d)"
build_au_repo() { # build_au_repo <name>
  local name="$1" work="$TMPD/auwork-$1" bare="$TMPD/aubare-$1" clone="$TMPD/auclone-$1" b
  mkdir -p "$work"
  git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/a.txt"; git -C "$work" add -A; git -C "$work" commit -q -m "chore: base"
  git -C "$work" branch nothing-unique
  for b in unique-work held-work; do
    git -C "$work" checkout -q -b "$b" main
    echo "$b" > "$work/$b.txt"; git -C "$work" add -A; git -C "$work" commit -q -m "feat: $b"
  done
  git -C "$work" checkout -q main
  git clone -q --bare "$work" "$bare"
  git clone -q "$bare" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  for b in nothing-unique unique-work held-work; do
    git -C "$clone" branch "$b" "origin/$b" >/dev/null 2>&1
  done
}
au_has() { git -C "$TMPD/aubare-$1" show-ref --verify --quiet "refs/heads/$2"; }
au_local() { git -C "$TMPD/auclone-$1" show-ref --verify --quiet "refs/heads/$2"; }
au_run() { KIT_CONFIG_ROOT="$KIT_DIR" "$WRAP" "$@" 2>&1; }

echo "--- dry run: previews the eligible branch, writes nothing"
build_au_repo dry
out="$(au_run apply --archive-unmerged "$TMPD/auclone-dry")"; rc=$?
chk "archive dry run exits 0" "$rc"
chk_has "archive dry run previews unique-work" "$out" \
  "WOULD archive unique-work -> origin archive/unique-work-${AU_DATE} (1 unique commits)"
chk_has "archive dry run leaves the ancestor for the merged sweep" "$out" \
  "nothing-unique: nothing unique, left for the merged sweep"
chk "archive dry run kept unique-work locally" "$(au_local dry unique-work; echo $?)"
chk "archive dry run pushed no archive ref" \
  "$(au_has dry "archive/unique-work-${AU_DATE}" && echo 1 || echo 0)"

echo "--- --apply: the branch lands on origin and disappears locally; the ancestor is untouched"
build_au_repo app
out="$(au_run apply --apply --archive-unmerged "$TMPD/auclone-app")"; rc=$?
chk "archive apply exits 0" "$rc"
chk_has "archive apply reports the landed ref" "$out" \
  "archived unique-work -> archive/unique-work-${AU_DATE}"
chk "archive apply pushed the ref to origin" "$(au_has app "archive/unique-work-${AU_DATE}"; echo $?)"
chk "archive apply deleted the local branch" "$(au_local app unique-work && echo 1 || echo 0)"
# nothing-unique is an ancestor of origin/main, so the EXISTING merged-branch sweep already
# deletes it before archive-unmerged ever looks at it (spec: "already covered by existing
# logic"); it must never be pushed to an archive ref either way.
chk "archive apply left nothing-unique for the existing ancestor sweep, not archive-unmerged" \
  "$(au_local app nothing-unique && echo 1 || echo 0)"
chk "archive apply never archived nothing-unique" \
  "$(au_has app "archive/nothing-unique-${AU_DATE}" && echo 1 || echo 0)"

echo "--- a worktree-held branch is skipped, never archived and never deleted"
build_au_repo wt
git -C "$TMPD/auclone-wt" worktree add -q "$TMPD/au-wt-held" held-work >/dev/null 2>&1
out="$(au_run apply --apply --archive-unmerged "$TMPD/auclone-wt")"; rc=$?
chk_has "archive wt-held is skipped by name" "$out" "SKIP held-work: held by a worktree"
chk "archive wt-held kept the branch locally" "$(au_local wt held-work; echo $?)"
chk "archive wt-held pushed no archive ref for it" \
  "$(au_has wt "archive/held-work-${AU_DATE}" && echo 1 || echo 0)"

echo "--- a push a pre-push hook refuses is FAILED, exit 2, the branch stays local"
build_au_repo hook
mkdir -p "$TMPD/auclone-hook/.git/hooks"
cat > "$TMPD/auclone-hook/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "refusing: attribution check failed" >&2
exit 1
HOOK
chmod +x "$TMPD/auclone-hook/.git/hooks/pre-push"
out="$(au_run apply --apply --archive-unmerged "$TMPD/auclone-hook")"; rc=$?
chk "archive hook refusal exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "archive hook refusal is FAILED with the hook's own line" "$out" \
  "FAILED archive unique-work: refusing: attribution check failed"
chk "archive hook refusal kept the branch locally" "$(au_local hook unique-work; echo $?)"
chk "archive hook refusal pushed no archive ref" \
  "$(au_has hook "archive/unique-work-${AU_DATE}" && echo 1 || echo 0)"
chk_has "archive hook refusal still ran the rest of apply" "$out" "-- pull:"

echo "--- an existing archive ref refuses the push without force, without deleting the branch"
build_au_repo dupe
git -C "$TMPD/auclone-dupe" push -q origin "unique-work:refs/heads/archive/unique-work-${AU_DATE}"
out="$(au_run apply --apply --archive-unmerged "$TMPD/auclone-dupe")"; rc=$?
chk "archive dupe-ref exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "archive dupe-ref is FAILED naming the existing ref" "$out" \
  "FAILED archive unique-work: origin archive/unique-work-${AU_DATE} already exists"
chk "archive dupe-ref kept the branch locally" "$(au_local dupe unique-work; echo $?)"

echo "--- never under --own: the whole sweep is scoped away, not just narrowed"
build_au_repo own
out="$(au_run apply --archive-unmerged --own "$TMPD/no-such-wt" "$TMPD/auclone-own")"; rc=$?
chk "archive --own exits 0" "$rc"
chk_has "archive --own is skipped by name" "$out" \
  "SKIP archive sweep: --own scopes cleanup to the named worktrees"
chk_no "archive --own never previews a branch" "$out" "WOULD archive"

echo "--- the flag off: apply's report carries no archive-unmerged section at all"
build_au_repo off
out="$(au_run apply "$TMPD/auclone-off")"
chk_no "archive-unmerged section is absent without the flag" "$out" "archive unmerged"

echo "=== absorbed proof: a branch whose content already sits on origin/<default> ==="
# A subagent commits on its own branch; the lead re-commits the same change under its own PR,
# so the branch has new-hash commits, no PR of its own, and no ancestry or gh proof. Every path
# it changed being byte-identical on origin/main is the proof. A partial landing or a later
# edit on main is not.
ABW="$TMPD/ab-work"; mkdir -p "$ABW"; git -C "$ABW" init -q -b main; gitc "$ABW"
printf 'base\n' > "$ABW/f.txt"; printf 'x\n' > "$ABW/g.txt"
git -C "$ABW" add -A; git -C "$ABW" commit -qm base
for b in absorbed partial conflicting; do git -C "$ABW" branch "$b"; done
git -C "$ABW" checkout -q absorbed
printf 'agent line\n' > "$ABW/new.txt"; git -C "$ABW" add -A; git -C "$ABW" commit -qm "agent: new.txt"
git -C "$ABW" checkout -q partial
printf 'landed\n' > "$ABW/p1.txt"; printf 'never landed\n' > "$ABW/p2.txt"
git -C "$ABW" add -A; git -C "$ABW" commit -qm "agent: p1 and p2"
git -C "$ABW" checkout -q conflicting
printf 'agent version\n' > "$ABW/c.txt"; git -C "$ABW" add -A; git -C "$ABW" commit -qm "agent: c.txt"
git -C "$ABW" checkout -q main
# The lead's own commits: new.txt and p1.txt re-committed, c.txt landed then edited further,
# plus an unrelated later change so origin/main is not just the branch tips.
printf 'agent line\n' > "$ABW/new.txt"; printf 'landed\n' > "$ABW/p1.txt"
printf 'agent version\n' > "$ABW/c.txt"
git -C "$ABW" add -A; git -C "$ABW" commit -qm "lead: land the agents' work"
printf 'lead edit\n' > "$ABW/c.txt"; printf 'y\n' > "$ABW/g.txt"
git -C "$ABW" add -A; git -C "$ABW" commit -qm "lead: later edits"
git clone -q --bare "$ABW" "$TMPD/ab-bare"
AB="$TMPD/ab-clone"; git clone -q "$TMPD/ab-bare" "$AB"; gitc "$AB"
for b in absorbed partial conflicting; do git -C "$AB" branch -q "$b" "origin/$b"; done
git -C "$AB" worktree add -q "$TMPD/ab-wt" absorbed

out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$AB" 2>&1)"
chk_has "absorbed: scan names it safe without gh" "$out" \
  "absorbed  [ABSORBED: content already on origin/main, safe to -D]"
chk_has "absorbed: a partial landing is left" "$out" "partial  [NOT merged / unknown: LEAVE]"
chk_has "absorbed: a branch main edited since is left" "$out" "conflicting  [NOT merged / unknown: LEAVE]"

out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --worktrees "$AB" 2>&1)"
chk_has "absorbed: dry run would remove the worktree" "$out" \
  "WOULD remove worktree $TMPD_P/ab-wt [absorbed, unlocked] and delete absorbed (content already on origin/main)"

out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply --worktrees "$AB" 2>&1)"
chk "absorbed: the worktree is gone" "$([ ! -d "$TMPD/ab-wt" ]; echo $?)"
chk "absorbed: the branch is gone" \
  "$(git -C "$AB" show-ref --verify --quiet refs/heads/absorbed && echo 1 || echo 0)"
chk "absorbed: the partial branch stays" \
  "$(git -C "$AB" show-ref --verify --quiet refs/heads/partial; echo $?)"
chk "absorbed: the conflicting branch stays" \
  "$(git -C "$AB" show-ref --verify --quiet refs/heads/conflicting; echo $?)"

# The branch sweep holds the same proof: a bare absorbed branch, no worktree, is deleted.
git -C "$AB" branch -q absorbed2 "origin/absorbed"
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply "$AB" 2>&1)"
chk_has "absorbed: the branch sweep names the proof" "$out" \
  "delete absorbed2 (content already on origin/main)"
chk "absorbed: the branch sweep deleted it" \
  "$(git -C "$AB" show-ref --verify --quiet refs/heads/absorbed2 && echo 1 || echo 0)"

echo "--- absorbed: merge drivers, a later edit, and a shadowing tag never fake the proof"
# Each shape a merge-based check got wrong in review. The proof compares trees, so no
# .gitattributes driver runs and no branch-only content can read as landed.
ADW="$TMPD/ad-work"; mkdir -p "$ADW"; git -C "$ADW" init -q -b main; gitc "$ADW"
printf 'o.txt merge=keepours\nu.txt merge=union\n' > "$ADW/.gitattributes"
printf 'one\n' > "$ADW/o.txt"; printf 'a\nb\nc\n' > "$ADW/u.txt"
printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > "$ADW/e.txt"
git -C "$ADW" add -A; git -C "$ADW" commit -qm base
for b in driver uniondel lateredit shadowed; do git -C "$ADW" branch "$b"; done
git -C "$ADW" checkout -q driver
printf 'one\nAGENT ONLY\n' > "$ADW/o.txt"; git -C "$ADW" commit -qam "agent: o.txt"
git -C "$ADW" checkout -q uniondel
printf 'a\nc\n' > "$ADW/u.txt"; git -C "$ADW" commit -qam "agent: drop b"
git -C "$ADW" checkout -q lateredit
printf 'l1 agent\nl2\nl3\nl4\nl5\nl6\n' > "$ADW/e.txt"; git -C "$ADW" commit -qam "agent: e.txt"
git -C "$ADW" checkout -q shadowed
printf 'never landed\n' > "$ADW/s.txt"; git -C "$ADW" add -A; git -C "$ADW" commit -qm "agent: s.txt"
git -C "$ADW" checkout -q main
printf 'one\nmain line\n' > "$ADW/o.txt"; printf 'a\nB\nc\n' > "$ADW/u.txt"
printf 'l1 agent\nl2\nl3\nl4\nl5\nl6 main\n' > "$ADW/e.txt"
git -C "$ADW" commit -qam "main: edits"
git -C "$ADW" tag shadowed main
git clone -q --bare "$ADW" "$TMPD/ad-bare"
AD="$TMPD/ad-clone"; git clone -q "$TMPD/ad-bare" "$AD"; gitc "$AD"
git -C "$AD" config merge.keepours.driver true
for b in driver uniondel lateredit shadowed; do git -C "$AD" branch -q "$b" "origin/$b"; done
git -C "$AD" worktree add -q "$TMPD/ad-wt-shadowed" shadowed

out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$AD" 2>&1)"
for b in driver uniondel lateredit; do
  chk_has "absorbed: $b stays LEAVE" "$out" "$b  [NOT merged / unknown: LEAVE]"
done
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --worktrees "$AD" 2>&1)"
chk_no "absorbed: a tag named like the branch does not prove it" "$out" \
  "and delete shadowed (content already on origin/main)"
chk_no "absorbed: nor does the ancestor proof take the tag for the branch" "$out" \
  "and delete shadowed (ancestor of origin/main)"
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply --worktrees "$AD" 2>&1)"
chk "absorbed: the tag-shadowed worktree survives apply" "$([ -d "$TMPD/ad-wt-shadowed" ]; echo $?)"
chk "absorbed: the tag-shadowed branch survives apply" \
  "$(git -C "$AD" show-ref --verify --quiet refs/heads/shadowed; echo $?)"
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply "$AD" 2>&1)"
for b in driver uniondel lateredit; do
  chk "absorbed: the $b branch survives apply" \
    "$(git -C "$AD" show-ref --verify --quiet "refs/heads/$b"; echo $?)"
done

echo "--- absorbed: a long diff or a grep error never reads as absorbed"
# Round-2 review: `! printf | grep -q` under pipefail returned 141 when grep matched early and
# its writer died on SIGPIPE, so an unlanded branch read as absorbed once main's diff passed
# about 64 KB. A non-UTF-8 path made BSD grep exit 2, which the negation also accepted.
ALW="$TMPD/al-work"; mkdir -p "$ALW/many"; git -C "$ALW" init -q -b main; gitc "$ALW"
printf 'base\n' > "$ALW/base.txt"; git -C "$ALW" add -A; git -C "$ALW" commit -qm base
git -C "$ALW" branch longdiff; git -C "$ALW" branch badbytes
git -C "$ALW" checkout -q longdiff
printf 'AGENT ONLY WORK\n' > "$ALW/a.txt"; git -C "$ALW" add -A; git -C "$ALW" commit -qm "agent: a.txt"
git -C "$ALW" checkout -q badbytes
# APFS refuses a non-UTF-8 file name, so the path goes in through the index, never the disk.
ALBLOB="$(printf 'agent\n' | git -C "$ALW" hash-object -w --stdin)"
git -C "$ALW" update-index --add --cacheinfo "100644,${ALBLOB},$(printf 'caf\351.txt')"
git -C "$ALW" commit -qm "agent: latin-1 name"
git -C "$ALW" reset -q --hard
git -C "$ALW" checkout -q main
# 3000 paths of about 40 bytes each puts main's diff well past a 64 KB pipe buffer, and the
# branch's a.txt sorts ahead of all of them.
i=0; while [ "$i" -lt 3000 ]; do
  printf 'x\n' > "$ALW/many/unrelated-file-number-$(printf '%05d' "$i").txt"; i=$((i + 1))
done
git -C "$ALW" add -A; git -C "$ALW" commit -qm "main: many unrelated files"
git clone -q --bare "$ALW" "$TMPD/al-bare"
AL="$TMPD/al-clone"; git clone -q "$TMPD/al-bare" "$AL"; gitc "$AL"
git -C "$AL" config core.quotePath false
for b in longdiff badbytes; do git -C "$AL" branch -q "$b" "origin/$b"; done
chk "absorbed: the latin-1 fixture has its own commit" \
  "$([ "$(git -C "$AL" rev-list --count origin/main..badbytes)" -eq 1 ]; echo $?)"
chk "absorbed: main's diff is past 64 KB" \
  "$([ "$(git -C "$AL" diff --name-only longdiff origin/main | wc -c)" -gt 65536 ]; echo $?)"

out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$AL" 2>&1)"
chk_has "absorbed: an early match in a long diff stays LEAVE" "$out" "longdiff  [NOT merged / unknown: LEAVE]"
chk_has "absorbed: a non-UTF-8 path stays LEAVE" "$out" "badbytes  [NOT merged / unknown: LEAVE]"
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply "$AL" 2>&1)"
for b in longdiff badbytes; do
  chk "absorbed: the $b branch survives apply" \
    "$(git -C "$AL" show-ref --verify --quiet "refs/heads/$b"; echo $?)"
done

echo "--- absorbed: diff.relative, and a landed non-UTF-8 path"
# Round 3: diff.relative with a subdirectory <repo> dropped the unlanded top-level path from
# both lists. And a Latin-1 path that DID land must still read absorbed under LC_ALL=C.
ARW="$TMPD/ar-work"; mkdir -p "$ARW/sub"; git -C "$ARW" init -q -b main; gitc "$ARW"
printf 'base\n' > "$ARW/sub/base"; git -C "$ARW" add -A; git -C "$ARW" commit -qm base
git -C "$ARW" branch relhide; git -C "$ARW" branch latinok
git -C "$ARW" checkout -q relhide
printf 'landed\n' > "$ARW/sub/a"; printf 'never landed\n' > "$ARW/top"
git -C "$ARW" add -A; git -C "$ARW" commit -qm "agent: sub/a and top"
git -C "$ARW" checkout -q latinok
ARBLOB="$(printf 'latin\n' | git -C "$ARW" hash-object -w --stdin)"
git -C "$ARW" update-index --add --cacheinfo "100644,${ARBLOB},$(printf 'caf\351.txt')"
git -C "$ARW" commit -qm "agent: latin-1 name"; git -C "$ARW" reset -q --hard
git -C "$ARW" checkout -q main
printf 'landed\n' > "$ARW/sub/a"; git -C "$ARW" add -A
git -C "$ARW" update-index --add --cacheinfo "100644,${ARBLOB},$(printf 'caf\351.txt')"
git -C "$ARW" commit -qm "main: land sub/a and the latin-1 file"; git -C "$ARW" reset -q --hard
git clone -q --bare "$ARW" "$TMPD/ar-bare"
AR="$TMPD/ar-clone"; git clone -q "$TMPD/ar-bare" "$AR"; gitc "$AR"
git -C "$AR" config diff.relative true; git -C "$AR" config core.quotePath false
for b in relhide latinok; do git -C "$AR" branch -q "$b" "origin/$b"; done
out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$AR/sub" 2>&1)"
chk_has "absorbed: diff.relative from a subdirectory stays LEAVE" "$out" \
  "relhide  [NOT merged / unknown: LEAVE]"
chk_has "absorbed: a landed non-UTF-8 path reads absorbed" "$out" \
  "latinok  [ABSORBED: content already on origin/main, safe to -D]"
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply "$AR/sub" 2>&1)"
chk "absorbed: the relhide branch survives apply" \
  "$(git -C "$AR" show-ref --verify --quiet refs/heads/relhide; echo $?)"

echo "--- absorbed: no free descriptor never reads as absorbed"
# Round 4: with a <(...) operand, a process that could not make a pipe lost the operand
# entirely, grep read stdin, found nothing, and exited 1: absorbed. The comparison is pure
# bash now. Source the real helper and starve it of descriptors, for both bash versions.
ABS_FN="$(sed -n '/^_absorbed() {/,/^}/p' "$KIT_DIR/lib/wrap/wrap.sh")"
# The limit where git still runs but a pipe cannot be made differs per bash version, so sweep
# it: every limit must fail closed.
for sh in /bin/bash bash; do
  opened=""
  for n in 4 5 6 7 8 9 10 11 12; do
    "$sh" -c "$ABS_FN"'
      ( ulimit -n "$2"; _absorbed "$1" main refs/heads/longdiff </dev/null )' _ "$AL" "$n" \
      2>/dev/null && opened="$opened $n"
  done
  chk "absorbed: descriptor exhaustion stays LEAVE under $sh (opened at:${opened:- none})" \
    "$([ -z "$opened" ]; echo $?)"
done

echo "--- absorbed: a backslash before an invalid byte, in a UTF-8 locale"
# Round 5: with core.quotePath=false, bash 5 in a UTF-8 locale cut the changed list at a
# backslash followed by an invalid byte, so the unlanded zz below was never compared. bash
# takes an ASCII fast path unless the string also holds a valid multibyte character, hence aé.
AQW="$TMPD/aq-work"; mkdir -p "$AQW"; git -C "$AQW" init -q -b main; gitc "$AQW"
printf 'base\n' > "$AQW/base"; git -C "$AQW" add -A; git -C "$AQW" commit -qm base
git -C "$AQW" branch quotecut
AQBLOB="$(printf 'q\n' | git -C "$AQW" hash-object -w --stdin)"
AQPATH="$(printf 'b\\\351\\x')"; AQUTF="$(printf 'a\303\251')"
# Index-only commits: APFS cannot hold the odd name on disk, so a checkout, reset --hard, or
# add -A would silently stage its deletion and the fixture would stop testing anything.
aq_commit() { # aq_commit <branch> <message> <path>...
  local br="$1" msg="$2" tree commit; shift 2
  GIT_INDEX_FILE="$TMPD/aq-index" git -C "$AQW" read-tree "$br"
  for f in "$@"; do
    GIT_INDEX_FILE="$TMPD/aq-index" git -C "$AQW" update-index --add --cacheinfo "100644,${AQBLOB},${f}"
  done
  tree="$(GIT_INDEX_FILE="$TMPD/aq-index" git -C "$AQW" write-tree)"
  commit="$(git -C "$AQW" commit-tree "$tree" -p "$br" -m "$msg")"
  git -C "$AQW" update-ref "refs/heads/$br" "$commit"
}
aq_commit quotecut "agent: odd paths and zz" "$AQUTF" "$AQPATH" zz
aq_commit main "main: land the odd paths" "$AQUTF" "$AQPATH"
git clone -q --bare "$AQW" "$TMPD/aq-bare"
AQ="$TMPD/aq-clone"; git clone -q --no-checkout "$TMPD/aq-bare" "$AQ"; gitc "$AQ"
git -C "$AQ" config core.quotePath false; git -C "$AQ" branch -q quotecut origin/quotecut
chk "absorbed: the branch tip holds both odd paths and zz" \
  "$([ "$(git -C "$AQ" -c core.quotePath=true ls-tree --name-only origin/quotecut | grep -cE '351|zz|303')" -eq 3 ]; echo $?)"
out="$(LC_ALL=en_US.UTF-8 GH_STUB_UNAUTH=1 "$WRAP" scan "$AQ" 2>&1)"
chk_has "absorbed: a backslash before an invalid byte stays LEAVE" "$out" \
  "quotecut  [NOT merged / unknown: LEAVE]"

echo "=== pinned refs: a colliding tag, branch, or leaked GIT_DIR never proves a branch merged ==="
# Each proof and tip read names refs/heads/<b> and refs/remotes/origin/<def>. A bare name
# resolves a tag or local branch first, so each fixture below once deleted unlanded work.
# pin_fixture <name> -- a clone whose `agent` (worktree <name>-wt) and `agent2` (no worktree)
# carry one commit origin/main lacks. Prints the clone path.
pin_fixture() {
  local w="$TMPD/$1-work" c="$TMPD/$1-clone"
  mkdir -p "$w"; git -C "$w" init -q -b main; gitc "$w"
  printf 'base\n' > "$w/f.txt"; git -C "$w" add -A; git -C "$w" commit -qm base
  git -C "$w" checkout -q -b agent
  printf 'never landed\n' > "$w/a.txt"; git -C "$w" add -A; git -C "$w" commit -qm "agent: a.txt"
  git -C "$w" checkout -q main
  git clone -q --bare "$w" "$TMPD/$1-bare"
  git clone -q "$TMPD/$1-bare" "$c"; gitc "$c"
  git -C "$c" branch -q agent origin/agent; git -C "$c" branch -q agent2 origin/agent
  git -C "$c" worktree add -q "$TMPD/$1-wt" agent
  printf '%s' "$c"
}
pin_kept() { # pin_kept <label> <clone> <worktree>
  chk "$1: the worktree survives apply" "$([ -d "$3" ]; echo $?)"
  chk "$1: agent survives apply" "$(git -C "$2" show-ref --verify --quiet refs/heads/agent; echo $?)"
  chk "$1: agent2 survives apply" "$(git -C "$2" show-ref --verify --quiet refs/heads/agent2; echo $?)"
}

echo "--- pinned refs: a tag named origin/main at the unlanded branch"
PT="$(pin_fixture pt)"
git -C "$PT" tag origin/main agent
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply --worktrees "$PT" 2>&1)"
chk_no "pinned tag: no ancestor proof from the tag" "$out" "(ancestor of origin/main"
pin_kept "pinned tag" "$PT" "$TMPD/pt-wt"

echo "--- pinned refs: a local branch named origin/main at the unlanded branch"
PB="$(pin_fixture pb)"
git -C "$PB" branch -q origin/main agent
out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$PB" 2>&1)"
chk_has "pinned branch: scan names the branch in full, never heads/" "$out" \
  "     origin/main  [NOT merged / unknown: LEAVE]"
chk_no "pinned branch: scan does not SAFE-d agent off the local branch" "$out" "agent  [SAFE-d"
out="$(GH_STUB_UNAUTH=1 "$WRAP" apply --apply --worktrees "$PB" 2>&1)"
chk_no "pinned branch: no ancestor proof from the local branch" "$out" "(ancestor of origin/main"
pin_kept "pinned branch" "$PB" "$TMPD/pb-wt"
chk "pinned branch: the origin/main branch itself survives" \
  "$(git -C "$PB" show-ref --verify --quiet refs/heads/origin/main; echo $?)"

echo "--- pinned refs: a tag at the merged PR head shadows a branch with an extra commit"
# gh reports agent merged at its first commit, the tag named agent points there, and the branch
# carries one more commit. The squash proof must read refs/heads/agent, and the scan snapshot
# must name it agent (not heads/agent) so the tip-moved guard still matches it.
PS="$(pin_fixture ps)"
git -C "$PS" tag agent agent
printf 'after the merge\n' > "$TMPD/ps-wt/b.txt"
git -C "$TMPD/ps-wt" add -A; git -C "$TMPD/ps-wt" commit -qm "agent: unpushed b.txt"
PS_MERGED="[{\"headRefOid\":\"$(git -C "$PS" rev-parse refs/tags/agent)\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]"
out="$(GH_STUB_MERGED_agent="$PS_MERGED" "$WRAP" scan "$PS" 2>&1)"
chk_has "pinned squash: scan leaves agent" "$out" "     agent  [NOT merged / unknown: LEAVE]"
chk_no "pinned squash: scan never names the branch heads/agent" "$out" "     heads/agent  ["
out="$(GH_STUB_MERGED_agent="$PS_MERGED" "$WRAP" apply --apply --worktrees "$PS" 2>&1)"
chk_no "pinned squash: no squash proof from the tag" "$out" "squash-merged per gh"
chk "pinned squash: the worktree survives apply" "$([ -d "$TMPD/ps-wt" ]; echo $?)"
chk "pinned squash: agent survives apply" \
  "$(git -C "$PS" show-ref --verify --quiet refs/heads/agent; echo $?)"

echo "--- pinned refs: a leaked GIT_DIR pointing at another repo"
# A git hook exports its own repo's GIT_DIR. Wrap must still act on the repo it was given: the
# other repo's merged agent2 stays, and the target's unlanded worktree is reported as its own.
PG="$(pin_fixture pg)"
PO="$(pin_fixture po)"
git -C "$TMPD/po-work" merge -q --ff-only agent; git -C "$TMPD/po-work" push -q "$TMPD/po-bare" main
git -C "$PO" fetch -q
out="$(GIT_DIR="$PO/.git" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --worktrees "$PG" 2>&1)"
chk_has "pinned GIT_DIR: apply reads the target's worktree" "$out" \
  "SKIP $TMPD_P/pg-wt: agent is not proven merged into main (leave it)"
pin_kept "pinned GIT_DIR" "$PG" "$TMPD/pg-wt"
chk "pinned GIT_DIR: the other repo's merged agent2 survives" \
  "$(git -C "$PO" show-ref --verify --quiet refs/heads/agent2; echo $?)"

echo "--- pinned refs: a leaked GIT_COMMON_DIR pointing at another repo"
# Not in the old hand-listed unset; git's --local-env-vars list covers it. The common dir holds
# refs and worktrees, so a leaked one points the sweep at the other repo's merged agent.
PC="$(pin_fixture pc)"
PD="$(pin_fixture pd)"
git -C "$TMPD/pd-work" merge -q --ff-only agent; git -C "$TMPD/pd-work" push -q "$TMPD/pd-bare" main
git -C "$PD" fetch -q
out="$(GIT_COMMON_DIR="$PD/.git" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --worktrees "$PC" 2>&1)"
chk_has "pinned GIT_COMMON_DIR: apply reads the target's worktree" "$out" \
  "SKIP $TMPD_P/pc-wt: agent is not proven merged into main (leave it)"
pin_kept "pinned GIT_COMMON_DIR" "$PC" "$TMPD/pc-wt"
chk "pinned GIT_COMMON_DIR: the other repo's merged worktree survives" "$([ -d "$TMPD/pd-wt" ]; echo $?)"
chk "pinned GIT_COMMON_DIR: the other repo's merged agent survives" \
  "$(git -C "$PD" show-ref --verify --quiet refs/heads/agent; echo $?)"
chk "pinned GIT_COMMON_DIR: the other repo's merged agent2 survives" \
  "$(git -C "$PD" show-ref --verify --quiet refs/heads/agent2; echo $?)"

echo "--- pinned refs: archive-unmerged pushes the branch, never a same-named tag"
# agent2 is unmerged; a tag named agent2 points at a different unmerged commit. The archive
# ref on origin must hold agent2's own tip, and the local branch goes only after that.
PA="$(pin_fixture pa)"
printf 'other work\n' > "$TMPD/pa-wt/o.txt"
git -C "$TMPD/pa-wt" add -A; git -C "$TMPD/pa-wt" commit -qm "agent: other work"
git -C "$PA" tag agent2 agent
PA_TIP="$(git -C "$PA" rev-parse refs/heads/agent2)"
PA_TAG="$(git -C "$PA" rev-parse refs/tags/agent2)"
PA_REF="refs/heads/archive/agent2-$(date +%Y%m%d)"
git -C "$PA" config branch.agent2.remote origin; git -C "$PA" config branch.agent2.merge refs/heads/agent2
out="$(KIT_CONFIG_ROOT="$KIT_DIR" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --archive-unmerged "$PA" 2>&1)"
chk_has "pinned archive: reports the archive" "$out" "archived agent2 -> ${PA_REF#refs/heads/}"
chk "pinned archive: origin holds the branch's own tip" \
  "$([ "$(git -C "$TMPD/pa-bare" rev-parse -q --verify "$PA_REF")" = "$PA_TIP" ]; echo $?)"
chk "pinned archive: origin never holds the tag's commit" \
  "$([ "$(git -C "$TMPD/pa-bare" rev-parse -q --verify "$PA_REF")" != "$PA_TAG" ]; echo $?)"
chk "pinned archive: the local branch goes once archived" \
  "$(git -C "$PA" show-ref --verify --quiet refs/heads/agent2 && echo 1 || echo 0)"
chk "pinned archive: the tag stays" "$([ "$(git -C "$PA" rev-parse -q --verify refs/tags/agent2)" = "$PA_TAG" ]; echo $?)"
chk "pinned archive: the branch.agent2 config goes with it" \
  "$([ -z "$(git -C "$PA" config --get-regexp '^branch\.agent2\.')" ]; echo $?)"
chk "pinned archive: the worktree-held agent stays" \
  "$(git -C "$PA" show-ref --verify --quiet refs/heads/agent; echo $?)"

echo "--- pinned refs: archive-unmerged never follows a symbolic ref into a held branch"
# zalias points at the worktree-held, unmerged agent. Its own guards pass, so a delete that
# followed the symref once removed agent out from under its worktree.
SY="$(pin_fixture sy)"
SY_TIP="$(git -C "$SY" rev-parse refs/heads/agent)"
git -C "$SY" symbolic-ref refs/heads/zalias refs/heads/agent
out="$(KIT_CONFIG_ROOT="$KIT_DIR" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --archive-unmerged "$SY" 2>&1)"
chk_has "pinned symref: the alias is skipped by name" "$out" "SKIP zalias: a symbolic ref, not a branch of its own"
chk "pinned symref: the held agent keeps its tip" \
  "$([ "$(git -C "$SY" rev-parse -q --verify refs/heads/agent)" = "$SY_TIP" ]; echo $?)"
chk "pinned symref: the worktree is still on agent" \
  "$([ "$(git -C "$TMPD/sy-wt" symbolic-ref -q HEAD)" = refs/heads/agent ]; echo $?)"

echo "--- pinned refs: archive-unmerged keeps a branch checked out during the push"
# The pre-push hook adds a worktree on agent2 after the guards ran; the delete must see it.
RK="$(pin_fixture rk)"
mkdir -p "$RK/.git/hooks"
cat > "$RK/.git/hooks/pre-push" <<HOOK
#!/bin/sh
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
git -C "$RK" worktree add -q "$TMPD/rk-wt2" agent2 >/dev/null 2>&1
exit 0
HOOK
chmod +x "$RK/.git/hooks/pre-push"
RK_REF="archive/agent2-$(date +%Y%m%d)"
out="$(KIT_CONFIG_ROOT="$KIT_DIR" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --archive-unmerged "$RK" 2>&1)"
chk_has "pinned recheck: reports the branch kept" "$out" \
  "kept agent2: archived to ${RK_REF}, but it was checked out during the push"
chk "pinned recheck: agent2 survives" "$(git -C "$RK" show-ref --verify --quiet refs/heads/agent2; echo $?)"
chk "pinned recheck: the archive ref landed" \
  "$(git -C "$TMPD/rk-bare" show-ref --verify --quiet "refs/heads/${RK_REF}"; echo $?)"

echo "--- pinned refs: archive-unmerged leases the delete to the tip it read"
# The pre-push hook moves agent2 after wrap read its tip: origin holds the old tip, the local
# branch now holds new work, and the leased delete must refuse.
LM="$(pin_fixture lm)"
printf 'more\n' > "$TMPD/lm-wt/m.txt"
git -C "$TMPD/lm-wt" add -A; git -C "$TMPD/lm-wt" commit -qm "agent: more"
LM_NEW="$(git -C "$LM" rev-parse refs/heads/agent)"
mkdir -p "$LM/.git/hooks"
cat > "$LM/.git/hooks/pre-push" <<HOOK
#!/bin/sh
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
git -C "$LM" update-ref refs/heads/agent2 "$LM_NEW"
exit 0
HOOK
chmod +x "$LM/.git/hooks/pre-push"
out="$(KIT_CONFIG_ROOT="$KIT_DIR" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --archive-unmerged "$LM" 2>&1)"; rc=$?
chk "pinned lease: a moved branch exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pinned lease: the refused delete is FAILED" "$out" \
  "FAILED archive agent2: pushed to archive/agent2-$(date +%Y%m%d) but the local branch delete refused"
chk "pinned lease: agent2 survives with its new work" \
  "$([ "$(git -C "$LM" rev-parse -q --verify refs/heads/agent2)" = "$LM_NEW" ]; echo $?)"

echo "--- pinned refs: archive-unmerged keeps the branch when origin holds another sha"
# A post-receive hook on the bare remote moves the archive ref, so origin never holds the tip.
RM="$(pin_fixture rm)"
mkdir -p "$TMPD/rm-bare/hooks"
cat > "$TMPD/rm-bare/hooks/post-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
  case "$ref" in refs/heads/archive/*) git update-ref "$ref" refs/heads/main ;; esac
done
HOOK
chmod +x "$TMPD/rm-bare/hooks/post-receive"
out="$(KIT_CONFIG_ROOT="$KIT_DIR" GH_STUB_UNAUTH=1 "$WRAP" apply --apply --archive-unmerged "$RM" 2>&1)"; rc=$?
chk "pinned remote lease: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pinned remote lease: FAILED names the mismatch" "$out" \
  "FAILED archive agent2: origin archive/agent2-$(date +%Y%m%d) holds"
chk "pinned remote lease: agent2 survives" "$(git -C "$RM" show-ref --verify --quiet refs/heads/agent2; echo $?)"

echo "--- pinned refs: injected GIT_CONFIG_COUNT config reaches wrap's git calls"
# mini-run and checkout-sync pass credential and insteadOf config through GIT_CONFIG_COUNT.
# origin's URL resolves only through that mapping, and agent2 is proven merged only once the
# fetch through it succeeds.
IC="$(pin_fixture ic)"
git -C "$TMPD/ic-work" merge -q --ff-only agent; git -C "$TMPD/ic-work" push -q "$TMPD/ic-bare" main
git -C "$IC" remote set-url origin "fake://ic/remote"
out="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$TMPD/ic-bare.insteadOf" GIT_CONFIG_VALUE_0="fake://ic/remote" \
  GH_STUB_UNAUTH=1 "$WRAP" apply --apply "$IC" 2>&1)"
chk_no "pinned config: the fetch through the mapping succeeds" "$out" "fetch failed"
chk_has "pinned config: agent2 is proven merged after that fetch" "$out" "delete agent2 (ancestor of origin/main)"
chk "pinned config: agent2 is gone" \
  "$(git -C "$IC" show-ref --verify --quiet refs/heads/agent2 && echo 1 || echo 0)"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-apply: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-apply: all $PASS passed"
