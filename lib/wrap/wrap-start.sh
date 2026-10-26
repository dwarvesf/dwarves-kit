# wrap-start.sh -- the start verb and its carry helper; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- start

# cmd_start <repo> <branch> [--pick <branch>]... [--carry [<path>...]] -- the start half `land` finishes.
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
#
# --pick <branch> (repeatable) folds a worker branch into the new worktree: for each one, in
# argument order, `_start_pick` cherry-picks the commits the branch carries past its merge base
# with origin/<default>. Picks run BEFORE --carry whatever the flag order on the command line:
# a cherry-pick onto a tree already holding carried edits is unsafe, while carrying onto the
# picked, committed tree is safe (a carry that collides with a picked file keeps its stash).
# A pick refusal or conflict skips the carry and leaves the main checkout's edits untouched.
# Like a carry refusal, a pick refusal never undoes the worktree and exits 2.
cmd_start() {
  local repo="" branch="" carry=0 ncarry=0 seen_repo=0 seen_branch=0 arg
  local carry_paths npick=0 pick_branches
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --carry)
        carry=1; shift
        while [ $# -gt 0 ] && [ "$1" != "--pick" ]; do
          _reject_packed start "$1" || return 64
          ncarry=$(( ncarry + 1 )); carry_paths[ncarry]="$1"; shift
        done
        ;;
      --pick)
        [ $# -ge 2 ] && case "$2" in -*) false ;; esac \
          || { echo "wrap.sh start: --pick needs a branch name" >&2; return 64; }
        _reject_packed start "$2" || return 64
        npick=$(( npick + 1 )); pick_branches[npick]="$2"; shift 2
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
    || { echo "usage: wrap.sh start <repo> <branch> [--pick <branch>]... [--carry [<path>...]]" >&2; return 64; }
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
  if [ "$npick" -gt 0 ]; then
    _start_pick "$repo" "$wt" "$def" "${pick_branches[@]}" || return $?
  fi
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
    # The new worktree lives in <repo>/.claude/worktrees. A gitignore normally hides it. Without
    # one (GIT_CONFIG_GLOBAL=/dev/null, a fresh account) `-u` takes it as dirt, so the pathspec
    # leaves it out; an ignored path in a pathspec makes git refuse, so only then.
    if git -C "$repo" check-ignore -q "$wt" 2>/dev/null; then
      git -C "$repo" stash push -u -q -m "$name" >/dev/null 2>&1
    else
      git -C "$repo" stash push -u -q -m "$name" -- . ':(exclude).claude/worktrees' >/dev/null 2>&1
    fi
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


# _start_pick <repo> <wt> <default> <branch>... -- the --pick half. Resolves every branch first
# (local ref, then origin's tracking ref, then a live fetch of that one branch), so a missing
# one refuses by name before any commit is picked. Then, per branch in argument order, it
# cherry-picks one at a time the non-merge commits between `merge-base origin/<default>
# <branch>` and the branch tip, oldest first. A branch with none prints a note and continues.
# A conflict is never resolved: the pick is aborted, the files and the commits already picked
# are named, the worktree keeps its earlier picks, and the verb exits 2 like a carry refusal.
# A commit that turns out empty against the new base (its change is already on origin) is
# skipped, not a conflict. stdout stays clean: the caller captured the path already.
_start_pick() {
  local repo="$1" wt="$2" def="$3"; shift 3
  local b ref tip base c n files done_list="" i
  local refs=()

  for b in "$@"; do
    ref=""
    if _ref_exists "$repo" "refs/heads/${b}"; then ref="refs/heads/${b}"
    elif _ref_exists "$repo" "refs/remotes/origin/${b}"; then ref="refs/remotes/origin/${b}"
    elif git -C "$repo" ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1 \
         && git -C "$repo" fetch -q origin "+refs/heads/${b}:refs/remotes/origin/${b}" 2>/dev/null; then
      ref="refs/remotes/origin/${b}"
    fi
    if [ -z "$ref" ]; then
      echo "wrap.sh start: --pick branch ${b} does not exist locally or on origin; nothing picked, the worktree exists at ${wt}" >&2
      return 2
    fi
    refs+=("$ref")
  done

  i=0
  for b in "$@"; do
    ref="${refs[$i]}"; i=$(( i + 1 ))
    tip="$(git -C "$repo" rev-parse "$ref" 2>/dev/null)"
    base="$(git -C "$repo" merge-base "origin/${def}" "$tip" 2>/dev/null)" || base=""
    if [ -z "$base" ]; then
      echo "wrap.sh start: --pick branch ${b} shares no history with origin/${def}; the worktree exists at ${wt}" >&2
      return 2
    fi
    n=0
    while read -r c; do
      [ -n "$c" ] || continue
      if git -C "$wt" cherry-pick "$c" >/dev/null 2>&1; then
        n=$(( n + 1 )); done_list="${done_list} $(_short "$c")"
        continue
      fi
      files="$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"
      if [ -z "$files" ]; then
        # No unmerged path: the commit is empty on this base. Drop it and go on.
        git -C "$wt" cherry-pick --skip >/dev/null 2>&1 || git -C "$wt" cherry-pick --abort >/dev/null 2>&1
        continue
      fi
      git -C "$wt" cherry-pick --abort >/dev/null 2>&1
      echo "PICK CONFLICT ${b}: ${files% }" >&2
      echo "  conflicting commit: $(_short "$c")" >&2
      echo "  already picked in ${wt}:${done_list:- (none)}" >&2
      echo "  cherry-pick aborted, earlier picks kept, nothing resolved; any --carry was skipped" >&2
      return 2
    done < <(git -C "$repo" rev-list --reverse --topo-order --no-merges "${base}..${tip}" 2>/dev/null)
    if [ "$n" -eq 0 ]; then echo "pick ${b}: nothing to pick" >&2
    else echo "picked ${b}: ${n} commits" >&2
    fi
  done
  return 0
}
