# wrap-start.sh -- the start verb and its carry helper; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- start

# cmd_start <repo> <branch> [--carry [<path>...]] -- the start half `land` finishes.
# Sessions repeatedly hand-run "worktree off origin/<default> with a fresh branch" when the
# main checkout is dirty or foreign; this is that step as a verb. It resolves the repo's
# default branch through the same `_default_branch` helper every other verb uses, fetches it
# quietly, and creates <repo>/.claude/worktrees/<slug> at origin/<default> on a NEW local
# branch <branch>, where <slug> is the branch name with its `type/` prefix stripped
# (gate-ledger's rid rule). The worktree path is the only stdout line, so a caller captures
# it directly; every diagnostic goes to stderr.
#
# A dirty main checkout is never a refusal: the worktree is isolated, which is
# the point of the verb. What refuses, each with its reason and before any
# write: a missing argument or a <repo> that is not a git repo or an invalid
# <branch> name (usage, 64); <branch> naming the default or a protected branch;
# <branch> already a local ref, or already pushed to origin; the worktree path
# already on disk; no default branch resolved; a failed fetch; a held
# index.lock; and a `worktree add` git itself refuses.
#
# --carry moves the main checkout's own uncommitted edits into the freshly created worktree,
# once the worktree exists exactly as it would without the flag: `_start_carry` (below) owns
# that half. A carry refusal (a foreign index.lock, or an apply conflict) never undoes the
# worktree; the worktree is the point that already landed.
cmd_start() {
  local repo="" branch="" carry=0 ncarry=0 seen_repo=0 seen_branch=0 arg
  local carry_paths
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --carry)
        carry=1; shift
        while [ $# -gt 0 ]; do
          _reject_packed start "$1" || return 64
          ncarry=$(( ncarry + 1 )); carry_paths[ncarry]="$1"; shift
        done
        ;;
      -*) echo "wrap.sh start: unknown flag '${arg}'" >&2; return 64 ;;
      *)
        _reject_packed start "$arg" || return 64
        if [ "$seen_repo" = 0 ]; then repo="$arg"; seen_repo=1
        elif [ "$seen_branch" = 0 ]; then branch="$arg"; seen_branch=1
        else echo "wrap.sh start: unexpected argument '${arg}'" >&2; return 64
        fi
        shift ;;
    esac
  done
  [ "$seen_repo" = 1 ] && [ "$seen_branch" = 1 ] \
    || { echo "usage: wrap.sh start <repo> <branch> [--carry [<path>...]]" >&2; return 64; }
  _is_repo "$repo" || { echo "wrap.sh start: ${repo} is not a git repo" >&2; return 64; }
  # git records a worktree fully resolved, so the printed path resolves the same way.
  repo="$(cd "$repo" 2>/dev/null && pwd -P)" \
    || { echo "wrap.sh start: ${repo} does not resolve" >&2; return 64; }
  git -C "$repo" check-ref-format --branch "$branch" >/dev/null 2>&1 \
    || { echo "wrap.sh start: '${branch}' is not a valid branch name" >&2; return 64; }

  local def
  def="$(_default_branch "$repo")" \
    || { echo "wrap.sh start: no default branch resolved for ${repo}" >&2; return 1; }
  case "$branch" in
    "$def"|main|master)
      echo "wrap.sh start: ${branch} is the default or a protected branch name" >&2
      return 1 ;;
  esac
  if _ref_exists "$repo" "refs/heads/${branch}"; then
    echo "wrap.sh start: branch ${branch} already exists in ${repo}" >&2; return 1
  fi

  local slug wt
  slug="${branch##*/}"
  wt="${repo}/.claude/worktrees/${slug}"
  [ -e "$wt" ] && { echo "wrap.sh start: ${wt} already exists" >&2; return 1; }

  git -C "$repo" fetch -q origin "$def" 2>/dev/null \
    || { echo "wrap.sh start: fetch origin ${def} failed" >&2; return 1; }
  # `worktree add -b` never sees the remote, so the same-name-on-origin check runs
  # here, live (ls-remote) plus the tracking ref for an unreachable remote's
  # already-known state. A local branch created anyway would collide at push.
  if _ref_exists "$repo" "refs/remotes/origin/${branch}" \
     || git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "wrap.sh start: branch ${branch} already exists on origin" >&2
    return 1
  fi
  _write_guard "$repo" \
    || { echo "wrap.sh start: index.lock held by another writer" >&2; return 1; }
  # A stale admin entry for a path deleted out-of-band wedges `worktree add`;
  # pruning first keeps that state a non-event.
  git -C "$repo" worktree prune 2>/dev/null
  mkdir -p "${repo}/.claude/worktrees" 2>/dev/null
  git -C "$repo" worktree add -b "$branch" "$wt" "origin/${def}" >/dev/null 2>&1 \
    || { echo "wrap.sh start: git worktree add refused ${wt} (${branch} at origin/${def})" >&2; return 1; }
  printf '%s\n' "$wt"
  [ "$carry" = 1 ] || return 0
  if [ "$ncarry" -gt 0 ]; then
    _start_carry "$repo" "$wt" "$branch" "${carry_paths[@]}"
  else
    _start_carry "$repo" "$wt" "$branch"
  fi
  return $?
}

# _start_carry <repo> <wt> <branch> [<path>...] -- the --carry half. Stashes the main
# checkout's own uncommitted edits (tracked and untracked, restricted to the given paths when
# any are given, else everything) under a name unique to this run, finds that entry by its
# message (never by index: the stash stack is shared with other sessions), applies it inside
# the new worktree, and on a clean apply drops that same entry by re-finding it. A conflict
# keeps the entry and reports its identity instead of guessing which side is right. Never
# `stash pop`, never a bare `stash`, never an entry this run did not push itself.
_start_carry() {
  local repo="$1" wt="$2" branch="$3"; shift 3
  local name sha ref h s gd out

  _write_guard "$repo" \
    || { echo "wrap.sh start: index.lock held by another writer; the worktree exists at ${wt}" >&2; return 2; }

  name="wrap-start-carry ${branch} $(date +%s)-$$"
  if [ $# -gt 0 ]; then
    git -C "$repo" stash push -u -q -m "$name" -- "$@" >/dev/null 2>&1
  else
    git -C "$repo" stash push -u -q -m "$name" >/dev/null 2>&1
  fi

  sha=""
  while read -r h s; do
    case "$s" in *": ${name}") sha="$h"; break ;; esac
  done < <(git -C "$repo" stash list --format='%H %gs' 2>/dev/null)
  if [ -z "$sha" ]; then
    echo "nothing to carry" >&2
    return 0
  fi
  echo "carried: $(git -C "$repo" stash show -u --name-only "$sha" 2>/dev/null | tr '\n' ' ')" >&2

  if out="$(git -C "$wt" stash apply -q "$sha" 2>&1)"; then
    ref=""
    while read -r gd h; do
      [ "$h" = "$sha" ] && { ref="$gd"; break; }
    done < <(git -C "$repo" stash list --format='%gd %H' 2>/dev/null)
    [ -z "$ref" ] || git -C "$repo" stash drop -q "$ref" >/dev/null 2>&1
    return 0
  fi
  echo "wrap.sh start: carry apply conflicted, stash $(_short "$sha") (${name}) kept" >&2
  [ -z "$out" ] || echo "$out" >&2
  return 2
}

