# wrap-session.sh -- the session verb: one read-only gather for commands/wrap.md.
# Sourced by lib/wrap/wrap.sh. stdout is exactly one JSON document; diagnostics stay on stderr.

# _session_lines_json -- stdin lines as a JSON array of strings.
_session_lines_json() { jq -R . 2>/dev/null | jq -s . 2>/dev/null; }

# _session_board_json <repo> -- active and held board rows, read straight from BACKLOG.md.
# Terminal rows are omitted: step 1 only needs rows a session could still close, and the
# board itself can be long. The wrapper path is reported so the write still goes through
# the repo's own board surface.
_session_board_json() {
  local repo="$1" file wrapper="" rows
  file="$repo/_meta/BACKLOG.md"
  [ -e "$repo/_meta/board" ] && wrapper="$repo/_meta/board"
  [ -z "$wrapper" ] && [ -e "$repo/board" ] && wrapper="$repo/board"
  if [ ! -f "$file" ]; then
    jq -cn --arg file "$file" --arg wrapper "$wrapper" \
      '{present:false,file:$file,wrapper:(if $wrapper=="" then null else $wrapper end),rows:[]}'
    return 0
  fi
  rows="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*\|/ {
      id=trim($2)
      if (id !~ /^[A-Z]+-[0-9]+$/) next
      title=trim($3)
      status=trim($(NF-1))
      state=status; sub(/[ \t].*$/, "", state)
      if (state ~ /^(queued|claimed|speccing|validated|executing|parked)$/)
        printf "%s\t%s\t%s\t%s\n", id, title, state, status
    }' "$file" 2>/dev/null \
    | jq -R 'split("\t") | {id:.[0],title:.[1],state:.[2],status:.[3]}' 2>/dev/null \
    | jq -s . 2>/dev/null)"
  [ -n "$rows" ] || rows='[]'
  jq -cn --arg file "$file" --arg wrapper "$wrapper" --argjson rows "$rows" \
    '{present:true,file:$file,wrapper:(if $wrapper=="" then null else $wrapper end),rows:$rows}'
}

# _session_worktrees_json <repo> -- porcelain worktree inventory as structured rows.
_session_worktrees_json() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function emit() {
      if (path != "") printf "%s\t%s\t%s\t%s\n", path, head, branch, detached
    }
    /^worktree / { emit(); path=substr($0, 10); head=""; branch="-"; detached="false" }
    /^HEAD / { head=$2 }
    /^branch / { branch=$2; sub(/^refs\/heads\//, "", branch) }
    /^detached/ { detached="true" }
    END { emit() }' \
  | jq -R 'split("\t") | {path:.[0],head:.[1],branch:(if .[2]=="-" then null else .[2] end),detached:(.[3]=="true")}' 2>/dev/null \
  | jq -s . 2>/dev/null
}

# _session_newest_reflog <repo> -- newest HEAD reflog unix timestamp across the worktrees.
_session_newest_reflog() {
  local repo="$1" wt ts newest=0
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    ts="$(git -C "$wt" reflog -1 --format=%ct 2>/dev/null)"
    case "$ts" in ''|*[!0-9]*) ;; *) [ "$ts" -gt "$newest" ] && newest="$ts" ;; esac
  done <<EOF_SESSION_REFL
$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10) }')
EOF_SESSION_REFL
  [ "$newest" -gt 0 ] && printf '%s\n' "$newest"
}

# _session_checkout_json <repo> <default-branch> -- checkout, dirty, counts, lock, reflog facts.
_session_checkout_json() {
  local repo="$1" def="$2" branch ahead behind dirty worktrees gd lock_exists=false lock_age="" newest
  branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
  ahead=""; behind=""
  if [ -n "$def" ]; then
    ahead="$(git -C "$repo" rev-list --count "origin/${def}..HEAD" 2>/dev/null)"
    behind="$(git -C "$repo" rev-list --count "HEAD..origin/${def}" 2>/dev/null)"
  fi
  case "$ahead" in ''|*[!0-9]*) ahead=null ;; esac
  case "$behind" in ''|*[!0-9]*) behind=null ;; esac
  dirty="$(git -C "$repo" status --short 2>/dev/null | _session_lines_json)"
  [ -n "$dirty" ] || dirty='[]'
  worktrees="$(_session_worktrees_json "$repo")"
  [ -n "$worktrees" ] || worktrees='[]'
  gd="$(git -C "$repo" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  if [ -n "$gd" ] && [ -e "$gd/index.lock" ]; then
    lock_exists=true
    lock_age="$(( $(date +%s) - $(_mtime "$gd/index.lock") ))"
  fi
  case "$lock_age" in ''|*[!0-9-]*) lock_age=null ;; esac
  newest="$(_session_newest_reflog "$repo")"
  case "$newest" in ''|*[!0-9]*) newest=null ;; esac
  jq -cn --arg branch "$branch" --arg git_dir "$gd" \
    --argjson ahead "$ahead" --argjson behind "$behind" \
    --argjson dirty "$dirty" --argjson worktrees "$worktrees" \
    --argjson lock_exists "$lock_exists" --argjson lock_age "$lock_age" --argjson newest "$newest" \
    '{branch:(if $branch=="" then null else $branch end),detached:($branch==""),ahead:$ahead,behind:$behind,
      dirty_files:$dirty,worktrees:$worktrees,newest_reflog_at:$newest,
      index_lock:{present:$lock_exists,age_seconds:$lock_age,git_dir:(if $git_dir=="" then null else $git_dir end)}}'
}

# _session_handoffs_json <repo> -- the read-only handoff scan, kept as lines plus status.
_session_handoffs_json() {
  local repo="$1" out err rc lines errline
  out="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"; err="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  bash "$LIB_ROOT/session/handoffs.sh" list --repo "$repo" --limit 0 >"$out" 2>"$err"; rc=$?
  lines="$(_session_lines_json < "$out")"; [ -n "$lines" ] || lines='[]'
  IFS= read -r errline < "$err" || errline=""
  rm -f "$out" "$err"
  jq -cn --argjson lines "$lines" --arg error "$errline" --argjson rc "$rc" \
    '{lines:$lines,exit_code:$rc,error:(if $error=="" then null else $error end)}'
}

# _session_repo_slug <origin-url> -- owner/name for GitHub remotes, empty otherwise.
_session_repo_slug() {
  local url="${1%/}" rest
  url="${url%.git}"
  case "$url" in
    git@github.com:*) rest="${url#git@github.com:}" ;;
    https://github.com/*) rest="${url#https://github.com/}" ;;
    http://github.com/*) rest="${url#http://github.com/}" ;;
    ssh://git@github.com/*) rest="${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
  rest="${rest#/}"
  case "$rest" in ""|*/*/*) return 1 ;; esac
  printf '%s\n' "$rest"
}

# _session_pr_json <detail-json> <gate> -- one compact open-PR row with check totals.
_session_pr_json() {
  local detail="$1" gate="$2"
  printf '%s' "$detail" | jq -c --arg gate "$gate" "${CI_JQ_DEFS}
    def rtime: [.completedAt, .startedAt, .createdAt] | map(real) | .[0] // \"\";
    def latest: (.statusCheckRollup // []) | group_by(.name // .context)
      | map(sort_by([(if pending then 1 else 0 end), rtime]) | last);
    {
      number, title, headRefName, headRefOid, baseRefName, isDraft,
      mergeable, mergeStateStatus, reviewDecision, gate: \$gate,
      checks: (latest as \$c | {
        total: (\$c | length),
        pending: (\$c | map(select(pending)) | length),
        failed: (\$c | map(select((pending | not)
          and (((.conclusion // .state // \"\") | ascii_upcase) != \"SUCCESS\")
          and (((.conclusion // .state // \"\") | ascii_upcase) != \"SKIPPED\"))) | length),
        latest: (\$c | map({name:(.name // .context // \"\"), status:(.status // null),
          conclusion:(.conclusion // .state // null), url:(.detailsUrl // .targetUrl // null)}))
      })
    }" 2>/dev/null
}

# _session_deploy_json <slug> <pr-json> -- check state on one merged PR's merge commit.
# All checks are reported; step 4 still chooses which names are deploy checks for the repo.
_session_deploy_json() {
  local slug="$1" prjson="$2" n sha checks state rows rc
  n="$(printf '%s' "$prjson" | jq -r '.number' 2>/dev/null)"
  sha="$(printf '%s' "$prjson" | jq -r '.merge_sha // ""' 2>/dev/null)"
  if [ -z "$slug" ] || [ -z "$sha" ]; then
    jq -cn --argjson pr "$n" --arg sha "$sha" \
      '{pr:$pr,merge_sha:(if $sha=="" then null else $sha end),state:"unsupported",checks:[]}'
    return 0
  fi
  checks="$(gh api "repos/${slug}/commits/${sha}/check-runs" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] || ! printf '%s' "$checks" | jq -e 'type == "object"' >/dev/null 2>&1; then
    jq -cn --argjson pr "$n" --arg sha "$sha" \
      '{pr:$pr,merge_sha:$sha,state:"unverified",checks:[]}'
    return 0
  fi
  rows="$(printf '%s' "$checks" | jq -c '
    [.check_runs // [] | .[]] | group_by(.name) | map(sort_by(.id // 0) | last
      | {name, status, conclusion:(.conclusion // null), url:(.html_url // null)})' 2>/dev/null)"
  [ -n "$rows" ] || rows='[]'
  state="$(printf '%s' "$rows" | jq -r '
    if length == 0 then "none"
    elif any(.[]; .status != "completed") then "pending"
    elif any(.[]; ((.conclusion // "") != "success" and (.conclusion // "") != "skipped" and (.conclusion // "") != "neutral")) then "failed"
    else "success" end' 2>/dev/null)"
  jq -cn --argjson pr "$n" --arg sha "$sha" --arg state "$state" --argjson checks "$rows" \
    '{pr:$pr,merge_sha:$sha,state:$state,checks:$checks}'
}

# _session_prs_json <repo> <default-branch> -- own open PRs, check totals, recent merge deploy state.
_session_prs_json() {
  local repo="$1" def="$2" ghs url own me n detail gate tmp open_json merged_raw merged slug prjson deploys dtmp workflows
  ghs="$(_gh_state)"
  url="$(_origin_url "$repo")"
  if [ "$ghs" != "ok" ]; then
    jq -cn --arg state "$ghs" '{gh_state:$state,error:null,open_own:[],merged_recent:[],deploys:[],dispatch_workflows:[]}'
    return 0
  fi
  own="$(_open_own_prs "$url" 2>/dev/null)"
  if [ -z "$own" ]; then
    jq -cn --arg state "$ghs" '{gh_state:$state,error:"open PR query failed",open_own:[],merged_recent:[],deploys:[],dispatch_workflows:[]}'
    return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    detail="$(_pr_detail "$url" "$n" 2>/dev/null)"
    gate=""
    [ -n "$detail" ] && gate="$(_pr_gate "$detail" "$def")"
    [ -n "$gate" ] || gate="unreadable PR JSON"
    if [ -n "$detail" ]; then
      _session_pr_json "$detail" "$gate" >> "$tmp"
    else
      jq -cn --argjson number "$n" --arg gate "$gate" '{number:$number,gate:$gate,error:"gh pr view failed"}' >> "$tmp"
    fi
  done <<EOF_SESSION_PRS
$(printf '%s' "$own" | jq -r '.[].number' 2>/dev/null)
EOF_SESSION_PRS
  open_json="$(jq -s . "$tmp" 2>/dev/null)"; [ -n "$open_json" ] || open_json='[]'
  rm -f "$tmp"

  me="$(gh api user --jq .login 2>/dev/null)"
  merged_raw="$(gh pr list --repo "$url" --state merged --limit 20 \
    --json number,title,headRefName,mergedAt,mergeCommit,author 2>/dev/null)"
  if [ -n "$merged_raw" ] && [ -n "$me" ]; then
    merged="$(printf '%s' "$merged_raw" | jq -c --arg me "$me" \
      '[.[] | select((.author.login // "") | ascii_downcase == ($me | ascii_downcase))]
       | .[0:5] | map({number,title,headRefName,mergedAt,merge_sha:(.mergeCommit.oid // null)})' 2>/dev/null)"
  fi
  [ -n "$merged" ] || merged='[]'

  slug="$(_session_repo_slug "$url" 2>/dev/null)"
  dtmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  while IFS= read -r prjson; do
    [ -n "$prjson" ] || continue
    _session_deploy_json "$slug" "$prjson" >> "$dtmp"
  done <<EOF_SESSION_DEPLOY
$(printf '%s' "$merged" | jq -c '.[]' 2>/dev/null)
EOF_SESSION_DEPLOY
  deploys="$(jq -s . "$dtmp" 2>/dev/null)"; [ -n "$deploys" ] || deploys='[]'
  rm -f "$dtmp"

  workflows="$(for f in "$repo"/.github/workflows/*.yml "$repo"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    grep -q 'workflow_dispatch' "$f" 2>/dev/null && printf '%s\n' "${f##*/}"
  done | _session_lines_json)"
  [ -n "$workflows" ] || workflows='[]'

  jq -cn --arg state "$ghs" --argjson open "$open_json" --argjson merged "$merged" \
    --argjson deploys "$deploys" --argjson workflows "$workflows" \
    '{gh_state:$state,error:null,open_own:$open,merged_recent:$merged,deploys:$deploys,dispatch_workflows:$workflows}'
}

# _session_sweep_json <repo> -- one sweep-read seam. `wrap sweep --json` wins once the verb
# exists; until then the row carries the `wrap apply --worktrees` dry-run text unchanged.
# WRAP_SESSION_WRAP_BIN is an internal test seam, defaulting to this install's bin/wrap.
_session_sweep_json() {
  local repo="$1" bin out err rc errline valid apply_out arc
  bin="${WRAP_SESSION_WRAP_BIN:-$LIB_ROOT/../bin/wrap}"
  err="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  out="$("$bin" sweep --json --worktrees "$repo" 2>"$err")"; rc=$?
  IFS= read -r errline < "$err" || errline=""
  rm -f "$err"
  valid=1
  if [ -n "$out" ] && printf '%s' "$out" | jq -e '.schema == "wrap-sweep/1"' >/dev/null 2>&1; then
    valid=0
  fi
  if [ "$valid" -eq 0 ]; then
    jq -cn --argjson exit_code "$rc" --argjson document "$out" --arg error "$errline" \
      '{format:"json",exit_code:$exit_code,document:$document,text:null,error:(if $error=="" then null else $error end)}'
    return 0
  fi
  apply_out="$("$bin" apply --worktrees "$repo" 2>&1)"; arc=$?
  jq -cn --arg text "$apply_out" --argjson exit_code "$arc" \
    '{format:"text",exit_code:$exit_code,document:null,text:$text,error:null}'
}

# _session_activity_json -- where step 6's line would land, without writing it.
_session_activity_json() {
  local target resolved copy exists=false regular=false writable=false worktree_copy=false home_ok=true err=""
  target="$(kit_config_get_root wrap.activity_log "")"
  if [ -z "$target" ]; then
    jq -cn '{configured:false,target:null,resolved:null,exists:false,writable:false,worktree_copy:false,error:null}'
    return 0
  fi
  case "$target" in "~"/*) target="${HOME}/${target#\~/}" ;; esac
  resolved="$(_realpath_f "$target" 2>/dev/null)"
  if [ -z "$resolved" ]; then
    err="cannot resolve target"
  else
    copy="$(_worktree_copy "$resolved")"
    [ "$copy" != "$resolved" ] && worktree_copy=true && resolved="$copy"
    [ -e "$resolved" ] && exists=true
    [ -f "$resolved" ] && regular=true
    [ -w "$resolved" ] && writable=true
    _home_fence "$resolved" "wrap log" >/dev/null 2>&1 || home_ok=false
  fi
  jq -cn --arg target "$target" --arg resolved "$resolved" --arg error "$err" \
    --argjson exists "$exists" --argjson regular "$regular" --argjson writable "$writable" \
    --argjson worktree_copy "$worktree_copy" --argjson home_ok "$home_ok" \
    '{configured:true,target:$target,resolved:(if $resolved=="" then null else $resolved end),
      exists:$exists,regular_file:$regular,writable:$writable,worktree_copy:$worktree_copy,home_ok:$home_ok,
      error:(if $error=="" then null else $error end)}'
}

# _session_config_json [lanes|all] -- the root-only knobs the command otherwise reads one by one.
_session_config_json() {
  local override="${1:-}" fm mode lanes
  fm="$(cmd_follow_mode "$override" 2>/dev/null)"
  mode="${fm%% *}"; lanes="${fm#* }"
  jq -cn \
    --arg distill "$(kit_config_get_root wrap.distill true)" \
    --arg before "$(kit_config_get_root wrap.before "")" \
    --arg after "$(kit_config_get_root wrap.after "")" \
    --arg merge_own_prs "$(kit_config_get_root wrap.merge_own_prs true)" \
    --arg tidy_worktrees "$(kit_config_get_root wrap.tidy_worktrees true)" \
    --arg delete_merged_remote_branches "$(kit_config_get_root wrap.delete_merged_remote_branches true)" \
    --arg carry_stray_lines "$(kit_config_get_root wrap.carry_stray_lines true)" \
    --arg autoland_carry "$(kit_config_get_root wrap.autoland_carry false)" \
    --arg build_candidates "$(kit_config_get_root wrap.build_candidates true)" \
    --arg build_lanes "$(kit_config_get_root wrap.build_lanes tiny)" \
    --arg drain_staged "$(kit_config_get_root wrap.drain_staged false)" \
    --arg follow_mode "$mode" --arg follow_lanes "$lanes" \
    '{wrap:{distill:$distill,before:$before,after:$after,merge_own_prs:$merge_own_prs,
      tidy_worktrees:$tidy_worktrees,delete_merged_remote_branches:$delete_merged_remote_branches,
      carry_stray_lines:$carry_stray_lines,autoland_carry:$autoland_carry,build_candidates:$build_candidates,
      build_lanes:$build_lanes,drain_staged:$drain_staged,follow_mode:$follow_mode,follow_lanes:$follow_lanes}}'
}

# _session_repo_json <repo> -- one repo object. Every child read degrades into a field,
# never into extra stdout, so the final document stays machine-readable.
_session_repo_json() {
  local input="$1" repo def board checkout handoffs prs sweep
  repo="$(cd "$input" 2>/dev/null && pwd -P)"
  [ -n "$repo" ] || repo="$input"
  if ! _is_repo "$repo"; then
    jq -cn --arg path "$input" '{path:$path,is_repo:false,error:"not a git repo",default_branch:null,
      checkout:null,board:null,handoffs:null,pull_requests:null,sweep:null}'
    return 0
  fi

  def="$(_default_branch "$repo" 2>/dev/null)"
  checkout="$(_session_checkout_json "$repo" "$def")"
  board="$(_session_board_json "$repo")"
  handoffs="$(_session_handoffs_json "$repo")"
  prs="$(_session_prs_json "$repo" "$def")"
  sweep="$(_session_sweep_json "$repo")"

  jq -cn --arg path "$repo" --arg def "$def" \
    --argjson checkout "$checkout" --argjson board "$board" --argjson handoffs "$handoffs" \
    --argjson prs "$prs" --argjson sweep "$sweep" \
    '{path:$path,is_repo:true,error:(if $def=="" then "no default branch resolved" else null end),
      fetch_error:null,
      default_branch:(if $def=="" then null else $def end),checkout:$checkout,board:$board,
      handoffs:$handoffs,pull_requests:$prs,sweep:$sweep}'
}

cmd_session() {
  local json=0 follow="" arg count=0 start end duration tmp repos config activity
  local -a repos_args=()
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --json) json=1 ;;
      --follow-mode) [ $# -ge 2 ] || { echo "usage: wrap.sh session --json [--follow-mode lanes|all] <repo> [<repo>...]" >&2; return 64; }
        case "$2" in lanes|all) ;; *) echo "usage: wrap.sh session --json [--follow-mode lanes|all] <repo> [<repo>...]" >&2; return 64 ;; esac
        follow="$2"; shift 2; continue ;;
      -*) echo "wrap.sh session: unknown flag '$arg'" >&2; return 64 ;;
      *) _reject_packed session "$arg" || return 64
         repos_args+=("$arg") ;;
    esac
    shift
  done
  count="${#repos_args[@]}"
  [ "$json" = 1 ] && [ "$count" -ge 1 ] || { echo "usage: wrap.sh session --json [--follow-mode lanes|all] <repo> [<repo>...]" >&2; return 64; }

  start=$(( $(date +%s) * 1000 ))
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  for arg in "${repos_args[@]}"; do _session_repo_json "$arg" >> "$tmp"; done
  repos="$(jq -s . "$tmp" 2>/dev/null)"; [ -n "$repos" ] || repos='[]'
  rm -f "$tmp"
  config="$(_session_config_json "$follow")"
  activity="$(_session_activity_json)"
  end=$(( $(date +%s) * 1000 )); duration=$(( end - start ))

  jq -cn --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson duration_ms "$duration" \
    --argjson repos "$repos" --argjson config "$config" --argjson activity "$activity" \
    '{schema:"wrap-session/1",generated_at:$started_at,duration_ms:$duration_ms,
      config:$config.wrap,activity_log:$activity,repos:$repos,
      summary:{repos:($repos|length),
        invalid_repos:([$repos[] | select(.is_repo != true)] | length),
        open_own_prs:([$repos[].pull_requests.open_own[]?] | length),
        pending_prs:([$repos[].pull_requests.open_own[]? | select((.checks.pending // 0) > 0)] | length),
        sweep_would_remove:([$repos[].sweep.document.summary.would_remove? // 0] | add // 0),
        sweep_rows:([$repos[].sweep.document.repos[]?.rows[]?] | length)}}'
  return 0
}
