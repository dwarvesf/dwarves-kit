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
