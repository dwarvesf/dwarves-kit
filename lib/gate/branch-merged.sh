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

# _squash_json <repo-url> <branch> -- the merged-PR list gh reports for that head.
_squash_json() {
  gh pr list --repo "$1" --head "$2" --state merged --json headRefOid,baseRefName,mergedAt 2>/dev/null
}

# The merge-proof grammar. The ladder and its squash rung print ONE line, `<code> <reason> <detail>`:
#   SAFE ancestor <phrase>   the tip is an ancestor of origin/<default>
#   SAFE absorbed <phrase>   every path the branch changed is byte-identical on origin/<default>
#   SAFE squash <phrase>     a merged PR into the default branch has this exact tip
#   LEAVE tip <sha>          merged into the default branch, but from another tip (sha = PR head)
#   LEAVE base <name>        merged into another branch
#   LEAVE none <phrase>      no merged PR for this head (also the answer for unusable JSON)
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

# branch_merged <repo> <default branch> <gh state> <branch> [tip] -- has <branch> already reached
# origin/<default>? One line of the grammar above, always exit 0. The rungs run in order: a plain
# ancestor, absorbed content, the gh squash proof. <tip> defaults to the local branch tip; a caller
# that already read and guarded a tip passes it, so the proof judges that exact commit.
# Full refs and the sha only: a bare name resolves a same-named tag first, and a tag or local
# branch called origin/<def> beats the remote-tracking ref. Either once proved an unlanded
# worktree branch "merged".
branch_merged() {
  local repo="$1" def="$2" ghs="$3" b="$4" tip="${5:-}" json
  [ -n "$tip" ] || tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
  if git -C "$repo" merge-base --is-ancestor "$tip" "refs/remotes/origin/${def}" 2>/dev/null; then
    printf 'SAFE ancestor ancestor of origin/%s\n' "$def"; return 0
  fi
  if _absorbed "$repo" "$def" "$tip"; then
    printf 'SAFE absorbed content already on origin/%s\n' "$def"; return 0
  fi
  if [ "$ghs" != "ok" ]; then
    printf 'LEAVE nogh %s\n' "$(_gh_note "$ghs")"; return 0
  fi
  json="$(_squash_json "$(_origin_url "$repo")" "$b")"
  _squash_verdict "$json" "$tip" "$def"
}
