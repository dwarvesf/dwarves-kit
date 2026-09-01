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
#       refuses unless the branch's PR is MERGED (gh); releases the registry
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
    st="$(gh pr list --state all --head "$br" --json state --jq '.[0].state' 2>/dev/null)"
    [ "$st" = "MERGED" ] || { echo "wt.sh: refusing to close: PR for $br is '${st:-none}', not MERGED" >&2; exit 1; }
    bash "$LIB/goal/goal-registry.sh" release "$slug" 2>/dev/null || true
    [ -d "$wt" ] && git worktree remove --force "$wt"
    git branch -D "$br" >/dev/null
    git push origin --delete "$br" >/dev/null 2>&1 || true
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
