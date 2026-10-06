# wrap-apply.sh -- the apply verb and its helpers; sourced by lib/wrap/wrap.sh.


_scanned_tip() { awk -v b="$1" '$1 == b { print $2 }' "$TIPS_FILE"; }

# _merge_proof <repo> <default branch> <gh state> <branch> -- prints the proof that the branch
# already reached the default branch and exits 0; exit 1 when no proof exists. The three proofs
# are the same three `_apply_branches` deletes a branch under: a plain ancestor, absorbed content,
# or the gh squash proof.
_merge_proof() {
  local repo="$1" def="$2" ghs="$3" b="$4" tip json
  # Full refs only: a bare name resolves a same-named tag first, and a tag or local branch
  # called origin/<def> beats the remote-tracking ref. Either once proved an unlanded worktree
  # branch "merged".
  if git -C "$repo" merge-base --is-ancestor "refs/heads/${b}" "refs/remotes/origin/${def}" 2>/dev/null; then
    printf 'ancestor of origin/%s\n' "$def"; return 0
  fi
  if _absorbed "$repo" "$def" "refs/heads/${b}"; then
    printf 'content already on origin/%s\n' "$def"; return 0
  fi
  [ "$ghs" = "ok" ] || return 1
  tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
  json="$(_squash_json "$(_origin_url "$repo")" "$b")"
  [ "$(_squash_verdict "$json" "$tip" "$def")" = "OK" ] || return 1
  printf 'squash-merged per gh\n'
}

# _absorbed <repo> <default branch> <commit> -- 0 when every path the commit changed since its
# merge base with origin/<def> is byte-identical (same blob and mode, or absent on both) at the
# commit and on origin/<def>. It covers a subagent branch whose lead re-committed the work under
# its own PR: new hashes, no PR for the branch, so neither other proof can ever hold. It never
# merges: a merge would run .gitattributes drivers, and keep-ours or union can return the
# default branch's side while the branch's edit exists nowhere else. Plain tree diffs read no
# attributes and write no objects. Like the squash proof, it guarantees the branch's net change,
# not content its own intermediate commits added and removed; `branch -D` prints the tip sha.
# Callers pass a full ref or a sha, so a tag named like the branch cannot stand in for it.
# --no-relative: diff.relative with a subdirectory <repo> would drop paths from both lists.
_absorbed() {
  local repo="$1" def="$2" tip="$3" main base changed differ rest path nl=$'\n'
  # core.quotePath=true makes both lists pure ASCII: bash 5 in a UTF-8 locale truncates a
  # string at a backslash before an invalid byte, which once dropped an overlapping path.
  # LC_ALL=C also halves the loop's cost.
  local LC_ALL=C
  local -a g=(git -C "$repo" --no-replace-objects -c core.quotePath=true)
  main="$("${g[@]}" rev-parse --verify --quiet "refs/remotes/origin/${def}^{commit}")" || return 1
  tip="$("${g[@]}" rev-parse --verify --quiet "${tip}^{commit}")" || return 1
  base="$("${g[@]}" merge-base "$main" "$tip" 2>/dev/null)" || return 1
  changed="$("${g[@]}" diff --no-relative --no-renames --ignore-submodules=none --name-only \
    "$base" "$tip")" || return 1
  [ -n "$changed" ] || return 1
  differ="$("${g[@]}" diff --no-relative --no-renames --ignore-submodules=none --name-only \
    "$tip" "$main")" || return 1
  # Both lists use git's quoted path form, one path per line, so an odd path still compares
  # exactly. The comparison is pure bash: no pipe, file, or subprocess that could fail and read
  # as "no overlap". A pipe into `grep -q` once read SIGPIPE's 141 as absorbed; a here-string
  # temp file and a <(...) operand can each vanish (full disk, no free descriptor) and leave
  # grep reading nothing. A quoted "$path" in a case pattern matches literally.
  rest="$changed"
  while [ -n "$rest" ]; do
    path="${rest%%"$nl"*}"
    case "$rest" in *"$nl"*) rest="${rest#*"$nl"}" ;; *) rest="" ;; esac
    case "$nl$differ$nl" in *"$nl$path$nl"*) return 1 ;; esac
  done
  return 0
}

# _wt_locked <worktree path> -- 0 when the worktree carries a lock. git keeps the lock as a
# `locked` file in that worktree's admin directory, the same state `worktree list` reports.
_wt_locked() {
  local gd
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  [ -n "$gd" ] && [ -f "${gd}/locked" ]
}

# _wt_lock_pid <worktree path> -- echoes the pid named in the worktree's lock reason, empty when
# unlocked or the reason names none. The Agent tool writes a reason shaped like
# "claude agent <id> (pid 47291 start ...)".
_wt_lock_pid() {
  local gd
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return
  [ -f "${gd}/locked" ] || return
  grep -oE 'pid [0-9]+' "${gd}/locked" 2>/dev/null | grep -oE '[0-9]+' | head -1
}

# _wt_lock_live <worktree path> -- 0 when the lock names a pid that is still alive.
_wt_lock_live() {
  local pid
  pid="$(_wt_lock_pid "$1")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# _wt_cleared <repo> <worktree path> -- 0 when the path is gone AND the list no longer names it.
# A removal that cannot delete the directory (a read-only parent) still prunes the admin entry,
# so neither half alone proves the worktree went. The removal is believed only after both.
_wt_cleared() {
  [ -e "$2" ] && return 1
  git -C "$1" worktree list --porcelain -z 2>/dev/null | tr '\0' '\n' \
    | grep -qxF "worktree $2" && return 1
  return 0
}

# _wt_busy <worktree path> -- 0 when a live process outside this wrap run holds the worktree:
# its current directory or an open file or mapping sits at or under the path. Sets BUSY_MSG to
# the one-line `SKIP <wt>: busy, held by pid <pid> (<command>)` (plus `and N more`). A
# subagent that reported done can still run a headless browser, a blocked `cp -i` or a test
# loop in its worktree; removing the directory under it makes every later write vanish. The
# form is one whole-system `lsof -Fpcn` filtered by path prefix: about 0.3s on a worktree of
# any size, where `lsof +D <wt>` walks the tree (3.6s on a 160k-file one). This run's own pid,
# its descendants and its ancestors never count: they hold the path only because the operator
# or a caller ran wrap from inside it. KIT_WRAP_SKIP_BUSY_CHECK=1 turns the check off. Without
# lsof it prints one NOTE per run and answers "not busy", today's behavior.
BUSY_MSG=""
_WT_BUSY_NOTED=0
_wt_busy() {
  local wt="$1" canon holders psnap pid cmd n
  BUSY_MSG=""
  [ "${KIT_WRAP_SKIP_BUSY_CHECK:-0}" = 1 ] && return 1
  if ! command -v lsof >/dev/null 2>&1; then
    if [ "$_WT_BUSY_NOTED" = 0 ]; then
      echo "     NOTE: busy check unavailable (no lsof)"; _WT_BUSY_NOTED=1
    fi
    return 1
  fi
  canon="$(cd "$wt" 2>/dev/null && pwd -P)" || return 1
  psnap="$(ps -axo pid=,ppid= 2>/dev/null)"
  # lsof runs from /, so this shell's own cwd inside the worktree cannot match.
  holders="$(cd / && lsof -nP -w +c 0 -Fpcn 2>/dev/null | WT="$canon" SELF="$$" PSNAP="$psnap" awk '
    BEGIN {
      n = split(ENVIRON["PSNAP"], rows, "\n")
      for (i = 1; i <= n; i++) { split(rows[i], f, " "); if (f[1] != "") par[f[1]] = f[2] }
      self = ENVIRON["SELF"]; wt = ENVIRON["WT"]; wl = length(wt)
      for (p = self; p != "" && p + 0 > 1 && !(p in anc); p = par[p]) anc[p] = 1
    }
    function mine(pid,   p, hops) {
      if (pid in anc) return 1
      for (p = pid; p != "" && p + 0 > 1 && hops < 64; p = par[p]) { if (p == self) return 1; hops++ }
      return 0
    }
    /^p/ { pid = substr($0, 2); next }
    /^c/ { cmd = substr($0, 2); next }
    /^n/ {
      name = substr($0, 2)
      if (name != wt && substr(name, 1, wl + 1) != wt "/") next
      if (pid in seen) next
      seen[pid] = 1
      if (mine(pid)) next
      if (count == 0) { fpid = pid; fcmd = cmd }
      count++
    }
    END { if (count > 0) printf "%s\t%s\t%d\n", fpid, fcmd, count }
  ')"
  [ -n "$holders" ] || return 1
  IFS=$'\t' read -r pid cmd n <<< "$holders"
  BUSY_MSG="SKIP ${wt}: busy, held by pid ${pid} (${cmd})"
  [ "${n:-1}" -gt 1 ] 2>/dev/null && BUSY_MSG="${BUSY_MSG} and $(( n - 1 )) more"
  return 0
}

# A worktree path may carry a newline, so the record stream is NUL-delimited: `--porcelain -z`
# terminates every attribute with NUL, which keeps the path whole.
_apply_worktrees() {
  local repo="$1" def="$2" cur="$3" fetch_ok="$4" ghs="$5"
  local main_wt rec wt wt_c wtb proof lock verdict tip scanned
  echo "-- worktrees:"
  [ -n "$OWN_SET" ] && echo "     scope --own: only the named worktrees are candidates"
  main_wt="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  main_wt="${main_wt%/.git}"; main_wt="${main_wt%/}"
  main_wt="$(cd "$main_wt" 2>/dev/null && pwd -P)"
  while IFS= read -r -d '' rec; do
    case "$rec" in "worktree "*) wt="${rec#worktree }" ;; *) continue ;; esac
    wt_c="$(cd "$wt" 2>/dev/null && pwd -P)"
    if [ -z "$wt_c" ]; then echo "     SKIP ${wt}: unresolvable"; continue; fi
    if [ -n "$OWN_SET" ]; then
      # --own is the operator's worktree opt-in for the named set only; an unnamed
      # entry is skipped without a line so a shared repo stays readable. Seen is
      # marked before the guards so a refused named worktree is never misreported.
      if printf '%s' "$OWN_SET" | grep -qxF "$wt_c"; then
        OWN_SEEN="${OWN_SEEN}${wt_c}"$'\n'
      else
        continue
      fi
    fi
    [ "$wt_c" = "$main_wt" ] && continue
    if [ -z "$OWN_SET" ] && [ "$WORKTREES" != 1 ]; then
      echo "     SKIP ${wt}: --worktrees not given (the operator must ask for worktree cleanup)"; continue
    fi
    if [ -n "$(git -C "$wt" status --short 2>/dev/null)" ]; then
      echo "     SKIP ${wt}: dirty (another session's work stays)"; continue
    fi
    wtb="$(git -C "$wt" branch --show-current 2>/dev/null)"
    if [ -z "$wtb" ]; then
      echo "     SKIP ${wt}: detached HEAD (removal could orphan the commit)"; continue
    fi
    case "$wtb" in "$def"|main|master)
      echo "     SKIP ${wt}: ${wtb} is the default or a protected branch name"; continue ;;
    esac
    if [ "$wtb" = "$cur" ]; then
      echo "     SKIP ${wt}: ${wtb} is the main checkout's branch"; continue
    fi
    if [ "$fetch_ok" != 1 ]; then
      echo "     SKIP ${wt}: fetch failed, stale merge proof for ${wtb}"; continue
    fi
    proof="$(_merge_proof "$repo" "$def" "$ghs" "$wtb")" || {
      echo "     SKIP ${wt}: ${wtb} is not proven merged into ${def} (leave it)"; continue
    }
    # The proof above can cost a network round trip, so both destructive inputs are re-read right
    # before the force: `-f -f` overrides a worktree that went dirty, and `-D` discards a commit
    # made since the run's own tip snapshot.
    if [ -n "$(git -C "$wt" status --short 2>/dev/null)" ]; then
      echo "     SKIP ${wt}: went dirty while the proof was read"; continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${wtb}" 2>/dev/null)"
    scanned="$(_scanned_tip "$wtb")"
    if [ -n "$scanned" ] && [ "$tip" != "$scanned" ]; then
      echo "     SKIP ${wt}: ${wtb} tip moved during this run ($(_short "$scanned") -> $(_short "$tip"))"; continue
    fi
    lock="unlocked"; _wt_locked "$wt" && lock="locked"
    if [ "$lock" = "locked" ] && _wt_lock_live "$wt"; then
      echo "     SKIP ${wt}: locked by live pid $(_wt_lock_pid "$wt") (an agent is still running)"; continue
    fi
    if _wt_busy "$wt"; then
      echo "     ${BUSY_MSG}"; continue
    fi
    verdict="remove worktree ${wt} [${wtb}, ${lock}] and delete ${wtb} (${proof})"
    if [ "$APPLY" != 1 ]; then
      echo "     WOULD ${verdict}"; continue
    fi
    if ! _write_guard "$repo"; then
      echo "     SKIP ${wt}: index.lock held by another writer"; continue
    fi
    # A lock alone is not proof the run finished: the Agent tool locks every worktree it creates,
    # including one made seconds ago for a subagent still running, so a fresh branch can be a
    # trivial ancestor of origin/<def> while the lock's pid is still alive (checked above, which
    # skips before this point). What remains here is a lock whose pid is dead or absent, safe to
    # override. `-f -f`, not `--force`: one --force refuses a locked worktree outright (`cannot
    # remove a locked working tree`), measured on git 2.55; two overrides the lock once every
    # guard above has passed.
    run "$repo" "$verdict" git -C "$repo" worktree remove -f -f "$wt"
    if _wt_cleared "$repo" "$wt"; then
      run "$repo" "delete ${wtb} (${proof}, its ${lock} worktree is gone)" \
        git -C "$repo" branch -D "$wtb"
    else
      echo "     FAILED ${verdict}: ${wt} survived the removal, ${wtb} not deleted"
      FAILURES=1
    fi
  done < <(git -C "$repo" worktree list --porcelain -z 2>/dev/null)
  if [ -n "$OWN_SET" ]; then
    local k=1 canon
    while [ "$k" -le "$OWN_N" ]; do
      canon="$(cd "${OWN_PATHS[$k]}" 2>/dev/null && pwd -P)"
      canon="${canon:-${OWN_PATHS[$k]}}"
      printf '%s' "$OWN_SEEN" | grep -qxF "$canon" \
        || echo "     SKIP ${OWN_PATHS[$k]}: not a registered worktree"
      k=$(( k + 1 ))
    done
  fi
}

_apply_branches() {
  local repo="$1" def="$2" cur="$3" fetch_ok="$4" ghs="$5"
  echo "-- branches:"
  local b tip scanned json verdict
  for b in $(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/); do
    case "$b" in "$def"|main|master) echo "     SKIP ${b}: default or protected branch name"; continue ;; esac
    if [ "$b" = "$cur" ]; then echo "     SKIP ${b}: currently checked out"; continue; fi
    if git -C "$repo" worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/${b}"; then
      echo "     SKIP ${b}: held by a worktree"; continue
    fi
    if [ "$fetch_ok" != 1 ]; then
      echo "     SKIP ${b}: fetch failed, stale ancestor data"; continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
    scanned="$(_scanned_tip "$b")"
    if [ -n "$scanned" ] && [ "$tip" != "$scanned" ]; then
      echo "     SKIP ${b}: tip moved during this run ($(_short "$scanned") -> $(_short "$tip"))"; continue
    fi
    # -D, not -d: the proof above is wrap's own, against origin/<def>. `branch -d` judges
    # against the branch's OWN upstream (or HEAD when it has none), so it refused a branch
    # that tracks another ref or nothing even though origin/<def> already holds its tip.
    # The sha and the full remote ref, never bare names: see _merge_proof.
    if git -C "$repo" merge-base --is-ancestor "$tip" "refs/remotes/origin/${def}" 2>/dev/null; then
      run "$repo" "delete ${b} (ancestor of origin/${def})" git -C "$repo" branch -D "$b"
      continue
    fi
    if _absorbed "$repo" "$def" "$tip"; then
      run "$repo" "delete ${b} (content already on origin/${def})" git -C "$repo" branch -D "$b"
      continue
    fi
    if [ "$ghs" != "ok" ]; then
      echo "     SKIP ${b}: $(_gh_note "$ghs"), no squash proof available"; continue
    fi
    json="$(_squash_json "$(_origin_url "$repo")" "$b")"
    verdict="$(_squash_verdict "$json" "$tip" "$def")"
    case "$verdict" in
      OK)
        run "$repo" "delete ${b} (squash-merged into ${def}, tip matches the PR head)" \
          git -C "$repo" branch -D "$b" ;;
      TIP\ *)
        echo "     SKIP ${b}: tip $(_short "$tip") != merged PR head $(_short "${verdict#TIP }") (unpushed commits, leave it)" ;;
      BASE\ *)
        echo "     SKIP ${b}: merged into ${verdict#BASE }, not the default branch" ;;
      *)
        echo "     SKIP ${b}: no merged PR found for this head" ;;
    esac
  done
}

# _archive_slug <branch> -- an origin-ref-safe slug: lower-case alnum runs joined by `-`,
# trimmed of leading/trailing dashes. Same shape as `_carry_stray_file`'s file slug, so a
# branch name carrying a `/` (e.g. feat/foo) collapses to one path segment under archive/.
_archive_slug() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//'
}

# _apply_archive_unmerged <repo> <default branch> <current branch> <fetch_ok> -- opt-in
# (--archive-unmerged, never under --own) sweep: every local branch that is not the current
# or default branch, is not held by a worktree, and carries at least one commit patch
# origin/<default> lacks (`git cherry origin/<default> <branch>` shows a `+`) gets pushed to
# a new origin archive/<slug>-<YYYYMMDD> ref and, only once that push lands, its local ref
# deleted. No force: an already-existing archive ref refuses the push and the branch stays
# local, reported FAILED. A branch with zero unique patches is already covered by
# `_apply_branches` above (an ancestor or a squash-merged proof) or is simply reported here
# and never deleted under this flag.
_apply_archive_unmerged() {
  local repo="$1" def="$2" cur="$3" fetch_ok="$4"
  echo "-- archive unmerged:"
  if [ -n "$OWN_SET" ]; then
    echo "     SKIP archive sweep: --own scopes cleanup to the named worktrees"; return 0
  fi
  if [ -z "$(_origin_url "$repo")" ]; then
    echo "     SKIP archive sweep: no origin remote"; return 0
  fi
  if [ "$fetch_ok" != 1 ]; then
    echo "     SKIP archive sweep: fetch failed, stale data"; return 0
  fi
  local b tip pushed cherry n slug ref err first
  # Full refs throughout, as in _merge_proof: a tag named like the branch once made the push
  # source ambiguous, and a bare origin/<def> can resolve a tag or local branch.
  for b in $(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/); do
    case "$b" in "$def"|main|master) continue ;; esac
    [ "$b" = "$cur" ] && continue
    # A symbolic ref names another branch's work: its guards would check the alias while the
    # push and the delete reached the target.
    if git -C "$repo" symbolic-ref -q "refs/heads/${b}" >/dev/null 2>&1; then
      echo "     SKIP ${b}: a symbolic ref, not a branch of its own"; continue
    fi
    if git -C "$repo" worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/${b}"; then
      echo "     SKIP ${b}: held by a worktree"; continue
    fi
    cherry="$(git -C "$repo" cherry "refs/remotes/origin/${def}" "refs/heads/${b}" 2>/dev/null)"
    n="$(printf '%s\n' "$cherry" | grep -c '^+')"
    if [ "$n" -eq 0 ]; then
      echo "     ${b}: nothing unique, left for the merged sweep"; continue
    fi
    slug="$(_archive_slug "$b")"
    ref="archive/${slug}-$(date +%Y%m%d)"
    if [ "$APPLY" != 1 ]; then
      echo "     WOULD archive ${b} -> origin ${ref} (${n} unique commits)"; continue
    fi
    if ! _write_guard "$repo"; then
      echo "     SKIP ${b}: index.lock held by another writer"; continue
    fi
    if git -C "$repo" ls-remote --exit-code --heads origin "$ref" >/dev/null 2>&1; then
      echo "     FAILED archive ${b}: origin ${ref} already exists"; FAILURES=1; continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}")"
    if err="$(git -C "$repo" push origin "refs/heads/${b}:refs/heads/${ref}" 2>&1)"; then
      # The local delete is leased to the tip read above, and only once origin holds that
      # tip: a commit made during the push, or an archive ref holding anything else, keeps
      # the branch.
      pushed="$(git -C "$repo" ls-remote origin "refs/heads/${ref}" 2>/dev/null \
        | awk -v r="refs/heads/${ref}" '$2 == r { print $1 }')"
      if [ -z "$tip" ] || [ "$pushed" != "$tip" ]; then
        echo "     FAILED archive ${b}: origin ${ref} holds $(_short "${pushed:-nothing}"), not the local tip $(_short "${tip:-unread}"); the branch stays"
        FAILURES=1
      # update-ref lacks branch -D's refusals, and the guards above ran before a network push,
      # so the checked-out and worktree-held checks are repeated right before the delete.
      # The list is captured, never piped into `grep -q`: an early grep exit can SIGPIPE the
      # writer, and under pipefail that 141 would read as "not held" and let the delete run.
      elif [ "$(git -C "$repo" symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/${b}" ] \
          || ! _wt_list="$(git -C "$repo" worktree list --porcelain 2>/dev/null)" \
          || case $'\n'"${_wt_list}"$'\n' in *$'\n'"branch refs/heads/${b}"$'\n'*) true ;; *) false ;; esac; then
        echo "     kept ${b}: archived to ${ref}, but it was checked out during the push"
      elif git -C "$repo" update-ref --no-deref -d "refs/heads/${b}" "$tip" >/dev/null 2>&1; then
        git -C "$repo" config --remove-section "branch.${b}" >/dev/null 2>&1
        echo "     archived ${b} -> ${ref}"
      else
        echo "     FAILED archive ${b}: pushed to ${ref} but the local branch delete refused"
        FAILURES=1
      fi
    else
      first="$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | head -1)"
      echo "     FAILED archive ${b}: ${first:-push refused}"
      FAILURES=1
    fi
  done
}

# _apply_origin_branches <repo> <default branch> <gh state> -- deletes origin branches
# whose work already merged. `merge` never passes --delete-branch, so without this pass every
# merged head lives on origin forever. A branch qualifies only when a same-repo MERGED PR has its
# exact origin tip, it is not the default branch, and no OPEN PR uses it as head or base
# (deleting a base closes the dependent PR). Everything else is kept without a line. Tips come
# from `ls-remote`, not refs/remotes: a checkout whose fetch refspec names only the default
# branch tracks a handful of origin's branches. Each delete is leased to the tip it read, so a
# branch pushed to after the read is refused rather than lost.
# ponytail: a branch whose merged PR sits past the list cap is kept; raise the cap if that bites.
_ORIGIN_PR_LIMIT=1000
# Names per `git push`; the env override is a test seam for the chunk loop.
_ORIGIN_DELETE_CHUNK=${WRAP_ORIGIN_DELETE_CHUNK:-100}
_apply_origin_branches() {
  local repo="$1" def="$2" ghs="$3" url merged open elig names n k left heads push_args
  echo "-- origin branches:"
  case "$(git -C "$repo" config --get remote.origin.url)" in
    *github.com[:/]*) ;;
    *) echo "     SKIP origin sweep: origin is not a GitHub remote"; return 0 ;;
  esac
  [ "$ghs" = "ok" ] || { echo "     SKIP origin sweep: $(_gh_note "$ghs")"; return 0; }
  url="$(_origin_url "$repo")"
  # A failed read leaves its list empty, which jq refuses as JSON, so the sweep skips.
  merged="$(gh pr list --repo "$url" --state merged --limit "$_ORIGIN_PR_LIMIT" \
    --json headRefName,headRefOid,isCrossRepository 2>/dev/null)" || merged=""
  open="$(gh pr list --repo "$url" --state open --limit "$_ORIGIN_PR_LIMIT" \
    --json headRefName,baseRefName 2>/dev/null)" || open=""
  # A full open page may hide the PR that protects a base branch, so the sweep stands down.
  if [ "$(printf '%s' "$open" | jq -r 'length' 2>/dev/null)" = "$_ORIGIN_PR_LIMIT" ]; then
    echo "     SKIP origin sweep: ${_ORIGIN_PR_LIMIT}+ open PRs, an unread one could need a branch"; return 0
  fi
  # One "<name> <tip>" line per eligible branch.
  elig="$(git -C "$repo" ls-remote --heads origin 2>/dev/null \
    | jq -R -r --argjson m "$merged" --argjson o "$open" --arg def "$def" '
        split("\t") as [$tip, $ref] | ($ref | ltrimstr("refs/heads/")) as $b
        | select($b != $def)
        | select(any($m[]; .isCrossRepository == false and .headRefName == $b and .headRefOid == $tip))
        | select(any($o[]; .headRefName == $b or .baseRefName == $b) | not)
        | "\($b) \($tip)"' 2>/dev/null)" \
    || { echo "     SKIP origin sweep: origin's branches or PRs could not be read"; return 0; }
  names="$(printf '%s' "$elig" | cut -d' ' -f1)"
  n="$(printf '%s' "$names" | grep -c .)"
  if [ "$n" -eq 0 ]; then echo "     no merged branches left on origin"; return 0; fi
  if [ "$(kit_config_get_root wrap.delete_merged_remote_branches true)" != "true" ]; then
    echo "     ${n} merged branches left on origin (wrap.delete_merged_remote_branches=false)"; return 0
  fi
  if [ "$APPLY" != 1 ]; then
    echo "     WOULD delete ${n} merged branches on origin:"
    printf '%s\n' "$names" | sed 's/^/       /'
    return 0
  fi
  # Ref names hold no whitespace or glob characters, so word splitting yields exact
  # name/tip pairs. A full refs/heads/ refspec keeps a same-named tag or a leading dash inert.
  # shellcheck disable=SC2086
  set -- $elig
  while [ $# -gt 0 ]; do
    k=0
    while [ $# -gt 0 ] && [ "$k" -lt "$_ORIGIN_DELETE_CHUNK" ]; do
      push_args[k * 2]="--force-with-lease=refs/heads/$1:$2"
      push_args[k * 2 + 1]=":refs/heads/$1"
      k=$(( k + 1 )); shift 2
    done
    git -C "$repo" push -q origin "${push_args[@]:0:$(( k * 2 ))}" \
      || { echo "     FAILED delete ${k} origin branches: exit $? (protected, no permission, or pushed since the read)"; FAILURES=1; }
  done
  # A multi-ref push is not atomic, so the count comes from what origin still holds.
  if ! heads="$(git -C "$repo" ls-remote --heads origin 2>/dev/null)"; then
    echo "     FAILED re-read origin after the delete, so the deleted count is unknown"; FAILURES=1; return 0
  fi
  left="$(printf '%s\n' "$heads" | sed 's|.*refs/heads/||' | grep -cxF -f <(printf '%s\n' "$names"))"
  echo "     deleted $(( n - left )) of ${n} merged branches on origin"
}


_apply_repo() {
  local repo="$1" ghs="$2"
  _is_repo "$repo" || { echo "== ${repo}: not a git repo, skipped"; return 0; }
  echo "== ${repo}"
  local fetch_ok=1
  if ! git -C "$repo" fetch --prune -q 2>/dev/null; then
    fetch_ok=0
    if [ "$PULL_ONLY" = 1 ]; then
      echo "     (fetch failed; the pull below will likely fail too)"
    else
      echo "     (fetch failed; every delete is skipped)"
    fi
  fi

  local def
  def="$(_default_branch "$repo")" || {
    echo "     SKIP ${repo}: no default branch resolved (origin/HEAD, origin/main and origin/master all absent)"
    [ "$PULL_ONLY" = 1 ] && FAILURES=1
    return 0
  }
  local cur; cur="$(git -C "$repo" branch --show-current 2>/dev/null)"

  # Tip snapshot for this repo, taken once, compared right before each delete. --tips-file
  # substitutes a prepared snapshot so a test can stage a tip that moved mid-run.
  # --pull-only runs no delete, so nothing reads a snapshot.
  local own_snapshot=1
  if [ "$PULL_ONLY" = 1 ]; then
    own_snapshot=0
  elif [ -n "$TIPS_OVERRIDE" ]; then
    TIPS_FILE="$TIPS_OVERRIDE"; own_snapshot=0
  else
    TIPS_FILE="$(mktemp)"
    git -C "$repo" for-each-ref --format='%(refname:lstrip=2) %(objectname)' refs/heads/ > "$TIPS_FILE" 2>/dev/null
  fi

  # --pull-only runs the fetch + pull stage alone: no worktree, branch, archive, origin-branch,
  # stray-line, or stray-commit write.
  if [ "$PULL_ONLY" != 1 ]; then
    if [ "$NO_PULL" = 1 ] && [ -z "$OWN_SET" ]; then
      # A step 0 stop tidies the session's own worktrees only: an unscoped sweep would
      # delete other live sessions' merged worktrees and branches.
      echo "-- worktrees:"
      echo "     SKIP worktree sweep: --no-pull needs --own (the session's own worktrees only)"
    else
      _apply_worktrees "$repo" "$def" "$cur" "$fetch_ok" "$ghs"
    fi
    if [ "$NO_PULL" = 1 ] && [ -z "$OWN_SET" ]; then
      echo "-- branches:"
      echo "     SKIP branch sweep: --no-pull needs --own (the all-branches sweep reaches other sessions' branches)"
    elif [ -n "$OWN_SET" ]; then
      # The named worktrees' branches were deleted by the worktree step itself; the
      # all-branches sweep would reach past the session's scope into other sessions'.
      echo "-- branches:"
      echo "     SKIP branch sweep: --own scopes cleanup to the named worktrees"
    else
      _apply_branches "$repo" "$def" "$cur" "$fetch_ok" "$ghs"
    fi
    # Opt-in and never under --own (see the function's own comment); a flag-off run prints
    # no new section, so the report is byte-identical to before this flag existed.
    [ "$ARCHIVE_UNMERGED" = 1 ] && _apply_archive_unmerged "$repo" "$def" "$cur" "$fetch_ok"
    # Outside the --own scope on purpose: it touches no local ref or worktree, and its own
    # proof (merged PR at the exact tip, no open PR on it) holds whoever owns the branch.
    # Skipping it under --own left every shared repo's merged heads on origin.
    _apply_origin_branches "$repo" "$def" "$ghs"

    # Any checked-out branch: the incident state is a shared main checkout sitting on a
    # feature branch while a session writes the board there.
    if [ "$fetch_ok" = 1 ]; then
      _carry_stray "$repo" "$def"
    else
      echo "-- stray lines:"
      echo "     SKIP stray lines: fetch failed, origin/${def} may be stale"
    fi
    # Before the pull, which a default branch ahead of origin can never fast-forward.
    if [ "$NO_PULL" = 1 ]; then
      echo "-- stray commits:"
      echo "     SKIP stray commits: --no-pull"
    elif [ "$fetch_ok" != 1 ]; then
      echo "-- stray commits:"
      echo "     SKIP stray commits: fetch failed, origin/${def} may be stale"
    elif [ "$cur" = "$def" ]; then
      _carry_stray_commits "$repo" "$def"
    fi
  fi

  echo "-- pull:"
  if [ "$NO_PULL" = 1 ]; then
    # --no-pull is a step 0 stop: the pull and the stray-commits move write HEAD and the
    # working tree of a checkout another session is writing.
    echo "     SKIP pull: --no-pull"
  elif [ "$cur" = "$def" ]; then
    # --pull-only skips the stray-commits carry, so name what it leaves behind rather than
    # letting unpushed commits on the default branch go silent run after run.
    if [ "$PULL_ONLY" = 1 ] && [ "$fetch_ok" = 1 ]; then
      local ahead; ahead="$(git -C "$repo" rev-list --count "origin/${def}..HEAD" 2>/dev/null)"
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && \
        echo "     NOTE: ${def} is ${ahead} commits ahead of origin/${def}; --pull-only never carries them, plain apply --apply does"
    fi
    _pull_default "$repo" "$cur"
  else
    echo "     SKIP pull: checkout on '${cur:-<detached>}', not the default branch ${def}"
    run "$repo" "fetch origin ${def}:${def} (ff-only by nature)" git -C "$repo" fetch origin "${def}:${def}"
  fi

  [ "$own_snapshot" = 1 ] && rm -f "$TIPS_FILE"
  TIPS_FILE=""
}

cmd_apply() {
  # Indexed assignment plus a counter, not `arr+=()` with `${#arr[@]}`: an empty array reads
  # as unbound under `set -u` in bash 3.2, which is what macOS ships.
  local arg count=0 i=1 want_tips=0 want_own=0 want_under=0 nu=0
  local repos unders
  for arg in "$@"; do
    case "$arg" in
      --apply) APPLY=1 ;;
      --worktrees) WORKTREES=1 ;;
      --archive-unmerged) ARCHIVE_UNMERGED=1 ;;
      --pull-only) PULL_ONLY=1 ;;
      --no-pull) NO_PULL=1 ;;
      --under=*) nu=$(( nu + 1 )); unders[nu]="${arg#--under=}" ;;
      --under) want_under=1 ;;
      --own=*) OWN_N=$(( OWN_N + 1 )); OWN_PATHS[OWN_N]="${arg#--own=}" ;;
      --own) want_own=1 ;;
      --tips-file=*) TIPS_OVERRIDE="${arg#--tips-file=}" ;;
      --tips-file) want_tips=1 ;;
      -*) echo "wrap.sh apply: unknown flag '$arg'" >&2; return 64 ;;
      *) _reject_packed apply "$arg" || return 64
         if [ "$want_own" = 1 ]; then OWN_N=$(( OWN_N + 1 )); OWN_PATHS[OWN_N]="$arg"; want_own=0
         elif [ "$want_under" = 1 ]; then nu=$(( nu + 1 )); unders[nu]="$arg"; want_under=0
         elif [ "$want_tips" = 1 ]; then TIPS_OVERRIDE="$arg"; want_tips=0
         else count=$(( count + 1 )); repos[count]="$arg"; fi ;;
    esac
  done
  [ "$want_tips" = 0 ] || { echo "wrap.sh apply: --tips-file needs a path" >&2; return 64; }
  [ "$want_own" = 0 ] || { echo "wrap.sh apply: --own needs a worktree path" >&2; return 64; }
  # --pull-only runs only the fetch + pull stage, so every other write-capable flag is a
  # conflict rather than a silent no-op. Checked before the --tips-file existence check just
  # below: a combination with --tips-file is refused for the conflict, not for whether the
  # path exists.
  if [ "$PULL_ONLY" = 1 ] && [ "$NO_PULL" = 1 ]; then
    echo "wrap.sh apply: --no-pull cannot combine with --pull-only" >&2; return 64
  fi
  if [ "$PULL_ONLY" = 1 ]; then
    if [ "$WORKTREES" = 1 ]; then echo "wrap.sh apply: --pull-only cannot combine with --worktrees" >&2; return 64; fi
    if [ "$ARCHIVE_UNMERGED" = 1 ]; then echo "wrap.sh apply: --pull-only cannot combine with --archive-unmerged" >&2; return 64; fi
    if [ "$OWN_N" -gt 0 ]; then echo "wrap.sh apply: --pull-only cannot combine with --own" >&2; return 64; fi
    if [ -n "$TIPS_OVERRIDE" ]; then echo "wrap.sh apply: --pull-only cannot combine with --tips-file" >&2; return 64; fi
  fi
  if [ -n "$TIPS_OVERRIDE" ] && [ ! -f "$TIPS_OVERRIDE" ]; then
    echo "wrap.sh apply: --tips-file '${TIPS_OVERRIDE}' is not an existing file" >&2; return 64
  fi
  if [ "$want_under" = 1 ]; then _expand_bare_under apply || return 64; fi
  [ "$count" -ge 1 ] || [ "$nu" -ge 1 ] || { echo "usage: wrap.sh apply [--apply] [--worktrees] [--archive-unmerged] [--pull-only|--no-pull] [--own <path>]... [--under <root>]... <repo> [<repo>...]" >&2; return 64; }
  while [ "$i" -le "$nu" ]; do _add_under "${unders[$i]}"; i=$(( i + 1 )); done
  # Canonicalise the own set once: the worktree loop compares against `pwd -P`
  # paths, so the same normalisation must apply to the names the operator typed.
  i=1
  while [ "$i" -le "$OWN_N" ]; do
    local canon
    canon="$(cd "${OWN_PATHS[$i]}" 2>/dev/null && pwd -P)"
    OWN_SET="${OWN_SET}${canon:-${OWN_PATHS[$i]}}"$'\n'
    i=$(( i + 1 ))
  done
  [ "$APPLY" = 1 ] && MODE="APPLY"
  # Every gh reader is a sweep --pull-only turns off, so skip the auth probe with them.
  local ghs=""; [ "$PULL_ONLY" = 1 ] || ghs="$(_gh_state)"
  i=1
  while [ "$i" -le "$count" ]; do _apply_repo "${repos[$i]}" "$ghs"; i=$(( i + 1 )); done
  echo "== ${MODE} complete. PR merges, deploy dispatch and board rows stay with the command."
  [ "$FAILURES" = 0 ] || return 2
  return 0
}

