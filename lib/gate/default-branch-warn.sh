#!/usr/bin/env bash
# default-branch-warn.sh -- one warning when a kit write verb lands a file in a checkout
# that has the repo's default branch checked out.
#
# WHY: the kit's in-checkout write verbs (`wrap log`, `wrap stage`, `board set`) write the
# file and nothing else; the caller decides whether to commit it. When the target checkout
# sits on the default branch, that commit cannot be pushed through a PR, so activity lines,
# staging blocks and board flips pile up on a local main nobody can land. One measured Air
# carried 29 such commits plus 61 merge commits before anyone noticed. The write itself is
# correct and stays; only the commit is wrong, so this warns and never refuses.
#
# Contract: `kit_warn_default_branch <written-path> [<label>]` prints at most one line to
# stderr and ALWAYS returns 0. Silent when the path lies outside a git repo, when HEAD is
# detached, when no default branch resolves, and when the checked-out branch is not the
# default one. A warning nobody can act on is worse than none, so every ambiguous case is a
# silent one.
#
# Sourced only; it has no CLI.

# Idempotent-source guard: sourcing twice is a no-op.
[ -n "${_KIT_DEFAULT_BRANCH_WARN_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_DEFAULT_BRANCH_WARN_SOURCED=1

# _kdbw_git <dir> <git-args...> -- every git read this file makes. `git -C` changes directory
# but does not clear an inherited GIT_DIR or GIT_WORK_TREE, so a verb invoked from inside a git
# hook would resolve HEAD and the remote refs against the hook's repo, not the written file's.
# Dropping both names makes `-C` the only thing that chooses the repo.
_kdbw_git() {
  local dir="$1"; shift
  env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" "$@"
}

# kit_default_branch_here <dir> -- the default branch name of the repo containing <dir>,
# empty when none resolves. origin/HEAD first, then origin/main, then origin/master. A repo
# with NO remote configured at all falls back to a local main or master, which is the shape a
# fresh `git init` checkout carries and the one case where no remote ref can answer.
#
# Deliberately separate from wrap.sh's own `_default_branch`, which four merge gates depend
# on and which has no local-branch fallback: widening that one would change what those gates
# do on a remoteless repo, and this warning is not worth that risk.
kit_default_branch_here() {
  local dir="$1" ref name
  ref="$(_kdbw_git "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)" || ref=""
  if [ -n "$ref" ]; then
    name="${ref#refs/remotes/origin/}"
    if [ "$name" != "$ref" ] \
       && _kdbw_git "$dir" show-ref --verify --quiet "refs/remotes/origin/$name" 2>/dev/null; then
      printf '%s' "$name"
      return 0
    fi
  fi
  for name in main master; do
    if _kdbw_git "$dir" show-ref --verify --quiet "refs/remotes/origin/$name" 2>/dev/null; then
      printf '%s' "$name"
      return 0
    fi
  done
  if [ -n "$(_kdbw_git "$dir" remote 2>/dev/null)" ]; then
    return 0
  fi
  for name in main master; do
    if _kdbw_git "$dir" show-ref --verify --quiet "refs/heads/$name" 2>/dev/null; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 0
}

# kit_warn_default_branch <written-path> [<label>]
kit_warn_default_branch() {
  local path="${1:-}" label="${2:-kit}" dir branch def
  [ -n "$path" ] || return 0
  dir="$(dirname -- "$path")"
  [ -d "$dir" ] || return 0
  branch="$(_kdbw_git "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" || branch=""
  [ -n "$branch" ] || return 0
  def="$(kit_default_branch_here "$dir")"
  [ -n "$def" ] && [ "$branch" = "$def" ] || return 0
  echo "${label}: wrote $(basename -- "$path") on the default branch (${branch}); do not commit it here, leave it for the next feature PR or move it to a branch" >&2
  return 0
}
