# wrap-common.sh -- helpers and run-state shared by every wrap verb; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- helpers

_is_repo() { [ -e "$1/.git" ] || git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

_origin_url() { git -C "$1" remote get-url origin 2>/dev/null; }

_ref_exists() { git -C "$1" show-ref --verify --quiet "$2"; }

# _default_branch <repo> -- origin/HEAD when it resolves to a live remote ref, else main,
# else master. Exit 1 when none resolves; the caller skips that repo.
_default_branch() {
  local repo="$1" ref name
  ref="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then
    name="${ref#refs/remotes/origin/}"
    if [ "$name" != "$ref" ] && _ref_exists "$repo" "refs/remotes/origin/$name"; then
      printf '%s\n' "$name"; return 0
    fi
  fi
  for name in main master; do
    if _ref_exists "$repo" "refs/remotes/origin/$name"; then printf '%s\n' "$name"; return 0; fi
  done
  return 1
}

# _reject_packed <verb> <arg> -- exit 64 (message on stderr) when a positional looks like
# several flags packed into one word, the shape an unsplit variable (zsh `$args`) produces:
# " --own /path". Without this the word becomes a "repo" and the --own scope is silently lost.
# A real path with spaces still passes unless it holds whitespace followed by `--`.
_reject_packed() {
  local trimmed="${2#"${2%%[![:space:]]*}"}"
  case "$trimmed" in -*) ;; *)
    case "$2" in *[[:space:]]--*) ;; *) return 0 ;; esac ;;
  esac
  echo "wrap.sh $1: argument '$2' looks like flags packed into one word (an unsplit variable?); pass each flag and path as its own argument" >&2
  return 64
}

# _gh_state -- ok | unavailable | unauthenticated. Read once per verb run.
_gh_state() {
  command -v gh >/dev/null 2>&1 || { printf 'unavailable\n'; return 0; }
  gh auth status >/dev/null 2>&1 || { printf 'unauthenticated\n'; return 0; }
  printf 'ok\n'
}

_gh_note() {
  case "$1" in
    unavailable)     printf '(gh unavailable)\n' ;;
    unauthenticated) printf '(gh unauthenticated)\n' ;;
  esac
}

# _gh_merge_transient -- reads a captured `gh pr merge` error on stdin; exit 0
# when the text reads transient (worth a retry), 1 for a real refusal. The
# whitelist names the failure shapes an outage actually prints; anything else
# (not mergeable, draft, conflict, a --match-head-commit mismatch, auth) falls
# through to the caller on the first try.
_gh_merge_transient() {
  grep -qiE 'HTTP (500|502|503|504|507|509|429)|bad gateway|gateway timeout'\
'|service unavailable|executing (your )?query|went wrong|rate.?limit'\
'|timed? ?out|connection reset|connection refused|TLS handshake|EOF'\
'|temporar|failed to connect'
}

# _gh_merge_retry <pr> <repo-url> <head-oid> -- `gh pr merge` behind a bounded
# transient-error retry: WRAP_MERGE_RETRY_MAX attempts (default 3) with
# attempt * WRAP_MERGE_RETRY_SLEEP seconds of backoff (default 5). A real
# refusal returns on the first try with its original exit code and output.
WRAP_MERGE_RETRY_MAX=${WRAP_MERGE_RETRY_MAX:-3}
WRAP_MERGE_RETRY_SLEEP=${WRAP_MERGE_RETRY_SLEEP:-5}
_gh_merge_retry() {
  local n="$1" url="$2" head_oid="$3"
  local attempt=1 out rc
  while :; do
    out="$(gh pr merge "$n" --repo "$url" --squash --match-head-commit "$head_oid" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    # A merge that landed but whose answer 5xx'd reads "already merged" on the
    # retry: treat it as the success it is. The caller still verifies MERGED.
    printf '%s' "$out" | grep -qi 'already merged' && { printf '%s\n' "$out"; return 0; }
    if [ "$attempt" -ge "$WRAP_MERGE_RETRY_MAX" ] || \
       ! printf '%s' "$out" | _gh_merge_transient; then
      printf '%s\n' "$out" >&2; return "$rc"
    fi
    echo "merge #${n}: transient GitHub error (attempt ${attempt}/${WRAP_MERGE_RETRY_MAX})," \
      "retrying in $((attempt * WRAP_MERGE_RETRY_SLEEP))s" >&2
    sleep "$((attempt * WRAP_MERGE_RETRY_SLEEP))"
    attempt=$((attempt + 1))
  done
}

# GNU stat first: on GNU, `-f` means file-system status and prints a mount point with exit 0,
# so a BSD-first order parses garbage on Linux. BSD stat rejects `-c` and falls through.
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

_fmode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null; }

_short() { printf '%s' "${1:0:7}"; }

# _open_own_prs <repo-url> -- the open PRs the operator authored, as a JSON array.
#
# The author filter runs HERE, not on the server: `gh pr list --author` sends gh to the
# GraphQL search index (query PullRequestSearch), which is eventually consistent and omits
# a PR opened seconds ago, so an own green PR silently vanished from `merge` three times on
# one day. The plain list reads repository.pullRequests, which holds the PR the moment it
# exists. Exit 1 when the login or the list does not resolve: a failed read reported as an
# empty set is the same silent miss one hop earlier, so the caller says so instead.
_OWN_PR_LIMIT=100
_open_own_prs() {
  local me list
  me="$(gh api user --jq .login 2>/dev/null)"
  [ -n "$me" ] || return 1
  list="$(gh pr list --repo "$1" --state open --limit "$_OWN_PR_LIMIT" \
    --json number,title,headRefName,author 2>/dev/null)" || return 1
  [ -n "$list" ] || return 1
  # A full page is the one case where an own PR can sit past the cap, so it is named.
  if [ "$(printf '%s' "$list" | jq -r 'length' 2>/dev/null)" = "$_OWN_PR_LIMIT" ]; then
    echo "note: ${1} has at least ${_OWN_PR_LIMIT} open PRs; only the first ${_OWN_PR_LIMIT} were read" >&2
  fi
  printf '%s' "$list" \
    | jq -c --arg me "$me" '[.[] | select((.author.login // "") | ascii_downcase
                                          == ($me | ascii_downcase))]' 2>/dev/null
}

# _squash_json <repo-url> <branch> -- the merged-PR list gh reports for that head.
_squash_json() {
  gh pr list --repo "$1" --head "$2" --state merged --json headRefOid,baseRefName,mergedAt 2>/dev/null
}

# _squash_verdict <json> <local tip> <default branch> -- one of:
#   OK            a merged PR into the default branch has this exact tip
#   TIP <sha>     merged into the default branch, but from a different tip
#   BASE <name>   merged into another branch
#   NONE          no merged PR for this head (also the answer for unusable JSON)
_squash_verdict() {
  local json="$1" tip="$2" def="$3" out
  out="$(printf '%s' "$json" | jq -r --arg tip "$tip" --arg def "$def" '
    [.[] | select(.mergedAt != null)] as $m
    | if ($m | length) == 0 then "NONE"
      elif ([$m[] | select(.baseRefName == $def and .headRefOid == $tip)] | length) > 0 then "OK"
      elif ([$m[] | select(.baseRefName == $def)] | length) > 0
        then "TIP " + ([$m[] | select(.baseRefName == $def)][0].headRefOid)
      else "BASE " + ($m[0].baseRefName) end' 2>/dev/null)"
  [ -n "$out" ] || out="NONE"
  printf '%s\n' "$out"
}

# --------------------------------------------------------------------------- apply

APPLY=0
WORKTREES=0
ARCHIVE_UNMERGED=0
PULL_ONLY=0
MODE="DRY-RUN"
FAILURES=0
TIPS_FILE=""
TIPS_OVERRIDE=""
OWN_SET=""   # newline-separated canonical paths from --own; empty = no scope
OWN_SEEN=""  # canonical paths matched against the worktree list this run
OWN_N=0      # count of --own flags; OWN_PATHS[1..OWN_N] holds the raw args

# _write_guard <repo> -- 0 when the checkout is free to write, 1 when another writer holds
# it. An index.lock at least LOCK_STALE_SECS old is foreign; a younger one is normal git
# traffic, proven by a passing status call. An unresolvable git dir refuses the write.
_write_guard() {
  # A young index.lock is ordinary git traffic and clears within the stale window; one that
  # persists past it is a writer. Polling the file itself is portable: a `git status` probe
  # contends for the same lock on some git builds and fails for the wrong reason.
  local repo="$1" gd lock age m now waited=0
  gd="$(git -C "$repo" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  [ -n "$gd" ] || return 1
  lock="${gd}/index.lock"
  while [ -e "$lock" ]; do
    now="$(date +%s)"; m="$(_mtime "$lock")"
    case "$m" in ''|*[!0-9]*) return 1 ;; esac
    age=$(( now - m ))
    [ "$age" -lt "$LOCK_STALE_SECS" ] || return 1
    [ "$waited" -lt "$LOCK_STALE_SECS" ] || return 1
    sleep 1; waited=$(( waited + 1 ))
  done
  return 0
}

# run <repo> <verdict> <command...> -- print the verdict, execute only under --apply.
# A failed write is reported once and turns the run's exit code into 2. Nothing is retried.
run() {
  local repo="$1" verdict="$2"; shift 2
  if ! _write_guard "$repo"; then
    echo "     SKIP ${verdict}: index.lock held by another writer"
    # Under --pull-only the pull is the whole job, so a skipped write is a failed call.
    [ "$PULL_ONLY" = 1 ] && [ "$APPLY" = 1 ] && FAILURES=1
    return 0
  fi
  echo "     [${MODE}] ${verdict}"
  [ "$APPLY" = 1 ] || return 0
  "$@"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "     FAILED ${verdict}: exit ${rc}"
    FAILURES=1
  fi
  return 0
}
# _union_marked <repo> <path> -- 0 when .gitattributes declares the path merge=union.
# The repo declares which files resolve by keeping every line from both sides. That
# declaration, not a guess, is what makes carrying local lines across a pull correct.
_union_marked() {
  case "$(git -C "$1" check-attr merge -- "$2" 2>/dev/null)" in
    *"merge: union") return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------- merge cycle: merge, verify, push

# The recovery `land` (and `merge`) runs when GitHub refuses a PR as CONFLICTING while the
# branch is already pushed. A rebase would rewrite pushed history and force the push, so
# the recovery is a merge: origin/<def> into the branch, only the conflict classes
# `_rb_resolve` owns, one fast-forward push, then the caller's second merge attempt.
# Return convention for the whole family: 0 success; 1 refused with <branch> back at <tip>,
# no merge in progress, a clean worktree; 2 when that state could not be restored, the line
# naming what a human runs; 5 on `_merge_default` for a refused conflict cleanly restored,
# so a caller can word that case without parsing output; 130 on an interrupted cycle.
# A caller never downgrades a 2 to a 1.
MVP_HIT=""   # set by the cycle's signal handler; helpers bail the moment it is set
MVP_RC=0     # the handler's own cleanup result; 2 turns the cycle's 130 into a 2
MERGED_OID=""
_MVP_WT=""; _MVP_BRANCH=""; _MVP_TIP=""; _MVP_PUSH=""
_MVP_IGNORED=()  # paths ignored under the PRE-merge rules; recorded before the merge runs

# _mvp_ignored <path> -- 0 when <path> equals a recorded pre-merge ignored entry or sits
# under a recorded ignored directory (those carry a trailing slash). The set is how the
# cycle tells "work the merge created" from "an operator file origin's .gitignore change
# just exposed": under the new rules the file is untracked, so it must never be staged or
# deleted.
_mvp_ignored() {
  local p="$1" e
  for e in ${_MVP_IGNORED[@]+"${_MVP_IGNORED[@]}"}; do
    [ "$p" = "$e" ] && return 0
    case "$e" in */) case "$p" in "$e"*) return 0 ;; esac ;; esac
  done
  return 1
}

# _merge_restore <wt> <branch> <tip> -- leave a stopped merge with the branch back at <tip>.
# Reads the state, never a flag, because the trap calls it too. The worktree copies the
# merge left changed that are NOT unmerged go back from the index (`merge --abort` owns the
# unmerged ones), then every new untracked path is removed one `rm` at a time (the checkout
# started clean, so none of them predates the merge), then `merge --abort`. The order is
# load-bearing: git 2.55 refuses the abort while an auto-merged staged path has a different
# worktree copy, which is exactly what the generator or the resolver leaves behind.
_merge_restore() {
  local wt="$1" branch="$2" tip="$3" p gd
  local -a unmerged=() changed=()
  while IFS= read -r -d '' p; do unmerged+=("$p"); done \
    < <(git -C "$wt" diff --name-only --diff-filter=U -z 2>/dev/null)
  while IFS= read -r -d '' p; do
    _rb_has "$p" ${unmerged[@]+"${unmerged[@]}"} || changed+=("$p")
  done < <(git -C "$wt" diff --name-only -z 2>/dev/null)
  [ "${#changed[@]}" -gt 0 ] && git -C "$wt" checkout -q -- "${changed[@]}" 2>/dev/null
  # A path the pre-merge rules ignored (an operator's .env, a node_modules/) can surface as
  # untracked once the merge brings origin's .gitignore; it is not this merge's work, so the
  # sweep skips it and the file survives the abort.
  while IFS= read -r -d '' p; do _mvp_ignored "$p" || rm -f -- "$wt/$p"; done \
    < <(git -C "$wt" ls-files -o --exclude-standard -z 2>/dev/null)
  git -C "$wt" merge --abort >/dev/null 2>&1
  gd="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  if [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$tip" ] \
     && { [ -z "$gd" ] || [ ! -e "$gd/MERGE_HEAD" ]; } \
     && [ -z "$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
    echo "     aborted; ${branch} is back at $(_short "$tip")"
    return 1
  fi
  echo "ABORT FAILED ${branch}: run git merge --abort in ${wt}"
  return 2
}

# _merge_default <wt> <branch> <def> <tip> <gen> -- `git merge --no-ff --no-commit
# origin/<def>` in a checkout that started fully clean, so every change after the merge
# starts is the merge's or this helper's own: that is what makes the stage set and the
# restore set exact without a before/after record. Unmerged paths go to `_rb_resolve`; a
# refusal restores and returns 5 so the caller can word that case. The generator then runs
# once more, so even a conflict-free merge carries a fresh generated file. The stage set is
# explicit -- unmerged paths, worktree copies differing from the index, new untracked paths
# -- marker-scanned, staged by name, committed with a conventional subject, then the union
# row dedupe lands as its own commit. Every failure after the merge starts runs
# `_merge_restore`; the dedupe failure runs `_undo_local` after the staged paths are put
# back from HEAD. Success sets MERGED_OID.
_merge_default() {
  local wt="$1" branch="$2" def="$3" tip="$4" gen="$5"
  local p gd hits rrc rout log
  local -a unmerged=() set=() staged=()
  [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$tip" ] \
    || { echo "     ${branch} is not at $(_short "$tip"); nothing merged"; return 1; }
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" ] \
    || { echo "     ${wt} is dirty; nothing merged"; return 1; }
  gd="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  { [ -n "$gd" ] && [ ! -e "$gd/MERGE_HEAD" ] && [ ! -e "$gd/CHERRY_PICK_HEAD" ] \
    && ! _rb_rebasing "$wt"; } \
    || { echo "     a merge, rebase or cherry-pick is already in progress in ${wt}; nothing merged"; return 1; }
  _write_guard "$wt" || { echo "     index.lock held by another writer in ${wt}"; return 1; }
  ! git -C "$wt" merge-base --is-ancestor "origin/${def}" "$tip" 2>/dev/null \
    || { echo "     ${branch} already contains origin/${def}; nothing to merge"; return 1; }

  # Record what the PRE-merge ignore rules cover before the merge can rewrite .gitignore:
  # a file ignored today (an operator's .env) becomes "untracked" under origin's rules and
  # would otherwise be swept into the stage set, or deleted by the restore. --directory
  # keeps an ignored directory to one entry, matched as a prefix by _mvp_ignored.
  _MVP_IGNORED=()
  while IFS= read -r -d '' p; do _MVP_IGNORED+=("$p"); done \
    < <(git -C "$wt" ls-files -o -i --exclude-standard --directory -z 2>/dev/null)

  # ort merge ignores --no-overwrite-ignore (a known git gap: it still overwrites ignored
  # files), so the refusal the flag was meant to give runs here by hand: a path the merge
  # writes that the pre-merge rules ignored is an operator file, and overwriting it loses
  # data the merge has no right to touch. The flag stays passed for the paths that honor it.
  local -a clobber=()
  while IFS= read -r -d '' p; do
    _mvp_ignored "$p" && clobber+=("$p")
  done < <(git -C "$wt" diff --name-only -z "$tip" "origin/${def}" 2>/dev/null)
  # An interrupt that landed inside the preconditions must never start a merge the
  # caller will not see through: the flag wins over every judgment from here on.
  [ -n "$MVP_HIT" ] && return 130
  if [ "${#clobber[@]}" -gt 0 ]; then
    echo "REFUSED ${branch}: merge origin/${def} would overwrite the ignored ${clobber[*]}"
    return 1
  fi

  log="$(mktemp)" || return 1
  [ -n "$MVP_HIT" ] && { rm -f "$log"; return 130; }
  _rb_git "$wt" merge --no-ff --no-commit --no-overwrite-ignore "origin/${def}" > "$log" 2>&1
  if [ -n "$MVP_HIT" ]; then
    rm -f "$log"
    # The trap restores on its own, but bash can only run it once the merge command
    # returns; a MERGE_HEAD still standing here means that restore never ran or could
    # not finish, and a failed retry is the cycle's 2, not a fresh failure's.
    if [ -e "$gd/MERGE_HEAD" ]; then
      _merge_restore "$wt" "$branch" "$tip"; [ "$?" -eq 2 ] && return 2
    fi
    return 130
  fi
  if [ ! -e "$gd/MERGE_HEAD" ]; then
    [ -n "$MVP_HIT" ] && { rm -f "$log"; return 130; }
    echo "FAILED ${branch}: merge origin/${def} did not start: $(grep -m1 -v '^$' "$log" 2>/dev/null)"
    rm -f "$log"
    _merge_restore "$wt" "$branch" "$tip"; return $?
  fi
  rm -f "$log"

  while IFS= read -r -d '' p; do unmerged+=("$p"); done \
    < <(git -C "$wt" diff --name-only --diff-filter=U -z 2>/dev/null)
  if [ "${#unmerged[@]}" -gt 0 ]; then
    rout="$(_rb_resolve "$wt" "$gen" "${unmerged[@]}")"; rrc=$?
    # The flag goes first: an interrupted resolver owes its return to the signal, and
    # the trap already ran the restore -- reporting it as GENERATOR FAILED would be a lie.
    [ -n "$MVP_HIT" ] && return 130
    if [ "$rrc" -eq 1 ]; then
      echo "REFUSED ${branch}: ${rout}"
      _merge_restore "$wt" "$branch" "$tip"; rrc=$?
      [ "$rrc" -eq 1 ] && return 5
      return "$rrc"
    fi
    if [ "$rrc" -ne 0 ]; then
      echo "GENERATOR FAILED ${branch}"
      _merge_restore "$wt" "$branch" "$tip"; return $?
    fi
  fi
  # A merge with no conflict still regenerates, so a listed file origin added reaches the
  # generated file through the same run as a resolved conflict.
  if [ -n "$gen" ] && ! ( cd "$wt" && bash "$gen" generate ) >/dev/null 2>&1; then
    [ -n "$MVP_HIT" ] && return 130
    echo "GENERATOR FAILED ${branch}"
    _merge_restore "$wt" "$branch" "$tip"; return $?
  fi
  [ -n "$MVP_HIT" ] && return 130
  set=(${unmerged[@]+"${unmerged[@]}"})
  while IFS= read -r -d '' p; do
    _rb_has "$p" ${set[@]+"${set[@]}"} || set+=("$p")
  done < <(_rb_changed "$wt")
  while IFS= read -r -d '' p; do
    _mvp_ignored "$p" && continue
    _rb_has "$p" ${set[@]+"${set[@]}"} || set+=("$p")
  done < <(git -C "$wt" ls-files -o --exclude-standard -z 2>/dev/null)
  if hits="$(_rb_markers "$wt" ${set[@]+"${set[@]}"})"; then
    echo "MARKERS ${branch}: $(printf '%s' "$hits" | paste -sd, - | sed 's/,/, /g')"
    _merge_restore "$wt" "$branch" "$tip"; return $?
  fi
  # An empty set means the merge auto-staged everything itself (a pure union or
  # conflict-free merge), so there is nothing left to name for git add.
  if [ "${#set[@]}" -gt 0 ] && ! git -C "$wt" add -- "${set[@]}" 2>/dev/null; then
    echo "FAILED ${branch}: git add of the resolved paths"
    _merge_restore "$wt" "$branch" "$tip"; return $?
  fi
  [ -n "$MVP_HIT" ] && return 130
  # A conventional subject so a consumer's commit-msg hook accepts the merge commit the
  # same way it accepts the fixups a rebase stop records.
  if ! git -C "$wt" commit -q -m "chore(merge): merge origin/${def}"; then
    echo "FAILED ${branch}: the merge commit was refused"
    _merge_restore "$wt" "$branch" "$tip"; return $?
  fi
  _union_dedupe_rows "$wt" "$tip"; rrc=$?
  [ -n "$MVP_HIT" ] && return 130
  if [ "$rrc" -ne 0 ]; then
    while IFS= read -r -d '' p; do staged+=("$p"); done \
      < <(git -C "$wt" diff --cached --name-only -z 2>/dev/null)
    [ "${#staged[@]}" -gt 0 ] \
      && git -C "$wt" restore -q --staged --worktree --source=HEAD -- "${staged[@]}" 2>/dev/null
    _undo_local "$wt" "$branch" "$tip"; return $?
  fi
  MERGED_OID="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  echo "     merged origin/${def} into ${branch}: ${#unmerged[@]} conflict(s) resolved, head $(_short "$MERGED_OID") (was $(_short "$tip"))"
  return 0
}

# _undo_local <wt> <branch> <tip> -- drop the commits this run made that origin does not
# hold. `reset --keep` keeps a change the verify command made to a file the merge did not
# touch, and any untracked file it left, which is exactly why the post-reset status is the
# check: leftovers mean a human owns them. 1 on a clean undo, 2 naming the leftovers or the
# command a human runs when the reset itself refuses.
_undo_local() {
  local wt="$1" branch="$2" tip="$3" left
  if ! git -C "$wt" reset -q --keep "$tip" 2>/dev/null; then
    echo "     the local merge commit $(_short "$(git -C "$wt" rev-parse HEAD 2>/dev/null)") stays on ${branch}, not pushed; run git reset --keep ${tip} in ${wt}"
    return 2
  fi
  left="$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)"
  if [ -z "$left" ]; then
    echo "     ${branch} is back at $(_short "$tip"); nothing was pushed"
    return 1
  fi
  left="$(printf '%s\n' "$left" | sed 's/^...//; s/.* -> //' | paste -sd, - | sed 's/,/, /g')"
  echo "     ${branch} is back at $(_short "$tip"), nothing was pushed, but ${wt} holds changes this run did not make: ${left}"
  return 2
}

# _verify_or_undo <wt> <branch> <tip> <cmd> -- the caller's `--verify`, run as typed through
# `bash -c` with <wt> as cwd and its output on the terminal. Green is exit 0 with HEAD still
# MERGED_OID and no tracked file touched: a verify that commits moves HEAD, and pushing then
# would land a tree nobody verified. Red undoes the merge commit before any push. The
# command is trusted operator input -- it only ever arrives through the `--verify` flag --
# so it is echoed as typed, and a secret belongs in the environment, not in the flag.
_verify_or_undo() {
  local wt="$1" branch="$2" tip="$3" cmd="$4" rc def
  def="$(_default_branch "$wt" 2>/dev/null)"
  ( cd "$wt" && exec bash -c "$cmd" ); rc=$?
  [ -n "$MVP_HIT" ] && return 130
  if [ "$rc" -ne 0 ]; then
    echo "     VERIFY FAILED ${branch}: ${cmd} exited ${rc} in ${wt} after merging origin/${def}"
    _undo_local "$wt" "$branch" "$tip"; return $?
  fi
  if [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$MERGED_OID" ]; then
    echo "     VERIFY FAILED ${branch}: ${cmd} moved HEAD in ${wt} after merging origin/${def}"
    _undo_local "$wt" "$branch" "$tip"; return $?
  fi
  if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "     VERIFY FAILED ${branch}: ${cmd} changed tracked files in ${wt} after merging origin/${def}"
    _undo_local "$wt" "$branch" "$tip"; return $?
  fi
  echo "     verified in ${wt}: ${cmd}"
  return 0
}

# _push_ff <wt> <branch> <tip> -- the one push of the cycle, HEAD:refs/heads/<branch> with
# no force and no `+`: the merge commit descends from <tip>, so origin takes it only as a
# fast-forward. A non-zero push is judged by what `git ls-remote` answers, never by the
# exit code alone: a dropped connection can land the update anyway (success), a still-at-tip
# origin is the plain refusal (undo like a verify failure), a moved one is another writer
# (undo the same), and an unreadable remote resets nothing, since the commit may be there.
_push_ff() {
  local wt="$1" branch="$2" tip="$3" rc remote rrc
  _MVP_PUSH=1
  git -C "$wt" push origin "HEAD:refs/heads/${branch}"; rc=$?
  [ -n "$MVP_HIT" ] && return 130
  [ "$rc" -eq 0 ] && return 0
  remote="$(git -C "$wt" ls-remote origin "refs/heads/${branch}" 2>/dev/null)"; rrc=$?
  remote="${remote%%[!0-9a-f]*}"
  if [ "$rrc" -ne 0 ] || [ -z "$remote" ]; then
    echo "     PUSH FAILED: git push exited ${rc} and origin could not be read; the merge commit $(_short "$MERGED_OID") may be on origin, check before re-running"
    return 2
  fi
  case "$remote" in
    "$MERGED_OID") return 0 ;;
    "$tip") echo "     PUSH REFUSED: git push exited ${rc}; origin still holds $(_short "$tip")" ;;
    *)
      # A push can land and the answer still come back failed (dropped connection,
      # gateway timeout). A remote head that descends from our merge commit is that
      # case: the merge is on origin under a later foreign commit. Fetched by sha,
      # not by ref: ls-remote's answer is the proof, and a named ref could move
      # again between the two reads.
      if git -C "$wt" fetch -q origin "$remote" 2>/dev/null \
         && git -C "$wt" merge-base --is-ancestor "$MERGED_OID" "$remote" 2>/dev/null; then
        return 0
      fi
      echo "     PUSH REFUSED: ${branch} on origin moved to $(_short "$remote")" ;;
  esac
  _undo_local "$wt" "$branch" "$tip"
}

# _mvp_trap -- INT/TERM/HUP inside a merge cycle. The first line ignores all three signals,
# so a second Ctrl-C cannot re-enter. Then it cleans up by state, never with a network call
# before the push started: mid-merge is `_merge_restore`; staged dedupe rows go back from
# HEAD or the reset would refuse; a merge commit whose push never started is `_undo_local`;
# once the push started, one `ls-remote` answers which way it went, judged by `_push_ff`'s
# rules. The flag is how the sequence learns it was interrupted: it returns 130, or 2 when
# this cleanup could not finish. Never `exit` -- the caller removes what it owns first.
_mvp_trap() {
  trap '' INT TERM HUP
  MVP_HIT=1; MVP_RC=0
  local gd remote rrc p
  local -a staged=()
  gd="$(git -C "$_MVP_WT" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  if [ -n "$gd" ] && [ -e "$gd/MERGE_HEAD" ]; then
    _merge_restore "$_MVP_WT" "$_MVP_BRANCH" "$_MVP_TIP"; MVP_RC=$?
    return
  fi
  while IFS= read -r -d '' p; do staged+=("$p"); done \
    < <(git -C "$_MVP_WT" diff --cached --name-only -z 2>/dev/null)
  [ "${#staged[@]}" -gt 0 ] \
    && git -C "$_MVP_WT" restore -q --staged --worktree --source=HEAD -- "${staged[@]}" 2>/dev/null
  if [ "$_MVP_PUSH" != 1 ]; then
    if [ "$(git -C "$_MVP_WT" rev-parse HEAD 2>/dev/null)" != "$_MVP_TIP" ]; then
      _undo_local "$_MVP_WT" "$_MVP_BRANCH" "$_MVP_TIP"; MVP_RC=$?
    fi
    return
  fi
  remote="$(git -C "$_MVP_WT" ls-remote origin "refs/heads/${_MVP_BRANCH}" 2>/dev/null)"; rrc=$?
  remote="${remote%%[!0-9a-f]*}"
  if [ "$rrc" -ne 0 ] || [ -z "$remote" ]; then
    echo "     PUSH FAILED: the push was interrupted and origin could not be read; the merge commit $(_short "$MERGED_OID") may be on origin, check before re-running"
    MVP_RC=2
  elif [ "$remote" = "$_MVP_TIP" ]; then
    echo "     PUSH REFUSED: the push was interrupted; origin still holds $(_short "$_MVP_TIP")"
    _undo_local "$_MVP_WT" "$_MVP_BRANCH" "$_MVP_TIP"; MVP_RC=$?
  elif [ "$remote" != "$MERGED_OID" ]; then
    echo "     PUSH REFUSED: ${_MVP_BRANCH} on origin moved to $(_short "$remote")"
    _undo_local "$_MVP_WT" "$_MVP_BRANCH" "$_MVP_TIP"; MVP_RC=$?
  fi
}

# _merge_verify_push <wt> <branch> <def> <tip> <gen> [<cmd>] -- the one merge cycle both
# callers run: fetch, the already-contains route-out (4), then merge, the caller's --verify
# when given, and push, the first non-zero return ending it. The signal handler covers the
# merge/verify/push half and the caller's own handlers go back on the way out. One call is
# at most one cycle: 4 when <tip> already holds origin/<def>, 130 when interrupted, 2 when
# the cleanup could not restore the pre-cycle state, else the first helper's return.
_merge_verify_push() {
  local wt="$1" branch="$2" def="$3" tip="$4" gen="$5" cmd="${6:-}"
  local rrc ti tt th
  git -C "$wt" fetch -q origin "$def" 2>/dev/null \
    || { echo "     fetch origin ${def} failed; nothing merged"; return 1; }
  git -C "$wt" merge-base --is-ancestor "origin/${def}" "$tip" 2>/dev/null && return 4

  MERGED_OID=""; MVP_HIT=""; MVP_RC=0; _MVP_PUSH=""; _MVP_IGNORED=()
  _MVP_WT="$wt"; _MVP_BRANCH="$branch"; _MVP_TIP="$tip"
  ti="$(trap -p INT)"; tt="$(trap -p TERM)"; th="$(trap -p HUP)"
  trap '_mvp_trap' INT TERM HUP

  _merge_default "$wt" "$branch" "$def" "$tip" "$gen"; rrc=$?
  if [ -z "$MVP_HIT" ] && [ "$rrc" -eq 0 ] && [ -n "$cmd" ]; then
    _verify_or_undo "$wt" "$branch" "$tip" "$cmd"; rrc=$?
  fi
  if [ -z "$MVP_HIT" ] && [ "$rrc" -eq 0 ]; then
    _push_ff "$wt" "$branch" "$tip"; rrc=$?
  fi

  # The caller's handlers go back whatever happened above: a bare `trap -` for a signal it
  # never trapped, the eval'd `trap -p` text for one it did.
  if [ -n "$ti" ]; then eval "$ti"; else trap - INT; fi
  if [ -n "$tt" ]; then eval "$tt"; else trap - TERM; fi
  if [ -n "$th" ]; then eval "$th"; else trap - HUP; fi

  if [ -n "$MVP_HIT" ]; then
    [ "$MVP_RC" -eq 2 ] && return 2
    return 130
  fi
  return "$rrc"
}
