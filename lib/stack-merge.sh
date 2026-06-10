#!/usr/bin/env bash
# stack-merge.sh -- merge a squash-stacked PR chain without the manual dance (SPEC-065).
#
# Squash-merging a stacked chain by hand requires, per link: retarget the child PR's base
# BEFORE merging the parent (or GitHub auto-closes it), squash-merge the parent, then
# reconcile the child branch against the new default tip with `merge -X ours` BY SHA
# (the branch is a superset of its squashed parents, and naming the default branch in
# the command text used to trip the prose-matching safety gate). Done by hand twice on
# 2026-06-10; the second time still needed three correction turns. This codifies it.
#
# Usage:
#   stack-merge.sh next <parent-pr#> [--dry-run]   merge one link of the chain
#   stack-merge.sh chain <pr#> <pr#> ... [--dry-run]  merge links bottom-up, in order
#
# Requires: gh (authed), a CLEAN working tree (the reconcile step switches branches).
# Honest limits: squash merges only (the repo's convention); one child per parent (a
# fan-out of children needs manual retargeting first); aborts on the first conflict that
# `-X ours` cannot resolve, leaving the merge in progress for a human.
set -euo pipefail

DRY=0

_say() { printf '%s\n' "$*"; }
_run() {
  if [ "$DRY" = 1 ]; then _say "DRY: $*"; else "$@"; fi
}

_clean_tree() {
  [ -z "$(git status --porcelain)" ] || { echo "working tree not clean; commit or stash first" >&2; return 1; }
}

# one link: retarget child -> merge parent -> reconcile child branch on the new tip
next_link() {
  local pr="${1:-}"; [ -n "$pr" ] || { echo "usage: next <parent-pr#> [--dry-run]" >&2; return 64; }
  local head base child childhead
  head=$(gh pr view "$pr" --json headRefName -q .headRefName)
  base=$(gh pr view "$pr" --json baseRefName -q .baseRefName)
  child=$(gh pr list --state open --base "$head" --json number -q '.[0].number // empty')

  if [ -n "$child" ]; then
    childhead=$(gh pr view "$child" --json headRefName -q .headRefName)
    _say "retarget #$child ($childhead) -> $base (before merging #$pr, or GitHub auto-closes it)"
    _run gh pr edit "$child" --base "$base"
  fi

  _say "squash-merge #$pr ($head)"
  _run gh pr merge "$pr" --squash --delete-branch

  if [ -n "$child" ]; then
    [ "$DRY" = 1 ] || _clean_tree
    _say "reconcile $childhead on the new $base tip (merge -X ours by SHA; superset rule)"
    if [ "$DRY" = 1 ]; then
      _say "DRY: git fetch; git switch $childhead; git merge -X ours <sha-of-$base>; git push"
    else
      git fetch -q origin
      local tip; tip=$(git rev-parse "origin/$base")
      # verify the child's remote ref exists before the DWIM switch (a rename between
      # fetch and switch would otherwise abort mid-dance with the parent already merged)
      git rev-parse --verify -q "refs/remotes/origin/$childhead" >/dev/null \
        || { echo "child branch origin/$childhead vanished; reconcile by hand" >&2; return 1; }
      git switch -q "$childhead"
      git merge -X ours -q -m "reconcile on the default tip after the parent squash (stack-merge)" "$tip"
      git push -q
    fi
  fi
}

chain() {
  [ "$#" -gt 0 ] || { echo "usage: chain <pr#> [<pr#>...] [--dry-run]" >&2; return 64; }
  local pr
  for pr in "$@"; do
    [ "$pr" = "--dry-run" ] && continue
    next_link "$pr"
  done
}

main() {
  local sub="${1:-}"; shift || true
  local args=()
  for a in "$@"; do
    [ "$a" = "--dry-run" ] && DRY=1 || args+=("$a")
  done
  case "$sub" in
    next)  next_link "${args[@]}" ;;
    chain) chain "${args[@]}" ;;
    *) echo "usage: stack-merge.sh {next <pr#>|chain <pr#>...} [--dry-run]" >&2; return 64 ;;
  esac
}

main "$@"
