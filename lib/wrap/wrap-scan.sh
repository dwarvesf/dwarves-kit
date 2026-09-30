# wrap-scan.sh -- the scan verb and its helpers; sourced by lib/wrap/wrap.sh.


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
  # Every proof below names full refs: a bare name resolves a same-named tag first, and a tag
  # or local branch called origin/<def> beats the remote-tracking ref.
  for b in $(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/); do
    case "$b" in "$def"|main|master) continue ;; esac
    if git -C "$repo" merge-base --is-ancestor "refs/heads/${b}" "refs/remotes/origin/${def}" 2>/dev/null; then
      echo "     ${b}  [SAFE-d: ancestor of origin/${def}]"
      continue
    fi
    if _absorbed "$repo" "$def" "refs/heads/${b}"; then
      echo "     ${b}  [ABSORBED: content already on origin/${def}, safe to -D]"
      continue
    fi
    if [ "$ghs" != "ok" ]; then
      echo "     ${b}  [NOT merged / unknown: LEAVE]"
      continue
    fi
    tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/${b}" 2>/dev/null)"
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
      *) _reject_packed scan "$arg" || return 64
         if [ "$want_under" = 1 ]; then nu=$(( nu + 1 )); unders[nu]="$arg"; want_under=0
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
