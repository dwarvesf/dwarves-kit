# wrap-land.sh -- the land verb and its helpers; sourced by lib/wrap/wrap.sh.


# _tree_verify <repo> <def> <head_oid> <merge_oid> -- "OK", "MISMATCH <n>", or
# "UNVERIFIABLE <reason>". Proves the merge commit gh named sits on the default branch and
# applied exactly the PR's net change: for every path either side touched, the merge
# commit's own diff equals the PR's diff from its merge-base. Whole trees are not compared,
# because a PR that landed on the default branch in between is not the mismatch this guards.
_tree_verify() {
  local repo="$1" def="$2" head_oid="$3" merge_oid="$4" tip parent base p n=0
  git -C "$repo" fetch -q origin "$def" 2>/dev/null || { echo "UNVERIFIABLE fetch of ${def} failed"; return; }
  tip="$(git -C "$repo" rev-parse "origin/${def}" 2>/dev/null)"
  [ -n "$tip" ] || { echo "UNVERIFIABLE origin/${def} did not resolve"; return; }
  git -C "$repo" cat-file -e "${head_oid}^{commit}" 2>/dev/null || {
    echo "UNVERIFIABLE the PR head is not a local object"; return; }
  [ -n "$merge_oid" ] && git -C "$repo" cat-file -e "${merge_oid}^{commit}" 2>/dev/null || {
    echo "UNVERIFIABLE the merge commit ${merge_oid:-gh did not name} is not a local object"; return; }
  git -C "$repo" merge-base --is-ancestor "$merge_oid" "$tip" 2>/dev/null || {
    echo "UNVERIFIABLE the merge commit $(_short "$merge_oid") is not on origin/${def}"; return; }
  if [ "$(git -C "$repo" rev-parse "${merge_oid}^{tree}" 2>/dev/null)" = \
       "$(git -C "$repo" rev-parse "${head_oid}^{tree}" 2>/dev/null)" ]; then
    echo "OK"; return
  fi
  parent="$(git -C "$repo" rev-parse -q --verify "${merge_oid}^1" 2>/dev/null)"
  [ -n "$parent" ] || { echo "UNVERIFIABLE the merge commit has no parent"; return; }
  base="$(git -C "$repo" merge-base "$head_oid" "$parent" 2>/dev/null)"
  [ -n "$base" ] || { echo "UNVERIFIABLE no common history with ${def}"; return; }
  [ -n "$(git -C "$repo" diff-tree -r --name-only "$base" "$head_oid" 2>/dev/null)" ] || {
    echo "UNVERIFIABLE the PR touched no path git can name"; return; }
  while IFS= read -r -d '' p; do
    [ "$(_path_change "$repo" "$base" "$head_oid" "$p")" = \
      "$(_path_change "$repo" "$parent" "$merge_oid" "$p")" ] || n=$((n + 1))
  done < <({ git -C "$repo" diff-tree -r -z --no-renames --name-only "$base" "$head_oid"
             git -C "$repo" diff-tree -r -z --no-renames --name-only "$parent" "$merge_oid"; } 2>/dev/null | sort -zu)
  if [ "$n" -eq 0 ]; then echo "OK"; else echo "MISMATCH ${n}"; fi
}

# _path_change <repo> <from> <to> <path> -- one path's change as a zero-context patch with
# the index and hunk-position lines dropped, so the same edit made on top of a file another
# PR also changed compares equal, while any difference in the added or removed lines does not.
_path_change() {
  git -C "$1" diff-tree -p -U0 --no-renames --binary "$2" "$3" -- ":(literal)$4" 2>/dev/null \
    | grep -v -e '^index ' -e '^@@ '
}

# _land_feature_title <wt> <def> -- the branch's feature-commit subject, for `land`'s
# no-`--title` default. Walks non-merge commits ahead of `origin/<def>`, oldest first
# (`--topo-order`, so a merged-in side commit with an older date never sorts ahead of the
# branch's own first commit), and picks the first whose subject is not a `docs`/`chore`/`test`
# conventional type. Falls back to the oldest non-merge commit ahead when every one is
# housekeeping. Never combines `--reverse` with `-1`/`-n1`: git applies a count limit BEFORE
# reversing, so that would silently return the newest commit instead of the oldest -- the walk
# reads the full list and takes the first line in the shell instead.
_land_feature_title() {
  local wt="$1" def="$2" s
  while IFS= read -r s; do
    printf '%s\n' "$s" | grep -qE '^(docs|chore|test)(\([^)]*\))?!?:' || { printf '%s\n' "$s"; return 0; }
  done < <(git -C "$wt" log --no-merges --topo-order --format=%s --reverse "origin/${def}..HEAD" 2>/dev/null)
  git -C "$wt" log --no-merges --topo-order --format=%s --reverse "origin/${def}..HEAD" 2>/dev/null | head -1
}

# _pr_template <wt> -- the repo's GitHub PR template (path relative to <wt>), empty when it
# has none. File names match case-insensitively, as GitHub reads them.
_pr_template() {
  local wt="$1" d f
  for d in .github . docs; do
    f="$(find "$wt/$d" -maxdepth 1 -type f -iname 'pull_request_template.md' 2>/dev/null | sed -n 1p)"
    [ -n "$f" ] && { printf '%s\n' "${f#"$wt"/}"; return 0; }
  done
  return 1
}

# _rollup_failed_checks <statusCheckRollup json> -- the names of the checks whose latest run
# ended red, comma-joined, empty when none did. Latest run per name wins, the same dedupe
# _pr_gate applies.
_rollup_failed_checks() {
  printf '%s' "$1" | jq -r "${CI_JQ_DEFS}"'
    def rtime: [.completedAt, .startedAt, .createdAt] | map(real) | .[0] // "";
    ((.statusCheckRollup // [])
      | group_by(.name // .context)
      | map(sort_by([(if pending then 1 else 0 end), rtime]) | last)
      | map(select(((.conclusion // .state // "") | ascii_upcase) as $c
            | $c == "FAILURE" or $c == "ERROR" or $c == "CANCELLED" or $c == "TIMED_OUT")
          | (.name // .context // "check")) | join(", "))' 2>/dev/null
}

# _land_pr_checks_gate <wt> <repo-url> <pr> -- before the first merge, let the PR's checks
# report and refuse a red one. A check opened seconds ago has not registered yet, and
# `gh pr merge` does not wait for it, so the merge beat the check and the failure only
# emailed afterwards. A repo with no `pull_request` workflow pays nothing. The wait is the
# ci wait with a short registration grace (KIT_WRAP_LAND_GRACE_SECS) and the usual completion
# bound (KIT_WRAP_CARRY_CHECKS_SECS). Under `--with-ci` that wait already ran, so only the
# verdict is read. Returns 2 with the PR left open.
# ponytail: the workflow test is a plain grep, so a commented-out trigger still arms the wait
# (costs one grace); parse the `on:` block if that ever matters.
KIT_WRAP_LAND_GRACE_SECS=${KIT_WRAP_LAND_GRACE_SECS:-30}
case "$KIT_WRAP_LAND_GRACE_SECS" in ''|*[!0-9]*) KIT_WRAP_LAND_GRACE_SECS=30 ;; esac
_land_pr_checks_gate() {
  local wt="$1" url="$2" n="$3" proll pnum failed
  grep -rqE 'pull_request' "$wt/.github/workflows" 2>/dev/null || return 0
  if ! _ci_on_merge; then
    CI_PRELABEL_KEYS='[]'
    local KIT_WRAP_CI_GRACE_SECS="$KIT_WRAP_LAND_GRACE_SECS"
    _ci_checks_wait "$url" "$n"
  fi
  proll="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null)" \
    && printf '%s' "$proll" | jq -e . >/dev/null 2>&1 || {
    echo "     MERGE REFUSED #${n}: its checks are unreadable; PR left open" >&2; return 2; }
  pnum="$(printf '%s' "$proll" | jq -r "${CI_JQ_DEFS} ([.statusCheckRollup // [] | .[] | select(pending)] | length)" 2>/dev/null)"
  if [ "$pnum" != "0" ]; then
    echo "     MERGE REFUSED #${n}: checks still pending after ${KIT_WRAP_CARRY_CHECKS_SECS}s; PR left open" >&2; return 2
  fi
  failed="$(_rollup_failed_checks "$proll")"
  if [ -n "$failed" ]; then
    echo "     MERGE REFUSED #${n}: checks failed: ${failed}; PR left open" >&2; return 2
  fi
}

# --------------------------------------------------------------------------- land

# cmd_land <worktree> [--title T] [--body-file F] -- the landing loop for ONE committed
# branch in a hand-made worktree: push, open the PR, squash-merge, verify the tree, fast
# forward the main checkout, remove the worktree, delete the branch. Each step prints one
# line with its sha or its refusal.
#
# The composition is deliberate. The push names its branch, because a bare push takes
# whatever the upstream config points at. The merge is its own command, because chaining a
# branch delete behind a failed merge closes the PR and drops its commits. The tree check
# is `merge`'s own `_tree_verify`, never a second copy. Nothing here logs a proof-ledger
# override: a ship-gate refusal on the push surfaces with the gate's own stderr and exit
# code, and the run stops there.
cmd_land() {
  local wt="" title="" body_file="" verify="" arg count=0 want="" flags_given=0
  for arg in "$@"; do
    if [ -n "$want" ]; then
      case "$want" in title) title="$arg" ;; body) body_file="$arg" ;; verify) verify="$arg" ;; esac
      want=""; continue
    fi
    case "$arg" in
      --title) want=title; flags_given=1 ;;
      --title=*) title="${arg#--title=}"; flags_given=1 ;;
      --body-file) want=body; flags_given=1 ;;
      --body-file=*) body_file="${arg#--body-file=}"; flags_given=1 ;;
      --verify) want=verify ;;
      --verify=*) verify="${arg#--verify=}" ;;
      --with-ci) KIT_WRAP_CI_ON_MERGE=1 ;;
      -*) echo "wrap.sh land: unknown flag '$arg'" >&2; return 64 ;;
      *) _reject_packed land "$arg" || return 64
         count=$(( count + 1 )); wt="$arg" ;;
    esac
  done
  [ -z "$want" ] || { echo "wrap.sh land: --${want} needs a value" >&2; return 64; }
  [ "$count" -eq 1 ] || { echo "usage: wrap.sh land <worktree> [--title T] [--body-file F] [--with-ci] [--verify <cmd>]" >&2; return 64; }
  _is_repo "$wt" || { echo "wrap.sh land: ${wt} is not a git worktree" >&2; return 64; }
  if [ -n "$body_file" ] && [ ! -f "$body_file" ]; then
    echo "wrap.sh land: --body-file '${body_file}' is not an existing file" >&2; return 64
  fi
  # git records a worktree fully resolved, so the postcondition below can only match a
  # path resolved the same way.
  wt="$(cd "$wt" 2>/dev/null && pwd -P)" || { echo "wrap.sh land: the worktree path does not resolve" >&2; return 64; }

  local repo; repo="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  repo="${repo%/.git}"; repo="${repo%/}"
  repo="$(cd "$repo" 2>/dev/null && pwd -P)" || { echo "wrap.sh land: the main checkout does not resolve" >&2; return 64; }
  if [ "$repo" = "$wt" ]; then
    echo "wrap.sh land: ${wt} is the main checkout, not a worktree" >&2; return 1
  fi

  # One read serves both the clean check and the baseline _land_tidy needs: what the
  # pre-merge ignore rules cover, written as the `??` lines it shows once a merge un-ignores
  # it. That file is the operator's, not a write made since, and it is the only difference
  # the pre-removal recheck tolerates on the merge path.
  local st0 base_ignored
  st0="$(git -C "$wt" status --porcelain --ignored=matching 2>/dev/null)"
  if [ -n "$(printf '%s\n' "$st0" | grep -v '^!! ')" ]; then
    echo "wrap.sh land: ${wt} is dirty, so the branch is not what a PR would carry" >&2; return 1
  fi
  base_ignored="$(printf '%s\n' "$st0" | sed -n 's/^!! /?? /p')"
  local branch; branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || { echo "wrap.sh land: ${wt} is on a detached HEAD, so there is no branch to land" >&2; return 1; }
  local def; def="$(_default_branch "$wt")" || { echo "wrap.sh land: no default branch resolved for ${wt}" >&2; return 1; }
  case "$branch" in
    "$def"|main|master)
      echo "wrap.sh land: HEAD is ${branch}, the default or a protected branch name" >&2; return 1 ;;
  esac
  local ghs; ghs="$(_gh_state)"
  [ "$ghs" = "ok" ] || { echo "wrap.sh land: gh is ${ghs}" >&2; return 1; }

  # Full refs, as _merge_proof reads them: a tag or local branch named like origin/<def> or
  # the branch resolves first as a short name, so the count and the proof could disagree.
  local fetch_ok=0
  git -C "$wt" fetch -q origin "$def" 2>/dev/null || fetch_ok=1
  local ahead; ahead="$(git -C "$wt" rev-list --count "refs/remotes/origin/${def}..refs/heads/${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac
  [ "$ahead" -gt 0 ] || {
    echo "wrap.sh land: ${branch} has no commits ahead of origin/${def}" >&2; return 1; }

  local tip url rc
  tip="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  url="$(_origin_url "$wt")"
  [ -n "$title" ] || title="$(_land_feature_title "$wt" "$def")"

  echo "land ${branch} -> ${def} (${wt})"

  # A full-lane run opens the PR before land runs (evidence, review), so land checks for
  # that PR first: `gh pr create` on an already-open branch just refuses. Fork entries
  # (isCrossRepository) are dropped before counting, so a fork's same-named branch never
  # counts as the operator's own open PR.
  local open_json openrc
  open_json="$(gh pr list --repo "$url" --head "$branch" --state open \
    --json number,baseRefName,author,isDraft,isCrossRepository 2>/dev/null)"; openrc=$?
  if [ "$openrc" -ne 0 ]; then
    echo "     PR REFUSED: open-PR lookup for ${branch} failed" >&2; return 2
  fi
  # A lookup gh answered with unparseable JSON is a failed lookup, never "no open PR".
  open_json="$(printf '%s' "$open_json" | jq -c '[.[] | select((.isCrossRepository // false) | not)]' 2>/dev/null)" || {
    echo "     PR REFUSED: open-PR lookup for ${branch} failed" >&2; return 2; }
  local open_count; open_count="$(printf '%s' "$open_json" | jq -r 'length' 2>/dev/null)"
  case "$open_count" in ''|*[!0-9]*)
    echo "     PR REFUSED: open-PR lookup for ${branch} failed" >&2; return 2 ;;
  esac

  # The branch's content may already be on the default branch by another route: a squash
  # merge writes a new commit, so `ahead` stays above zero and the branch looks unlanded. The
  # ancestor route cannot fire here (ahead > 0 above), so an ancestor-shaped proof is dropped
  # rather than acted on. A failed fetch proves nothing either way, so it skips the check.
  local proof=""
  if [ "$fetch_ok" -eq 0 ]; then
    proof="$(_merge_proof "$repo" "$def" "$ghs" "$branch")" || proof=""
    case "$proof" in ancestor*) proof="" ;; esac
  fi
  if [ -n "$proof" ]; then
    # The proof can cost a network round trip: the tree and tip it judged must still be the
    # ones on disk.
    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] \
       || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$tip" ]; then
      echo "     LAND REFUSED: ${branch} changed while the merge proof was read" >&2; return 2
    fi
    # The proof is about the LOCAL tip. Origin's copy must be absent or the same commit; a
    # failed read proves nothing, so it refuses (exit 2 of --exit-code is the only "absent").
    local ls_out ls_rc origin_probe osha
    ls_out="$(git -C "$wt" ls-remote --exit-code origin "refs/heads/${branch}" 2>&1)"; ls_rc=$?
    case "$ls_rc" in
      2) origin_probe=absent ;;
      0) # ls-remote matches the pattern as a path suffix, so a tag named
         # refs/tags/refs/heads/<branch> is listed too: only the exact ref counts, and two
         # lines for it is an answer nothing can trust.
         local exact nexact
         exact="$(printf '%s\n' "$ls_out" | awk -F'\t' -v r="refs/heads/${branch}" '$2 == r')"
         nexact="$(printf '%s\n' "$exact" | grep -c .)"
         if [ "$nexact" -gt 1 ]; then
           echo "     LAND REFUSED: origin/${branch} could not be confirmed: ${ls_out}" >&2; return 2
         elif [ "$nexact" -eq 0 ]; then origin_probe=absent
         else
           osha="$(printf '%s' "$exact" | cut -f1)"
           if [ "$osha" = "$tip" ]; then origin_probe=present
           else
             echo "     LAND REFUSED: origin/${branch} ($(_short "$osha")) differs from the proven $(_short "$tip")" >&2
             return 2
           fi
         fi ;;
      *) echo "     LAND REFUSED: origin/${branch} could not be confirmed: ${ls_out}" >&2; return 2 ;;
    esac
    echo "     already landed: ${proof}; nothing to push, no PR opened"
    # A still-open PR (wrap merge's <branch>-squash fallback leaves the original open on
    # purpose) is reported, never closed as a side effect of deleting its branch.
    if [ "$open_count" -ge 1 ]; then
      echo "     PR #$(printf '%s' "$open_json" | jq -r '.[0].number' 2>/dev/null) still open for ${branch}: left untouched" >&2
      return 2
    fi
    # Nothing ran in the tree since the proof, so the only state the removal accepts is clean.
    _land_tidy "$repo" "$wt" "$branch" "$def" "$url" "$tip" "$origin_probe" ""
    return $?
  fi

  # A title-only body skips the repo's PR template (and any check that reads it), so a NEW
  # PR with no --body-file refuses before anything is pushed. An adopted PR keeps its body.
  if [ "$open_count" -eq 0 ] && [ -z "$body_file" ]; then
    local tpl; tpl="$(_pr_template "$wt")"
    if [ -n "$tpl" ]; then
      echo "     PR REFUSED: ${tpl} exists, so a title-only PR body is not allowed; fill it in and pass --body-file <file>" >&2
      return 2
    fi
  fi

  git -C "$wt" push origin "$branch"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "     PUSH REFUSED: git push origin ${branch} exited ${rc}" >&2
    return "$rc"
  fi
  echo "     pushed ${branch} ($(_short "$tip"))"

  local created n
  if [ "$open_count" -gt 1 ]; then
    echo "     PR REFUSED: ${open_count} open PRs for ${branch}" >&2; return 2
  elif [ "$open_count" -eq 1 ]; then
    n="$(printf '%s' "$open_json" | jq -r '.[0].number' 2>/dev/null)"
    case "$n" in
      ''|*[!0-9]*) echo "     PR REFUSED: open-PR lookup for ${branch} named no PR number" >&2; return 2 ;;
    esac
    local open_base; open_base="$(printf '%s' "$open_json" | jq -r '.[0].baseRefName' 2>/dev/null)"
    if [ "$open_base" != "$def" ]; then
      echo "     PR REFUSED: open PR #${n} targets ${open_base}, not ${def}" >&2; return 2
    fi
    # The same login read and case-insensitive compare _open_own_prs uses for `merge`.
    local me; me="$(gh api user --jq .login 2>/dev/null)"
    if [ -z "$me" ]; then
      echo "     PR REFUSED: open PR #${n}: operator login did not resolve" >&2; return 2
    fi
    local open_author; open_author="$(printf '%s' "$open_json" | jq -r '.[0].author.login // ""' 2>/dev/null)"
    if [ "$(printf '%s' "$open_author" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$me" | tr 'A-Z' 'a-z')" ]; then
      echo "     PR REFUSED: open PR #${n} is authored by ${open_author}" >&2; return 2
    fi
    local open_draft; open_draft="$(printf '%s' "$open_json" | jq -r '.[0].isDraft // false' 2>/dev/null)"
    if [ "$open_draft" = "true" ]; then
      gh pr ready "$n" --repo "$url" >/dev/null 2>&1 || {
        echo "     PR REFUSED: open PR #${n} is a draft and gh pr ready failed" >&2; return 2; }
    fi
    echo "     adopted PR #${n}"
    [ "$flags_given" -eq 1 ] && echo "     note: adopted PR #${n} keeps its own title and body" >&2
  else
    # `--head`, never `--base`: a base the caller names is the way a PR ends up targeting
    # another feature branch. With --repo, gh targets the repository's own default branch.
    if [ -n "$body_file" ]; then
      created="$(gh pr create --repo "$url" --head "$branch" --title "$title" --body-file "$body_file" 2>&1)"; rc=$?
    else
      created="$(gh pr create --repo "$url" --head "$branch" --title "$title" --body "$title" 2>&1)"; rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
      echo "     PR REFUSED: gh pr create exited ${rc}: ${created}" >&2; return 2
    fi
    n="$(printf '%s\n' "$created" | tail -1)"; n="${n##*/}"
    case "$n" in
      ''|*[!0-9]*) echo "     PR REFUSED: gh pr create named no PR number: ${created}" >&2; return 2 ;;
    esac
    echo "     opened PR #${n}"
  fi

  # Under `--with-ci`/`KIT_WRAP_CI_ON_MERGE=1` a label-gated repo runs no checks until the
  # PR carries `ci`, so the label goes on before the merge and the runs it starts get a
  # bounded wait. With the gate off (the default), or on a repo without the label, the
  # merge runs as it always did; under the gate, a label that could not be set refuses
  # rather than merging untested.
  if _ci_on_merge; then
    _ci_label_sync "$url" "$n"; rc=$?
    case "$rc" in
      0) _ci_checks_wait "$url" "$n" ;;
      1) ;;
      *) echo "     MERGE FAILED #${n}: the ci label could not be set" >&2; return 2 ;;
    esac
  fi

  _land_pr_checks_gate "$wt" "$url" "$n" || return 2

  _gh_merge_retry "$n" "$url" "$tip"; rc=$?
  if [ "$rc" -ne 0 ]; then
    # A refusal worth answering is CONFLICTING and nothing else: the branch is already
    # pushed, so one merge of origin/<def> into it (never a rebase) is the only move that
    # keeps the published history. Any other verdict keeps today's exit.
    local mdetail mhead m mgen mrc proll pnum pwaited failed_checks
    mdetail="$(_pr_detail_at_head "$url" "$n" "$tip")"
    mhead="$(printf '%s' "$mdetail" | jq -r '.headRefOid // ""' 2>/dev/null)"
    if [ -z "$mdetail" ] || [ -z "$mhead" ]; then
      echo "     MERGE FAILED #${n}: exit ${rc}; the PR state is unreadable, nothing merged" >&2
      return 2
    fi
    if [ "$mhead" != "$tip" ]; then
      echo "     MERGE FAILED #${n}: GitHub still shows head $(_short "$mhead"), not the pushed $(_short "$tip")" >&2
      return 2
    fi
    m="$(printf '%s' "$mdetail" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"
    if [ "$m" != "CONFLICTING" ]; then
      echo "     MERGE FAILED #${n}: exit ${rc}" >&2; return 2
    fi
    echo "     #${n} is CONFLICTING: merging origin/${def} into ${branch}"
    mgen=""; [ -f "$wt/$_RB_GENERATOR" ] && mgen="$wt/$_RB_GENERATOR"
    if [ -n "$verify" ]; then
      _merge_verify_push "$wt" "$branch" "$def" "$tip" "$mgen" "$verify"
    else
      _merge_verify_push "$wt" "$branch" "$def" "$tip" "$mgen"
    fi
    mrc=$?
    case "$mrc" in
      0) ;;
      4) echo "     ${branch} already contains origin/${def}; GitHub's conflict is the union-blind case, run wrap merge --apply --pr ${n}" >&2
         return 2 ;;
      130) return 130 ;;
      *) echo "     PR #${n} left open" >&2; return 2 ;;
    esac

    # From here on the merge commit is on origin whatever happens next, so every exit names
    # it: a rerun that cannot see that sha would merge the wrong head.
    echo "     waiting for GitHub to see $(_short "$MERGED_OID")"
    mdetail="$(_pr_detail_settled "$url" "$n" "$MERGED_OID" "$tip")"
    mhead="$(printf '%s' "$mdetail" | jq -r '.headRefOid // ""' 2>/dev/null)"
    m="$(printf '%s' "$mdetail" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"
    if [ -z "$mdetail" ] || [ -z "$mhead" ]; then
      echo "     #${n} is unreadable after the push; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    if [ "$mhead" = "$tip" ]; then
      echo "     GitHub has not caught up with $(_short "$MERGED_OID"); run wrap merge --apply --pr ${n}; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    if [ "$mhead" != "$MERGED_OID" ]; then
      echo "     PR #${n} head is $(_short "$mhead"), another writer pushed; left open; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    if [ "$m" = "CONFLICTING" ]; then
      echo "     #${n} is still CONFLICTING; run wrap merge --apply --pr ${n}; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    tip="$MERGED_OID"

    if _ci_on_merge; then
      _ci_label_sync "$url" "$n"; rc=$?
      case "$rc" in
        0) _ci_checks_wait "$url" "$n" ;;
        1) ;;
        *) echo "     MERGE FAILED #${n}: the ci label could not be set; the merge commit $(_short "$tip") is on origin" >&2
           return 2 ;;
      esac
      proll="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null)"; rc=$?
    else
      # The pending-only wait holds no grace: a push that starts no checks pays nothing.
      # An unreadable read ends it at once; the single judgment below reads the last
      # answer either way.
      pwaited=0
      while :; do
        proll="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null)"; rc=$?
        [ "$rc" -eq 0 ] && [ -n "$proll" ] || break
        pnum="$(printf '%s' "$proll" | jq -r "${CI_JQ_DEFS} ([.statusCheckRollup // [] | .[] | select(pending)] | length)" 2>/dev/null)"
        case "$pnum" in ''|*[!0-9]*) break ;; esac
        [ "$pnum" -eq 0 ] && break
        [ "$pwaited" -lt "$KIT_WRAP_CARRY_CHECKS_SECS" ] || break
        sleep 10; pwaited=$(( pwaited + 10 ))
      done
    fi
    # The merge commit is already on origin, so what the rollup cannot answer is judged
    # against a state that cannot be taken back: an unreadable read, or checks still
    # pending when the bound ran out, stop the land naming the commit the same way a red
    # check does. A readable rollup with nothing pending -- the empty one of a repo that
    # registered no checks included -- keeps the straight path.
    if [ "$rc" -ne 0 ] || ! printf '%s' "$proll" | jq -e . >/dev/null 2>&1; then
      echo "     checks unreadable on the merged head $(_short "$tip"); the merge commit is on origin" >&2
      return 2
    fi
    pnum="$(printf '%s' "$proll" | jq -r "${CI_JQ_DEFS} ([.statusCheckRollup // [] | .[] | select(pending)] | length)" 2>/dev/null)"
    if [ "$pnum" != "0" ]; then
      echo "     checks still pending on the merged head $(_short "$tip"); the merge commit is on origin" >&2
      return 2
    fi
    # A red check on the merged head stops the land before the second merge: a clean
    # textual merge that broke the build must never land. Latest run per name wins, the
    # same dedupe _pr_gate applies.
    failed_checks="$(_rollup_failed_checks "$proll")"
    if [ -n "$failed_checks" ]; then
      echo "     checks failed on the merged head $(_short "$tip"): ${failed_checks}; the merge commit is on origin" >&2
      return 2
    fi
    _gh_merge_retry "$n" "$url" "$tip"; rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "     MERGE FAILED #${n}: exit ${rc} after the merge cycle; once its checks pass, run wrap merge --apply --pr ${n}; the merge commit $(_short "$tip") is on origin" >&2
      return 2
    fi
  fi

  local after state sha
  after="$(gh pr view "$n" --repo "$url" --json state,mergeCommit 2>/dev/null)"
  state="$(printf '%s' "$after" | jq -r '.state // ""' 2>/dev/null)"
  sha="$(printf '%s' "$after" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)"
  if [ "$state" != "MERGED" ]; then
    echo "     MERGE FAILED #${n}: state is '${state:-unknown}', not MERGED" >&2; return 2
  fi
  local tv; tv="$(_tree_verify "$wt" "$def" "$tip" "$sha")"
  case "$tv" in
    OK) echo "     merged #${n} (${sha}): tree verified" ;;
    MISMATCH*)
      echo "     merged #${n} (${sha}): TREE MISMATCH, ${tv#MISMATCH } paths differ; ${def} does not hold the PR head" >&2
      return 3 ;;
    *)
      echo "     merged #${n} (${sha}): tree ${tv}" >&2
      return 3 ;;
  esac

  # Ship-gate record: `/kit:ship` records `| GATE | ship | ran | shipping pr=#<n>`
  # on its own path (commands/ship.md Step 8); `land` never did, so a spec cycle shipped
  # through `land` instead never trips /kit:wrap step 8's retro-trigger grep. Reuse the
  # existing `rid` verb (cwd'd into the worktree, still on the landed branch -- removal is
  # several steps below) rather than reimplementing its slug rule, and record only when the
  # rid already started a run (a `show` hit), so a plain hand-made land with no spec cycle
  # behind it stays silent. The reason carries `via=land` so this line is distinguishable
  # from one hooks/ship-gate.sh actually gated (it only fires on a literal push/PR-create);
  # /kit:wrap step 8's `shipping pr=#<n>([^0-9]|$)` grep still matches it (the next char is
  # a space). A rid whose ledger already carries a `ship` gate line is never recorded a
  # second time: the same PR number is an idempotent re-land (e.g. /kit:ship already wrote
  # it), a different PR number means this rid's slug is shared by an unrelated branch (a
  # reused `type/` prefix, same stripped slug) and overwriting it would misattribute the
  # line. A failed derive or record never fails the land: one line instead, naming the
  # command to run by hand.
  local land_rid; land_rid="$(cd "$wt" && bash "$GATE_LEDGER_SH" rid 2>/dev/null)" || land_rid=""
  if [ -n "$land_rid" ]; then
    local land_ledger
    if land_ledger="$(bash "$GATE_LEDGER_SH" show "$land_rid" 2>/dev/null)"; then
      local prior_pr
      prior_pr="$(printf '%s\n' "$land_ledger" | grep -i '| GATE | ship |' | grep -oE 'pr=#[0-9]+' | tail -1)"
      if [ "$prior_pr" = "pr=#${n}" ]; then
        echo "     ship gate for ${land_rid} already names pr=#${n}; skipping (already recorded)"
      elif [ -n "$prior_pr" ]; then
        echo "     ship gate for ${land_rid} already names ${prior_pr}, not pr=#${n}; skipping (reused slug, different run)"
      else
        local record_err
        if record_err="$(bash "$GATE_LEDGER_SH" record "$land_rid" Ship ran "shipping pr=#${n} via=land" 2>&1 >/dev/null)"; then
          echo "     recorded ship gate for ${land_rid} (pr=#${n})"
        else
          echo "     ship-gate record FAILED for ${land_rid} (pr=#${n}): ${record_err}; record it by hand: bash ${GATE_LEDGER_SH} record ${land_rid} Ship ran \"shipping pr=#${n} via=land\"" >&2
        fi
      fi
    fi
  fi

  _land_tidy "$repo" "$wt" "$branch" "$def" "$url" "$tip" "" "$base_ignored"
}

# _land_tidy <repo> <wt> <branch> <def> <url> <tip> [<origin_probe> [<allowed>]] -- the tail both land
# paths share once the branch is proven on the default branch: retire the origin branch,
# fast-forward the main checkout, remove the worktree, delete the local branch. <origin_probe>
# is `absent` or `present` when the caller already read origin's copy of the branch; without
# one this reads it itself; only `ls-remote --exit-code` exit 2 counts as gone, any other
# failure falls through to the delete attempt and its own FAILED line. <allowed> is the
# caller's expected tree state: the `status --porcelain` lines the tree may show at removal.
# Empty means clean. The caller takes it before the work that could write, never here, so a
# write made during that work is a difference and not a baseline.
_land_tidy() {
  local repo="$1" wt="$2" branch="$3" def="$4" url="$5" tip="$6" probe="${7:-}" allowed="${8:-}"
  # Mirrors _apply_origin_branches: leased to the tip land itself pushed, skipped when an
  # open PR still bases off this branch (deleting it would close that PR), and never fails
  # land, since the merge is already verified.
  if [ "$(kit_config_get_root wrap.delete_merged_remote_branches true)" != "true" ]; then
    echo "     ${branch} left on origin (wrap.delete_merged_remote_branches=false)"
  else
    if [ -z "$probe" ]; then
      git -C "$wt" ls-remote --exit-code origin "refs/heads/${branch}" >/dev/null 2>&1
      [ "$?" -eq 2 ] && probe=absent
    fi
    local base_open
    if [ "$probe" = "absent" ]; then
      echo "     ${branch} already gone from origin"
      base_open=skip
    else
      base_open="$(gh pr list --repo "$url" --state open --json baseRefName 2>/dev/null \
        | jq -r --arg b "$branch" '[.[] | select(.baseRefName == $b)] | length' 2>/dev/null)"
    fi
    case "$base_open" in
      skip) ;;
      0)
        if git -C "$wt" push -q origin "--force-with-lease=refs/heads/${branch}:${tip}" ":refs/heads/${branch}" 2>/dev/null; then
          echo "     deleted ${branch} on origin"
        else
          echo "     FAILED delete ${branch} on origin (protected, no permission, or pushed since land read it)"
        fi ;;
      ''|*[!0-9]*) echo "     FAILED delete ${branch} on origin (open-PR lookup failed)" ;;
      *) echo "     ${branch} left on origin: an open PR bases off it" ;;
    esac
  fi

  # The fast-forward is advisory: a checkout this call does not own may be dirty or on
  # another branch, and neither is a reason to strand a merged worktree. A dirty file the
  # repo declares merge=union is carried across (_land_ff_pull); any other dirty
  # file is never stashed past and never reset; the refusal is reported and the tidy continues.
  local blocked=0 cur
  cur="$(git -C "$repo" branch --show-current 2>/dev/null)"
  if [ "$cur" != "$def" ]; then
    echo "     PULL BLOCKED: ${repo} is on '${cur:-<detached>}', not ${def}"
    blocked=1
  elif _land_ff_pull "$repo"; then
    echo "     pulled ${repo}: $(git -C "$repo" log --oneline -1 2>/dev/null)"
  else
    echo "     PULL BLOCKED: pull --ff-only refused in ${repo}, nothing was stashed or reset"
    blocked=1
  fi

  # The pull and the origin delete above can cost network round trips, and `-f -f` below
  # discards a dirty tree and `-D` a newer commit, so both are re-read right before the
  # removal. A mismatch skips only the removal; what already ran stands.
  # Any status line outside <allowed> refuses and names its path; an unreadable status does too.
  local st_now st_rc line extra="" detail=""
  st_now="$(git -C "$wt" status --porcelain 2>/dev/null)"; st_rc=$?
  [ "$st_rc" -eq 0 ] || detail=" (status unreadable)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $'\n'"$allowed"$'\n' in *$'\n'"$line"$'\n'*) continue ;; esac
    extra="${line#???}"; detail=" (${extra})"; break
  done <<< "$st_now"
  if [ -n "$detail" ] || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$tip" ]; then
    echo "     ${branch} changed since it was checked${detail}; worktree and branch left in place" >&2
    return 2
  fi

  # `-f -f` overrides the lock the Agent tool puts on every worktree it creates; the merge
  # proof above is what earns the removal. The removal counts only once the path is gone.
  git -C "$repo" worktree remove -f -f "$wt" >/dev/null 2>&1
  if ! _wt_cleared "$repo" "$wt"; then
    echo "     FAILED remove worktree ${wt}: it survived, so ${branch} stays" >&2
    return 2
  fi
  echo "     removed worktree ${wt}"
  if git -C "$repo" branch -D "$branch" >/dev/null 2>&1; then
    echo "     deleted ${branch}"
  else
    echo "     FAILED delete ${branch}" >&2
    return 2
  fi

  [ "$blocked" = 0 ] || return 2
  return 0
}

