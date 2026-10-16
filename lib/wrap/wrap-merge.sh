# wrap-merge.sh -- the merge verb and its helpers; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- merge

# _pr_detail <url> <number> -- the fields every merge gate reads.
_pr_detail() {
  gh pr view "$2" --repo "$1" \
    --json number,title,body,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft 2>/dev/null
}

# _pr_gate <json> <default branch> -- "OK" or "SKIP <reason>". mergeStateStatus carries the
# unresolved-conversation signal: gh pr view has no reviewThreads field, and BLOCKED is the
# state GitHub reports for an unresolved thread or an unmet review requirement. Anything but
# a clean state fails closed here. An empty or null rollup proves nothing on its own, so it
# passes only when GitHub itself reports the merge state as CLEAN. A draft reports
# mergeable=MERGEABLE and mergeStateStatus=CLEAN on a free private repo, so the draft check
# runs first: a draft is never eligible no matter what the rest of the state says.
#
# `gh pr view --json statusCheckRollup` returns one entry per check RUN, not per check name:
# a re-run of the same job (e.g. a flaky check re-triggered) leaves both the old FAILURE run
# and the new SUCCESS run in the array. Grouping by name and keeping only the run with the
# latest real time mirrors what `gh pr checks` already shows and what GitHub's own merge
# button honors. gh reports a pending run's completedAt as the zero time 0001-01-01T00:00:00Z,
# never null, so `rtime` takes the first time that is neither null, empty, nor zero. Every
# pending entry sorts last in its group whatever its time: a SKIPPED run from a later
# `labeled` event completes after an IN_PROGRESS `ci` run started, and keyed on time alone
# it would stand in as the verdict for an untested head. The cost is fail-closed: a pending
# entry a newer run superseded blocks its name until it completes or is cancelled.
#
# The rollup also mixes two GitHub types: CheckRun (`.name`, `.completedAt`/`.startedAt`,
# `.conclusion`) and StatusContext (`.context`, `.startedAt`, `.targetUrl`, `.state`, no
# `.name` at all).
# Grouping on `.name` alone puts every StatusContext entry (all `.name == null`) into ONE
# group, so two distinct commit statuses collapse into a single row and only the last one
# survives -- a real failing status can be hidden behind a later, unrelated passing one.
# `.name // .context` keys each type by its own identifier; `rtime` walks completedAt,
# startedAt, createdAt to cover both types' timestamp fields.
_pr_gate() {
  printf '%s' "$1" | jq -r --arg def "$2" "${CI_JQ_DEFS}"'
    def rtime: [.completedAt, .startedAt, .createdAt] | map(real) | .[0] // "";
    def checks: (.statusCheckRollup // [])
      | group_by(.name // .context)
      | map(sort_by([(if pending then 1 else 0 end), rtime]) | last);
    if (.isDraft == true) then "SKIP draft"
    elif (.baseRefName != $def) then "SKIP base is \(.baseRefName), not the default branch \($def)"
    elif (.mergeable != "MERGEABLE") then "SKIP not mergeable (\(.mergeable // "unknown"))"
    elif ((checks | length) == 0 and ((.mergeStateStatus // "") != "CLEAN"))
      then "SKIP checks are pending or failing"
    elif ((checks | map(select(((.conclusion // .state // "") | ascii_upcase) as $c
                               | $c != "SUCCESS" and $c != "SKIPPED")) | length) > 0)
      then "SKIP checks are pending or failing"
    elif (.reviewDecision == "CHANGES_REQUESTED") then "SKIP changes requested"
    elif ((.mergeStateStatus // "CLEAN") as $m
          | $m != "CLEAN" and $m != "HAS_HOOKS" and $m != "UNSTABLE")
      then "SKIP merge state \(.mergeStateStatus) (an unresolved thread or a blocked merge)"
    else "OK" end' 2>/dev/null
}

# _pr_detail_settled <url> <number> [<pushed-oid> <prior-oid>] -- the detail read once
# GitHub has recomputed mergeability. GitHub computes it asynchronously after a push: for
# ten to twenty seconds it can serve UNKNOWN, or the OLD head with its old CONFLICTING
# verdict, and a gate reading inside that window refuses a PR that is fine. Without a
# pushed oid the wait lasts while the field reads UNKNOWN. With one (wrap's own push) it
# also lasts while the head is still the prior one or the verdict is CONFLICTING, and ends
# at once on a head that is neither: another writer pushed, and the caller refuses that.
# Bounded by KIT_WRAP_SETTLE_SECS, one read every 2s; the last read is returned either way,
# so a verdict that never settles still fails closed rather than spinning.
KIT_WRAP_SETTLE_SECS=${KIT_WRAP_SETTLE_SECS:-60}
case "$KIT_WRAP_SETTLE_SECS" in ''|*[!0-9]*) KIT_WRAP_SETTLE_SECS=60 ;; esac
_pr_detail_settled() {
  local url="$1" n="$2" want="${3:-}" prior="${4:-}" waited=0 detail="" m h
  while :; do
    detail="$(_pr_detail "$url" "$n")"
    m="$(printf '%s' "$detail" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"
    if [ -z "$want" ]; then
      [ "$m" = "UNKNOWN" ] || break
    else
      h="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
      # An empty head is a failed read, not a moved head: keep waiting.
      [ -z "$h" ] || [ "$h" = "$want" ] || [ "$h" = "$prior" ] || break
      [ "$h" = "$want" ] && [ "$m" != "UNKNOWN" ] && [ "$m" != "CONFLICTING" ] && break
    fi
    [ "$waited" -lt "$KIT_WRAP_SETTLE_SECS" ] || break
    sleep 2; waited=$(( waited + 2 ))
  done
  printf '%s' "$detail"
}

# _pr_detail_at_head <url> <number> <tip> -- the detail read after a refused merge, pinned
# to the pushed tip: GitHub can still serve the pre-push head inside the settle window, and
# a CONFLICTING verdict against the old head would answer for a branch that no longer
# exists. It waits until headRefOid is <tip> and mergeable is computed, one read every 2s
# bounded by KIT_WRAP_SETTLE_SECS, and returns the last read either way. Unlike
# _pr_detail_settled it does not keep waiting on CONFLICTING: a real conflict is the answer
# the read exists to find.
_pr_detail_at_head() {
  local url="$1" n="$2" tip="$3" waited=0 detail="" m h
  while :; do
    detail="$(_pr_detail "$url" "$n")"
    h="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
    m="$(printf '%s' "$detail" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"
    [ "$h" = "$tip" ] && [ "$m" != "UNKNOWN" ] && break
    [ "$waited" -lt "$KIT_WRAP_SETTLE_SECS" ] || break
    sleep 2; waited=$(( waited + 2 ))
  done
  printf '%s' "$detail"
}

# _resync_state <url> <number> -- the PR's state as OPEN, CLOSED or MERGED, else
# `unreadable`. Nothing GitHub returns is echoed unless it is one of the three words.
_resync_state() {
  local s
  s="$(gh pr view "$2" --repo "$1" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null)"
  case "$s" in OPEN|CLOSED|MERGED) printf '%s' "$s" ;; *) printf 'unreadable' ;; esac
}

# _url_public <url> -- <url> without userinfo, for a command printed to a human. Greedy up
# to the last @ before the first /, so a raw @ inside a password goes too.
_url_public() { printf '%s' "$1" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/]*@#\1#'; }

# _resync_reopen_after_interrupt -- one reopen on behalf of an interrupted resync; prints
# its outcome to stderr.
_resync_reopen_after_interrupt() {
  if gh pr reopen "$_RS_N" --repo "$_RS_URL" >/dev/null 2>&1; then
    _RS_REOPENED=1
    echo "reopened #${_RS_N} after the interrupt" >&2
  else
    echo "could not reopen #${_RS_N} after the interrupt; reopen it: gh pr reopen ${_RS_N} --repo ${_RS_PUB}" >&2
  fi
}

# _resync_trap -- INT/TERM/HUP inside `_pr_head_resync`. Shaped like `_mvp_trap`: the first
# line ignores the signals (and PIPE, so a closed carry pipe cannot end it mid-reopen) until
# the caller's handlers go back, it sets the flag the helper checks, and it never calls
# `exit`. Before the close is under way there is nothing to undo and no network call. Once
# it is, the recovery command goes to stderr first, then one state read decides: exactly
# CLOSED gets one reopen; anything else is reported, never acted on.
_resync_trap() {
  trap '' INT TERM HUP PIPE
  _RS_HIT=1
  if [ -z "$_RS_CLOSING" ]; then
    echo "INTERRUPTED inside the resync of #${_RS_N} before the close; nothing changed on GitHub" >&2
    return
  fi
  echo "INTERRUPTED inside the resync of #${_RS_N}; if #${_RS_N} is closed, reopen it: gh pr reopen ${_RS_N} --repo ${_RS_PUB}" >&2
  local s
  s="$(_resync_state "$_RS_URL" "$_RS_N")"
  case "$s" in
    CLOSED) _resync_reopen_after_interrupt ;;
    OPEN) echo "#${_RS_N} is still open after the interrupt; nothing to undo" >&2 ;;
    *) echo "#${_RS_N} state reads '${s}' after the interrupt, so no reopen was tried; check it: gh pr view ${_RS_N} --repo ${_RS_PUB}" >&2 ;;
  esac
}

# _pr_head_resync <repo> <url> <n> <branch> <prior-oid> <pushed-oid> -- one close and
# reopen of an own PR whose head GitHub never re-read after wrap's own push. GitHub can
# keep serving the pre-push head long past the settle window; a close and a reopen makes
# it re-read the head ref. It acts only on proof that wrap's push is the only difference:
# the PR is OPEN, not a draft, not from a fork, no auto-merge armed, still on <prior-oid>,
# and origin's branch tip is exactly <pushed-oid>. It never merges and never reads the
# verdict. Returns 0 resynced, 3 caught up (no close ran), 1 no resync (the last read
# showed the PR open and unchanged), 2 needs a human, 130 interrupted. Prints every line
# it owns. Runs in the current shell: the trap and its flag live here, so never call it
# inside $(...).
#
# This wrapper owns the trap's whole life: it saves the caller's handlers, arms the trap,
# runs the body, and restores the handlers once, whichever way the body returned. A signal
# can land after the body's last flag check and before `gh pr close` starts; the handler
# then reads OPEN and the close still runs. So after any interrupt once the close was under
# way, and with no reopen on record, one more state read decides, and exactly CLOSED gets
# a reopen.
_pr_head_resync() {
  local rc ti tt th tp
  _RS_HIT=""; _RS_CLOSING=""; _RS_REOPENED=""; _RS_COMMENT=""
  _RS_N="$3"; _RS_URL="$2"; _RS_PUB="$(_url_public "$2")"
  ti="$(trap -p INT)"; tt="$(trap -p TERM)"; th="$(trap -p HUP)"; tp="$(trap -p PIPE)"
  trap '_resync_trap' INT TERM HUP
  _pr_head_resync_body "$@"; rc=$?
  if [ -n "$_RS_HIT" ] && [ -n "$_RS_CLOSING" ] && [ -z "$_RS_REOPENED" ] \
     && [ "$(_resync_state "$_RS_URL" "$_RS_N")" = "CLOSED" ]; then
    _resync_reopen_after_interrupt
  fi
  if [ -n "$ti" ]; then eval "$ti"; else trap - INT; fi
  if [ -n "$tt" ]; then eval "$tt"; else trap - TERM; fi
  if [ -n "$th" ]; then eval "$th"; else trap - HUP; fi
  if [ -n "$tp" ]; then eval "$tp"; else trap - PIPE; fi
  [ -n "$_RS_HIT" ] && return 130
  # A best-effort trail on the PR, after the trap is gone: static text plus short oids only.
  if [ -n "$_RS_COMMENT" ]; then
    gh pr comment "$3" --repo "$2" --body "$_RS_COMMENT" >/dev/null 2>&1 \
      || echo "     comment on #${3} failed; the resync itself is unaffected"
  fi
  return "$rc"
}

# _pr_head_resync_body -- the steps of `_pr_head_resync`, under its trap. Plain returns;
# the wrapper restores the handlers and turns a set flag into 130.
_pr_head_resync_body() {
  local repo="$1" url="$2" n="$3" branch="$4" prior="$5" pushed="$6"
  local pre head reason tips tip rc s tries

  # Step 1: a fresh read right before acting. Every field must be present; a missing one
  # fails its test, never a `// false` default that would read it as a pass.
  pre="$(gh pr view "$n" --repo "$url" --json state,isDraft,isCrossRepository,headRefOid,autoMergeRequest 2>/dev/null)"
  [ -z "$_RS_HIT" ] || return 130  # pre-close check: interrupted during the read
  head="$(printf '%s' "$pre" | jq -r '.headRefOid // ""' 2>/dev/null)"
  case "$head" in *[!0-9a-f]*|'') head="" ;; esac
  [ "${#head}" -eq 40 ] || head=""
  if [ -n "$head" ] && [ "$head" = "$pushed" ]; then
    echo "     #${n} caught up on its own; no resync needed"
    return 3
  fi
  reason="unreadable PR state"
  if [ -n "$pre" ]; then
    reason="$(printf '%s' "$pre" | jq -r '
      if type != "object" then "unreadable PR state"
      elif .state != "OPEN" then
        "state " + ((.state // "") as $s | if $s == "CLOSED" or $s == "MERGED" then $s else "unreadable" end)
      elif .isDraft != false then "isDraft is not false"
      elif .isCrossRepository != false then "a fork PR or unreadable"
      elif (has("autoMergeRequest") | not) or .autoMergeRequest != null then "auto-merge armed or unreadable"
      else "" end' 2>/dev/null)" || reason="unreadable PR state"
  fi
  if [ -z "$reason" ] && [ "$head" != "$prior" ]; then
    if [ -n "$head" ]; then reason="head moved to $(_short "$head")"; else reason="unreadable PR state"; fi
  fi
  if [ -n "$reason" ]; then
    echo "     no resync for #${n}: ${reason}"
    return 1
  fi

  # Step 2: origin's tip, the ref GitHub reads. `ls-remote` patterns match on the ref's
  # tail, so only the line naming exactly refs/heads/<branch> counts, and only one may.
  if tips="$(git -C "$repo" ls-remote origin "refs/heads/${branch}" 2>/dev/null)"; then
    tips="$(printf '%s\n' "$tips" | awk -F'\t' -v r="refs/heads/${branch}" '$2 == r { print $1 }')"
  else
    tips=""
  fi
  if [ -z "$tips" ] || [ "$(printf '%s\n' "$tips" | wc -l | tr -d ' ')" != 1 ]; then
    echo "     no resync for #${n}: origin ref is ambiguous or missing"
    return 1
  fi
  tip="$tips"
  if [ "$tip" != "$pushed" ]; then
    echo "     no resync for #${n}: origin tip is $(_short "$tip"), not the pushed $(_short "$pushed")"
    return 1
  fi

  [ -z "$_RS_HIT" ] || return 130  # pre-close check: interrupted during the origin read
  echo "     #${n} still shows head $(_short "$prior") after the push of $(_short "$pushed"); closing and reopening #${n} to resync"
  # From here a signal makes the handler read the state.
  _RS_CLOSING=1
  [ -z "$_RS_HIT" ] || return 130  # pre-close check: the last one before the close
  gh pr close "$n" --repo "$url" >/dev/null 2>&1; rc=$?
  # The flag before the close's exit code: a handler that already ran owns the outcome.
  [ -z "$_RS_HIT" ] || return 130
  if [ "$rc" -ne 0 ]; then
    # A close that errors may still have landed (a timeout, a 502). Judge it by state, fail
    # closed: exactly OPEN means nothing changed, exactly CLOSED means reopen, anything else
    # after three reads is a human's call, never a blind reopen.
    tries=0
    while :; do
      s="$(_resync_state "$url" "$n")"; tries=$(( tries + 1 ))
      case "$s" in OPEN|CLOSED) break ;; esac
      [ "$tries" -lt 3 ] || break
      sleep 2
      [ -z "$_RS_HIT" ] || return 130
    done
    case "$s" in
      OPEN)
        echo "     no resync for #${n}: close failed and #${n} is still open"
        return 1 ;;
      CLOSED) ;;
      *)
        echo "FAILED merge #${n}: close #${n} errored and its state is unreadable; if it is closed: gh pr reopen ${n} --repo ${_RS_PUB}" >&2
        return 2 ;;
    esac
  fi

  # The reopen, one retry after 2s.
  tries=0; rc=1
  while [ "$tries" -lt 2 ]; do
    [ -z "$_RS_HIT" ] || return 130
    if gh pr reopen "$n" --repo "$url" >/dev/null 2>&1; then rc=0; _RS_REOPENED=1; break; fi
    tries=$(( tries + 1 ))
    [ "$tries" -lt 2 ] && sleep 2
  done
  [ -z "$_RS_HIT" ] || return 130
  if [ "$rc" -eq 0 ]; then
    echo "     resynced #${n}: closed and reopened"
    _RS_COMMENT="wrap merge closed and reopened this PR so GitHub re-reads its head: it still showed $(_short "$prior") after the push of $(_short "$pushed")."
    return 0
  fi
  # Printed while the trap still stands, so no late signal can drop the recovery command.
  echo "FAILED merge #${n}: closed #${n} to resync its head, and the reopen failed; reopen it: gh pr reopen ${n} --repo ${_RS_PUB} (if origin lost ${branch}, push it at $(_short "$pushed") first)" >&2
  _RS_COMMENT="wrap merge closed this PR so GitHub re-reads its head ($(_short "$prior") stale, $(_short "$pushed") pushed), and the reopen failed. Reopen it: gh pr reopen ${n}."
  return 2
}

# _branch_worktree <repo> <branch> -- the checkout that holds <branch>, empty when none does.
# `--porcelain -z` NUL-terminates every attribute, which keeps a path carrying a newline whole.
_branch_worktree() {
  local repo="$1" branch="$2" wt="" rec
  while IFS= read -r -d '' rec; do
    case "$rec" in
      "worktree "*) wt="${rec#worktree }" ;;
      "branch refs/heads/${branch}") printf '%s' "$wt"; return 0 ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain -z 2>/dev/null)
  return 1
}

# _main_holds_branch <repo> <branch> -- 0 when the MAIN checkout (not another worktree) has
# <branch> checked out. Under --no-pull such a PR is some live session's branch, and a
# re-merge of it would write the main checkout's HEAD and working tree.
_main_holds_branch() {
  local repo="$1" branch="$2" held main
  held="$(_branch_worktree "$repo" "$branch")" || return 1
  main="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  main="${main%/.git}"; main="${main%/}"
  [ "$(cd "$held" 2>/dev/null && pwd -P)" = "$(cd "$main" 2>/dev/null && pwd -P)" ]
}

# _union_remerge <repo> <branch> <def> <head-oid> -- the one bounded recovery from a conflict
# GitHub invented. A squash merge resolves on GitHub's side, which never reads .gitattributes,
# so two branches that both appended to a merge=union log conflict on the PR while a local
# `git merge` resolves them by keeping both sides. This runs that merge in the checkout that
# holds the branch and pushes the result, which is the recovery an operator runs by hand.
#
# A merge that stops on a conflict is the proof that the divergence was NOT the union case:
# git applies the union attribute here, so anything it cannot resolve is a real conflict a
# human owns. That case aborts and leaves the branch exactly as it was. Runs once, never in
# a loop, and only when the branch tip is still the head the PR gates read.
# _union_dedupe_rows <wt> <pre-merge-tip> -- the merge above resolves a union-marked log by
# keeping both sides, which duplicates a row when the two branches flipped the SAME id's
# status. Scoped to files the merge just touched, declared merge=union, and shaped like a
# kanban table (backlog.sh owns that row grammar); a duplicate elsewhere is not this pass's
# job. Never amends the merge commit: a drop lands as its own follow-up commit so the merge
# commit stays exactly what `git merge` produced.
_union_dedupe_rows() {
  local wt="$1" tip="$2" f dropped staged=0 note=""
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$wt/$f" ] || continue
    _union_marked "$wt" "$f" || continue
    grep -qE '^\| *[A-Z]+-[0-9]+ *\|' "$wt/$f" || continue
    dropped="$(bash "$BACKLOG_SH" dedupe-all "$wt/$f" 2>/dev/null)"
    [ -n "$dropped" ] || continue
    git -C "$wt" add "$f"
    staged=1
    note="${note}${note:+; }${f}: ${dropped}"
  done < <(git -C "$wt" diff --name-only "$tip" HEAD -- 2>/dev/null)
  [ "$staged" -eq 1 ] || return 0
  if git -C "$wt" commit -q -m "fix(board): dedupe union-merged rows" -m "dropped duplicate ids -- ${note}"; then
    echo "     deduped union-merged rows: ${note}"
  else
    echo "     found duplicate rows (${note}) but the follow-up commit failed; left staged for a human"
    return 1
  fi
}

# _scratch_wt_add <repo> <commit> -- a detached worktree at <commit> in a fresh temp dir;
# prints its path. No operator checkout is touched. `_scratch_wt_drop` removes it.
_scratch_wt_add() {
  local d
  d="$(mktemp -d)" || return 1
  git -C "$1" worktree add -q --detach "$d/wt" "$2" >/dev/null 2>&1 || { rm -rf "$d"; return 1; }
  printf '%s' "$d/wt"
}

# _scratch_wt_drop <repo> <wt> -- removes a worktree `_scratch_wt_add` made, and its temp dir.
_scratch_wt_drop() {
  git -C "$1" worktree remove --force "$2" >/dev/null 2>&1
  rm -rf "${2%/wt}"
}

# Success sets REMERGE_OID to the pushed head, the only head the caller may merge.
# A branch no local checkout holds (the worktree that pushed it is gone) re-merges in a
# scratch detached worktree at the PR head, removed afterwards, so no operator checkout
# is touched and the same merge, abort and dedupe rules apply.
_union_remerge() {
  local repo="$1" branch="$2" def="$3" head_oid="$4" cmd="${5:-}" wt tip scratch="" rc
  REMERGE_OID=""; REMERGE_WT=""
  [ -n "$branch" ] && [ -n "$head_oid" ] || { echo "     no branch or head SHA to re-merge"; return 1; }
  if wt="$(_branch_worktree "$repo" "$branch")"; then
    tip="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
    [ "$tip" = "$head_oid" ] || {
      echo "     ${branch} tip $(_short "$tip") is not the PR head $(_short "$head_oid"), left alone"; return 1; }
    [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || {
      echo "     ${wt} is dirty, so a re-merge would sweep uncommitted work into the branch"; return 1; }
    _write_guard "$wt" || { echo "     index.lock held by another writer in ${wt}"; return 1; }
  else
    git -C "$repo" fetch -q origin "$branch" 2>/dev/null || {
      echo "     no local checkout holds ${branch} and fetching it failed"; return 1; }
    tip="$(git -C "$repo" rev-parse FETCH_HEAD 2>/dev/null)"
    [ "$tip" = "$head_oid" ] || {
      echo "     origin ${branch} tip $(_short "$tip") is not the PR head $(_short "$head_oid"), left alone"; return 1; }
    wt="$(_scratch_wt_add "$repo" "$head_oid")" || {
      echo "     no local checkout holds ${branch} and a scratch worktree failed"; return 1; }
    scratch=1
    echo "     no local checkout holds ${branch}; re-merging in a scratch worktree"
  fi
  REMERGE_WT="$wt"
  _remerge_push "$repo" "$wt" "$branch" "$def" "$tip" "$cmd"; rc=$?
  # A 2 means the checkout is mid-state for a human to finish, so a scratch worktree
  # holding it stays; every other outcome is self-contained and the scratch goes.
  [ -n "$scratch" ] && [ "$rc" -ne 2 ] && _scratch_wt_drop "$repo" "$wt"
  return "$rc"
}

# _remerge_push <repo> <wt> <branch> <def> <tip> [<cmd>] -- the merge and push half of
# `_union_remerge`, run in whichever checkout it picked. The fetch runs here first so the
# generator decision can compare the two sides: the worktree's own generator runs only
# when <tip> and origin/<def> carry the same file. `merge` runs unattended under
# /kit:wrap and wrap.autoland_carry on a branch someone else can push to, so a generator
# the two sides disagree on (or that only one side has) is never run; a FEATURES conflict
# is then refused by name. The merge itself is `_merge_verify_push`, the sequence `land`
# runs; success sets REMERGE_OID to the pushed head.
_remerge_push() {
  local repo="$1" wt="$2" branch="$3" def="$4" tip="$5" cmd="${6:-}" gen="" rc
  git -C "$repo" fetch -q origin "$def" 2>/dev/null || { echo "     fetch origin ${def} failed"; return 1; }
  [ -f "$wt/$_RB_GENERATOR" ] \
    && git -C "$wt" diff --quiet "$tip" "origin/${def}" -- "$_RB_GENERATOR" 2>/dev/null \
    && gen="$wt/$_RB_GENERATOR"
  _merge_verify_push "$wt" "$branch" "$def" "$tip" "$gen" ${cmd:+"$cmd"}; rc=$?
  case "$rc" in
    0)
      REMERGE_OID="$MERGED_OID"
      echo "     re-merged origin/${def} into ${branch}, pushed $(_short "$REMERGE_OID")"
      return 0 ;;
    4) echo "     ${branch} already contains origin/${def}, so a re-merge cannot clear the conflict"; return 1 ;;
    5) echo "     merging origin/${def} into ${branch} conflicts beyond the union-marked files, aborted"; return 1 ;;
    *) return "$rc" ;;
  esac
}

# _squash_fallback <repo> <url> <def> <pr> <branch> <head-oid> <detail-json> -- the second
# recovery leg for a conflict GitHub invented, for the case `_union_remerge` cannot touch:
# the pushed head ALREADY carries origin/<def>, the union-marked files resolved locally,
# and only GitHub's attribute-blind merge still says CONFLICTING, so there is nothing left
# to merge into the branch. What replaces the stuck PR is the commit a squash merge would
# have computed: one commit of the merged tree onto origin/<def>, pushed to a
# <branch>-squash branch and carried to a replacement PR under the original title and
# body. The replacement gates through `_pr_gate` and merges through the caller's same
# squash+verify path, so every refusal the first merge owed still applies. Success sets
# SQ_PR and SQ_OID for that path and returns 0; every failure prints its reason, and
# whatever was already pushed (the -squash branch, the replacement PR) stays for a human
# rather than being quietly deleted.

# _fallback_ok <cache> <branch> <pr> -- the dependents gate applied to the fallback
# leg: a conflicting PR whose verdict is SKIP never reaches the OK-path dependent
# check, but merging its squash-equivalent strands an open PR still targeting the
# original branch exactly the same. Same cache shape, same refusal text.
_fallback_ok() {
  local cache="$1" c_head="$2" c_n="$3"
  if awk -F'\t' -v h="$c_head" -v n="$c_n" '$3 == h && $1 != n { found = 1 } END { exit !found }' "$cache"; then
    echo "     fallback refused for #${c_n}: dependents open on ${c_head}, retarget them first"
    return 1
  fi
  return 0
}

_squash_fallback() {
  local repo="$1" url="$2" def="$3" n="$4" head="$5" head_oid="$6" detail="$7"
  SQ_PR=""; SQ_OID=""
  [ -n "$head" ] && [ -n "$head_oid" ] || { echo "     no branch or head SHA for the squash fallback"; return 1; }

  # CONFLICTING has to be the whole refusal: a failing check, a requested change or a
  # blocked merge state beside it means the stuck PR is not one squash away from green.
  # mergeStateStatus DIRTY is the same refusal restated (the merge commit cannot be
  # created cleanly), so it is masked together with mergeable; every other state still
  # decides on its own.
  local masked verdict
  masked="$(printf '%s' "$detail" | jq '(.mergeable = "MERGEABLE")
    | if .mergeStateStatus == "DIRTY" then .mergeStateStatus = "CLEAN" else . end' 2>/dev/null)"
  verdict="$(_pr_gate "$masked" "$def")"
  case "$verdict" in
    OK) ;;
    SKIP*) echo "     #${n} is not one squash away from green: ${verdict#SKIP }"; return 1 ;;
    *)     echo "     #${n} is not one squash away from green: unreadable PR JSON"; return 1 ;;
  esac

  git -C "$repo" fetch -q origin "$def" 2>/dev/null || { echo "     fetch origin ${def} failed"; return 1; }
  git -C "$repo" fetch -q origin "$head" 2>/dev/null \
    || { echo "     fetch of the PR branch ${head} failed"; return 1; }
  [ "$(git -C "$repo" rev-parse FETCH_HEAD 2>/dev/null)" = "$head_oid" ] || {
    echo "     ${head} moved past the head the gates read ($(_short "$head_oid")); nothing to supersede"; return 1; }
  # The signature this leg exists for: the pushed head already holds the base, so a merge
  # has nothing left to resolve and GitHub's CONFLICTING is provably its union blindness,
  # not a real divergence.
  git -C "$repo" merge-base --is-ancestor "origin/${def}" "$head_oid" 2>/dev/null || {
    echo "     ${head} does not contain origin/${def}; the conflict is not the carried-base case"; return 1; }

  # A merge of a descendant into its ancestor yields the descendant's tree; merge-tree
  # computes it anyway, doubling as the clean-merge proof. Its first output line is the
  # tree oid.
  local mtree sq_oid
  mtree="$(git -C "$repo" merge-tree --write-tree "origin/${def}" "$head_oid" 2>/dev/null)" || {
    echo "     merging origin/${def} and ${head} does not resolve cleanly"; return 1; }
  mtree="${mtree%%$'\n'*}"

  local title body sq_branch
  title="$(printf '%s' "$detail" | jq -r '.title // ""' 2>/dev/null)"
  [ -n "$title" ] || title="squash-equivalent of ${head}"
  body="$(printf '%s' "$detail" | jq -r '.body // ""' 2>/dev/null)"
  [ -n "$body" ] || body="$title"
  sq_branch="${head}-squash"

  sq_oid="$(git -C "$repo" commit-tree "$mtree" -p "origin/${def}" -m "$title" \
    -m "Squash-equivalent of #${n} (${head}), whose head already carries origin/${def} while GitHub still reports the PR conflicting." 2>/dev/null)" || {
    echo "     commit-tree for the squash-equivalent commit failed"; return 1; }

  # update-ref writes over a stale scratch ref of the same name, but never under a
  # checkout that holds it: a worktree's branch moving under it would strand its index.
  local held
  held="$(_branch_worktree "$repo" "$sq_branch")" && {
    echo "     ${sq_branch} is checked out at ${held}; left for a human"; return 1; }
  git -C "$repo" update-ref "refs/heads/${sq_branch}" "$sq_oid" \
    || { echo "     could not write the local ${sq_branch} ref"; return 1; }
  if ! git -C "$repo" push -q origin "$sq_branch" 2>/dev/null; then
    # A leftover -squash branch from an earlier attempt is scratch state this run owns:
    # deleted once, then pushed again -- but only when no open PR rides it. Deleting the
    # head of a live PR closes it unreported, and an operator branch can share the name.
    if [ -n "$(gh pr list --repo "$url" --head "$sq_branch" --state open --json number -q '.[].number' 2>/dev/null)" ]; then
      echo "     ${sq_branch} has an open PR already; refusing to delete it, left for a human"
      return 1
    fi
    git -C "$repo" push -q origin --delete "$sq_branch" >/dev/null 2>&1 \
      && git -C "$repo" push -q origin "$sq_branch" 2>/dev/null \
      || { echo "     push of ${sq_branch} failed; the squash commit stays local at $(_short "$sq_oid")"; return 1; }
  fi
  echo "     committed the squash-equivalent tree on ${sq_branch}, pushed $(_short "$sq_oid")"

  # `--head`, never `--base`, for the same reason land names only the head: with --repo,
  # gh targets the repository's own default branch.
  local created rc new_n
  created="$(gh pr create --repo "$url" --head "$sq_branch" --title "$title" --body "$body" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "     PR REFUSED: gh pr create for ${sq_branch} exited ${rc}: ${created}" >&2
    return 1
  fi
  new_n="$(printf '%s\n' "$created" | tail -1)"; new_n="${new_n##*/}"
  case "$new_n" in
    ''|*[!0-9]*) echo "     PR REFUSED: gh pr create named no PR number: ${created}" >&2; return 1 ;;
  esac
  echo "     opened replacement PR #${new_n} on ${sq_branch} (supersedes #${n})"

  # The replacement gates through the same `_pr_gate` every other merge passes, and its
  # head must still be the commit just built: a push landing between create and gate must
  # not slip past the caller's --match-head-commit.
  local new_detail new_head
  new_detail="$(_pr_detail_settled "$url" "$new_n")"
  new_head="$(printf '%s' "$new_detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
  if [ "$new_head" != "$sq_oid" ]; then
    echo "     #${new_n} does not point at the squash commit $(_short "$sq_oid"); ${sq_branch} and #${new_n} stay for a human"
    return 1
  fi
  verdict="$(_pr_gate "$new_detail" "$def")"
  if [ "$verdict" != "OK" ]; then
    case "$verdict" in
      SKIP*) echo "     SKIP #${new_n} after the squash fallback: ${verdict#SKIP }" ;;
      *)     echo "     SKIP #${new_n} after the squash fallback: unreadable PR JSON" ;;
    esac
    echo "     ${sq_branch} and replacement PR #${new_n} stay open; #${n} is unchanged"
    return 1
  fi
  SQ_PR="$new_n"; SQ_OID="$sq_oid"
  echo "     eligible #${new_n} after the squash fallback"
  return 0
}

cmd_merge() {
  local do_apply=0 repo="" count=0 pr_only="" verify="" pr_head=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) do_apply=1; shift ;;
      --no-pull) NO_PULL=1; shift ;;
      --pr) pr_only="${2:-}"; shift 2 ;;
      --with-ci) KIT_WRAP_CI_ON_MERGE=1; shift ;;
      --verify) [ $# -ge 2 ] || { echo "wrap.sh merge: --verify needs a value" >&2; return 64; }
                verify="$2"; shift 2 ;;
      --verify=*) verify="${1#--verify=}"; shift ;;
      -*) echo "wrap.sh merge: unknown flag '$1'" >&2; return 64 ;;
      *) _reject_packed merge "$1" || return 64
         count=$(( count + 1 )); repo="$1"; shift ;;
    esac
  done
  [ "$count" -eq 1 ] || { echo "usage: wrap.sh merge [--apply] [--no-pull] [--pr N] [--with-ci] [--verify <cmd>] <repo>" >&2; return 64; }
  case "$pr_only" in
    '') ;;
    *[!0-9]*) echo "wrap.sh merge: --pr wants a PR number" >&2; return 64 ;;
  esac
  _is_repo "$repo" || { echo "wrap.sh merge: ${repo} is not a git repo" >&2; return 64; }

  local ghs; ghs="$(_gh_state)"
  if [ "$ghs" != "ok" ]; then _gh_note "$ghs"; return 1; fi

  local def; def="$(_default_branch "$repo")" || { echo "no default branch resolved for ${repo}" >&2; return 1; }
  local url; url="$(_origin_url "$repo")"

  local own
  own="$(_open_own_prs "$url")" || {
    echo "the open-PR query on ${url} failed; nothing merged" >&2; return 1; }
  local numbers; numbers="$(printf '%s' "$own" | jq -r '.[].number' 2>/dev/null)"

  # --pr N: a lead review targets exactly one PR. It must already be the operator's own
  # open PR (the _open_own_prs membership check below the operator never bypasses), and
  # when it is a draft the draft skip in _pr_gate would refuse it forever, so a draft
  # under --pr is the one case `merge` marks ready itself, an explicit lead decision made
  # by naming the PR, never a background guess. Checked ahead of the "no open PRs" return
  # below, so a PR that is not the operator's own refuses by name instead of reading as
  # an empty board.
  if [ -n "$pr_only" ]; then
    if ! printf '%s\n' "$numbers" | grep -qx "$pr_only"; then
      echo "wrap.sh merge: PR #${pr_only} is not an open PR authored by you on ${url}" >&2
      return 1
    fi
    numbers="$pr_only"
    if [ "$NO_PULL" = 1 ]; then
      pr_head="$(printf '%s' "$(_pr_detail "$url" "$pr_only")" | jq -r '.headRefName // ""' 2>/dev/null)"
      if [ -n "$pr_head" ] && _main_holds_branch "$repo" "$pr_head"; then
        echo "SKIP #${pr_only}: head ${pr_head} is checked out in the main checkout (--no-pull)"
        return 0
      fi
    fi
    if [ "$(printf '%s' "$(_pr_detail "$url" "$pr_only")" | jq -r '.isDraft // false' 2>/dev/null)" = "true" ]; then
      if [ "$do_apply" != 1 ]; then
        echo "note: #${pr_only} is a draft; --apply would run \`gh pr ready\` before merging"
      else
        echo "marking #${pr_only} ready (was draft)"
        gh pr ready "$pr_only" --repo "$url" >/dev/null 2>&1 || {
          echo "FAILED merge #${pr_only}: gh pr ready failed" >&2; return 2; }
      fi
    fi
  else
    [ -n "$numbers" ] || { echo "no open PRs authored by the operator on ${url}"; return 0; }
  fi

  # Exactly one detail read per PR. The full JSON goes to its own temp file and the
  # eligibility loop reads it back, because the dependents gate needs every base first.
  local jsondir; jsondir="$(mktemp -d)"
  local cache="${jsondir}/index"
  local n detail base head
  for n in $numbers; do
    detail="$(_pr_detail_settled "$url" "$n")"
    printf '%s' "$detail" > "${jsondir}/pr-${n}.json"
    base="$(printf '%s' "$detail" | jq -r '.baseRefName // ""' 2>/dev/null)"
    head="$(printf '%s' "$detail" | jq -r '.headRefName // ""' 2>/dev/null)"
    printf '%s\t%s\t%s\n' "$n" "$head" "$base" >> "$cache"
  done

  local first_eligible="" verdict title conflict_n="" conflict_count=0
  local superseded_n="" superseded_branch=""
  for n in $numbers; do
    detail="$(cat "${jsondir}/pr-${n}.json" 2>/dev/null)"
    verdict="$(_pr_gate "$detail" "$def")"
    if [ -z "$verdict" ]; then
      echo "SKIP #${n}: unreadable PR JSON"
      continue
    fi
    title="$(printf '%s' "$detail" | jq -r '.title // ""' 2>/dev/null)"
    head="$(printf '%s' "$detail" | jq -r '.headRefName // ""' 2>/dev/null)"
    if [ "$NO_PULL" = 1 ] && [ -n "$head" ] && _main_holds_branch "$repo" "$head"; then
      echo "SKIP #${n}: head ${head} is checked out in the main checkout (--no-pull)"
      continue
    fi
    if [ "$verdict" = "OK" ] && awk -F'\t' -v h="$head" -v n="$n" '$3 == h && $1 != n { found = 1 } END { exit !found }' "$cache"; then
      verdict="SKIP dependents open, retarget them first"
    fi
    if [ "$verdict" = "OK" ]; then
      echo "eligible #${n} ${title} [${head}]"
      [ -n "$first_eligible" ] || first_eligible="$n"
    else
      echo "SKIP #${n} ${title}: ${verdict#SKIP }"
      case "$verdict" in
        "SKIP not mergeable (CONFLICTING)")
          conflict_count=$(( conflict_count + 1 )); conflict_n="$n" ;;
      esac
    fi
  done

  local head_oid=""
  [ -n "$first_eligible" ] && head_oid="$(jq -r '.headRefOid // ""' "${jsondir}/pr-${first_eligible}.json" 2>/dev/null)"

  # One bounded retry, and only when the conflict is the whole story: nothing else is
  # eligible and exactly one PR is conflicting, so the branch to recover is unambiguous.
  # The re-gate after the push is the authority: it re-reads every gate against the new
  # head, so a push that dismissed an approval or broke a check refuses here.
  if [ -z "$first_eligible" ] && [ "$conflict_count" = 1 ]; then
    local c_head c_oid
    c_head="$(jq -r '.headRefName // ""' "${jsondir}/pr-${conflict_n}.json" 2>/dev/null)"
    c_oid="$(jq -r '.headRefOid // ""' "${jsondir}/pr-${conflict_n}.json" 2>/dev/null)"
    if [ "$do_apply" != 1 ]; then
      echo "note: #${conflict_n} conflicts; --apply would try one re-merge of ${def} into ${c_head}"
      echo "note: when ${c_head} already holds origin/${def}, --apply falls back to a squash-equivalent ${c_head}-squash PR"
    else
      echo "retry #${conflict_n}: one re-merge of ${def} into ${c_head}"
      _union_remerge "$repo" "$c_head" "$def" "$c_oid" "$verify"; local urc=$?
      # An interrupted cycle exits as it arrived, and a checkout the re-merge could not
      # restore is a human's job: both skip the squash fallback, which has no answer for
      # either.
      case "$urc" in
        130) rm -rf "$jsondir"; return 130 ;;
        2)   rm -rf "$jsondir"
             echo "FAILED merge #${conflict_n}: the re-merge left ${REMERGE_WT} needing a human" >&2
             return 2 ;;
      esac
      if [ "$urc" -eq 0 ]; then
        # Wait for GitHub to see the pushed head and recompute mergeability, then gate only
        # that head: a head that never arrived or that someone else pushed is refused.
        detail="$(_pr_detail_settled "$url" "$conflict_n" "$REMERGE_OID" "$c_oid")"
        local r_head; r_head="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
        # Still the pre-push head once the wait ran out: GitHub may never re-read the head
        # ref on its own, and one close and reopen makes it. Dependents open would refuse
        # the merge anyway, so the resync there would be churn with no merge behind it.
        local resynced=""
        if [ -n "$r_head" ] && [ "$r_head" = "$c_oid" ]; then
          if awk -F'\t' -v h="$c_head" -v n="$conflict_n" \
               '$3 == h && $1 != n { found = 1 } END { exit !found }' "$cache"; then
            echo "     no resync for #${conflict_n}: dependents open"
          else
            _pr_head_resync "$repo" "$url" "$conflict_n" "$c_head" "$c_oid" "$REMERGE_OID"; local rsc=$?
            case "$rsc" in
              0|3)
                [ "$rsc" -eq 0 ] && resynced=1
                detail="$(_pr_detail_settled "$url" "$conflict_n" "$REMERGE_OID" "$c_oid")"
                r_head="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)" ;;
              2|130) rm -rf "$jsondir"; return "$rsc" ;;
            esac
          fi
        fi
        verdict="$(_pr_gate "$detail" "$def")"
        if [ "$r_head" != "$REMERGE_OID" ]; then
          verdict="SKIP head is $(_short "$r_head"), not the pushed $(_short "$REMERGE_OID")"
          if [ -n "$resynced" ] && [ "$r_head" = "$c_oid" ]; then
            verdict="${verdict}, still stale after a close and reopen; wait until gh pr view ${conflict_n} --json headRefOid shows $(_short "$REMERGE_OID"), then re-run wrap merge --apply --pr ${conflict_n} (a re-run before that ends at left alone), or close and reopen it by hand: gh pr close ${conflict_n} && gh pr reopen ${conflict_n}"
          fi
        elif [ -z "$verdict" ]; then
          verdict="SKIP unreadable PR JSON"
        elif [ "$verdict" = "OK" ] && awk -F'\t' -v h="$c_head" -v n="$conflict_n" \
             '$3 == h && $1 != n { found = 1 } END { exit !found }' "$cache"; then
          verdict="SKIP dependents open, retarget them first"
        fi
        if [ "$verdict" = "OK" ]; then
          first_eligible="$conflict_n"
          head_oid="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
          echo "eligible #${conflict_n} after the re-merge"
        else
          echo "SKIP #${conflict_n} after the re-merge: ${verdict#SKIP }"
          # The same anomaly one merge later: the re-merge pushed, the head now holds
          # origin/<def>, and GitHub still reports CONFLICTING. The squash fallback
          # applies to the pushed head the re-gate just read.
          if [ "$verdict" = "SKIP not mergeable (CONFLICTING)" ]; then
            local r_oid
            r_oid="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
            if _fallback_ok "$cache" "$c_head" "$conflict_n" \
               && _squash_fallback "$repo" "$url" "$def" "$conflict_n" "$c_head" "$r_oid" "$detail"; then
              first_eligible="$SQ_PR"; head_oid="$SQ_OID"
              superseded_n="$conflict_n"; superseded_branch="${c_head}-squash"
            fi
          fi
        fi
      elif _fallback_ok "$cache" "$c_head" "$conflict_n" \
        && _squash_fallback "$repo" "$url" "$def" "$conflict_n" "$c_head" "$c_oid" \
             "$(cat "${jsondir}/pr-${conflict_n}.json" 2>/dev/null)"; then
        first_eligible="$SQ_PR"; head_oid="$SQ_OID"
        superseded_n="$conflict_n"; superseded_branch="${c_head}-squash"
      fi
    fi
  fi
  rm -rf "$jsondir"

  [ "$do_apply" = 1 ] || { echo "dry run; pass --apply to merge one PR."; return 0; }
  [ -n "$first_eligible" ] || { echo "nothing eligible to merge."; return 0; }
  [ -n "$head_oid" ] || {
    echo "FAILED merge #${first_eligible}: no head SHA to pin the merge to" >&2; return 2; }

  # Under `--with-ci`/`KIT_WRAP_CI_ON_MERGE=1` a label-gated repo runs no checks until the
  # PR carries `ci`, so the gate above read an empty rollup on an untested head and called
  # it mergeable. Sync the label and wait out the runs it starts, then re-read and re-gate
  # that same head: a check the label reveals failing refuses here. With the gate off (the
  # default), or on a repo without the label, the merge runs as it always did; under the
  # gate, a label that will not set refuses rather than merging untested.
  local rc=1
  if _ci_on_merge; then
  _ci_label_sync "$url" "$first_eligible"; rc=$?
  case "$rc" in
    0)
      _ci_checks_wait "$url" "$first_eligible"
      detail="$(_pr_detail_settled "$url" "$first_eligible")"
      local new_head; new_head="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
      verdict="$(_pr_gate "$detail" "$def")"
      if [ "$new_head" != "$head_oid" ]; then
        echo "FAILED merge #${first_eligible}: head moved to $(_short "$new_head") during the check wait; left open" >&2
        return 2
      fi
      if [ "$verdict" != "OK" ]; then
        echo "FAILED merge #${first_eligible}: ${verdict#SKIP } once the ci label's checks ran; left open" >&2
        return 2
      fi
      # No new check reported inside the grace hold, so the verdict rests on checks that
      # predate the label. Those pass only on CLEAN, the rule an empty rollup already meets.
      local ms; ms="$(printf '%s' "$detail" | jq -r '.mergeStateStatus // ""' 2>/dev/null)"
      if [ "${CI_WAIT_END:-}" = "NONEW" ] && [ "${CI_PRELABEL_KEYS:-[]}" != "[]" ] && [ "$ms" != "CLEAN" ]; then
        echo "FAILED merge #${first_eligible}: no check reported after the ci label went on, and merge state ${ms:-unknown} is not CLEAN; left open" >&2
        return 2
      fi ;;
    1) ;;
    *) echo "FAILED merge #${first_eligible}: the ci label could not be set" >&2; return 2 ;;
  esac
  fi

  # Squash only, one PR per call, never --delete-branch (a worktree may hold the branch)
  # and never --auto (an armed auto-merge lands a later push).
  # --match-head-commit pins the merge to the head the gates just read, so a push that
  # lands between the gate and the merge aborts the call instead of shipping unreviewed.
  _gh_merge_retry "$first_eligible" "$url" "$head_oid"
  local rc=$?
  if [ "$rc" -ne 0 ]; then echo "FAILED merge #${first_eligible}: exit ${rc}" >&2; return 2; fi

  local after state sha
  after="$(gh pr view "$first_eligible" --repo "$url" --json state,mergeCommit 2>/dev/null)"
  state="$(printf '%s' "$after" | jq -r '.state // ""' 2>/dev/null)"
  sha="$(printf '%s' "$after" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)"
  if [ "$state" != "MERGED" ]; then
    echo "FAILED merge #${first_eligible}: state is '${state:-unknown}', not MERGED" >&2
    return 2
  fi

  # gh reporting MERGED is GitHub's word, not proof main holds the reviewed tree: a
  # squash resolves on GitHub's own side, and a stale headRefOid captured before a late
  # push, or an armed auto-merge overtaken by a push after the gates read, can both
  # report MERGED while the default branch moves on without it.
  local tv; tv="$(_tree_verify "$repo" "$def" "$head_oid" "$sha")"
  case "$tv" in
    OK)
      echo "merged #${first_eligible} (${sha}): tree verified"
      [ -z "$superseded_n" ] || echo "superseded #${superseded_n}: its tree landed via #${first_eligible} on ${superseded_branch}; close #${superseded_n} when ready"
      ;;
    MISMATCH*)
      echo "merged #${first_eligible} (${sha}): TREE MISMATCH, ${tv#MISMATCH } paths differ; ${def} does not hold the PR head" >&2
      return 3 ;;
    *)
      echo "merged #${first_eligible} (${sha}): tree ${tv}" >&2
      return 3 ;;
  esac
  return 0
}
