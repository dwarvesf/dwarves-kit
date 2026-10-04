# wrap-pull.sh -- helpers that pull origin/<default> into a repo or worktree; sourced by lib/wrap/wrap.sh.


# _union_carry_back <saved-local> <saved-base> <target> -- put the local lines back into the
# pulled file. Prints how many lines the local copy holds and the pulled file lacks; returns 1
# when the merge refused, having restored the local copy so the operator's work is never the
# thing that goes missing.
#
# A file with a `---` anchor keeps the anchor rule: a carried line lands directly below the
# header, as the newest entry, which is where `wrap log` writes one and what a newest-first log
# means. A file with NO anchor gets git's own union driver instead, over the three sides any
# merge of this file would use: the pulled content, the pre-pull content as base, and the local
# copy. The prepend has no right answer there. A board table has no anchor, so a carried ROW
# landed at line 1, above the title and outside the table it belongs to, and a file with two
# tables offers the anchor rule two equally wrong places.
_union_carry_back() {
  local local_copy="$1" base="$2" target="$3" add tmp head_n mode n
  add="$(mktemp)"
  grep -Fxv -f "$target" "$local_copy" > "$add" 2>/dev/null
  n="$(grep -c '' "$add" 2>/dev/null)"; n="${n:-0}"
  if [ "$n" -le 0 ] 2>/dev/null; then rm -f "$add"; printf '0'; return 0; fi

  tmp="$(mktemp)"
  mode="$(_fmode "$target")"
  case "$mode" in ''|*[!0-7]*) mode="" ;; esac
  [ -n "$mode" ] && chmod "$mode" "$tmp"   # mktemp opens 0600; carry the target's mode over

  head_n="$(_log_anchor_head_lines "$target")"
  if [ "$head_n" -gt 0 ] 2>/dev/null; then
    sed -n "1,${head_n}p" "$target" > "$tmp"
    cat "$add" >> "$tmp"
    tail -n "+$((head_n + 1))" "$target" >> "$tmp"
    rm -f "$add"
    mv -f "$tmp" "$target"
    printf '%s'  "$n"
    return 0
  fi
  rm -f "$add"
  cp "$target" "$tmp"
  if git merge-file --union -q "$tmp" "$base" "$local_copy" >/dev/null 2>&1; then
    mv -f "$tmp" "$target"
    printf '%s' "$n"
    return 0
  fi
  rm -f "$tmp"
  cp "$local_copy" "$target"   # the operator's lines are never the thing that goes missing
  printf '0'
  return 1
}

# _pull_past_dirty_on -- 0 when the operator authorized stashing a sibling session's dirty
# tracked files aside for the length of one pull. Root-only: a project `.kit.toml` rides
# inside a pull request and must never authorize a write to a shared checkout.
_pull_past_dirty_on() { [ "$(kit_config_get_root wrap.pull_past_dirty false)" = "true" ]; }

# _ff_blocked_into <repo> <outfile> -- writes the NUL-separated paths a fast-forward would
# refuse to overwrite and prints how many. A path qualifies when it is dirty in the worktree
# AND changes between HEAD and the upstream tip, which is the same per-entry test git applies
# before it reports `would be overwritten by merge`. Nothing qualifies when the upstream is
# unresolvable or HEAD is not already an ancestor of it: then the pull refuses for a reason no
# stash can clear. Untracked paths never qualify, so an incoming commit that adds one still
# aborts the pull, as it does today.
_ff_blocked_into() {
  local repo="$1" out="$2" up inc="" f n=0
  : > "$out"
  up="$(git -C "$repo" rev-parse --verify --quiet '@{u}' 2>/dev/null)"
  [ -n "$up" ] || { printf '0'; return 0; }
  git -C "$repo" merge-base --is-ancestor HEAD "$up" 2>/dev/null || { printf '0'; return 0; }
  # --no-renames, because rename detection prints only the incoming name. A commit that
  # renames a file the worktree has dirty would otherwise hide the very path git blocks on.
  while IFS= read -r -d '' f; do inc="${inc}${f}"$'\n'; done \
    < <(git -C "$repo" diff --name-only -z --no-renames HEAD "$up" 2>/dev/null)
  while IFS= read -r -d '' f; do
    # A path that is not a regular file never belongs in the stash. Git rewrites a
    # worktree-deleted file rather than refusing the fast-forward, and a dirty submodule
    # gitlink is stashable by nobody; stashing either turns a clean pull into a pop conflict.
    [ -f "$repo/$f" ] || continue
    case $'\n'"$inc" in
      *$'\n'"$f"$'\n'*) printf '%s\0' "$f" >> "$out"; n=$(( n + 1 )) ;;
    esac
  done < <(git -C "$repo" diff --name-only -z 2>/dev/null)
  printf '%s' "$n"
}

# _stash_blocked <repo> <name> <nul-list file> -- stash exactly the listed paths under a
# findable name and print the stash commit. The list goes in as a NUL pathspec file, so a
# path holding a glob character, a leading colon, or a space means itself and nothing else;
# a bare `git stash` would take every other dirty file and every untracked file in a
# checkout this session does not own. The entry is found by its own subject, never by
# reading refs/stash after the push: a sibling pushing in that gap puts ITS commit at the
# top, and a run that recorded it would pop and drop the sibling's stash while its own sat
# orphaned under this name. The push's exit code is not the answer either, for the same
# reason in the other direction: a push that failed after writing the entry still took the
# files, and only the list says whether it did. A push that saved nothing has no entry, and
# the empty answer says so, because a caller that recorded a stash it never made would
# report the operator's work lost when nothing was ever taken.
_stash_blocked() {
  local repo="$1" name="$2" list="$3" h s
  git -C "$repo" stash push -q -m "$name" \
    --pathspec-from-file="$list" --pathspec-file-nul >/dev/null 2>&1
  while read -r h s; do
    case "$s" in *": ${name}") printf '%s' "$h"; return 0 ;; esac
  done < <(git -C "$repo" stash list --format='%H %s' 2>/dev/null)
  return 1
}

# _unstash <repo> <sha> <name> <pulled> -- pop the run's own stash BY IDENTITY. A bare
# `git stash pop` takes whatever sits on top, which on a shared checkout is another
# session's stash; a positional ref resolved a moment earlier is no better, because any
# session pushing or dropping an entry shifts every index. The commit recorded at push time
# is the only handle that cannot drift. A pop conflict keeps the stash and leaves the
# markers: wrap does not know which side of a file it did not write is the right one. A file
# the repo declares merge=union never reaches that branch, because the union driver resolves
# it during the pop itself.
_unstash() {
  local repo="$1" sha="$2" name="$3" pulled="$4" ref="" gd h conflicted
  while read -r gd h; do
    if [ "$h" = "$sha" ]; then ref="$gd"; break; fi
  done < <(git -C "$repo" stash list --format='%gd %H' 2>/dev/null)
  if [ -z "$ref" ]; then
    echo "     FAILED restore: stash ${name} left the stash list; recover it with git stash apply $(_short "$sha")"
    FAILURES=1; return 0
  fi
  if git -C "$repo" stash pop -q "$ref" >/dev/null 2>&1; then
    echo "     restored the stashed file(s) and dropped ${name}"
    return 0
  fi
  conflicted="$(git -C "$repo" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"
  if [ -z "$conflicted" ]; then
    echo "     FAILED restore: the pop of ${name} refused with no conflict, so the stash is kept"
  elif [ "$pulled" = 1 ]; then
    echo "     PULLED, POP CONFLICT: ${conflicted% }, stash ${name} kept"
  else
    echo "     POP CONFLICT: ${conflicted% }, stash ${name} kept"
  fi
  FAILURES=1
}

# _pull_default <repo> <branch> -- the ff-only pull, with the repo's own append-only logs
# carried across it.
#
# Several sessions share one checkout, so uncommitted lines sit in log files nobody committed
# yet. Git prints `Updating a..b`, then aborts the merge to protect them, and the checkout
# stays behind. An operator who missed that abort deployed from a stale tree. Files marked
# merge=union are the safe case: the repo declares that keeping both sides resolves them, so
# this saves each one aside, restores the committed content, pulls, then carries the local
# lines back. Any other modified file keeps today's behavior, with the reason printed before
# the pull instead of buried under the abort.
_pull_default() {
  local repo="$1" cur="$2"
  local verdict="pull --ff-only (checkout on ${cur})"
  local staged modified f nonunion="" saved_dir="" n=0 before carried
  local union_tmp=""

  staged="$(git -C "$repo" diff --cached --name-only 2>/dev/null)"
  modified="$(git -C "$repo" diff --name-only 2>/dev/null)"

  if [ -n "$staged" ]; then
    echo "     NOTE: the index carries staged changes, so no log file is carried across (restoring an index is out of scope)"
  elif [ -n "$modified" ]; then
    union_tmp="$(mktemp)"
    while IFS= read -r -d '' f; do
      # A path git reports as modified but that is not a regular file cannot be copied back,
      # so it counts as a judgment call and stops the whole carry.
      if [ -f "$repo/$f" ] && _union_marked "$repo" "$f"; then
        printf '%s\0' "$f" >> "$union_tmp"
      else
        nonunion="${nonunion}${nonunion:+, }${f}"
      fi
    done < <(git -C "$repo" diff --name-only -z 2>/dev/null)
    if [ -n "$nonunion" ] && ! _pull_past_dirty_on; then
      echo "     NOTE: uncommitted and not declared merge=union, so the pull aborts on: ${nonunion}"
    elif [ -n "$nonunion" ] && [ "$APPLY" = 1 ]; then
      echo "     NOTE: uncommitted and not declared merge=union; wrap.pull_past_dirty is on, so the pull stashes whichever of these block it: ${nonunion}"
    elif [ -n "$nonunion" ]; then
      echo "     NOTE: uncommitted and not declared merge=union; --apply would stash whichever of these block the pull: ${nonunion}"
    fi
    # The union carry is independent of the nonunion branch: union files were once
    # lumped into the pull-past-dirty stash whenever a non-union file was also dirty,
    # and a pop conflict there left them dirty through the pull and the stash kept.
    # It still only runs when the pull can actually proceed: the knob is off and a
    # non-union file is dirty, the pull aborts regardless and the churn buys nothing.
    if [ -s "$union_tmp" ]; then
      if [ "$APPLY" != 1 ]; then
        if [ -z "$nonunion" ]; then
          echo "     NOTE: every modified file is merge=union; --apply would carry its local lines across the pull"
        else
          echo "     NOTE: modified merge=union file(s) alongside; --apply would carry their local lines across the pull"
        fi
      elif [ -z "$nonunion" ] || _pull_past_dirty_on; then
        saved_dir="$(mktemp -d)"
        while IFS= read -r -d '' f; do
          n=$(( n + 1 ))
          cp "$repo/$f" "${saved_dir}/${n}"
          printf '%s\0' "$f" >> "${saved_dir}/list"
          git -C "$repo" checkout -- "$f"
          # The restored file IS the merge base the carry-back needs, captured here because
          # after the pull the pre-pull content is no longer anywhere in the worktree.
          cp "$repo/$f" "${saved_dir}/${n}.base"
        done < "$union_tmp"
        echo "     saved ${n} union-marked file(s) aside so the pull can fast-forward"
      fi
    fi
    rm -f "$union_tmp"
  fi

  # The knob path: the files that block the fast-forward go aside under a name this run can
  # find again, the pull lands, and they come back. Off by default, and never entered while
  # the index carries staged changes, because a pop cannot restore an index it did not stash.
  local blocked_file="" stash_name="" stash_sha="" nblocked=0
  if [ "$APPLY" = 1 ] && [ -z "$staged" ] && [ -n "$nonunion" ] && _pull_past_dirty_on \
     && _write_guard "$repo"; then
    blocked_file="$(mktemp)"
    nblocked="$(_ff_blocked_into "$repo" "$blocked_file")"
    if [ "$nblocked" -gt 0 ] 2>/dev/null; then
      stash_name="wrap-pull-past-dirty-$(date +%s)-$$"
      stash_sha="$(_stash_blocked "$repo" "$stash_name" "$blocked_file")"
      if [ -n "$stash_sha" ]; then
        echo "     stashed ${nblocked} dirty tracked file(s) as ${stash_name} so the pull can fast-forward"
      else
        stash_name=""
        echo "     NOTE: no stash was created, so the pull runs as it does with the knob off"
      fi
    fi
    rm -f "$blocked_file"
  fi

  before="$FAILURES"
  run "$repo" "$verdict" git -C "$repo" pull --ff-only

  # Whatever the pull did, the operator's lines come back out of the stash. A failed pull
  # leaves the checkout exactly as it was found.
  if [ -n "$stash_name" ]; then
    if [ "$FAILURES" = "$before" ]; then
      _unstash "$repo" "$stash_sha" "$stash_name" 1
    else
      _unstash "$repo" "$stash_sha" "$stash_name" 0
    fi
  fi

  if [ -n "$saved_dir" ]; then
    n=0
    while IFS= read -r -d '' f; do
      n=$(( n + 1 ))
      if [ "$FAILURES" = "$before" ]; then
        if carried="$(_union_carry_back "${saved_dir}/${n}" "${saved_dir}/${n}.base" "$repo/$f")"; then
          echo "     carried ${carried} local line(s) back into ${f}"
        else
          echo "     FAILED carry: ${f} would not union-merge, so its pre-pull content is back"
          FAILURES=1
        fi
      else
        # The operator's lines never stay only in a temp file, whatever failed the pull.
        cp "${saved_dir}/${n}" "$repo/$f"
        echo "     pull failed, restored ${f} to its pre-pull content"
      fi
    done < "${saved_dir}/list"
    rm -rf "$saved_dir"
  fi

  # A pull that printed is not a pull that landed. HEAD prints in the same block so a stale
  # checkout cannot hide behind an abort line the operator scrolled past.
  echo "     HEAD: $(git -C "$repo" log --oneline -1 2>/dev/null)"
}

# _land_ff_pull <repo> -- `land`'s fast-forward, with a dirty merge=union file carried across
# it. Reuses `_union_marked` and `_union_carry_back`, the same building blocks `_pull_default`
# carries `apply`'s pull with, but never the `wrap.pull_past_dirty` stash: `land` runs after a
# merge has already landed, on a checkout it does not own, and stays inside the guarantee its
# caller states ("never stashed past and never reset") for any file the repo has not itself
# declared safe to keep both sides of. A staged change skips the carry entirely, same guard as
# `_pull_default`, since restoring an index the carry did not stash is out of scope.
_land_ff_pull() {
  local repo="$1" f staged modified union_tmp saved_dir="" n=0 rc carried

  staged="$(git -C "$repo" diff --cached --name-only 2>/dev/null)"
  modified="$(git -C "$repo" diff --name-only 2>/dev/null)"
  if [ -z "$staged" ] && [ -n "$modified" ]; then
    union_tmp="$(mktemp)"
    while IFS= read -r -d '' f; do
      [ -f "$repo/$f" ] && _union_marked "$repo" "$f" && printf '%s\0' "$f" >> "$union_tmp"
    done < <(git -C "$repo" diff --name-only -z 2>/dev/null)
    if [ -s "$union_tmp" ]; then
      saved_dir="$(mktemp -d)"
      while IFS= read -r -d '' f; do
        n=$(( n + 1 ))
        cp "$repo/$f" "${saved_dir}/${n}"
        printf '%s\0' "$f" >> "${saved_dir}/list"
        git -C "$repo" checkout -- "$f"
        cp "$repo/$f" "${saved_dir}/${n}.base"
      done < "$union_tmp"
      echo "     saved ${n} union-marked file(s) aside so the pull can fast-forward"
    fi
    rm -f "$union_tmp"
  fi

  if git -C "$repo" pull --ff-only; then rc=0; else rc=1; fi

  if [ -n "$saved_dir" ]; then
    n=0
    while IFS= read -r -d '' f; do
      n=$(( n + 1 ))
      if [ "$rc" = 0 ]; then
        if carried="$(_union_carry_back "${saved_dir}/${n}" "${saved_dir}/${n}.base" "$repo/$f")"; then
          echo "     carried ${carried} local line(s) back into ${f}"
        else
          echo "     FAILED carry: ${f} would not union-merge, so its pre-pull content is back"
          rc=1
        fi
      else
        cp "${saved_dir}/${n}" "$repo/$f"
      fi
    done < "${saved_dir}/list"
    rm -rf "$saved_dir"
  fi
  return "$rc"
}
