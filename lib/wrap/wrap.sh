#!/usr/bin/env bash
# wrap.sh -- the landing step after ship. One pass over every repo a session
# touched, with nine verbs:
#
#   wrap.sh scan  [--under <root>]... <repo> [<repo>...]    report only, exit 0
#   wrap.sh apply [--apply] [--worktrees] [--own <path>]... [--under <root>]... <repo> [...]  dry-run by default
#   wrap.sh merge [--apply] [--pr N] <repo>                 merges ONE own green PR (--pr: a named draft)
#   wrap.sh land  <worktree> [--title T] [--body-file F]    one hand-made worktree, landed
#   wrap.sh start <repo> <branch>                           one hand-made worktree, started
#   wrap.sh log   "<slug>: <one sentence>" [--date YYYY-MM-DD]
#   wrap.sh default-branch <repo>                           prints the detected name
#   wrap.sh knowledge-root <repo>                           the fenced knowledge dir
#   wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]  stage a candidate
#   wrap.sh --help
#
#   --under <root> (scan and apply, repeatable) appends every immediate child of <root> that
#   holds a .git file or directory, in sorted order, to the repo list. Other children are
#   skipped; a root with no repos prints one line. A bare --under (no directory follows it)
#   expands to every root in the wrap.roots knob instead (tilde-expanded, listed order, each
#   through the same immediate-child scan); an empty knob exits 64 naming it.
#
#   internal, a test seam: apply --tips-file <path> replaces the run's own tip snapshot
#   internal, a test seam: WRAP_ORIGIN_DELETE_CHUNK sets the names per origin delete push
#
# Verify a change in the shape commands/wrap.md runs it: step 5 passes `--own` on a shared
# repo, so a test or real-repo run of the bare form alone misses that path. The first origin
# sweep shipped skipping `--own` and every shared repo kept its merged heads.
#
# The write set is closed: branch delete under two proofs, `apply`'s origin delete of
# merged branches, each leased to the tip it read (knob wrap.delete_merged_remote_branches),
# worktree remove under
# --worktrees, pull --ff-only on the default branch and its pull-past-dirty stash, the
# activity-log prepend, the knowledge-root project directory, the staging-file append, one
# gh pr merge, one bounded union re-merge push (with its own follow-up commit when the
# re-merge duplicates a kanban row, and a scratch detached worktree added and removed when
# no checkout holds the branch), one `gh pr ready` when `merge --pr N` targets a draft,
# `merge`'s squash-equivalent fallback for a conflicting own PR whose head already holds
# the base (one commit-tree, one <branch>-squash push with a single scratch-ref delete and
# repush, one replacement `gh pr create`), `land`'s own named push, PR create, squash
# merge, worktree remove and branch delete, `apply`'s stray-line carry (per dirty
# union-marked file, one scratch detached worktree at origin/<default>, one commit, one push
# of a new wrap/stray-* branch, knob wrap.carry_stray_lines),
# and `start`'s one worktree add under `.claude/worktrees` on a new local branch.
# Every other action is a report line. The
# verbs never switch a branch and never force a push or a pull. The one force is
# `worktree remove -f -f`: it overrides a LOCK, never a dirty, detached, checked-out or
# unproven worktree, and the removal counts only once a postcondition finds the path gone.
#
# Ported from the operator's repo-wrapup scripts. The default branch is DETECTED, never
# assumed to be main.
# `-e` is deliberately absent. The `run()` helper captures the exit code of every write
# itself, reports the failure once and sets FAILURES; under `-e` the shell would exit at
# the first failed write and the remaining repos would never report.
set -uo pipefail

# A git call must never block on a credential prompt inside an unattended wrap.
export GIT_TERMINAL_PROMPT=0

# An index.lock at least this old belongs to a foreign writer, not to ordinary git traffic.
LOCK_STALE_SECS=5
# A routine activity line stays inside this many characters. Over it, `log` warns and writes.
LOG_LINE_BUDGET=300

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"
# The one staging-block writer: `stage` shells out to it rather
# than growing a second copy of the dedupe/render/append grammar in bash.
STAGING_FORMAT_PY="$LIB_ROOT/reflect/staging-format.py"
BACKLOG_SH="$LIB_ROOT/board/backlog.sh"
# shellcheck source=lib/config/kit-config.sh
source "$LIB_ROOT/config/kit-config.sh" || { echo "FATAL: lib/config/kit-config.sh missing or unreadable" >&2; exit 1; }
# shellcheck source=lib/gate/default-branch-warn.sh
source "$LIB_ROOT/gate/default-branch-warn.sh" || { echo "FATAL: lib/gate/default-branch-warn.sh missing or unreadable" >&2; exit 1; }

_usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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

# --------------------------------------------------------------------------- scan

_scan_repo() {
  local repo="$1" ghs="$2"
  _is_repo "$repo" || { echo "== ${repo}: not a git repo, skipped"; return 0; }
  echo "===================================================================="
  echo "== ${repo}"
  git -C "$repo" fetch --prune -q 2>/dev/null || echo "  (fetch failed; counts may be stale)"

  local def
  def="$(_default_branch "$repo")" || {
    echo "-- no default branch resolved (origin/HEAD, origin/main and origin/master all absent); skipped"
    return 0
  }

  local cur; cur="$(git -C "$repo" branch --show-current 2>/dev/null)"
  echo "-- checkout on: ${cur:-<detached>}"

  local ahead behind
  ahead="$(git -C "$repo" rev-list --count "origin/${def}..HEAD" 2>/dev/null)"
  behind="$(git -C "$repo" rev-list --count "HEAD..origin/${def}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) ahead='?' ;; esac
  case "$behind" in ''|*[!0-9]*) behind='?' ;; esac
  echo "-- vs origin/${def}: ahead=${ahead} behind=${behind}"

  echo "-- dirty files (do NOT assume they are yours):"
  local st; st="$(git -C "$repo" status --short 2>/dev/null)"
  if [ -n "$st" ]; then printf '%s\n' "$st" | sed -n 1,10p | sed 's/^/     /'
  else echo "     (clean)"; fi

  echo "-- worktrees:"
  git -C "$repo" worktree list 2>/dev/null | sed 's/^/     /'

  echo "-- local branches (an ancestor of origin/${def} is SAFE-d; a squash merge needs the gh proof):"
  local b tip json verdict
  for b in $(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/); do
    case "$b" in "$def"|main|master) continue ;; esac
    if git -C "$repo" merge-base --is-ancestor "$b" "origin/${def}" 2>/dev/null; then
      echo "     ${b}  [SAFE-d: ancestor of origin/${def}]"
      continue
    fi
    if [ "$ghs" != "ok" ]; then
      echo "     ${b}  [NOT merged / unknown: LEAVE]"
      continue
    fi
    tip="$(git -C "$repo" rev-parse "$b" 2>/dev/null)"
    json="$(_squash_json "$(_origin_url "$repo")" "$b")"
    verdict="$(_squash_verdict "$json" "$tip" "$def")"
    case "$verdict" in
      OK) echo "     ${b}  [SQUASH-MERGED per gh: safe to -D]" ;;
      *)  echo "     ${b}  [NOT merged / unknown: LEAVE]" ;;
    esac
  done

  echo "-- open PRs authored by me:"
  case "$ghs" in
    ok)
      local own
      if own="$(_open_own_prs "$(_origin_url "$repo")")"; then
        printf '%s' "$own" \
          | jq -r '.[] | "     #\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null
      else
        echo "     (gh query failed)"
      fi
      ;;
    *) echo "     $(_gh_note "$ghs")" ;;
  esac
}

# _add_under <root> -- appends every immediate child of <root> holding a .git file or
# directory, in sorted order, to the CALLER's `repos` array and `count` (bash dynamic scope;
# both callers declare them local). A root with none prints one line and appends nothing.
_add_under() {
  local found r
  found="$(for r in "${1%/}"/*/; do [ -e "${r}.git" ] && printf '%s\n' "${r%/}"; done | LC_ALL=C sort)"
  if [ -z "$found" ]; then echo "== ${1}: --under found no git repos"; return 0; fi
  while IFS= read -r r; do count=$(( count + 1 )); repos[count]="$r"; done <<< "$found"
}

# _expand_bare_under <verb> -- a trailing `--under` given no directory expands to every root
# in the wrap.roots knob (tilde-expanded, listed order), appended to the CALLER's `unders`
# array and `nu` counter (same bash-dynamic-scope convention as `_add_under`'s `repos`/
# `count`). An empty knob is a hard error naming it, so a bare --under never silently means
# "nothing" -- `--under <root>` with a path is unaffected either way.
_expand_bare_under() {
  local roots r
  roots="$(kit_config_get_root wrap.roots "")"
  if [ -z "$roots" ]; then
    echo "wrap.sh ${1}: --under given no directory and wrap.roots is empty" >&2
    return 64
  fi
  for r in $roots; do
    case "$r" in
      "~") r="$HOME" ;;
      "~/"*) r="$HOME/${r#\~/}" ;;
    esac
    nu=$(( nu + 1 )); unders[nu]="$r"
  done
  want_under=0
}

cmd_scan() {
  local ghs arg count=0 i=1 want_under=0 nu=0
  local repos unders
  for arg in "$@"; do
    case "$arg" in
      --under=*) nu=$(( nu + 1 )); unders[nu]="${arg#--under=}" ;;
      --under) want_under=1 ;;
      -*) echo "wrap.sh scan: unknown flag '$arg'" >&2; return 64 ;;
      *) if [ "$want_under" = 1 ]; then nu=$(( nu + 1 )); unders[nu]="$arg"; want_under=0
         else count=$(( count + 1 )); repos[count]="$arg"; fi ;;
    esac
  done
  if [ "$want_under" = 1 ]; then _expand_bare_under scan || return 64; fi
  [ "$count" -ge 1 ] || [ "$nu" -ge 1 ] || { echo "usage: wrap.sh scan [--under <root>]... <repo> [<repo>...]" >&2; return 64; }
  while [ "$i" -le "$nu" ]; do _add_under "${unders[$i]}"; i=$(( i + 1 )); done
  ghs="$(_gh_state)"
  i=1
  while [ "$i" -le "$count" ]; do _scan_repo "${repos[$i]}" "$ghs"; i=$(( i + 1 )); done
  echo "===================================================================="
  echo "Report only. Deletion, merging and pulling stay a judgment call."
  return 0
}

# --------------------------------------------------------------------------- apply

APPLY=0
WORKTREES=0
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

_scanned_tip() { awk -v b="$1" '$1 == b { print $2 }' "$TIPS_FILE"; }

# _merge_proof <repo> <default branch> <gh state> <branch> -- prints the proof that the branch
# already reached the default branch and exits 0; exit 1 when no proof exists. The two proofs are
# the same two `_apply_branches` deletes a branch under: a plain ancestor, or the gh squash proof.
_merge_proof() {
  local repo="$1" def="$2" ghs="$3" b="$4" tip json
  if git -C "$repo" merge-base --is-ancestor "$b" "origin/${def}" 2>/dev/null; then
    printf 'ancestor of origin/%s\n' "$def"; return 0
  fi
  [ "$ghs" = "ok" ] || return 1
  tip="$(git -C "$repo" rev-parse "$b" 2>/dev/null)"
  json="$(_squash_json "$(_origin_url "$repo")" "$b")"
  [ "$(_squash_verdict "$json" "$tip" "$def")" = "OK" ] || return 1
  printf 'squash-merged per gh\n'
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
    tip="$(git -C "$repo" rev-parse "$wtb" 2>/dev/null)"
    scanned="$(_scanned_tip "$wtb")"
    if [ -n "$scanned" ] && [ "$tip" != "$scanned" ]; then
      echo "     SKIP ${wt}: ${wtb} tip moved during this run ($(_short "$scanned") -> $(_short "$tip"))"; continue
    fi
    lock="unlocked"; _wt_locked "$wt" && lock="locked"
    if [ "$lock" = "locked" ] && _wt_lock_live "$wt"; then
      echo "     SKIP ${wt}: locked by live pid $(_wt_lock_pid "$wt") (an agent is still running)"; continue
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
  for b in $(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/); do
    case "$b" in "$def"|main|master) echo "     SKIP ${b}: default or protected branch name"; continue ;; esac
    if [ "$b" = "$cur" ]; then echo "     SKIP ${b}: currently checked out"; continue; fi
    if git -C "$repo" worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/${b}"; then
      echo "     SKIP ${b}: held by a worktree"; continue
    fi
    if [ "$fetch_ok" != 1 ]; then
      echo "     SKIP ${b}: fetch failed, stale ancestor data"; continue
    fi
    tip="$(git -C "$repo" rev-parse "$b" 2>/dev/null)"
    scanned="$(_scanned_tip "$b")"
    if [ -n "$scanned" ] && [ "$tip" != "$scanned" ]; then
      echo "     SKIP ${b}: tip moved during this run ($(_short "$scanned") -> $(_short "$tip"))"; continue
    fi
    # -D, not -d: the proof above is wrap's own, against origin/<def>. `branch -d` judges
    # against the branch's OWN upstream (or HEAD when it has none), so it refused a branch
    # that tracks another ref or nothing even though origin/<def> already holds its tip.
    if git -C "$repo" merge-base --is-ancestor "$b" "origin/${def}" 2>/dev/null; then
      run "$repo" "delete ${b} (ancestor of origin/${def})" git -C "$repo" branch -D "$b"
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

# _union_marked <repo> <path> -- 0 when .gitattributes declares the path merge=union.
# The repo declares which files resolve by keeping every line from both sides. That
# declaration, not a guess, is what makes carrying local lines across a pull correct.
_union_marked() {
  case "$(git -C "$1" check-attr merge -- "$2" 2>/dev/null)" in
    *"merge: union") return 0 ;;
  esac
  return 1
}

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

# _carry_stray_file <repo> <def> <path> <lines-file> <n> -- commits origin/<def>'s version of
# the file plus the stray lines onto a new branch in a scratch worktree and pushes it. The
# lines land below the `---` anchor when the file has one, the rule the union carry uses,
# else at the end. The main checkout's working copy is never touched. Opens no PR.
_carry_stray_file() {
  local repo="$1" def="$2" f="$3" add="$4" n="$5" slug branch wt base head_n name
  if [ "$(kit_config_get_root wrap.carry_stray_lines true)" != "true" ]; then
    echo "     ${n} stray lines in ${f} stay in the working copy (wrap.carry_stray_lines=false)"; return 0
  fi
  slug="$(printf '%s' "$f" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"
  # An open carry branch for this file means an earlier run already carried; a second one
  # would duplicate the lines. They stay in the working copy until that branch merges.
  if [ -n "$(git -C "$repo" ls-remote --heads origin "wrap/stray-${slug}-*" 2>/dev/null)" ]; then
    echo "     SKIP ${f}: ${n} stray lines, but an origin wrap/stray-${slug}-* branch already carries this file; merge it first"
    return 0
  fi
  if [ "$APPLY" != 1 ]; then
    echo "     WOULD carry ${n} stray lines in ${f} onto a branch"; return 0
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
    echo "     open its PR with: gh pr create --head ${branch}"
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

_apply_repo() {
  local repo="$1" ghs="$2"
  _is_repo "$repo" || { echo "== ${repo}: not a git repo, skipped"; return 0; }
  echo "== ${repo}"
  local fetch_ok=1
  git -C "$repo" fetch --prune -q 2>/dev/null || { fetch_ok=0; echo "     (fetch failed; every delete is skipped)"; }

  local def
  def="$(_default_branch "$repo")" || {
    echo "     SKIP ${repo}: no default branch resolved (origin/HEAD, origin/main and origin/master all absent)"
    return 0
  }
  local cur; cur="$(git -C "$repo" branch --show-current 2>/dev/null)"

  # Tip snapshot for this repo, taken once, compared right before each delete. --tips-file
  # substitutes a prepared snapshot so a test can stage a tip that moved mid-run.
  local own_snapshot=1
  if [ -n "$TIPS_OVERRIDE" ]; then
    TIPS_FILE="$TIPS_OVERRIDE"; own_snapshot=0
  else
    TIPS_FILE="$(mktemp)"
    git -C "$repo" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/ > "$TIPS_FILE" 2>/dev/null
  fi

  _apply_worktrees "$repo" "$def" "$cur" "$fetch_ok" "$ghs"
  if [ -n "$OWN_SET" ]; then
    # The named worktrees' branches were deleted by the worktree step itself; the
    # all-branches sweep would reach past the session's scope into other sessions'.
    echo "-- branches:"
    echo "     SKIP branch sweep: --own scopes cleanup to the named worktrees"
  else
    _apply_branches "$repo" "$def" "$cur" "$fetch_ok" "$ghs"
  fi
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

  echo "-- pull:"
  if [ "$cur" = "$def" ]; then
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
      --under=*) nu=$(( nu + 1 )); unders[nu]="${arg#--under=}" ;;
      --under) want_under=1 ;;
      --own=*) OWN_N=$(( OWN_N + 1 )); OWN_PATHS[OWN_N]="${arg#--own=}" ;;
      --own) want_own=1 ;;
      --tips-file=*) TIPS_OVERRIDE="${arg#--tips-file=}" ;;
      --tips-file) want_tips=1 ;;
      -*) echo "wrap.sh apply: unknown flag '$arg'" >&2; return 64 ;;
      *) if [ "$want_own" = 1 ]; then OWN_N=$(( OWN_N + 1 )); OWN_PATHS[OWN_N]="$arg"; want_own=0
         elif [ "$want_under" = 1 ]; then nu=$(( nu + 1 )); unders[nu]="$arg"; want_under=0
         elif [ "$want_tips" = 1 ]; then TIPS_OVERRIDE="$arg"; want_tips=0
         else count=$(( count + 1 )); repos[count]="$arg"; fi ;;
    esac
  done
  [ "$want_tips" = 0 ] || { echo "wrap.sh apply: --tips-file needs a path" >&2; return 64; }
  [ "$want_own" = 0 ] || { echo "wrap.sh apply: --own needs a worktree path" >&2; return 64; }
  if [ -n "$TIPS_OVERRIDE" ] && [ ! -f "$TIPS_OVERRIDE" ]; then
    echo "wrap.sh apply: --tips-file '${TIPS_OVERRIDE}' is not an existing file" >&2; return 64
  fi
  if [ "$want_under" = 1 ]; then _expand_bare_under apply || return 64; fi
  [ "$count" -ge 1 ] || [ "$nu" -ge 1 ] || { echo "usage: wrap.sh apply [--apply] [--worktrees] [--own <path>]... [--under <root>]... <repo> [<repo>...]" >&2; return 64; }
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
  local ghs; ghs="$(_gh_state)"
  i=1
  while [ "$i" -le "$count" ]; do _apply_repo "${repos[$i]}" "$ghs"; i=$(( i + 1 )); done
  echo "== ${MODE} complete. PR merges, deploy dispatch and board rows stay with the command."
  [ "$FAILURES" = 0 ] || return 2
  return 0
}

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
_pr_gate() {
  printf '%s' "$1" | jq -r --arg def "$2" '
    def checks: (.statusCheckRollup // []);
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
  local repo="$1" branch="$2" def="$3" head_oid="$4" wt tip scratch="" rc
  REMERGE_OID=""
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
  _remerge_push "$repo" "$wt" "$branch" "$def" "$tip"; rc=$?
  [ -n "$scratch" ] && _scratch_wt_drop "$repo" "$wt"
  return "$rc"
}

# _remerge_push <repo> <wt> <branch> <def> <tip> -- the merge and push half of
# `_union_remerge`, run in whichever checkout it picked.
_remerge_push() {
  local repo="$1" wt="$2" branch="$3" def="$4" tip="$5"
  git -C "$repo" fetch -q origin "$def" 2>/dev/null || { echo "     fetch origin ${def} failed"; return 1; }
  if git -C "$repo" merge-base --is-ancestor "origin/${def}" "$tip" 2>/dev/null; then
    echo "     ${branch} already contains origin/${def}, so a re-merge cannot clear the conflict"; return 1
  fi
  if ! git -C "$wt" merge --no-edit "origin/${def}" >/dev/null 2>&1; then
    git -C "$wt" merge --abort >/dev/null 2>&1
    echo "     merging origin/${def} into ${branch} conflicts beyond the union-marked files, aborted"
    return 1
  fi
  _union_dedupe_rows "$wt" "$tip" || return 1
  if ! git -C "$wt" push -q origin "HEAD:refs/heads/${branch}" 2>/dev/null; then
    echo "     push of the re-merged ${branch} failed; origin still holds the PR head"
    return 1
  fi
  REMERGE_OID="$(git -C "$wt" rev-parse HEAD)"
  echo "     re-merged origin/${def} into ${branch}, pushed $(_short "$REMERGE_OID")"
  return 0
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
  local do_apply=0 repo="" count=0 pr_only=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) do_apply=1; shift ;;
      --pr) pr_only="${2:-}"; shift 2 ;;
      -*) echo "wrap.sh merge: unknown flag '$1'" >&2; return 64 ;;
      *) count=$(( count + 1 )); repo="$1"; shift ;;
    esac
  done
  [ "$count" -eq 1 ] || { echo "usage: wrap.sh merge [--apply] [--pr N] <repo>" >&2; return 64; }
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
      if _union_remerge "$repo" "$c_head" "$def" "$c_oid"; then
        # Wait for GitHub to see the pushed head and recompute mergeability, then gate only
        # that head: a head that never arrived or that someone else pushed is refused.
        detail="$(_pr_detail_settled "$url" "$conflict_n" "$REMERGE_OID" "$c_oid")"
        local r_head; r_head="$(printf '%s' "$detail" | jq -r '.headRefOid // ""' 2>/dev/null)"
        verdict="$(_pr_gate "$detail" "$def")"
        if [ "$r_head" != "$REMERGE_OID" ]; then
          verdict="SKIP head is $(_short "$r_head"), not the pushed $(_short "$REMERGE_OID")"
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
  local tv; tv="$(_tree_verify "$repo" "$def" "$head_oid")"
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

# _tree_verify <repo> <def> <head_oid> -- "OK", "MISMATCH <n>", or "UNVERIFIABLE <reason>".
# Checks the WHOLE tree first (the common case: the squash carried nothing else onto the
# default branch), falling back to only the paths the PR itself touched, because another
# commit landing on the default branch meanwhile is not the mismatch this guards against.
_tree_verify() {
  local repo="$1" def="$2" head_oid="$3" tip base paths diff_paths n
  git -C "$repo" fetch -q origin "$def" 2>/dev/null || { echo "UNVERIFIABLE fetch of ${def} failed"; return; }
  tip="$(git -C "$repo" rev-parse "origin/${def}" 2>/dev/null)"
  [ -n "$tip" ] || { echo "UNVERIFIABLE origin/${def} did not resolve"; return; }
  git -C "$repo" cat-file -e "${head_oid}^{commit}" 2>/dev/null || {
    echo "UNVERIFIABLE the PR head is not a local object"; return; }
  if [ "$(git -C "$repo" rev-parse "${tip}^{tree}" 2>/dev/null)" = \
       "$(git -C "$repo" rev-parse "${head_oid}^{tree}" 2>/dev/null)" ]; then
    echo "OK"; return
  fi
  base="$(git -C "$repo" merge-base "$head_oid" "$tip" 2>/dev/null)"
  [ -n "$base" ] || { echo "UNVERIFIABLE no common history with ${def}"; return; }
  paths="$(git -C "$repo" diff --name-only "$base" "$head_oid" 2>/dev/null)"
  [ -n "$paths" ] || { echo "UNVERIFIABLE the PR touched no path git can name"; return; }
  # ponytail: word-splits $paths on IFS, so a touched filename containing a space is read as
  # two paths. Upgrade to NUL-delimited (diff -z + a bash array) if that ever bites.
  diff_paths="$(git -C "$repo" diff --name-only "$tip" "$head_oid" -- $paths 2>/dev/null)"
  if [ -z "$diff_paths" ]; then
    echo "OK"
  else
    n="$(printf '%s\n' "$diff_paths" | grep -c .)"
    echo "MISMATCH ${n}"
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
  local wt="" title="" body_file="" arg count=0 want="" flags_given=0
  for arg in "$@"; do
    if [ -n "$want" ]; then
      case "$want" in title) title="$arg" ;; body) body_file="$arg" ;; esac
      want=""; continue
    fi
    case "$arg" in
      --title) want=title; flags_given=1 ;;
      --title=*) title="${arg#--title=}"; flags_given=1 ;;
      --body-file) want=body; flags_given=1 ;;
      --body-file=*) body_file="${arg#--body-file=}"; flags_given=1 ;;
      -*) echo "wrap.sh land: unknown flag '$arg'" >&2; return 64 ;;
      *) count=$(( count + 1 )); wt="$arg" ;;
    esac
  done
  [ -z "$want" ] || { echo "wrap.sh land: --${want} needs a value" >&2; return 64; }
  [ "$count" -eq 1 ] || { echo "usage: wrap.sh land <worktree> [--title T] [--body-file F]" >&2; return 64; }
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

  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    echo "wrap.sh land: ${wt} is dirty, so the branch is not what a PR would carry" >&2; return 1
  fi
  local branch; branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || { echo "wrap.sh land: ${wt} is on a detached HEAD, so there is no branch to land" >&2; return 1; }
  local def; def="$(_default_branch "$wt")" || { echo "wrap.sh land: no default branch resolved for ${wt}" >&2; return 1; }
  case "$branch" in
    "$def"|main|master)
      echo "wrap.sh land: HEAD is ${branch}, the default or a protected branch name" >&2; return 1 ;;
  esac
  local ghs; ghs="$(_gh_state)"
  [ "$ghs" = "ok" ] || { echo "wrap.sh land: gh is ${ghs}" >&2; return 1; }

  git -C "$wt" fetch -q origin "$def" 2>/dev/null
  local ahead; ahead="$(git -C "$wt" rev-list --count "origin/${def}..${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac
  [ "$ahead" -gt 0 ] || {
    echo "wrap.sh land: ${branch} has no commits ahead of origin/${def}" >&2; return 1; }

  local tip url rc
  tip="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  url="$(_origin_url "$wt")"
  [ -n "$title" ] || title="$(git -C "$wt" log -1 --format=%s 2>/dev/null)"

  echo "land ${branch} -> ${def} (${wt})"

  git -C "$wt" push origin "$branch"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "     PUSH REFUSED: git push origin ${branch} exited ${rc}" >&2
    return "$rc"
  fi
  echo "     pushed ${branch} ($(_short "$tip"))"

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

  _gh_merge_retry "$n" "$url" "$tip"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "     MERGE FAILED #${n}: exit ${rc}" >&2; return 2; fi

  local after state sha
  after="$(gh pr view "$n" --repo "$url" --json state,mergeCommit 2>/dev/null)"
  state="$(printf '%s' "$after" | jq -r '.state // ""' 2>/dev/null)"
  sha="$(printf '%s' "$after" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)"
  if [ "$state" != "MERGED" ]; then
    echo "     MERGE FAILED #${n}: state is '${state:-unknown}', not MERGED" >&2; return 2
  fi
  local tv; tv="$(_tree_verify "$wt" "$def" "$tip")"
  case "$tv" in
    OK) echo "     merged #${n} (${sha}): tree verified" ;;
    MISMATCH*)
      echo "     merged #${n} (${sha}): TREE MISMATCH, ${tv#MISMATCH } paths differ; ${def} does not hold the PR head" >&2
      return 3 ;;
    *)
      echo "     merged #${n} (${sha}): tree ${tv}" >&2
      return 3 ;;
  esac

  # Mirrors _apply_origin_branches: leased to the tip land itself pushed, skipped when an
  # open PR still bases off this branch (deleting it would close that PR), and never fails
  # land, since the merge is already verified.
  if [ "$(kit_config_get_root wrap.delete_merged_remote_branches true)" != "true" ]; then
    echo "     ${branch} left on origin (wrap.delete_merged_remote_branches=false)"
  else
    local base_open; base_open="$(gh pr list --repo "$url" --state open --json baseRefName 2>/dev/null \
      | jq -r --arg b "$branch" '[.[] | select(.baseRefName == $b)] | length' 2>/dev/null)"
    case "$base_open" in
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
  # another branch, and neither is a reason to strand a merged worktree. It is never
  # stashed past and never reset; the refusal is reported and the tidy continues.
  local blocked=0 cur
  cur="$(git -C "$repo" branch --show-current 2>/dev/null)"
  if [ "$cur" != "$def" ]; then
    echo "     PULL BLOCKED: ${repo} is on '${cur:-<detached>}', not ${def}"
    blocked=1
  elif git -C "$repo" pull --ff-only; then
    echo "     pulled ${repo}: $(git -C "$repo" log --oneline -1 2>/dev/null)"
  else
    echo "     PULL BLOCKED: pull --ff-only refused in ${repo}, nothing was stashed or reset"
    blocked=1
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

# --------------------------------------------------------------------------- start

# cmd_start <repo> <branch> -- the start half `land` finishes. Sessions repeatedly
# hand-run "worktree off origin/<default> with a fresh branch" when the main
# checkout is dirty or foreign; this is that step as a verb. It resolves the
# repo's default branch through the same `_default_branch` helper every other
# verb uses, fetches it quietly, and creates <repo>/.claude/worktrees/<slug> at
# origin/<default> on a NEW local branch <branch>, where <slug> is the branch
# name with its `type/` prefix stripped (gate-ledger's rid rule). The worktree
# path is the only stdout line, so a caller captures it directly; every
# diagnostic goes to stderr.
#
# A dirty main checkout is never a refusal: the worktree is isolated, which is
# the point of the verb. What refuses, each with its reason and before any
# write: a missing argument or a <repo> that is not a git repo or an invalid
# <branch> name (usage, 64); <branch> naming the default or a protected branch;
# <branch> already a local ref, or already pushed to origin; the worktree path
# already on disk; no default branch resolved; a failed fetch; a held
# index.lock; and a `worktree add` git itself refuses.
cmd_start() {
  [ $# -eq 2 ] || { echo "usage: wrap.sh start <repo> <branch>" >&2; return 64; }
  local repo="$1" branch="$2"
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
  return 0
}

# --------------------------------------------------------------------------- log

# _realpath_f <path> -- absolute path with every symlink on it resolved. The directory must
# exist; the leaf need not.
_realpath_f() {
  local p="$1" dir base tgt n=0
  dir="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
  base="$(basename "$p")"
  while [ -L "$dir/$base" ] && [ "$n" -lt 16 ]; do
    tgt="$(readlink "$dir/$base")"
    case "$tgt" in /*) ;; *) tgt="${dir}/${tgt}" ;; esac
    dir="$(cd "$(dirname "$tgt")" 2>/dev/null && pwd -P)" || return 1
    base="$(basename "$tgt")"
    n=$(( n + 1 ))
  done
  printf '%s/%s\n' "${dir%/}" "$base"
}

# _home_fence <path> [<label>] -- 0 when <path> is the physical $HOME or sits under it.
# The fence resolves its own argument: a caller that forgets to resolve first would otherwise
# fence a string whose parent directory is a symlink pointing anywhere on disk. $HOME itself
# is accepted so this fence agrees with `_under_home`, the parity `config seams` reports on.
# Prints the reason and returns 1 otherwise.
_home_fence() {
  local p="$1" label="${2:-wrap}" home_real real
  home_real="$(cd "$HOME" 2>/dev/null && pwd -P)" \
    || { echo "${label}: cannot resolve HOME" >&2; return 1; }
  real="$(_realpath_f "$p")" || { echo "${label}: cannot resolve '${p}'" >&2; return 1; }
  case "$real" in
    "$home_real"|"$home_real"/*) return 0 ;;
    *) echo "${label}: '${real}' is outside HOME (${home_real})" >&2; return 1 ;;
  esac
}

# _refuse_symlink <path> [<label>] -- 1 when <path> is a symlink. A symlink at a write target
# redirects the append to whatever it points at, so every write path refuses one.
_refuse_symlink() {
  local p="$1" label="${2:-wrap}"
  [ -L "$p" ] || return 0
  echo "${label}: '${p}' is a symlink" >&2
  return 1
}

# _worktree_copy <file>: the configured log names one fixed file, usually inside a repo's
# main checkout. A session that works in a git worktree of that same repo cannot commit a
# line written to the main checkout (its branch is not the session's), so when the current
# directory is a worktree sharing the file's repo, the same repo-relative path inside the
# current worktree is the target. Prints the path to use; the input when nothing applies.
_worktree_copy() {
  local file="$1" fdir fcommon ftop cur_common cur_top rel
  fdir="$(dirname "$file")"
  fcommon="$(git -C "$fdir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  ftop="$(git -C "$fdir" rev-parse --show-toplevel 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  cur_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  cur_top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  [ "$fcommon" = "$cur_common" ] || { printf '%s' "$file"; return 0; }
  [ "$ftop" != "$cur_top" ] || { printf '%s' "$file"; return 0; }
  rel="${file#"$ftop"/}"
  # `[ -f ]` follows symlinks, so this gate accepts a symlink whose target is a regular file
  # anywhere on disk. The returned path is a NEW path no earlier check saw: every caller must
  # re-run its symlink refusal and its fence on the value this prints.
  [ -f "$cur_top/$rel" ] || { printf '%s' "$file"; return 0; }
  printf '%s' "$cur_top/$rel"
}

# _log_anchor_head_lines <file>: prints how many lines of <file> stay ABOVE the new entry.
# The anchor is the first line that is exactly `---` (the header/entries separator), plus
# any blank lines immediately following it, so the new entry lands as the newest ENTRY, not
# above the file's title. If line 1 is itself `---` (a YAML frontmatter opening delimiter),
# the frontmatter's own closing `---` is the SECOND such line and becomes the anchor instead,
# so the entry never lands inside frontmatter. Prints 0 when no anchor line exists at all
# (or line 1 is `---` with no closing delimiter): the caller falls back to the old prepend-at-
# line-0 behavior rather than failing, since a file with no recognizable header has no wrong
# place to land above, and every pre-anchor-rule caller already depends on that prepend shape.
_log_anchor_head_lines() {
  awk '
    NR==1 { want = ($0=="---") ? 2 : 1 }
    state==0 {
      if ($0=="---") { c++; if (c==want) { state=1; head=NR } }
      next
    }
    state==1 {
      if ($0=="") { head=NR; next }
      state=2
    }
    END { print head+0 }
  ' "$1"
}

cmd_log() {
  local date_str text="" arg have_text=0
  date_str="$(date +%F)"
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --date) [ $# -ge 2 ] || { echo "usage: wrap.sh log [--date YYYY-MM-DD] \"<slug>: <one sentence>\"" >&2; return 64; }
              date_str="$2"; shift 2 ;;
      *) [ "$have_text" = 0 ] || { echo "wrap.sh log: one text argument only" >&2; return 64; }
         text="$arg"; have_text=1; shift ;;
    esac
  done
  [ "$have_text" = 1 ] && [ -n "$text" ] || { echo "usage: wrap.sh log [--date YYYY-MM-DD] \"<slug>: <one sentence>\"" >&2; return 64; }

  # The date prefixes a line in a file the kit writes. Anything but a plain YYYY-MM-DD, a
  # second line or an out-of-range field included, refuses before any write.
  case "$date_str" in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
    *) echo "wrap log: --date must be YYYY-MM-DD" >&2; return 1 ;;
  esac

  case "$text" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      echo "wrap log: the text carries a control character; one line, no tabs" >&2; return 1 ;;
  esac
  case "$text" in
    *$'\xe2\x80\x94'*|*$'\xe2\x80\x93'*)
      echo "wrap log: the text carries an em or en dash; use a comma, a colon or a new sentence" >&2; return 1 ;;
  esac

  local line="${date_str} · ${text}"

  local target; target="$(kit_config_get_root wrap.activity_log "")"
  if [ -z "$target" ]; then
    printf '%s\n' "$line"
    echo "wrap log: no wrap.activity_log key in the kit-root kit.toml; line not written" >&2
    return 0
  fi

  case "$target" in
    "~"/*) target="${HOME}/${target#\~/}" ;;
    /*) ;;
    *) echo "wrap log: wrap.activity_log must be an absolute or ~-prefixed path, got '${target}'" >&2; return 1 ;;
  esac

  local resolved
  resolved="$(_realpath_f "$target")" || { echo "wrap log: cannot resolve '${target}'" >&2; return 1; }
  _home_fence "$resolved" "wrap log" || return 1
  [ -f "$resolved" ] || { echo "wrap log: '${resolved}' is not an existing regular file" >&2; return 1; }

  # The worktree copy is a different path, gated only by `[ -f ]`, so it gets the same
  # refusal and the same fence before anything is written to it. The refusal covers the leaf;
  # resolving the whole path covers a symlink at any parent directory, which would otherwise
  # carry the write outside HOME while the string still reads as being under the worktree.
  resolved="$(_worktree_copy "$resolved")"
  _refuse_symlink "$resolved" "wrap log" || return 1
  resolved="$(_realpath_f "$resolved")" \
    || { echo "wrap log: cannot resolve the worktree copy" >&2; return 1; }
  _home_fence "$resolved" "wrap log" || return 1
  [ -f "$resolved" ] || { echo "wrap log: '${resolved}' is not an existing regular file" >&2; return 1; }

  local n=${#line}
  [ "$n" -gt "$LOG_LINE_BUDGET" ] && echo "wrap log: note: ${n} chars, over the ${LOG_LINE_BUDGET}-char routine budget" >&2

  local head_n tmp mode; tmp="$(mktemp)"
  head_n="$(_log_anchor_head_lines "$resolved")"
  if [ "$head_n" -gt 0 ] 2>/dev/null; then
    sed -n "1,${head_n}p" "$resolved" > "$tmp"
    printf '%s\n' "$line" >> "$tmp"
    tail -n "+$((head_n + 1))" "$resolved" >> "$tmp"
  else
    printf '%s\n' "$line" > "$tmp"
    cat "$resolved" >> "$tmp"
  fi
  mode="$(_fmode "$resolved")"
  case "$mode" in ''|*[!0-7]*) mode="" ;; esac
  [ -n "$mode" ] && chmod "$mode" "$tmp"   # mktemp opens 0600; carry the target's mode over
  mv -f "$tmp" "$resolved"
  printf '%s\n' "$line"
  kit_warn_default_branch "$resolved" "wrap log"
  return 0
}

# --------------------------------------------------------------------------- knowledge-root

# cmd_knowledge_root <repo> -- prints one absolute directory and always
# exits 0: `knowledge.root` empty or any failure resolving/fencing/creating it falls back to
# `<repo>/.claude/memory`, never an error. The `<repo>` argument itself is validated (must
# exist, basename must not be `.`/`..`/empty) and THAT failure is the one case that is a
# real usage error (exit 64), since there is no repo to fall back under.
cmd_knowledge_root() {
  [ $# -eq 1 ] || { echo "usage: wrap.sh knowledge-root <repo>" >&2; return 64; }
  local repo="$1" repo_real trimmed base
  repo_real="$(cd "$repo" 2>/dev/null && pwd -P)" \
    || { echo "usage: wrap.sh knowledge-root <repo>" >&2; return 64; }
  trimmed="${repo_real%/}"
  base="${trimmed##*/}"
  case "$base" in
    .|..|"") echo "usage: wrap.sh knowledge-root <repo>" >&2; return 64 ;;
  esac

  local fallback="${repo_real}/.claude/memory"
  local root; root="$(kit_config_get_root knowledge.root "")"
  if [ -z "$root" ]; then
    printf '%s\n' "$fallback"
    return 0
  fi

  # Same `~` expansion rule cmd_log applies to wrap.activity_log.
  case "$root" in
    "~"/*) root="${HOME}/${root#\~/}" ;;
  esac

  # The dir variant of _realpath_f: `cd && pwd -P` follows every symlink on the path and
  # collapses it to the physical directory, or fails when the directory does not exist.
  local resolved
  resolved="$(cd "$root" 2>/dev/null && pwd -P)"
  if [ -z "$resolved" ]; then
    echo "knowledge-root: '${root}' is not an existing directory, using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi

  if ! _home_fence "$resolved" knowledge-root; then
    echo "knowledge-root: using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi

  # No `_write_guard` here (unlike `cmd_log`/`cmd_stage`): the only write below is `mkdir -p`
  # under `<root>/projects/<base>`, which sits OUTSIDE `$repo` entirely -- `_write_guard`
  # shells out to `git -C "$repo" rev-parse`, which fails on a non-git `<repo>` and reported
  # the misleading "index.lock held by another writer" for a directory with no lock and no git
  # dir at all. `<root>` itself is fenced above and re-fenced after the create; that is the
  # write this verb owes a guard for, and it already has one via `_home_fence`.
  #
  # Only `<root>` was fenced above. `mkdir -p` walks through a symlink at `projects` or at the
  # leaf without complaint, so both are refused before the create, and the created directory is
  # re-resolved and re-fenced after it.
  local projects="${resolved}/projects"
  local target="${projects}/${base}"
  if ! _refuse_symlink "$projects" knowledge-root || ! _refuse_symlink "$target" knowledge-root; then
    echo "knowledge-root: using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  if ! mkdir -p "$target" 2>/dev/null; then
    echo "knowledge-root: could not create '${target}', using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  local target_real
  target_real="$(cd "$target" 2>/dev/null && pwd -P)"
  if [ -z "$target_real" ] || ! _home_fence "$target_real" knowledge-root; then
    echo "knowledge-root: using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  printf '%s\n' "$target_real"
  return 0
}

# --------------------------------------------------------------------------- stage

# cmd_stage "<title>" "<intent>" "<home>" [--repo <repo>] -- resolves the
# staging file the same way cmd_log resolves its target (dir realpath, symlink refusal, a
# HOME/repo fence, `_worktree_copy`), then hands the write itself to the one place the
# staging-block grammar and its dedupe rule live: `staging-format.py stage`.
cmd_stage() {
  local repo="" arg count=0
  local pos1="" pos2="" pos3=""
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --repo)
        [ $# -ge 2 ] || {
          echo 'usage: wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]' >&2
          return 64
        }
        repo="$2"; shift 2 ;;
      *)
        count=$(( count + 1 ))
        case "$count" in 1) pos1="$arg" ;; 2) pos2="$arg" ;; 3) pos3="$arg" ;; esac
        shift ;;
    esac
  done
  [ "$count" -eq 3 ] || {
    echo 'usage: wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]' >&2
    return 64
  }
  local title="$pos1" intent="$pos2" home="$pos3"

  local repo_top
  if [ -n "$repo" ]; then
    repo_top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
  else
    repo_top="$(git rev-parse --show-toplevel 2>/dev/null)"
  fi
  [ -n "$repo_top" ] || {
    echo 'usage: wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]' >&2
    return 64
  }
  repo_top="$(cd "$repo_top" 2>/dev/null && pwd -P)" \
    || { echo "wrap stage: cannot resolve the repo toplevel" >&2; return 64; }

  local staging="${BACKLOG_STAGE_STAGING:-${repo_top}/_meta/backlog-staging.md}"
  local backlog="${BACKLOG_STAGE_BACKLOG:-${repo_top}/_meta/BACKLOG.md}"

  # The staging path's parent directory must resolve. Only the default parent (the repo's
  # own `_meta/`) is created on demand; an env-override parent must already exist.
  local staging_dir; staging_dir="$(dirname "$staging")"
  if [ -z "${BACKLOG_STAGE_STAGING:-}" ]; then
    mkdir -p "$staging_dir" 2>/dev/null \
      || { echo "wrap stage: cannot create ${staging_dir}" >&2; return 1; }
  fi
  local staging_dir_real
  staging_dir_real="$(cd "$staging_dir" 2>/dev/null && pwd -P)" \
    || { echo "wrap stage: '${staging_dir}' does not resolve" >&2; return 1; }

  local leaf; leaf="$(basename "$staging")"
  local resolved="${staging_dir_real%/}/${leaf}"

  # Never a symlink; absent or an existing regular file only.
  _refuse_symlink "$resolved" "wrap stage" || return 1
  if [ -e "$resolved" ] && [ ! -f "$resolved" ]; then
    echo "wrap stage: '${resolved}' is not a regular file" >&2; return 1
  fi

  # Inside the repo toplevel by default; under HOME when the env override chose the path. The
  # override comes from the environment, which a repo `.envrc` writes, so it may only append to
  # a file that already exists: create-on-absent under HOME would let it seed a new block into
  # any absent path, an agent instruction file included. Only the repo default creates.
  if [ -n "${BACKLOG_STAGE_STAGING:-}" ]; then
    _home_fence "$resolved" "wrap stage" || return 1
    [ -f "$resolved" ] \
      || { echo "wrap stage: '${resolved}' is not an existing regular file" >&2; return 1; }
  else
    case "$resolved" in
      "$repo_top"/*) ;;
      *) echo "wrap stage: '${resolved}' is outside the repo (${repo_top})" >&2; return 1 ;;
    esac
  fi

  if ! _write_guard "$repo_top"; then
    echo "wrap stage: index.lock held by another writer" >&2; return 1
  fi

  # The worktree copy is a path none of the checks above saw, and `_worktree_copy` gates it
  # only with `[ -f ]`, which follows a symlink. Re-run the refusal and the fence on it. The
  # refusal covers the leaf; resolving the whole path covers a symlink at any parent directory
  # (`<worktree>/_meta` pointing off disk), which the prefix rules below would otherwise pass
  # because the unresolved string still starts with the worktree toplevel.
  local pre_copy="$resolved"
  resolved="$(_worktree_copy "$resolved")"
  if [ "$resolved" != "$pre_copy" ]; then
    _refuse_symlink "$resolved" "wrap stage" || return 1
    resolved="$(_realpath_f "$resolved")" \
      || { echo "wrap stage: cannot resolve the worktree copy" >&2; return 1; }
    [ -f "$resolved" ] \
      || { echo "wrap stage: '${resolved}' is not a regular file" >&2; return 1; }
    if [ -n "${BACKLOG_STAGE_STAGING:-}" ]; then
      _home_fence "$resolved" "wrap stage" || return 1
    else
      # The copy lives in the CURRENT worktree, which is a different toplevel of the same repo.
      # Both toplevels are compared as realpaths, matching the resolved copy.
      local cur_top
      cur_top="$(git rev-parse --show-toplevel 2>/dev/null)" \
        && cur_top="$(cd "$cur_top" 2>/dev/null && pwd -P)"
      case "$resolved" in
        "$repo_top"/*) ;;
        "${cur_top:-/dev/null/never}"/*) ;;
        *) echo "wrap stage: '${resolved}' is outside the repo (${repo_top})" >&2; return 1 ;;
      esac
    fi
  fi

  [ -f "$STAGING_FORMAT_PY" ] \
    || { echo "wrap stage: staging-format.py missing at ${STAGING_FORMAT_PY}" >&2; return 1; }

  # Build the JSON with sys.argv, never string interpolation: title/intent/home are
  # session text and must never be able to forge a stdin field.
  python3 -c '
import json, sys
title, intent, home, staging, backlog = sys.argv[1:6]
json.dump(
    {"title": title, "intent": intent, "home": home, "staging": staging, "backlog": backlog},
    sys.stdout,
)
' "$title" "$intent" "$home" "$resolved" "$backlog" \
    | python3 "$STAGING_FORMAT_PY" stage
  local rc=$?
  if [ "$rc" -eq 0 ]; then kit_warn_default_branch "$resolved" "wrap stage"; fi
  return "$rc"
}

# --------------------------------------------------------------------------- default-branch

cmd_default_branch() {
  [ $# -eq 1 ] || { echo "usage: wrap.sh default-branch <repo>" >&2; return 64; }
  _is_repo "$1" || { echo "wrap.sh default-branch: $1 is not a git repo" >&2; return 1; }
  local def
  def="$(_default_branch "$1")" || { echo "wrap.sh default-branch: no default branch resolved for $1" >&2; return 1; }
  printf '%s\n' "$def"
  return 0
}

# --------------------------------------------------------------------------- entry

main() {
  local verb="${1:-}"
  [ $# -gt 0 ] && shift
  case "$verb" in
    scan)           cmd_scan "$@" ;;
    apply)          cmd_apply "$@" ;;
    merge)          cmd_merge "$@" ;;
    land)           cmd_land "$@" ;;
    start)          cmd_start "$@" ;;
    log)            cmd_log "$@" ;;
    default-branch) cmd_default_branch "$@" ;;
    knowledge-root) cmd_knowledge_root "$@" ;;
    stage)          cmd_stage "$@" ;;
    -h|--help|help|"") _usage; return 0 ;;
    *) echo "wrap: unknown verb '$verb' (try: wrap --help)" >&2; return 64 ;;
  esac
}

main "$@"
