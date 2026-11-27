#!/usr/bin/env bash
# branch-merged.sh -- sourced: the one answer to "has this branch's tip reached the default branch".
#
# Every caller that decides on merged-ness (wrap scan, apply, land, the origin sweep, adopt, and
# lib/goal/wt.sh close) calls branch_merged, so a looser private meaning cannot delete work.
# The helpers below move with it unchanged: _origin_url, _gh_state, _gh_note, _absorbed,
# _squash_json, _squash_verdict. Never sets shell options; bash 3.2.

_origin_url() { git -C "$1" remote get-url origin 2>/dev/null; }

# _gh_state -- ok | unavailable | unauthenticated. Read once per verb run.
_gh_state() {
  if [ -n "${_WRAP_GH_STATE:-}" ]; then
    printf '%s\n' "$_WRAP_GH_STATE"; return 0
  fi
  command -v gh >/dev/null 2>&1 || { printf 'unavailable\n'; return 0; }
  gh auth status >/dev/null 2>&1 || { printf 'unauthenticated\n'; return 0; }
  printf 'ok\n'
}

# _gh_owner_repo <origin url> -- prints "<owner>\t<repo>" for a GitHub remote URL, returns 1 otherwise.
_gh_owner_repo() {
  local url="$1" slug
  case "$url" in
    *github.com:*) slug="${url#*github.com:}" ;;
    *github.com/*) slug="${url#*github.com/}" ;;
    *) return 1 ;;
  esac
  slug="${slug%/}"
  slug="${slug%.git}"
  case "$slug" in
    ""|*/*/*) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  local owner="${slug%%/*}" name="${slug#*/}"
  [ -n "$owner" ] && [ -n "$name" ] || return 1
  printf '%s\t%s\n' "$owner" "$name"
}

# branch_merged_batch_fetch <repo> <gh state> <merged json file> <open json file> [closed json file] -- [branch...]
# One batched GraphQL query per chunk of 40 branches: fetches merged PRs (and closed PRs when
# closed_file is non-empty) for the named head branches plus up to 100 open PRs for the repo.
# Returns 0 on verified success, 1 on any failure (non-GitHub remote, gh error, GraphQL errors,
# or truncated merged-PR pagination for a branch) so callers fall back to the per-branch path.
branch_merged_batch_fetch() {
  local repo="$1" ghs="$2" mfile="$3" ofile="$4" cfile="${5:-}"
  shift 4
  if [ $# -gt 0 ] && [ "${1:-}" != "--" ]; then
    cfile="$1"; shift
  fi
  [ "${1:-}" = "--" ] && shift

  [ "$ghs" = "ok" ] || return 1
  local url or owner name
  url="$(git -C "$repo" config --get remote.origin.url 2>/dev/null)"
  [ -n "$url" ] || url="$(_origin_url "$repo")"
  or="$(_gh_owner_repo "$url")" || return 1
  IFS=$'\t' read -r owner name <<< "$or"

  # Deduplicate candidate branch names while preserving bash 3.2 compatibility.
  local branches=() nl=$'\n' seen b n_br=0
  seen="$nl"
  for b in "$@"; do
    [ -n "$b" ] || continue
    case "$seen" in
      *"$nl${b}$nl"*) continue ;;
    esac
    seen="${seen}${b}${nl}"
    branches[$n_br]="$b"
    n_br=$(( n_br + 1 ))
  done

  if [ "$n_br" -eq 0 ]; then
    printf '[]\n' > "$mfile"
    printf '[]\n' > "$ofile"
    [ -n "$cfile" ] && printf '[]\n' > "$cfile"
    return 0
  fi

  local tmp_m tmp_c tmp_o
  tmp_m="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1
  tmp_c="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || { rm -f "$tmp_m"; return 1; }
  tmp_o=""
  : > "$tmp_m"
  : > "$tmp_c"

  local idx=0 total="$n_br" chunk_sz=40 first_chunk=1
  local want_closed=0
  [ -n "$cfile" ] && want_closed=1

  while [ "$idx" -lt "$total" ]; do
    local chunk=() k=0
    while [ "$k" -lt "$chunk_sz" ] && [ "$idx" -lt "$total" ]; do
      chunk[${#chunk[@]}]="${branches[$idx]}"
      idx=$(( idx + 1 ))
      k=$(( k + 1 ))
    done
    local inc_open=0
    [ "$first_chunk" -eq 1 ] && inc_open=1
    first_chunk=0

    local payload resp rc=0
    payload="$(printf '%s\n' "${chunk[@]}" | jq -Rsc \
      --arg owner "$owner" --arg name "$name" \
      --argjson include_open "$inc_open" --argjson want_closed "$want_closed" '
      (split("\n")[:-1]) as $branches |
      ($branches | to_entries | map("$b" + (.key | tostring) + ": String!") | join(", ")) as $vardecls |
      ($branches | to_entries | map(
        "m" + (.key | tostring) + ": pullRequests(headRefName: $b" + (.key | tostring) + ", states: [MERGED], first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) { pageInfo { hasNextPage } nodes { number state headRefName headRefOid baseRefName mergedAt isCrossRepository } }"
        + (if $want_closed == 1 then " c" + (.key | tostring) + ": pullRequests(headRefName: $b" + (.key | tostring) + ", states: [CLOSED], first: 5, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { number state headRefName headRefOid baseRefName mergedAt isCrossRepository } }" else "" end)
      ) | join(" ")) as $fields |
      (if $include_open == 1 then "openPrs: pullRequests(states: [OPEN], first: 100) { pageInfo { hasNextPage } nodes { number state headRefName headRefOid baseRefName isCrossRepository } } " else "" end) as $openq |
      ($branches | to_entries | map({key: ("b" + (.key | tostring)), value: .value}) | from_entries) as $bvars |
      {
        query: ("query($owner: String!, $name: String!" + (if $vardecls != "" then ", " + $vardecls else "" end) + ") { repository(owner: $owner, name: $name) { " + $openq + $fields + " } }"),
        variables: ({owner: $owner, name: $name} + $bvars)
      }')" || { rm -f "$tmp_m" "$tmp_c"; return 1; }

    resp="$(printf '%s' "$payload" | gh api graphql --input - 2>/dev/null)"; rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$resp" ]; then
      rm -f "$tmp_m" "$tmp_c"; return 1
    fi
    if ! printf '%s' "$resp" | jq -e '
      (.errors == null) and (.data.repository | type == "object") and
      ([.data.repository | to_entries[] | select(.key | test("^m[0-9]+$")) | .value.pageInfo.hasNextPage] | all(. == false))
    ' >/dev/null 2>&1; then
      rm -f "$tmp_m" "$tmp_c"; return 1
    fi

    printf '%s' "$resp" | jq -c '.data.repository | to_entries[] | select(.key | test("^m[0-9]+$")) | .value.nodes[]' >> "$tmp_m" 2>/dev/null \
      || { rm -f "$tmp_m" "$tmp_c"; return 1; }
    if [ "$want_closed" -eq 1 ]; then
      printf '%s' "$resp" | jq -c '.data.repository | to_entries[] | select(.key | test("^c[0-9]+$")) | .value.nodes[]' >> "$tmp_c" 2>/dev/null \
        || { rm -f "$tmp_m" "$tmp_c"; return 1; }
    fi
    if [ "$inc_open" -eq 1 ]; then
      if printf '%s' "$resp" | jq -e '.data.repository.openPrs.pageInfo.hasNextPage == false' >/dev/null 2>&1; then
        printf '%s' "$resp" | jq -c '.data.repository.openPrs.nodes' > "$ofile" 2>/dev/null \
          || : > "$ofile"
        tmp_o="$ofile"
      else
        : > "$ofile"
      fi
    fi
  done

  jq -cs '.' "$tmp_m" > "$mfile" 2>/dev/null || { rm -f "$tmp_m" "$tmp_c"; return 1; }
  if [ "$want_closed" -eq 1 ]; then
    jq -cs '.' "$tmp_c" > "$cfile" 2>/dev/null || { rm -f "$tmp_m" "$tmp_c"; return 1; }
  fi
  rm -f "$tmp_m" "$tmp_c"
  return 0
}

# _branch_own_commits <repo> <default branch> <branch> -- number of own commits on the branch
# not on the default branch at its fork point; 0 marks a fresh branch.
_branch_own_commits() {
  local repo="$1" def="$2" b="$3" ahead fork_sha own
  if _branch_never_committed "$repo" "$def" "$b"; then
    printf '0\n'; return 0
  fi
  ahead="$(git -C "$repo" rev-list --count "refs/remotes/origin/${def}..refs/heads/${b}" 2>/dev/null)"
  case "$ahead" in
    ''|*[!0-9]*) ;;
    *) if [ "$ahead" -gt 0 ]; then printf '%s\n' "$ahead"; return 0; fi ;;
  esac
  fork_sha="$(git -C "$repo" reflog show --format='%H' "refs/heads/${b}" 2>/dev/null | tail -1)"
  if [ -n "$fork_sha" ]; then
    own="$(git -C "$repo" rev-list --count "${fork_sha}..refs/heads/${b}" 2>/dev/null)"
    case "$own" in
      ''|*[!0-9]*) ;;
      *) if [ "$own" -gt 0 ]; then printf '%s\n' "$own"; return 0; fi ;;
    esac
  fi
  printf '1\n'
}

# _branch_pr_info <branch> <tip> <default> <merged_file> <open_file> <closed_file>
# Prints "<pr>\t<pr_state>" (e.g. "12\tMERGED" or "null\tnull") from already-fetched PR files.
_branch_pr_info() {
  local b="$1" tip="$2" def="$3" mf="${4:-}" of="${5:-}" cf="${6:-}"
  local mjson="[]" ojson="[]" cjson="[]"
  [ -n "$mf" ] && [ -s "$mf" ] && mjson="$(cat "$mf" 2>/dev/null)" || mjson="[]"
  [ -n "$of" ] && [ -s "$of" ] && ojson="$(cat "$of" 2>/dev/null)" || ojson="[]"
  [ -n "$cf" ] && [ -s "$cf" ] && cjson="$(cat "$cf" 2>/dev/null)" || cjson="[]"
  jq -nr --arg b "$b" --arg tip "$tip" --arg def "$def" \
    --argjson m "$mjson" --argjson o "$ojson" --argjson c "$cjson" '
    def mine: select((.isCrossRepository == false) and (.headRefName == $b));
    ([ $m[] | mine | select(.mergedAt != null and .baseRefName == $def and .headRefOid == $tip) ][0]) //
    ([ $m[] | mine | select(.mergedAt != null) ][0]) as $mh |
    if $mh != null then "\($mh.number // "null")\tMERGED"
    else
      ([ $o[] | mine ][0]) as $oh |
      if $oh != null then "\($oh.number // "null")\tOPEN"
      else
        ([ $c[] | mine ][0]) as $ch |
        if $ch != null then "\($ch.number // "null")\tCLOSED"
        else "null\tnull" end
      end
    end
  ' 2>/dev/null || printf 'null\tnull\n'
}

# _branch_pr_info_fallback <repo> <default> <gh state> <branch> <tip>
# Queries gh for a single branch when batch PR files are unavailable (e.g. non-GitHub stubbed origin).
_branch_pr_info_fallback() {
  local repo="$1" def="$2" ghs="$3" b="$4" tip="$5"
  [ "$ghs" = "ok" ] || { printf 'null\tnull\n'; return 0; }
  local url mjson ojson cjson
  url="$(_origin_url "$repo")"
  mjson="$(_squash_json "$url" "$b")"
  printf '%s' "$mjson" | jq -e 'type == "array"' >/dev/null 2>&1 || mjson="[]"
  ojson="$(gh pr list --repo "$url" --head "$b" --state open \
    --json number,headRefName,headRefOid,baseRefName,isCrossRepository 2>/dev/null)" || ojson="[]"
  printf '%s' "$ojson" | jq -e 'type == "array"' >/dev/null 2>&1 || ojson="[]"
  cjson="$(gh pr list --repo "$url" --head "$b" --state closed \
    --json number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository 2>/dev/null)" || cjson="[]"
  printf '%s' "$cjson" | jq -e 'type == "array"' >/dev/null 2>&1 || cjson="[]"
  jq -nr --arg b "$b" --arg tip "$tip" --arg def "$def" \
    --argjson m "$mjson" --argjson o "$ojson" --argjson c "$cjson" '
    def mine: select((.isCrossRepository == false) and (.headRefName == $b));
    ([ $m[] | mine | select(.mergedAt != null and .baseRefName == $def and .headRefOid == $tip) ][0]) //
    ([ $m[] | mine | select(.mergedAt != null) ][0]) as $mh |
    if $mh != null then "\($mh.number // "null")\tMERGED"
    else
      ([ $o[] | mine ][0]) as $oh |
      if $oh != null then "\($oh.number // "null")\tOPEN"
      else
        ([ $c[] | mine | select(.mergedAt == null) ][0]) as $ch |
        if $ch != null then "\($ch.number // "null")\tCLOSED"
        else "null\tnull" end
      end
    end
  ' 2>/dev/null || printf 'null\tnull\n'
}

_gh_note() {
  case "$1" in
    unavailable)     printf '(gh unavailable)\n' ;;
    unauthenticated) printf '(gh unauthenticated)\n' ;;
  esac
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
  # LC_ALL=C reaches git through env, never as a bash variable: Homebrew bash 5.3 on macOS
  # SIGSEGVs (rc 139) in setlocale when a function exit restores LC_ALL, about 1 call in 20
  # under load, and the proof then reads as "not absorbed".
  local -a g=(env LC_ALL=C git -C "$repo" --no-replace-objects -c core.quotePath=true)
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

# _branch_never_committed <repo> <default> <branch> -- 0 when the local branch ref shows no
# sign of ever moving past its creation off the default line. The branch reflog is the only
# place that distinction survives after a merge: once origin/<default> contains the tip, the
# graph of a fast-forwarded real branch and of a never-used worker branch is identical.
# Entry-kind scan: `commit*`, `cherry-pick*`, `revert*`, `am*`, and `merge <non-default>`
# mark real own work; sync, rebase, reset, and rename entries leave a branch fresh. An
# unrecognised merge target (e.g. `@{u}`, `FETCH_HEAD`, or a bare SHA) does not count as own
# work when the entry's new sha is an ancestor of `origin/<default>`; when unsure, keep fresh.
# Creation from `origin/<same branch>` (`wrap start --existing`) is a feature copy; `origin/HEAD`,
# `origin/<default>`, another ref, a SHA, a revision expression, or a missing/expired reflog
# fails safe as fresh. This only distrusts trivial ancestry; absorbed content and an exact
# merged PR still prove SAFE.
_branch_never_committed() {
  local repo="$1" def="$2" b="$3" entries line sha msg source target rc
  entries="$(git -C "$repo" reflog show --format='%H%x09%gs' "refs/heads/${b}" 2>/dev/null)"
  [ -n "$entries" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sha="${line%%	*}"
    msg="${line#*	}"
    case "$msg" in
      commit*|cherry-pick*|revert*|am*)
        return 1 ;;
      "merge "*)
        target="${msg#merge }"
        target="${target%%:*}"
        case "$target" in
          "$def"|"refs/heads/${def}"|"origin/${def}"|"refs/remotes/origin/${def}"|\
          "origin/HEAD"|"refs/remotes/origin/HEAD"|\
          main|master|"origin/main"|"origin/master"|\
          "refs/heads/main"|"refs/heads/master"|\
          "refs/remotes/origin/main"|"refs/remotes/origin/master") ;;
          *)
            if [ -n "$sha" ]; then
              git -C "$repo" merge-base --is-ancestor "$sha" "refs/remotes/origin/${def}" 2>/dev/null
              rc=$?
              [ "$rc" -eq 1 ] && return 1
            fi ;;
        esac ;;
      "branch: Created from "*)
        source="${msg#branch: Created from }"
        case "$b" in
          "$def"|main|master|HEAD|"") ;;
          *)
            case "$source" in
              "origin/${b}"|"refs/remotes/origin/${b}") return 1 ;;
            esac ;;
        esac ;;
    esac
  done <<< "$entries"
  return 0
}

# _squash_json <repo-url> <branch> -- the merged-PR list gh reports for that head.
_squash_json() {
  gh pr list --repo "$1" --head "$2" --state merged \
    --json number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository 2>/dev/null
}

# _squash_rows <json> <branch> -- the merged-PR rows that may speak for <branch>: rows that say, in
# fields gh sent, that they name this head (headRefName) and come from this repo
# (isCrossRepository exactly false). A field that is null or missing keeps the row out: nothing
# gh did not send is read as the answer that lets a delete through. Unusable JSON prints nothing.
_squash_rows() {
  printf '%s' "$1" | jq -c --arg b "$2" '
    [.[] | select(.isCrossRepository == false and .headRefName == $b)]' 2>/dev/null
}

# The merge-proof grammar. The ladder and its squash rung print ONE line, `<code> <reason> <detail>`:
#   SAFE ancestor <phrase>   the tip is an ancestor of origin/<default>
#   SAFE absorbed <phrase>   every path the branch changed is byte-identical on origin/<default>
#   SAFE squash <phrase>     a merged PR into the default branch has this exact tip
#   LEAVE tip <sha>          merged into the default branch, but from another tip (sha = PR head)
#   LEAVE base <name>        merged into another branch
#   LEAVE none <phrase>      no merged PR for this head (also the answer for unusable JSON)
#   LEAVE fresh <phrase>     a never-committed branch whose only proof would be trivial ancestry
#   LEAVE nogh <gh note>     the squash rung could not run: gh is not ok
# A caller branches on the first two words and prints the detail, never the other way round.
# The detail of a LEAVE tip or base is data (a sha, a branch name); every other detail is a
# phrase a caller may print or reword, and none may match on it.

# _squash_verdict <json> <local tip> <default branch> -- the gh rung of the ladder, one line of the
# grammar above (SAFE squash, LEAVE tip, LEAVE base or LEAVE none).
_squash_verdict() {
  local json="$1" tip="$2" def="$3" out
  out="$(printf '%s' "$json" | jq -r --arg tip "$tip" --arg def "$def" '
    [.[] | select(.mergedAt != null)] as $m
    | if ($m | length) == 0 then "LEAVE none no merged PR found for this head"
      elif ([$m[] | select(.baseRefName == $def and .headRefOid == $tip)] | length) > 0
        then "SAFE squash squash-merged per gh"
      elif ([$m[] | select(.baseRefName == $def)] | length) > 0
        then "LEAVE tip " + ([$m[] | select(.baseRefName == $def)][0].headRefOid)
      else "LEAVE base " + ($m[0].baseRefName) end' 2>/dev/null)"
  [ -n "$out" ] || out="LEAVE none no merged PR found for this head"
  printf '%s\n' "$out"
}

# branch_merged [--need any|pr] [--tip SHA] [--prs-json FILE] [--numbers] <repo> <default branch> <gh state> <branch>
# -- has <branch> already reached origin/<default>? One line of the grammar above, always exit 0. The
# rungs run in order: a plain ancestor, absorbed content, the gh squash proof.
#   --need pr       skip the ancestor and absorbed rungs: only a merged PR at the exact tip can say SAFE.
#                   For callers that refuse a branch with no merged PR (wt.sh close, the origin sweep, adopt).
#   --tip SHA       judge this commit instead of refs/heads/<branch>: a caller that read and guarded a tip,
#                   or a branch that exists only on origin.
#   --prs-json FILE use this merged-PR list instead of one gh call (the origin sweep reads it once for
#                   every branch). Rows must say headRefName and isCrossRepository=false; others never count.
#   --numbers       print the numbers of the merged PRs that speak for the tip, one per line, instead of a
#                   verdict: exit 0 at least one, 1 none, 2 unreadable (gh not ok, gh failed, unusable JSON).
# A usage error exits 64 with nothing on stdout, which every caller reads as LEAVE.
# Full refs and the sha only: a bare name resolves a same-named tag first, and a tag or local
# branch called origin/<def> beats the remote-tracking ref. Either once proved an unlanded
# worktree branch "merged".
branch_merged() {
  local need=any tip="" prsjson="" numbers=0 repo def ghs b json rows grc=0 out fresh=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --need) need="${2:-}"; shift 2 || return 64 ;;
      --tip) tip="${2:-}"; shift 2 || return 64 ;;
      --prs-json) prsjson="${2:-}"; shift 2 || return 64 ;;
      --numbers) numbers=1; shift ;;
      --) shift; break ;;
      -*) return 64 ;;
      *) break ;;
    esac
  done
  [ "$#" -eq 4 ] || return 64
  case "$need" in any|pr) ;; *) return 64 ;; esac
  repo="$1"; def="$2"; ghs="$3"; b="$4"
  [ -n "$tip" ] || tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
  if [ "$need" = any ] && [ "$numbers" = 0 ] && _branch_never_committed "$repo" "$def" "$b"; then
    fresh=1
  fi
  if [ "$need" = any ] && [ "$numbers" = 0 ]; then
    if git -C "$repo" merge-base --is-ancestor "$tip" "refs/remotes/origin/${def}" 2>/dev/null; then
      [ "$fresh" = 1 ] || { printf 'SAFE ancestor ancestor of origin/%s\n' "$def"; return 0; }
    fi
    if _absorbed "$repo" "$def" "$tip"; then
      printf 'SAFE absorbed content already on origin/%s\n' "$def"; return 0
    fi
  fi
  if [ "$ghs" != "ok" ]; then
    [ "$numbers" = 1 ] && return 2
    if [ "$fresh" = 1 ]; then
      printf 'LEAVE fresh fresh branch, no own commits and no merged PR (leave it)\n'; return 0
    fi
    printf 'LEAVE nogh %s\n' "$(_gh_note "$ghs")"; return 0
  fi
  if [ -n "$prsjson" ]; then
    json="$(cat "$prsjson" 2>/dev/null)" || grc=1
  else
    json="$(_squash_json "$(_origin_url "$repo")" "$b")" || grc=1
  fi
  rows="$(_squash_rows "$json" "$b")"
  if [ "$numbers" = 1 ]; then
    [ "$grc" = 0 ] && [ -n "$rows" ] || return 2
    out="$(printf '%s' "$rows" | jq -r --arg tip "$tip" --arg def "$def" \
      '.[] | select(.mergedAt != null and .baseRefName == $def and .headRefOid == $tip) | .number' 2>/dev/null)" || return 2
    [ -n "$out" ] || return 1
    printf '%s\n' "$out"; return 0
  fi
  out="$(_squash_verdict "$rows" "$tip" "$def")"
  if [ "$fresh" = 1 ]; then
    case "$out" in
      "SAFE squash "*) printf '%s\n' "$out" ;;
      *) printf 'LEAVE fresh fresh branch, no own commits and no merged PR (leave it)\n' ;;
    esac
    return 0
  fi
  printf '%s\n' "$out"
}
