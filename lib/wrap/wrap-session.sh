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

# _session_reflog_latest_at <worktree> -- newest HEAD reflog entry time. `%ct` is the
# commit's date; `%gd` with --date=unix is the reflog entry's own write time.
_session_reflog_latest_at() {
  local wt="$1" sel t
  sel="$(git -C "$wt" log -g -1 --date=unix --format=%gd HEAD 2>/dev/null)"
  t="$(printf '%s' "$sel" | awk -F'[{}]' '{print $2}' 2>/dev/null)"
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$t"
}

# _session_newest_reflog <repo> -- newest HEAD reflog unix timestamp across the worktrees.
_session_newest_reflog() {
  local repo="$1" wt ts newest=0
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    ts="$(_session_reflog_latest_at "$wt" 2>/dev/null)"
    case "$ts" in ''|*[!0-9]*) ;; *) [ "$ts" -gt "$newest" ] && newest="$ts" ;; esac
  done <<EOF_SESSION_REFL
$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10) }')
EOF_SESSION_REFL
  [ "$newest" -gt 0 ] && printf '%s\n' "$newest"
}

# _session_abs_path <path> -- symlink-free directory path when it exists.
_session_abs_path() {
  [ -d "$1" ] && (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"
}

# _session_main_checkout <repo> -- the primary checkout behind a worktree or main repo.
_session_main_checkout() {
  local common main
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  case "$common" in
    */.git) main="${common%/.git}" ;;
    *) return 1 ;;
  esac
  _session_abs_path "$main"
}

# _session_reflog_identity <worktree> -- HEAD reflog head, entry time, and content digest.
# The digest changes on every reflog append, including one that lands on the same commit.
_session_reflog_identity() {
  local wt="$1" gd log head latest digest
  head="$(git -C "$wt" log -g -1 --format=%H HEAD 2>/dev/null)"
  latest="$(_session_reflog_latest_at "$wt" 2>/dev/null)"
  gd="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  log="$gd/logs/HEAD"
  digest=""
  [ -n "$gd" ] && [ -f "$log" ] && digest="$(git hash-object "$log" 2>/dev/null)"
  case "$head" in ''|*[!0-9a-f]*) head=null ;; *) head="\"$head\"" ;; esac
  case "$latest" in ''|*[!0-9]*) latest=null ;; esac
  case "$digest" in ''|*[!0-9a-f]*) digest=null ;; *) digest="\"$digest\"" ;; esac
  jq -cn --argjson head "$head" --argjson latest "$latest" --argjson digest "$digest" \
    '{head:$head,latest_at:$latest,digest:$digest}'
}

# _session_writer_mark_write <file> <repo> <rows-json> -- atomically save every worktree's
# reflog identity. The mark is scratch state, never repository state.
_session_writer_mark_write() {
  local file="$1" repo="$2" rows="$3" tmp rc
  [ ! -d "$file" ] || return 1
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  jq -cn --arg repo "$repo" --argjson rows "$rows" --argjson now "$(date +%s)" \
    '{schema:"wrap-writer-mark/1",marked_at_epoch:$now,repo:$repo,
      worktrees:[$rows[] | {path:.path,reflog:{head:.reflog.head,latest_at:.reflog.latest_at,digest:.reflog.digest}}]}' \
    > "$tmp" 2>/dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then mv "$tmp" "$file" 2>/dev/null; rc=$?; fi
  [ ! -e "$tmp" ] || rm -f "$tmp"
  return "$rc"
}

# _session_writers_json <repo> <since> <check-mark> <write-mark> [self]... --
# live per-worktree foreign-writer facts. Session worktrees are excluded except the
# main checkout, whose lock always counts and whose reflog is judged against the mark.
_session_writers_json() {
  local input="$1" since="$2" check_mark="$3" write_mark="$4"
  shift 4
  local repo rows tmp row wt branch detached head main_top
  local wt_abs gd lock_exists lock_age ts newer foreign rows_json any_foreign
  local ident rhead rdigest changed marked_head marked_digest mark_found mark_valid mark_error
  local self_in self_top selfs_json filtered_rows write_error=""
  local -a self_tops=()
  repo="$(_session_abs_path "$input")"
  if ! _is_repo "$repo"; then
    jq -cn --arg path "$input" '{schema:"wrap-writers/1",repo:$path,is_repo:false,error:"not a git repo",worktrees:[]}'
    return 0
  fi
  if [ $# -eq 0 ]; then set -- "$PWD"; fi
  for self_in in "$@"; do
    self_top="$(git -C "$self_in" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
    [ -n "$self_top" ] || self_top="$(_session_abs_path "$self_in")"
    self_tops+=("$self_top")
  done
  selfs_json='[]'
  for self_top in "${self_tops[@]}"; do
    selfs_json="$(jq -cn --argjson rows "$selfs_json" --arg path "$self_top" '$rows + [$path]' 2>/dev/null)"
  done
  [ -n "$selfs_json" ] || selfs_json='[]'
  main_top="$(_session_main_checkout "$repo" 2>/dev/null)"
  rows="$(_session_worktrees_json "$repo")"
  [ -n "$rows" ] || rows='[]'
  if [ -z "$main_top" ]; then
    main_top="$(printf '%s' "$rows" | jq -r '.[0].path // empty' 2>/dev/null)"
    [ -z "$main_top" ] || main_top="$(_session_abs_path "$main_top")"
  fi

  mark_valid=null
  if [ -n "$check_mark" ]; then
    if [ -f "$check_mark" ] && jq -e '.schema == "wrap-writer-mark/1" and (.worktrees|type) == "array"' "$check_mark" >/dev/null 2>&1; then
      mark_valid=true
    else
      mark_valid=false
    fi
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  printf '%s' "$rows" | jq -c '.[]' 2>/dev/null | while IFS= read -r row; do
    wt="$(printf '%s' "$row" | jq -r '.path' 2>/dev/null)"
    [ -n "$wt" ] || continue
    wt_abs="$(_session_abs_path "$wt")"
    branch="$(printf '%s' "$row" | jq -r '.branch // ""' 2>/dev/null)"
    detached="$(printf '%s' "$row" | jq -r '.detached' 2>/dev/null)"
    head="$(printf '%s' "$row" | jq -r '.head // ""' 2>/dev/null)"
    gd="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
    lock_exists=false; lock_age=null
    if [ -n "$gd" ] && [ -e "$gd/index.lock" ]; then
      lock_exists=true
      lock_age="$(( $(date +%s) - $(_mtime "$gd/index.lock") ))"
      case "$lock_age" in ''|*[!0-9-]*) lock_age=null ;; esac
    fi
    ident="$(_session_reflog_identity "$wt" 2>/dev/null)"
    [ -n "$ident" ] || ident='{"head":null,"latest_at":null,"digest":null}'
    ts="$(printf '%s' "$ident" | jq -r '.latest_at // null' 2>/dev/null)"
    rhead="$(printf '%s' "$ident" | jq -r 'if .head == null then "" else .head end' 2>/dev/null)"
    rdigest="$(printf '%s' "$ident" | jq -r 'if .digest == null then "" else .digest end' 2>/dev/null)"
    newer=null
    if [ "$since" != "null" ] && [ "$ts" != "null" ]; then
      if [ "$ts" -gt "$since" ]; then newer=true; else newer=false; fi
    fi
    changed=null
    if [ -n "$check_mark" ] && [ "$mark_valid" = true ]; then
      mark_found="$(jq -r --arg path "$wt_abs" '([.worktrees[]? | select(.path == $path)] | length) > 0' "$check_mark" 2>/dev/null)"
      marked_head="$(jq -r --arg path "$wt_abs" '(([.worktrees[]? | select(.path == $path)][0]).reflog.head) // ""' "$check_mark" 2>/dev/null)"
      marked_digest="$(jq -r --arg path "$wt_abs" '(([.worktrees[]? | select(.path == $path)][0]).reflog.digest) // ""' "$check_mark" 2>/dev/null)"
      if [ "$mark_found" != true ]; then
        changed=true
      elif [ "$marked_head" != "$rhead" ] || [ "$marked_digest" != "$rdigest" ]; then
        changed=true
      else
        changed=false
      fi
    fi
    foreign=false
    [ "$lock_exists" = true ] && foreign=true
    if [ -n "$check_mark" ]; then
      [ "$mark_valid" != true ] && foreign=true
      [ "$changed" = true ] && foreign=true
    else
      [ "$newer" = true ] && foreign=true
    fi
    jq -cn --arg path "$wt_abs" --arg branch "$branch" --arg head "$head" \
      --argjson detached "$detached" --argjson lock_exists "$lock_exists" --argjson lock_age "$lock_age" \
      --argjson ts "$ts" --argjson newer "$newer" --arg reflog_head "$rhead" --arg reflog_digest "$rdigest" \
      --argjson changed "$changed" --argjson foreign "$foreign" \
      '{path:$path,branch:(if $branch=="" then null else $branch end),head:(if $head=="" then null else $head end),
        detached:$detached,index_lock:{present:$lock_exists,age_seconds:$lock_age},
        reflog:{latest_at:$ts,newer_than_since:$newer,
          head:(if $reflog_head=="" then null else $reflog_head end),
          digest:(if $reflog_digest=="" then null else $reflog_digest end),changed_since_mark:$changed},
        foreign_activity:$foreign}' >> "$tmp"
  done
  rows_json="$(jq -s . "$tmp" 2>/dev/null)"; [ -n "$rows_json" ] || rows_json='[]'
  rm -f "$tmp"

  if [ -n "$write_mark" ]; then
    if ! _session_writer_mark_write "$write_mark" "$repo" "$rows_json"; then
      write_error="writer mark write failed"
    fi
  fi

  filtered_rows="$(jq -cn --argjson rows "$rows_json" --argjson selves "$selfs_json" --arg main "$main_top" \
    '[ $rows[] | . as $row | select(($row.path == $main) or (($selves | index($row.path)) == null)) ]' 2>/dev/null)"
  [ -n "$filtered_rows" ] || filtered_rows='[]'
  any_foreign="$(printf '%s' "$filtered_rows" | jq 'any(.[]; .foreign_activity)' 2>/dev/null)"
  [ -n "$any_foreign" ] || any_foreign=false
  [ "$mark_valid" = false ] && any_foreign=true
  [ -n "$write_error" ] && any_foreign=true
  mark_error=null
  [ "$mark_valid" = false ] && mark_error='"writer mark missing or invalid"'
  [ -n "$write_error" ] && mark_error="\"$write_error\""
  jq -cn --arg repo "$repo" --arg main "$main_top" --argjson selves "$selfs_json" --argjson since "$since" \
    --arg check_mark "$check_mark" --arg write_mark "$write_mark" --argjson mark_valid "$mark_valid" --argjson mark_error "$mark_error" \
    --argjson rows "$filtered_rows" --argjson any_foreign "$any_foreign" --argjson now "$(date +%s)" \
    '{schema:"wrap-writers/1",generated_at_epoch:$now,repo:$repo,is_repo:true,error:null,
      since:$since,self:$selves,main_checkout:(if $main=="" then null else $main end),
      writer_mark:{check:(if $check_mark=="" then null else $check_mark end),write:(if $write_mark=="" then null else $write_mark end),valid:$mark_valid,error:$mark_error},
      foreign_activity:$any_foreign,worktrees:$rows}'
}

# _session_writers_text <json> -- the same writer facts in the text fallback shape.
_session_writers_text() {
  printf '%s' "$1" | jq -r '
    "wrap-writers repo=\(.repo) is_repo=\(.is_repo) since=\(.since // "null") self=\((.self // []) | join(",")) foreign_activity=\(.foreign_activity // false)",
    (.worktrees[]? | "writer path=\(.path) branch=\(.branch // "null") detached=\(.detached) index_lock_present=\(.index_lock.present) index_lock_age_seconds=\(if .index_lock.age_seconds == null then "null" else .index_lock.age_seconds end) reflog_latest_at=\(if .reflog.latest_at == null then "null" else .reflog.latest_at end) reflog_newer_than_since=\(if .reflog.newer_than_since == null then "null" else .reflog.newer_than_since end) reflog_changed_since_mark=\(if .reflog.changed_since_mark == null then "null" else .reflog.changed_since_mark end) foreign_activity=\(.foreign_activity)")' 2>/dev/null
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
  dirty="$(git --no-optional-locks -C "$repo" status --short 2>/dev/null | _session_lines_json)"
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
  slug="$(_session_repo_slug "$url" 2>/dev/null)"
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
  open_json="$(printf '%s' "$open_json" | jq -c --arg slug "$slug" \
    'map(. + {url:(if $slug == "" then null else "https://github.com/\($slug)/pull/\(.number)" end)})' 2>/dev/null)"
  [ -n "$open_json" ] || open_json='[]'

  me="$(gh api user --jq .login 2>/dev/null)"
  merged_raw="$(gh pr list --repo "$url" --state merged --limit 20 \
    --json number,title,headRefName,mergedAt,mergeCommit,author 2>/dev/null)"
  if [ -n "$merged_raw" ] && [ -n "$me" ]; then
    merged="$(printf '%s' "$merged_raw" | jq -c --arg me "$me" \
      '[.[] | select((.author.login // "") | ascii_downcase == ($me | ascii_downcase))]
       | .[0:5] | map({number,title,headRefName,mergedAt,merge_sha:(.mergeCommit.oid // null)})' 2>/dev/null)"
  fi
  [ -n "$merged" ] || merged='[]'
  merged="$(printf '%s' "$merged" | jq -c --arg slug "$slug" \
    'map(. + {url:(if $slug == "" then null else "https://github.com/\($slug)/pull/\(.number)" end)})' 2>/dev/null)"
  [ -n "$merged" ] || merged='[]'

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

# _session_sweep_text_readonly <repo> -- the fallback sweep facts without a fetch. This is
# deliberately narrower than `apply`: no deletion verdict needs fresh origin state here, and
# the session gather's read-only contract outranks a preview of what apply would remove.
_session_sweep_text_readonly() {
  local repo="$1" def="$2" b tip wt merged
  {
    printf 'wrap-session sweep fallback (read-only; no fetch; origin refs may be stale)\n'
    printf 'worktrees:\n'
    _session_worktrees_json "$repo" | jq -r '.[]? | "  \(.path) branch=\(.branch // "detached") head=\((.head // "")[0:7])"' 2>/dev/null
    printf 'branches:\n'
    while IFS="$(printf '\t')" read -r b tip wt; do
      [ -n "$b" ] || continue
      merged=unknown
      if [ -n "$def" ] && git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$def" >/dev/null 2>&1; then
        if git -C "$repo" merge-base --is-ancestor "$b" "refs/remotes/origin/$def" >/dev/null 2>&1; then
          merged=yes
        else
          merged=no
        fi
      fi
      printf '  %s tip=%s merged_in_origin_%s=%s worktree=%s\n' "$b" "$tip" "${def:-unknown}" "$merged" "${wt:-none}"
    done <<EOF_SESSION_BRANCHES
$(git -C "$repo" for-each-ref --format='%(refname:short)%09%(objectname:short)%09%(worktreepath)' refs/heads 2>/dev/null)
EOF_SESSION_BRANCHES
    printf 'fetch: not attempted (read-only gather)\n'
  } 2>/dev/null
}

# _session_sweep_json <repo> -- one sweep-read seam. `wrap sweep --json` wins once the verb
# exists; until then the row carries read-only local inventory text, never an apply dry run
# (even a dry-run apply fetches, which breaks this gather's no-write contract).
# WRAP_SESSION_WRAP_BIN is an internal test seam, defaulting to this install's bin/wrap.
_session_sweep_json() {
  local repo="$1" def="$2" bin out err rc errline valid apply_out arc
  bin="${WRAP_SESSION_WRAP_BIN:-$LIB_ROOT/../bin/wrap}"
  err="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  out="$("$bin" sweep --json --no-fetch --worktrees "$repo" 2>"$err")"; rc=$?
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
  apply_out="$(_session_sweep_text_readonly "$repo" "$def")"; arc=0
  jq -cn --arg text "$apply_out" --argjson exit_code "$arc" --arg error "$errline" \
    '{format:"text",exit_code:$exit_code,document:null,text:$text,error:(if $error=="" then null else $error end)}'
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
  local input="$1" repo def board checkout handoffs prs sweep origin slug fetch_err
  repo="$(cd "$input" 2>/dev/null && pwd -P)"
  [ -n "$repo" ] || repo="$input"
  if ! _is_repo "$repo"; then
    jq -cn --arg path "$input" '{path:$path,is_repo:false,error:"not a git repo",default_branch:null,
      origin_url:null,github_slug:null,checkout:null,board:null,handoffs:null,pull_requests:null,sweep:null}'
    return 0
  fi

  def="$(_default_branch "$repo" 2>/dev/null)"
  origin="$(_origin_url "$repo")"
  slug="$(_session_repo_slug "$origin" 2>/dev/null)"
  checkout="$(_session_checkout_json "$repo" "$def")"
  board="$(_session_board_json "$repo")"
  handoffs="$(_session_handoffs_json "$repo")"
  prs="$(_session_prs_json "$repo" "$def")"
  sweep="$(_session_sweep_json "$repo" "$def")"

  fetch_err="$(printf '%s' "$sweep" | jq -r --arg repo "$repo" \
    'if .format == "json" then ([.document.repos[]? | select(.path == $repo) | .error // empty] | first // "") else "" end' 2>/dev/null)"
  if [ -z "$fetch_err" ]; then
    if [ -z "$origin" ]; then
      fetch_err="no origin remote"
    elif [ -n "$def" ] && ! git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$def" >/dev/null 2>&1; then
      fetch_err="origin/$def missing locally; the read-only gather does not fetch"
    else
      fetch_err="fetch not attempted (read-only gather); origin data may be stale"
    fi
  fi

  jq -cn --arg path "$repo" --arg def "$def" --arg origin "$origin" --arg slug "$slug" \
    --arg fetch_err "$fetch_err" \
    --argjson checkout "$checkout" --argjson board "$board" --argjson handoffs "$handoffs" \
    --argjson prs "$prs" --argjson sweep "$sweep" \
    '{path:$path,is_repo:true,error:(if $def=="" then "no default branch resolved" else null end),
      fetch_error:(if $fetch_err=="" then null else $fetch_err end),
      default_branch:(if $def=="" then null else $def end),
      origin_url:(if $origin=="" then null else $origin end),github_slug:(if $slug=="" then null else $slug end),
      checkout:$checkout,board:$board,
      handoffs:$handoffs,pull_requests:$prs,sweep:$sweep}'
}

cmd_session() {
  local json=0 follow="" arg count=0 start end duration tmp repos config activity
  local writers=0 writers_text=0 since_json=null start_epoch writers_out check_mark="" write_mark=""
  local wusage="usage: wrap.sh session --writers [--since <epoch>] [--check-mark <state>] [--mark <state>] [--self <worktree>]... [--text] <repo>"
  local -a repos_args=() selfs=()
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --json) json=1 ;;
      --writers) writers=1 ;;
      --text) writers_text=1 ;;
      --since) [ $# -ge 2 ] || { echo "$wusage" >&2; return 64; }
        case "$2" in ''|*[!0-9]*) echo "wrap.sh session --since: epoch must be a whole number" >&2; return 64 ;; esac
        since_json="$2"; shift 2; continue ;;
      --self) [ $# -ge 2 ] || { echo "$wusage" >&2; return 64; }
        selfs+=("$2"); shift 2; continue ;;
      --mark) [ $# -ge 2 ] || { echo "$wusage" >&2; return 64; }
        write_mark="$2"; shift 2; continue ;;
      --check-mark) [ $# -ge 2 ] || { echo "$wusage" >&2; return 64; }
        check_mark="$2"; shift 2; continue ;;
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

  if [ "$writers" = 1 ]; then
    [ "$count" -eq 1 ] || { echo "$wusage" >&2; return 64; }
    if [ "$since_json" = "null" ]; then
      case "${WRAP_SESSION_START:-}" in ''|*[!0-9]*) ;; *) since_json="$WRAP_SESSION_START" ;; esac
    fi
    if [ -n "$check_mark" ] && [ -n "$write_mark" ]; then
      echo "wrap.sh session --writers: --mark and --check-mark are separate steps" >&2; return 64
    fi
    if [ "${#selfs[@]}" -eq 0 ]; then
      writers_out="$(_session_writers_json "${repos_args[0]}" "$since_json" "$check_mark" "$write_mark")"
    else
      writers_out="$(_session_writers_json "${repos_args[0]}" "$since_json" "$check_mark" "$write_mark" "${selfs[@]}")"
    fi
    if [ "$writers_text" = 1 ]; then
      _session_writers_text "$writers_out"
    else
      printf '%s\n' "$writers_out"
    fi
    return 0
  fi

  [ "$json" = 1 ] && [ "$count" -ge 1 ] || { echo "usage: wrap.sh session --json [--follow-mode lanes|all] <repo> [<repo>...]" >&2; return 64; }

  start_epoch="$(date +%s)"; start=$(( start_epoch * 1000 ))
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")"
  for arg in "${repos_args[@]}"; do _session_repo_json "$arg" >> "$tmp"; done
  repos="$(jq -s . "$tmp" 2>/dev/null)"; [ -n "$repos" ] || repos='[]'
  rm -f "$tmp"
  config="$(_session_config_json "$follow")"
  activity="$(_session_activity_json)"
  end=$(( $(date +%s) * 1000 )); duration=$(( end - start ))

  jq -cn --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson started_epoch "$start_epoch" \
    --argjson duration_ms "$duration" \
    --argjson repos "$repos" --argjson config "$config" --argjson activity "$activity" \
    '{schema:"wrap-session/1",generated_at:$started_at,generated_at_epoch:$started_epoch,duration_ms:$duration_ms,
      config:$config.wrap,activity_log:$activity,repos:$repos,
      summary:{repos:($repos|length),
        invalid_repos:([$repos[] | select(.is_repo != true)] | length),
        open_own_prs:([$repos[].pull_requests.open_own[]?] | length),
        pending_prs:([$repos[].pull_requests.open_own[]? | select((.checks.pending // 0) > 0)] | length),
        sweep_would_remove:([$repos[].sweep.document.summary.would_remove? // 0] | add // 0),
        sweep_rows:([$repos[].sweep.document.repos[]?.rows[]?] | length)}}'
  return 0
}
