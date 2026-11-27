#!/usr/bin/env bash
# wrap-labeled-fixture.sh <sandbox> -- build the labeled wrap-apply sandbox.
# Local bare origin only: no network, no GitHub, no push to any default branch. The
# origin's later main advance is prepared as refs/heads/next-main; a test moves main
# to it inside the bare repo when it exercises the after-fetch case.
set -euo pipefail

root="${1:?usage: wrap-labeled-fixture.sh <sandbox>}"
seed="$root/seed"
bare="$root/origin.git"
repo="$root/repo"

mkdir -p "$seed" "$root/no-git-template"
GIT_TEMPLATE_DIR="$root/no-git-template"
export GIT_TEMPLATE_DIR
git -C "$seed" init -q
git -C "$seed" config user.email t@t
git -C "$seed" config user.name t
git -C "$seed" config commit.gpgsign false
git -C "$seed" symbolic-ref HEAD refs/heads/main
echo base > "$seed/a.txt"
git -C "$seed" add a.txt
git -C "$seed" commit -qm base

commit_file() { # commit_file <repo> <path> <text> <subject>
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "$4"
}

merge_branch() { # merge_branch <branch> <file> <text>
  git -C "$seed" checkout -q -b "$1" main
  commit_file "$seed" "$2" "$3" "$1"
  git -C "$seed" checkout -q main
  git -C "$seed" merge -q --no-ff --no-edit "$1"
}

topic_branch() { # topic_branch <branch> <file> <text>
  git -C "$seed" checkout -q -b "$1" main
  commit_file "$seed" "$2" "$3" "$1"
  git -C "$seed" checkout -q main
}

# A fast-forward merge: main and the branch tip are the same commit.
git -C "$seed" checkout -q -b case-merged-ff main
commit_file "$seed" merged-ff.txt ff case-merged-ff
git -C "$seed" checkout -q main
git -C "$seed" merge -q --ff-only case-merged-ff

# A true merge commit: the branch tip is an ancestor through the second parent.
git -C "$seed" checkout -q -b case-merged-commit main
commit_file "$seed" merged-commit.txt mc case-merged-commit
git -C "$seed" checkout -q main
git -C "$seed" merge -q --no-ff --no-edit case-merged-commit

# A squash-equivalent branch: same bytes on main, different commit hash.
git -C "$seed" checkout -q -b case-squash-equiv main
commit_file "$seed" squash-equiv.txt squash case-squash-equiv
git -C "$seed" checkout -q main
commit_file "$seed" squash-equiv.txt squash "squash equivalent"

merge_branch case-merged-more merged-more.txt more
merge_branch case-merged-dirty merged-dirty.txt dirty-base
merge_branch case-merged-untracked merged-untracked.txt untracked-base
merge_branch case-live-holder live-holder.txt holder-base
topic_branch case-unmerged-gone unmerged-gone.txt unmerged
topic_branch case-pr-merged pr-merged.txt pr-head
topic_branch case-pr-closed-unmerged pr-closed.txt closed

# The after-fetch main advance is already an object in the bare origin.
git -C "$seed" checkout -q -b next-main main
commit_file "$seed" later.txt later "advance main later"
git -C "$seed" checkout -q main

git clone -q --bare "$seed" "$bare"
git clone -q "$bare" "$repo"
git -C "$repo" config user.email t@t
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false
git -C "$repo" remote set-head origin main >/dev/null 2>&1
# Detach the checkout so both protected names can be held by labeled worktrees.
git -C "$repo" checkout -q --detach origin/main

for b in \
  case-merged-ff case-merged-commit case-squash-equiv case-merged-more \
  case-merged-dirty case-merged-untracked case-live-holder case-unmerged-gone \
  case-pr-merged case-pr-closed-unmerged; do
  git -C "$repo" branch "$b" "origin/$b"
done

# Fresh cases: worktree and branch-only refs still at their creation commit, including
# creation by SHA and revision expression rather than the default ref's name.
git -C "$repo" worktree add -b case-fresh-zero "$root/wt-fresh-zero" origin/main >/dev/null 2>&1
git -C "$repo" branch case-fresh-branch origin/main
base_sha="$(git -C "$repo" rev-parse origin/main)"
git -C "$repo" worktree add -b case-fresh-sha "$root/wt-fresh-sha" "$base_sha" >/dev/null 2>&1
git -C "$repo" branch case-fresh-revision 'origin/main~0'

# Removal-proof cases and the merged-then-more case.
git -C "$repo" worktree add "$root/wt-merged-ff" case-merged-ff >/dev/null 2>&1
git -C "$repo" worktree add "$root/wt-squash-equiv" case-squash-equiv >/dev/null 2>&1
git -C "$repo" worktree add "$root/wt-merged-more" case-merged-more >/dev/null 2>&1
commit_file "$root/wt-merged-more" after-merge.txt after "one more local commit"

# Dirt and untracked data must win before any merge proof.
git -C "$repo" worktree add "$root/wt-merged-dirty" case-merged-dirty >/dev/null 2>&1
echo dirt >> "$root/wt-merged-dirty/merged-dirty.txt"
git -C "$repo" worktree add "$root/wt-merged-untracked" case-merged-untracked >/dev/null 2>&1
echo loose > "$root/wt-merged-untracked/loose.txt"

# A detached worktree, a live process holder, and the protected names.
git -C "$repo" worktree add --detach "$root/wt-detached-head" origin/main >/dev/null 2>&1
git -C "$repo" worktree add "$root/wt-live-holder" case-live-holder >/dev/null 2>&1
( cd "$root/wt-live-holder" && exec sleep 120 </dev/null >/dev/null 2>&1 ) &
echo "$!" > "$root/holder.pid"
git -C "$repo" branch master origin/main
git -C "$repo" worktree add "$root/wt-protected-main" main >/dev/null 2>&1
git -C "$repo" worktree add "$root/wt-protected-master" master >/dev/null 2>&1

# The upstream-gone branch existed when the local branch was made, then vanished on origin.
git -C "$bare" update-ref -d refs/heads/case-unmerged-gone

mkdir -p "$root/bin"
pr_tip="$(git -C "$repo" rev-parse refs/heads/case-pr-merged)"
printf '[{"headRefName":"case-pr-merged","headRefOid":"%s","baseRefName":"main","mergedAt":"2026-01-01T00:00:00Z","isCrossRepository":false}]\n' \
  "$pr_tip" > "$root/merged-pr.json"
cat > "$root/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Local canned gh: auth succeeds; only the merged-PR list for case-pr-merged has rows.
root="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  auth) exit 0 ;;
  pr)
    [ "${2:-}" = "list" ] || exit 1
    head=""; state=""
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --head) head="$2"; shift 2 ;;
        --state) state="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ "$state" = "merged" ] && { [ -z "$head" ] || [ "$head" = "case-pr-merged" ]; }; then
      cat "$root/merged-pr.json"
    else
      printf '[]\n'
    fi
    exit 0 ;;
esac
exit 1
STUB
chmod +x "$root/bin/gh"

cat > "$root/labels.tsv" <<'LABELS'
fresh-zero	keep
fresh-branch	keep
fresh-sha	keep
fresh-revision	keep
merged-ff	remove
merged-commit	remove
squash-equiv	remove
merged-more	keep
merged-dirty	keep
merged-untracked	keep
unmerged-gone	keep
detached-head	keep
live-holder	keep
protected-main	keep
protected-master	keep
pr-merged	remove
pr-closed-unmerged	keep
LABELS

printf 'labeled fixture: %s\n' "$root"
