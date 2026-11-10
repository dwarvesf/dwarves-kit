# wrap-ship.sh -- the ship verb; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- ship

# cmd_ship <repo> <branch> --carry <path>... --message-file <file> [--title T] [--body-file F]
#          [--proof-override "<reason>"] [--no-pull] -- the hand sequence of a small docs or
# content change from a shared dirty checkout, as one verb: `start --carry`, stage the named
# paths, commit, log an override only when asked, `land`. It composes the existing verbs
# in-process (cmd_start, cmd_land) and copies none of their refusals; each step's own exit
# code is the verb's exit code. `ship` owns four things: the argument contract, staging by
# named path (never -A, never .), the committed-diff guard, and the explicit-only override.
#
# Nothing is written before `start` runs. Every ship-owned refusal before that point, and
# every argument refusal, leaves the repo as it was. A refusal after `start` leaves the
# worktree and its branch; the verb never removes anything. The last stdout line is always one
# `SHIP:` line, after `land`'s own `LAND:` line:
#   SHIP: shipped #<n> (<sha7>) pull=<ok|blocked|skipped> worktree=<removed|kept>
#   SHIP: already landed (<proof>) pull=.. worktree=..
#   SHIP: refused (<step>, exit <rc>) worktree=<path|none>
# <step> is preflight, start, carry, branch, stage, commit, guard, override or land:<step>.
cmd_ship() {
  _SHIP_STEP=preflight _SHIP_WT=none _SHIP_FINAL=""
  local rc
  _ship_run "$@"; rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$_SHIP_FINAL" ]; then
    echo "SHIP: ${_SHIP_FINAL}"
  else
    [ "$rc" -ne 0 ] || rc=1
    echo "SHIP: refused (${_SHIP_STEP}, exit ${rc}) worktree=${_SHIP_WT}"
  fi
  return "$rc"
}

# _ship_in_scope <path> <carry-path>... -- 0 when <path> equals a carry path or sits under one.
_ship_in_scope() {
  local p="$1" c; shift
  for c in "$@"; do
    c="${c%/}"
    case "$p" in "$c"|"$c"/*) return 0 ;; esac
  done
  return 1
}

# _ship_abs <file> -- the file's absolute path, so a later `git -C <wt>` reads the same file.
_ship_abs() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"; }

# _ship_resume <wt> <title> <body-file> <no-pull> -- the `wrap land` line that continues a
# committed worktree with the flags the caller gave. The override reason is never echoed.
_ship_resume() {
  local line="resume: wrap land $1"
  [ -z "$2" ] || line="${line} --title $(printf '%q' "$2")"
  [ -z "$3" ] || line="${line} --body-file $(printf '%q' "$3")"
  [ "$4" -eq 0 ] || line="${line} --no-pull"
  echo "$line" >&2
}

_ship_run() {
  local repo="" branch="" title="" body_file="" message_file="" reason="" arg p
  local nopull=0 reason_given=0 carry_seen=0 npos=0
  local carry=()
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --carry)
        carry_seen=1; shift
        while [ $# -gt 0 ]; do
          case "$1" in --*) break ;; esac
          _reject_packed ship "$1" || return 64
          carry[${#carry[@]}]="$1"; shift
        done ;;
      --message-file|--title|--body-file|--proof-override)
        [ $# -ge 2 ] || { echo "wrap.sh ship: ${arg} needs a value" >&2; return 64; }
        case "$arg" in
          --message-file) message_file="$2" ;;
          --title) title="$2" ;;
          --body-file) body_file="$2" ;;
          --proof-override) reason="$2"; reason_given=1 ;;
        esac
        shift 2 ;;
      --no-pull) nopull=1; shift ;;
      --draft|--with-ci|--verify|--pick)
        echo "wrap.sh ship: ${arg} is not accepted; run wrap start and wrap land directly" >&2
        return 64 ;;
      -*) echo "wrap.sh ship: unknown flag '${arg}'" >&2; return 64 ;;
      *)
        _reject_packed ship "$arg" || return 64
        npos=$(( npos + 1 ))
        case "$npos" in
          1) repo="$arg" ;;
          2) branch="$arg" ;;
          *) echo "wrap.sh ship: unexpected argument '${arg}'" >&2; return 64 ;;
        esac
        shift ;;
    esac
  done

  local usage="usage: wrap.sh ship <repo> <branch> --carry <path>... --message-file <file> [--title T] [--body-file F] [--proof-override \"<reason>\"] [--no-pull]"
  [ "$npos" -eq 2 ] || { echo "$usage" >&2; return 64; }
  if [ "$carry_seen" -eq 0 ] || [ "${#carry[@]}" -eq 0 ]; then
    echo "wrap.sh ship: --carry needs at least one path; a bare --carry would stage the whole checkout" >&2
    return 64
  fi
  [ -n "$message_file" ] || { echo "$usage" >&2; return 64; }
  for p in "${carry[@]}"; do
    case "$p" in
      ""|/*|:*|-*|*[\*\?\[]*)
        echo "wrap.sh ship: carry path '${p}' must be a repo-relative path with no glob, no leading ':' or '-'" >&2
        return 64 ;;
    esac
    case "/${p}/" in
      */../*|*/./*)
        echo "wrap.sh ship: carry path '${p}' must not contain a '.' or '..' component" >&2
        return 64 ;;
    esac
  done
  if [ ! -f "$message_file" ] || [ ! -s "$message_file" ]; then
    echo "wrap.sh ship: --message-file '${message_file}' is not an existing non-empty file" >&2
    return 64
  fi
  if [ -n "$body_file" ] && [ ! -f "$body_file" ]; then
    echo "wrap.sh ship: --body-file '${body_file}' is not an existing file" >&2
    return 64
  fi
  if [ "$reason_given" -eq 1 ]; then
    case "$reason" in
      "") echo "wrap.sh ship: --proof-override needs a non-empty reason" >&2; return 64 ;;
      *$'\n'*) echo "wrap.sh ship: --proof-override reason must be one line" >&2; return 64 ;;
    esac
  fi
  _is_repo "$repo" || { echo "wrap.sh ship: ${repo} is not a git repo" >&2; return 64; }
  repo="$(cd "$repo" 2>/dev/null && pwd -P)" \
    || { echo "wrap.sh ship: ${repo} does not resolve" >&2; return 64; }
  message_file="$(_ship_abs "$message_file")"
  [ -z "$body_file" ] || body_file="$(_ship_abs "$body_file")"

  # Preflight: cheap reads of what land would refuse on after a commit exists. No write.
  local ghs; ghs="$(_gh_state)"
  if [ "$ghs" != "ok" ]; then
    echo "wrap.sh ship: gh is ${ghs}" >&2; return 1
  fi
  if [ -z "$body_file" ]; then
    local tpl; tpl="$(_pr_template "$repo")"
    if [ -n "$tpl" ]; then
      echo "wrap.sh ship: ${tpl} exists, so a title-only PR body is not allowed; pass --body-file <file>" >&2
      return 1
    fi
  fi
  if [ -z "$(git -C "$repo" status --porcelain --untracked-files=all -- "${carry[@]}" 2>/dev/null)" ]; then
    echo "wrap.sh ship: nothing to ship: no changes under ${carry[*]} in ${repo}" >&2
    return 1
  fi

  # start --carry: its own refusals, unchanged. It prints the worktree path as its only stdout.
  local wt rc
  _SHIP_STEP=start
  wt="$(cmd_start "$repo" "$branch" --carry "${carry[@]}")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -n "$wt" ]; then _SHIP_WT="$wt"; _SHIP_STEP=carry; fi
    return "$rc"
  fi
  _SHIP_WT="$wt"
  echo "ship: worktree ${wt}"

  # The commit must land on the new branch, never on the default branch, whatever start did.
  _SHIP_STEP=branch
  local cur def
  cur="$(git -C "$wt" branch --show-current 2>/dev/null)"
  def="$(_default_branch "$wt" 2>/dev/null)" || def=""
  if [ -z "$cur" ] || [ "$cur" != "$branch" ]; then
    echo "wrap.sh ship: ${wt} is on '${cur:-<detached>}', not ${branch}; nothing committed" >&2
    return 1
  fi
  case "$cur" in
    "$def"|main|master)
      echo "wrap.sh ship: ${cur} is the default or a protected branch name; nothing committed" >&2
      return 1 ;;
  esac

  # Stage by named path only.
  _SHIP_STEP=stage
  local out
  out="$(git -C "$wt" add -- "${carry[@]}" 2>&1)" || {
    echo "wrap.sh ship: git add refused: $(printf '%s\n' "$out" | tail -n 1)" >&2; return 1; }
  if [ -z "$(git -C "$wt" diff --cached --name-only --no-renames 2>/dev/null)" ]; then
    echo "wrap.sh ship: nothing staged under ${carry[*]} in ${wt}" >&2
    return 1
  fi

  _SHIP_STEP=commit
  out="$(git -C "$wt" commit -q -F "$message_file" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    echo "wrap.sh ship: git commit exited ${rc}; the worktree is left at ${wt}" >&2
    return 1
  fi

  # The committed diff, re-read: a commit hook can add files after the staged list was read.
  _SHIP_STEP=guard
  local f nfiles=0 miss=""
  while IFS= read -r -d '' f; do
    nfiles=$(( nfiles + 1 ))
    [ -n "$miss" ] || _ship_in_scope "$f" "${carry[@]}" || miss="$f"
  done < <(git -C "$wt" diff --name-only --no-renames -z HEAD^ HEAD 2>/dev/null)
  echo "ship: committed $(_short "$(git -C "$wt" rev-parse HEAD 2>/dev/null)") (${nfiles} files)"
  if [ -n "$miss" ] || [ "$nfiles" -eq 0 ]; then
    echo "wrap.sh ship: the commit holds ${miss:-no files}, outside the carried paths; nothing pushed, the worktree is left at ${wt}" >&2
    return 1
  fi

  if [ "$reason_given" -eq 1 ]; then
    _SHIP_STEP=override
    local slug="${branch#*/}"
    out="$(cd "$wt" && bash "$PROOF_LEDGER_SH" override "$slug" "$reason" 2>&1)"; rc=$?
    [ -z "$out" ] || printf '%s\n' "$out"
    if [ "$rc" -ne 0 ]; then
      _ship_resume "$wt" "$title" "$body_file" "$nopull"
      return "$rc"
    fi
    echo "ship: override logged (slug ${slug})"
  fi

  local land_args=()
  [ -z "$title" ] || land_args=("${land_args[@]+"${land_args[@]}"}" --title "$title")
  [ -z "$body_file" ] || land_args=("${land_args[@]+"${land_args[@]}"}" --body-file "$body_file")
  [ "$nopull" -eq 0 ] || land_args=("${land_args[@]+"${land_args[@]}"}" --no-pull)
  cmd_land "$wt" ${land_args[@]+"${land_args[@]}"}; rc=$?
  if [ "$rc" -ne 0 ]; then
    _SHIP_STEP="land:${_LAND_STEP}"
    _ship_resume "$wt" "$title" "$body_file" "$nopull"
    return "$rc"
  fi
  _ship_final
}

# _ship_final -- sets _SHIP_FINAL from the kind `land` ended in. `ship` never passes --draft
# (it rejects the flag), so kind `draft` cannot arrive here; any kind but merged or already is
# a bug, named on stderr instead of reported as an ordinary refusal.
_ship_final() {
  case "$_LAND_KIND" in
    merged)  _SHIP_FINAL="shipped ${_LAND_REF} pull=${_LAND_PULL} worktree=${_LAND_WT}" ;;
    already) _SHIP_FINAL="already landed (${_LAND_REF}) pull=${_LAND_PULL} worktree=${_LAND_WT}" ;;
    *)       _SHIP_STEP="land:${_LAND_STEP}"
             echo "wrap.sh ship: unexpected land outcome '${_LAND_KIND}' (ship never passes --draft); this is a bug" >&2
             return 1 ;;
  esac
  return 0
}
