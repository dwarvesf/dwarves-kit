# wrap-carry.sh -- stray-line and autoland carry helpers; sourced by lib/wrap/wrap.sh.


# _stray_lines <repo> <def> <path> -- prints, in working-copy order and once each, every
# non-blank line of the working copy that neither origin/<def>'s version nor HEAD's version
# holds: a line written into this checkout that no commit origin can see carries.
_stray_lines() {
  awk 'FNR == NR { seen[$0] = 1; next } $0 != "" && !($0 in seen) { seen[$0] = 1; print }' \
    <(git -C "$1" show "origin/$2:$3" 2>/dev/null; echo; git -C "$1" show "HEAD:$3" 2>/dev/null) "$1/$3"
}

# _stray_board_rows <base-file> <lines-file> -- on a kanban board (backlog.sh's row shape), a
# stray row whose id origin's version already holds is a flipped row: it replaces that row
# in place, and leaves the lines file. Appended instead, it would sit beside origin's old
# copy, and `dedupe-all` keeps the first non-queued copy, which is the stale one when a
# claimed row went shipped. Any other file, and any other line, is left as is.
_stray_board_rows() {
  local base="$1" add="$2" tmp
  grep -qE '^\| *[A-Z]+-[0-9]+ *\|' "$base" || return 0
  tmp="$(mktemp)"
  awk -F'|' 'function rid() { if ($0 !~ /^\| *[A-Z]+-[0-9]+ *\|/) return ""; id = $2; gsub(/^ +| +$/, "", id); return id }
    FNR == NR { if ((i = rid()) != "") row[i] = $0; next }
    { i = rid(); if (i != "" && (i in row)) print row[i]; else print }' "$add" "$base" > "$tmp"
  awk -F'|' 'function rid() { if ($0 !~ /^\| *[A-Z]+-[0-9]+ *\|/) return ""; id = $2; gsub(/^ +| +$/, "", id); return id }
    FNR == NR { if ((i = rid()) != "") have[i] = 1; next }
    { i = rid(); if (i == "" || !(i in have)) print }' "$base" "$add" > "$add.rest"
  mv -f "$tmp" "$base"
  mv -f "$add.rest" "$add"
}

# _autoland_on -- 0 when the operator authorized `apply` to open and merge its own carry PRs.
# Root-only for the same reason as the carry itself: it authorizes a write to origin/<def>.
# wrap.merge_own_prs false wins: an operator who holds back their own PRs holds these too.
# --no-pull is a step 0 stop: the checkout's dirty lines may be another live session's, so
# the branch is pushed and its PR command printed, never merged.
_autoland_on() {
  [ "$NO_PULL" != 1 ] || return 1
  [ "$(kit_config_get_root wrap.autoland_carry false)" = "true" ] \
    && [ "$(kit_config_get_root wrap.merge_own_prs true)" = "true" ]
}

# _carry_branch_ours <repo> <def> <branch> <path> <slug> <oid> -- 0 when <branch> at <oid>
# reads as this file's carry: the exact wrap/stray-<slug>-<stamp> name, a diff from
# origin/<def> touching <path> alone, every line it adds present in the working copy, and no
# line removed except a board row whose id it adds back (the in-place flip the carry makes).
# Opening the PR makes any branch "own", so a look-alike branch is never landed.
_carry_branch_ours() {
  local repo="$1" def="$2" b="$3" f="$4" slug="$5" oid="$6" base d
  printf '%s' "$b" | grep -qxE "wrap/stray-${slug}-[0-9]{8}-[0-9]{4}" || return 1
  base="$(git -C "$repo" merge-base "origin/${def}" "$oid" 2>/dev/null)" || return 1
  [ "$(git -C "$repo" diff --name-only "$base" "$oid")" = "$f" ] || return 1
  d="$(mktemp -d)"
  # Every line before the first hunk is header; after it, a leading + or - is content.
  git -C "$repo" diff -U0 "$base" "$oid" -- "$f" | awk -v d="$d" '
    /^@@/ { h = 1; next }
    h && /^\+/ { print substr($0, 2) > (d "/add") }
    h && /^-/  { print substr($0, 2) > (d "/del") }'
  touch "$d/add" "$d/del"
  if grep -Fxv -f "$repo/$f" "$d/add" | grep -q . \
     || awk -F'|' 'function rid() { if ($0 !~ /^\| *[A-Z]+-[0-9]+ *\|/) return ""; i = $2; gsub(/^ +| +$/, "", i); return i }
          FILENAME == ARGV[1] { if ((i = rid()) != "") back[i] = 1; next }
          { i = rid(); if (i == "" || !(i in back)) { bad = 1 } } END { exit !bad }' "$d/add" "$d/del"; then
    rm -rf "$d"; return 1
  fi
  rm -rf "$d"
}

# _autoland_carry <repo> <def> <branch> <oid> -- lands one carry branch through the door every own PR
# takes: `cmd_merge --apply --pr` (the own-PR check, `_pr_gate`, the union re-merge, the pinned
# squash, `_tree_verify`), never a second merge path. It opens the branch's PR when none is
# open and waits a bounded time for pending checks first. 0 only once a merge verified; a gate
# refusal leaves the PR open for step 3, and a failed merge or tree check sets FAILURES.
# <oid> is the head the caller checked; a branch or PR head anywhere else by the merge refuses,
# so a push landing during the check wait never rides the merge unchecked.
KIT_WRAP_CARRY_CHECKS_SECS=${KIT_WRAP_CARRY_CHECKS_SECS:-300}
case "$KIT_WRAP_CARRY_CHECKS_SECS" in ''|*[!0-9]*) KIT_WRAP_CARRY_CHECKS_SECS=300 ;; esac
_autoland_carry() {
  local repo="$1" def="$2" branch="$3" want="$4" ghs url tip open cnt n title created out rc waited=0 pending
  ghs="$(_gh_state)"
  if [ "$ghs" != "ok" ]; then
    echo "     SKIP land ${branch}: $(_gh_note "$ghs")"
    echo "     open its PR with: gh pr create --head ${branch}"; return 1
  fi
  url="$(_origin_url "$repo")"
  tip="$(git -C "$repo" ls-remote origin "refs/heads/${branch}" 2>/dev/null | cut -f1)"
  [ -n "$tip" ] || { echo "     SKIP land ${branch}: not on origin"; return 1; }
  [ "$tip" = "$want" ] || { echo "     SKIP land ${branch}: origin moved to $(_short "$tip"), not the checked $(_short "$want")"; return 1; }
  # A squash-fallback replacement on <branch>-squash that merged landed this branch too.
  if [ "$(_squash_verdict "$(_squash_json "$url" "$branch")" "$tip" "$def")" = "OK" ] \
     || [ "$(_squash_json "$url" "${branch}-squash" | jq -r --arg d "$def" \
           '[.[] | select(.mergedAt != null and .baseRefName == $d)] | length' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
    echo "     origin/${branch} already merged"; return 0
  fi
  open="$(gh pr list --repo "$url" --head "$branch" --state open --json number,isDraft,isCrossRepository,author 2>/dev/null \
    | jq -c '[.[] | select((.isCrossRepository // false) | not)]' 2>/dev/null)"
  cnt="$(printf '%s' "$open" | jq -r 'length' 2>/dev/null)"
  case "$cnt" in
    0)
      title="$(git -C "$repo" log -1 --format=%s "$tip" 2>/dev/null)"
      [ -n "$title" ] || title="chore: land ${branch}"
      # `--head`, never `--base`: with --repo, gh targets the repository's own default branch.
      created="$(gh pr create --repo "$url" --head "$branch" --title "$title" \
        --body "Carried by \`wrap apply\` from a shared checkout; wrap.autoland_carry lands it." 2>&1)"; rc=$?
      n="$(printf '%s\n' "$created" | tail -1)"; n="${n##*/}"
      if [ "$rc" -ne 0 ] || ! [ "$n" -gt 0 ] 2>/dev/null; then
        echo "     FAILED land ${branch}: gh pr create exited ${rc}: ${created}"; FAILURES=1; return 1
      fi
      echo "     opened PR #${n} for ${branch}" ;;
    1)
      n="$(printf '%s' "$open" | jq -r '.[0].number')"
      local me; me="$(gh api user --jq .login 2>/dev/null)"
      if [ -z "$me" ] || [ "$(printf '%s' "$open" | jq -r '.[0].author.login // ""' | tr 'A-Z' 'a-z')" != "$(printf '%s' "$me" | tr 'A-Z' 'a-z')" ]; then
        echo "     SKIP land ${branch}: its PR #${n} is not authored by you"; return 1
      fi
      # Marking a draft ready is the lead's call, made by naming it to `merge --pr`.
      if [ "$(printf '%s' "$open" | jq -r '.[0].isDraft // false')" = "true" ]; then
        echo "     SKIP land ${branch}: its PR #${n} is a draft"; return 1
      fi
      echo "     adopted PR #${n} for ${branch}" ;;
    *) echo "     SKIP land ${branch}: the open-PR lookup failed or found several"; return 1 ;;
  esac
  # On an opted-in ci-gated repo the label sync arms the checks, which the plain wait
  # below would otherwise read as "nothing pending" and merge untested; sync the label
  # first, then wait for the runs it starts. With the gate off (the default) a merge
  # takes the wait it always did, as does a repo without the label; under the gate, a
  # label that could not be set refuses the land rather than landing untested.
  if _ci_on_merge; then
    _ci_label_sync "$url" "$n"; rc=$?
    case "$rc" in
      0) _ci_checks_wait "$url" "$n" ;;
      2) echo "     SKIP land ${branch}: PR #${n} is unlabeled on a ci-gated repo; left open"; return 1 ;;
    esac
  else rc=1; fi
  if [ "$rc" -eq 1 ]; then
  # Pending: a check still running, or no check reported yet on a merge state that is not
  # CLEAN, which is what a PR opened seconds ago shows before its checks register.
  while :; do
    pending="$(gh pr view "$n" --repo "$url" --json statusCheckRollup,mergeStateStatus 2>/dev/null | jq -r "${CI_JQ_DEFS}"'
      (.statusCheckRollup // []) as $r
      | if ($r | length) == 0 then (if ((.mergeStateStatus // "") | IN("CLEAN", "DIRTY", "BEHIND")) then 0 else 1 end)
        else [$r[] | select(pending)] | length end' 2>/dev/null)"
    [ "${pending:-0}" -gt 0 ] 2>/dev/null && [ "$waited" -lt "$KIT_WRAP_CARRY_CHECKS_SECS" ] || break
    sleep 10; waited=$(( waited + 10 ))
  done
  fi
  tip="$(gh pr view "$n" --repo "$url" --json headRefOid 2>/dev/null | jq -r '.headRefOid // ""' 2>/dev/null)"
  if [ "$tip" != "$want" ]; then
    echo "     SKIP land ${branch}: PR #${n} head is $(_short "$tip"), not the checked $(_short "$want"); left open"; return 1
  fi
  # A subshell keeps merge's globals (REMERGE_OID, SQ_PR, SQ_OID) out of this run.
  out="$( (cmd_merge --apply --pr "$n" "$repo") 2>&1)"; rc=$?
  printf '%s\n' "$out" | sed '/^[[:space:]]*$/d; s/^/       /'
  if [ "$rc" -ne 0 ]; then FAILURES=1; return 1; fi
  printf '%s\n' "$out" | grep -qE '^merged #[0-9]+ \(.*\): tree verified' || {
    echo "     PR #${n} left open; wrap merge --apply --pr ${n} merges it once green"; return 1; }
  # The squash fallback landed a replacement; the original stays open unless closed here, and
  # an open own PR on this branch is what the next pass would adopt and land a second time.
  if printf '%s\n' "$out" | grep -q "^superseded #${n}:"; then
    gh pr close "$n" --repo "$url" --comment "Landed by its squash-equivalent replacement." >/dev/null 2>&1 \
      && echo "     closed superseded PR #${n}" \
      || { echo "     FAILED close superseded PR #${n}; close it by hand"; FAILURES=1; }
  fi
  return 0
}

# _carry_stray_file <repo> <def> <path> <lines-file> <n> -- commits origin/<def>'s version of
# the file plus the stray lines onto a new branch in a scratch worktree and pushes it. The
# lines land below the `---` anchor when the file has one, the rule the union carry uses,
# else at the end. The main checkout's working copy is never touched. Opens no PR unless
# wrap.autoland_carry lands the branch.
_carry_stray_file() {
  local repo="$1" def="$2" f="$3" add="$4" n="$5" slug branch wt base head_n name held b boid all=1
  if [ "$(kit_config_get_root wrap.carry_stray_lines true)" != "true" ]; then
    echo "     ${n} stray lines in ${f} stay in the working copy (wrap.carry_stray_lines=false)"; return 0
  fi
  slug="$(printf '%s' "$f" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"
  # An open carry branch for this file means an earlier run already carried; a second one
  # would duplicate the lines. They stay in the working copy until that branch merges, which
  # wrap.autoland_carry does here: land every such branch, then carry only what is left.
  held="$(git -C "$repo" ls-remote --heads origin "wrap/stray-${slug}-*" 2>/dev/null | sed 's|.*refs/heads/||')"
  if [ -n "$held" ] && [ "$APPLY" = 1 ] && _autoland_on; then
    while IFS= read -r b; do
      boid="$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/${b}")"
      if [ -n "$boid" ] && _carry_branch_ours "$repo" "$def" "$b" "$f" "$slug" "$boid"; then
        _autoland_carry "$repo" "$def" "$b" "$boid" || all=0
      else
        echo "     SKIP land ${b}: not a carry of ${f} alone, or adds lines this checkout lacks"; all=0
      fi
    done <<< "$held"
    if [ "$all" = 1 ]; then
      git -C "$repo" fetch -q origin "$def" 2>/dev/null || {
        echo "     SKIP ${f}: the carry landed, but fetching origin/${def} failed; the next pass carries the rest"; return 0; }
      _stray_lines "$repo" "$def" "$f" > "$add"
      n="$(grep -c '' "$add")"
      [ "$n" -gt 0 ] 2>/dev/null || { echo "     ${f}: the landed carry held every stray line"; return 0; }
      held=""
    fi
  fi
  if [ -n "$held" ]; then
    echo "     SKIP ${f}: ${n} stray lines, but an origin wrap/stray-${slug}-* branch already carries this file; merge it first"
    [ "$APPLY" != 1 ] && _autoland_on && echo "     WOULD open and merge its PR (wrap.autoland_carry=true)"
    return 0
  fi
  if [ "$APPLY" != 1 ]; then
    echo "     WOULD carry ${n} stray lines in ${f} onto a branch"
    _autoland_on && echo "     WOULD open and merge its PR (wrap.autoland_carry=true)"
    return 0
  fi
  branch="wrap/stray-${slug}-$(date +%Y%m%d-%H%M)"
  wt="$(_scratch_wt_add "$repo" "origin/${def}")" || {
    echo "     FAILED carry ${f}: a scratch worktree at origin/${def} failed"; FAILURES=1; return 0; }
  base="$(mktemp)"
  git -C "$repo" show "origin/${def}:${f}" > "$base" 2>/dev/null
  # A last line with no newline would fuse with the first carried line.
  [ -s "$base" ] && [ -n "$(tail -c 1 "$base")" ] && echo >> "$base"
  _stray_board_rows "$base" "$add"
  mkdir -p "$(dirname "$wt/$f")"
  head_n="$(_log_anchor_head_lines "$base")"
  if [ "$head_n" -gt 0 ] 2>/dev/null; then
    { sed -n "1,${head_n}p" "$base"; cat "$add"; tail -n "+$(( head_n + 1 ))" "$base"; } > "$wt/$f"
  else
    cat "$base" "$add" > "$wt/$f"
  fi
  # The same dedupe the union re-merge runs, as a net for a board the rows above missed.
  grep -qE '^\| *[A-Z]+-[0-9]+ *\|' "$wt/$f" && bash "$BACKLOG_SH" dedupe-all "$wt/$f" >/dev/null 2>&1
  name="${f##*/}"; name="${name%.*}"
  if git -C "$wt" add -- "$f" >/dev/null 2>&1 \
     && git -C "$wt" commit -q -m "chore(${name}): carry ${n} stray lines from a shared checkout" >/dev/null 2>&1 \
     && git -C "$wt" push -q origin "HEAD:refs/heads/${branch}" >/dev/null 2>&1; then
    echo "     carried ${n} stray lines in ${f} to origin/${branch}"
    if _autoland_on; then _autoland_carry "$repo" "$def" "$branch" "$(git -C "$wt" rev-parse HEAD)"
    else echo "     open its PR with: gh pr create --head ${branch}"; fi
  else
    echo "     FAILED carry ${n} stray lines in ${f} to ${branch}: the commit or the push refused"
    FAILURES=1
  fi
  _scratch_wt_drop "$repo" "$wt"
  rm -f "$base"
}

# _carry_stray <repo> <def> -- the stray-lines report. A session that writes a union-marked
# file (`board set`, `wrap log`) in the SHARED main checkout leaves its lines in that
# working tree only; the union carry keeps them across a pull, but nothing ever takes them
# to origin. For each dirty union-marked tracked file this names the lines origin lacks and,
# under --apply, carries them to a branch of their own.
_carry_stray() {
  local repo="$1" def="$2" f add n found=0 gd cd_
  echo "-- stray lines:"
  gd="$(git -C "$repo" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  cd_="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -z "$gd" ] || [ "$gd" != "$cd_" ]; then echo "     SKIP stray lines: not the main checkout"; return 0; fi
  while IFS= read -r -d '' f; do
    [ -f "$repo/$f" ] && _union_marked "$repo" "$f" || continue
    add="$(mktemp)"
    _stray_lines "$repo" "$def" "$f" > "$add"
    n="$(grep -c '' "$add")"
    if [ "$n" -gt 0 ] 2>/dev/null; then
      found=1
      _carry_stray_file "$repo" "$def" "$f" "$add" "$n"
    fi
    rm -f "$add"
  done < <(git -C "$repo" diff HEAD --name-only -z 2>/dev/null)
  [ "$found" = 1 ] || echo "     none"
}

# _carry_stray_commits <repo> <def> -- the stray-commits step, main checkout on <def> only.
# A session that COMMITS on the shared checkout's default branch and never pushes leaves it
# ahead of origin, and every later `pull --ff-only` refuses as diverging. Under --apply the
# commits go to a wrap/stray-commits-<stamp> branch on origin (a local branch of the same
# name keeps them too), and <def> moves back with `reset --keep` to where it left
# origin/<def>; the pull that follows fast-forwards it the rest of the way. The fork point,
# not origin/<def> itself, is the target: `--keep` refuses a dirty file the target changes,
# and origin changes the union-marked board and log on every merge. The move needs a tree
# whose only dirty tracked files are unstaged merge=union files the commits do not change
# (the pull carries those) and origin holding the commits. Opens no PR.
_carry_stray_commits() {
  local repo="$1" def="$2" gd cd_ ahead head fork f tip ref branch="" landed="" pid
  local staged changed dirty="" overlap="" block="" err where
  echo "-- stray commits:"
  gd="$(git -C "$repo" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  cd_="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -z "$gd" ] || [ "$gd" != "$cd_" ]; then echo "     SKIP stray commits: not the main checkout"; return 0; fi
  ahead="$(git -C "$repo" rev-list --count "origin/${def}..HEAD" 2>/dev/null)"
  if ! [ "$ahead" -gt 0 ] 2>/dev/null; then echo "     none"; return 0; fi
  if [ "$(kit_config_get_root wrap.carry_stray_lines true)" != "true" ]; then
    echo "     ${ahead} stray commits on ${def} stay local (wrap.carry_stray_lines=false)"; return 0
  fi
  head="$(git -C "$repo" rev-parse HEAD)"
  fork="$(git -C "$repo" merge-base "$head" "origin/${def}" 2>/dev/null)"
  [ -n "$fork" ] || { echo "     SKIP stray commits: ${def} shares no history with origin/${def}"; return 0; }

  # A staged union file blocks too: the pull skips its union carry while the index is dirty.
  # A dirty union file the commits change is one `reset --keep` would refuse.
  staged="$(git -C "$repo" diff --cached --name-only 2>/dev/null)"
  changed="$(git -C "$repo" diff --name-only "$fork" "$head" 2>/dev/null)"
  while IFS= read -r -d '' f; do
    if [ -f "$repo/$f" ] && _union_marked "$repo" "$f" && ! printf '%s\n' "$staged" | grep -qxF -- "$f"; then
      printf '%s\n' "$changed" | grep -qxF -- "$f" && overlap="${overlap}${overlap:+, }${f}"
      continue
    fi
    dirty="${dirty}${dirty:+, }${f}"
  done < <(git -C "$repo" diff HEAD --name-only -z 2>/dev/null)
  if [ -n "$dirty" ]; then block="dirty tracked files block the move: ${dirty}"
  elif [ -n "$overlap" ]; then block="dirty files the stray commits change block the move: ${overlap}"; fi

  # A carry PR that squash-merged put the commits' whole change on origin as one commit, and
  # the branch sweeps then deleted the carry branch. Pushing again would open a duplicate.
  pid="$(git -C "$repo" diff "$fork" "$head" | git patch-id --stable | cut -d' ' -f1)"
  [ -n "$pid" ] && landed="$(git -C "$repo" log -p --no-merges "${fork}..origin/${def}" \
    | git patch-id --stable | awk -v p="$pid" '$1 == p { print $2; exit }')"

  if [ "$APPLY" != 1 ]; then
    if [ -n "$landed" ]; then
      echo "     the ${ahead} stray commits on ${def} already landed on origin/${def} as $(git -C "$repo" rev-parse --short "$landed"); nothing to carry"
    else
      echo "     WOULD carry ${ahead} stray commits on ${def} onto a branch:"
      git -C "$repo" log --format='       %h %s' "origin/${def}..HEAD"
      [ -z "$block" ] && _autoland_on && echo "     WOULD open and merge its PR (wrap.autoland_carry=true)"
    fi
    if [ -n "$block" ]; then echo "     ${def} would stay ahead: ${block}"
    else echo "     WOULD move ${def} back to origin/${def}"; fi
    return 0
  fi
  _write_guard "$repo" || { echo "     SKIP stray commits: index.lock held by another writer"; return 0; }

  if [ -n "$landed" ]; then
    where="origin/${def} as $(git -C "$repo" rev-parse --short "$landed")"
    echo "     the ${ahead} stray commits on ${def} already landed on ${where}; nothing to carry"
  else
    # An earlier run that pushed but could not move left its branch on origin. The tip test
    # comes first: a narrow fetch refspec never downloads that branch's objects.
    while read -r tip ref; do
      case "$ref" in refs/heads/wrap/stray-commits-*) ;; *) continue ;; esac
      if [ "$tip" = "$head" ] || git -C "$repo" merge-base --is-ancestor "$head" "$tip" 2>/dev/null; then
        branch="${ref#refs/heads/}"; break
      fi
    done < <(git -C "$repo" ls-remote --heads origin 'wrap/stray-commits-*' 2>/dev/null)
    if [ -n "$branch" ]; then
      git -C "$repo" rev-parse -q --verify "refs/heads/${branch}" >/dev/null \
        || git -C "$repo" branch "$branch" "$head" >/dev/null 2>&1
      echo "     origin/${branch} already carries the ${ahead} stray commits on ${def}"
    else
      branch="wrap/stray-commits-$(date +%Y%m%d-%H%M)"
      # A same-minute rerun after a refused push finds its own local branch at HEAD.
      if { [ "$(git -C "$repo" rev-parse -q --verify "refs/heads/${branch}")" = "$head" ] \
           || git -C "$repo" branch "$branch" "$head" >/dev/null 2>&1; } \
         && git -C "$repo" push -q origin "refs/heads/${branch}:refs/heads/${branch}" >/dev/null 2>&1; then
        echo "     carried ${ahead} stray commits on ${def} to origin/${branch}"
      else
        echo "     FAILED carry ${ahead} stray commits on ${def} to ${branch}: the branch or the push refused"
        FAILURES=1; return 0
      fi
    fi
    # Landed only when the move can follow and the branch holds exactly HEAD: a squash with
    # <def> still ahead is re-carried by the next pass whenever patch ids stop matching.
    tip="$(git -C "$repo" ls-remote origin "refs/heads/${branch}" 2>/dev/null | cut -f1)"
    if _autoland_on && [ -z "$block" ] && [ "$tip" = "$head" ]; then
      _autoland_carry "$repo" "$def" "$branch" "$head"
    else
      echo "     open its PR with: gh pr create --head ${branch}"
      _autoland_on && echo "     not landed: ${block:-origin/${branch} holds more than HEAD}"
    fi
    where="$branch"
  fi
  [ -z "$block" ] || { echo "     ${def} left ahead: ${block}"; return 0; }

  # The move is safe only once origin itself holds every commit it moves away from.
  if [ -z "$landed" ]; then
    tip="$(git -C "$repo" ls-remote origin "refs/heads/${branch}" 2>/dev/null | cut -f1)"
    if [ -z "$tip" ] || { [ "$tip" != "$head" ] && ! git -C "$repo" merge-base --is-ancestor "$head" "$tip" 2>/dev/null; }; then
      echo "     ${def} left ahead: origin/${branch} does not hold HEAD"; return 0
    fi
  fi
  if [ "$(git -C "$repo" rev-parse HEAD)" != "$head" ]; then
    echo "     ${def} left ahead: HEAD moved during the step"; return 0
  fi
  if ! err="$(git -C "$repo" reset -q --keep "$fork" 2>&1)"; then
    echo "     ${def} left ahead: git reset --keep refused: $(printf '%s' "$err" | head -n 1)"; return 0
  fi
  # A commit that landed between the check above and the reset is on no branch now; put it back.
  if [ "$(git -C "$repo" rev-parse ORIG_HEAD 2>/dev/null)" != "$head" ]; then
    git -C "$repo" reset -q --keep ORIG_HEAD 2>/dev/null
    echo "     ${def} left ahead: HEAD moved during the step, restored"; return 0
  fi
  if [ "$fork" = "$(git -C "$repo" rev-parse "origin/${def}")" ]; then
    echo "     moved ${def} back to origin/${def}; the ${ahead} commits live on ${where}"
  else
    echo "     moved ${def} back to $(git -C "$repo" rev-parse --short "$fork"), where it left origin/${def}; the ${ahead} commits live on ${where}"
  fi
}
