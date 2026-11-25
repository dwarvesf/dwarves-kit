#!/bin/bash
# wt.sh -- the start/close ritual for one kit work unit in its own worktree.
# Distilled from a session that ran the same two sequences by hand seven times
# and hit the same traps each time (worktree-guard blocks compound bash, so a
# script; `gh pr create` needs a fetch + --head after a fresh push; `gh pr merge
# --delete-branch` fails inside a worktree; the main checkout's dirty BACKLOG
# blocks the post-merge pull).
#
#   wt.sh start <slug> [lane] [type] [ID-NNN]
#       fetch origin/master, `git worktree add .claude/worktrees/<slug>` on
#       <type>/<slug>, gate-ledger START (lane chosen == classified), and, when
#       an ID is given, flip its board row to claimed. Prints the worktree path.
#   wt.sh close <slug> [type]
#       refuses unless the branch tip is the head of a merged PR (lib/gate/branch-merged.sh, PR rung); releases the registry
#       claim, removes the worktree, deletes the local + remote branch, and
#       fast-forwards the main checkout (stashing a dirty BACKLOG around the
#       pull and restoring it).
#
# Never creates a branch on the shared checkout (branch-on-purpose, one
# writer per worktree). Never deletes an unmerged branch.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "wt.sh: not in a git repo" >&2; exit 2; }
# Resolve the MAIN checkout even when invoked from inside a worktree.
MAIN="$(git -C "$ROOT" worktree list --porcelain | awk 'NR==1 && $1=="worktree"{print $2}')"
cd "$MAIN" || exit 2
LIB="$MAIN/lib"
# shellcheck source=lib/gate/branch-merged.sh
source "$LIB/gate/branch-merged.sh" || { echo "wt.sh: lib/gate/branch-merged.sh missing or unreadable" >&2; exit 2; }

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }
verb="${1:-}"; shift || true
case "$verb" in
  start)
    slug="${1:?wt.sh start <slug> [lane] [type] [ID-NNN]}"; lane="${2:-normal}"; type="${3:-feat}"; id="${4:-}"
    case "$slug" in *[!a-z0-9-]*|"") echo "wt.sh: slug must be [a-z0-9-]+" >&2; exit 2;; esac
    wt="$MAIN/.claude/worktrees/$slug"; br="$type/$slug"
    [ -e "$wt" ] && { echo "wt.sh: $wt already exists" >&2; exit 1; }
    git fetch origin master -q || { echo "wt.sh: fetch failed" >&2; exit 1; }
    git worktree add "$wt" -b "$br" origin/master >/dev/null || exit 1
    ( cd "$wt" && bash "$LIB/gate/gate-ledger.sh" start "$slug" "$lane" "$lane" spec-feature spec-feature ) || true
    if [ -n "$id" ] && [ -f "$MAIN/_meta/BACKLOG.md" ]; then
      ( cd "$wt" && bash "$LIB/board/backlog.sh" set "$id" claimed ) || true
    fi
    echo "$wt"
    ;;
  close)
    slug="${1:?wt.sh close <slug> [type]}"; type="${2:-feat}"
    wt="$MAIN/.claude/worktrees/$slug"; br="$type/$slug"
    git rev-parse -q --verify "refs/heads/$br" >/dev/null || { echo "wt.sh: no local branch $br" >&2; exit 1; }
    # The shared merged check, PR rung only: a merged PR whose head is this branch's exact tip. A commit
    # the PR never carried, a PR into another base, or any gh failure leaves the branch in place.
    tip="$(git rev-parse -q --verify "refs/heads/$br")"
    verdict="$(branch_merged --need pr --tip "$tip" "$MAIN" master "$(_gh_state)" "$br")"
    case "$verdict" in
      "SAFE squash "*) ;;
      *) echo "wt.sh: refusing to close: $br is not at the head of a merged PR (${verdict:-no answer})" >&2
         # GitHub can move the PR head past the local tip (Update branch, a web suggestion) before it
         # merges; the exact tip stays the rule, so say how to bring the local branch level.
         case "$verdict" in
           "LEAVE tip "*)
             case "$wt" in
               ""|*[!A-Za-z0-9/._-]*) echo "Fix: in that worktree run git pull --ff-only, then close again" >&2 ;;
               *) echo "Fix: git -C $wt pull --ff-only, then close again" >&2 ;;
             esac ;;
         esac
         exit 1 ;;
    esac
    # gh lists the newest PR first, so one merged PR says nothing about a later one from the same head:
    # any OPEN PR that names the head keeps the branch, and so does a list that cannot be read.
    open="$(gh pr list --repo "$(_origin_url "$MAIN")" --head "$br" --state open --json number 2>/dev/null)" || open=""
    if [ "$(printf '%s' "$open" | jq -r 'if type == "array" then length else -1 end' 2>/dev/null)" != 0 ]; then
      echo "wt.sh: refusing to close: an open PR names $br, or the open-PR list could not be read" >&2; exit 1
    fi
    [ "$(git rev-parse -q --verify "refs/heads/$br")" = "$tip" ] || { echo "wt.sh: refusing to close: $br moved while it was checked" >&2; exit 1; }
    # The remote ref is read once, before anything local is removed: it must be gone already or sit at the
    # judged tip. A branch that moved on (a newer PR from the same head), or a read that failed, keeps everything.
    if ! remote="$(git ls-remote origin "refs/heads/$br" 2>/dev/null)"; then
      echo "wt.sh: refusing to close: LEAVE remote unreadable (the origin ref of $br could not be read)" >&2; exit 1
    fi
    rsha="$(printf '%s\n' "$remote" | awk -v r="refs/heads/$br" '$2 == r { print $1; exit }')"
    if [ -n "$rsha" ] && [ "$rsha" != "$tip" ]; then
      echo "wt.sh: refusing to close: LEAVE remote $rsha (origin/$br is not at the judged tip)" >&2; exit 1
    fi
    bash "$LIB/goal/goal-registry.sh" release "$slug" 2>/dev/null || true
    # -f -f: a single --force no-ops on a locked worktree, and the `git branch -D` below then
    # fails with "used by worktree", which reads as a second unrelated problem.
    [ -d "$wt" ] && git worktree remove -f -f "$wt"
    git branch -D "$br" >/dev/null
    # Leased to the tip that was judged: an origin branch that moved on (a newer PR from the same head) stays.
    git push origin --force-with-lease="refs/heads/$br:$tip" ":refs/heads/$br" >/dev/null 2>&1 || true
    git worktree prune
    # The main checkout often carries an uncommitted BACKLOG flip; park it
    # around the fast-forward so the pull never aborts on it.
    stashed=0
    if [ -n "$(git status --porcelain _meta/BACKLOG.md 2>/dev/null)" ]; then
      git stash push -q -m "wt-close-$slug" _meta/BACKLOG.md && stashed=1
    fi
    git pull --ff-only origin master -q || echo "wt.sh: pull did not fast-forward; resolve by hand" >&2
    if [ "$stashed" -eq 1 ]; then
      git stash pop -q 2>/dev/null || echo "wt.sh: BACKLOG stash did not apply cleanly (kept in stash list)" >&2
    fi
    echo "closed $br @ $(git rev-parse --short HEAD)"
    ;;
  -h|--help|help|"") usage 0 ;;
  *) echo "wt.sh: unknown verb '$verb'" >&2; usage ;;
esac
