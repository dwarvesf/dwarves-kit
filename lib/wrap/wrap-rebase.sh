# wrap-rebase.sh -- the rebase verb and its helpers; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- rebase

# The one generated file `rebase` regenerates at a stop, and the generator that owns it. The
# generator runs from the worktree under rebase, never from this kit's own LIB_ROOT, because
# the projection must match the tree being rebased. A repo without that generator (a consumer)
# gets an ordinary refusal on the path.
# ponytail: one hardcoded pair; a second generated file turns this into a [wrap] knob.
_RB_GENERATED="docs/FEATURES.md"
_RB_GENERATOR="lib/registry/feature-registry.sh"
# The only path resolved by keeping both sides, and only when both sides purely added lines.
_RB_CHANGELOG="docs/CHANGELOG.md"

# _rb_git <wt> <args...> -- git in <wt> with the pins every rebase call carries: a recorded
# rerere resolution or an operator's updateRefs default must never act inside the verb.
_rb_git() {
  local wt="$1"; shift
  GIT_EDITOR=true git -C "$wt" -c rerere.enabled=false -c rebase.updateRefs=false "$@"
}

# _rb_rebasing <wt> -- 0 while a rebase is in progress (stopped) in <wt>.
_rb_rebasing() {
  local gd
  gd="$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]
}

# _rb_markers <wt> <path>... -- prints each path holding a conflict-marker line (the marker
# plus a space or the line end, so a Markdown `=======` underline never trips it). 0 on a hit.
_rb_markers() {
  local wt="$1" p hit=1; shift
  for p in "$@"; do
    [ -f "$wt/$p" ] || continue
    if grep -qE '^(<{7}|>{7}|\|{7})( |$)' "$wt/$p"; then printf '%s\n' "$p"; hit=0; fi
  done
  return "$hit"
}

# _rb_stages <wt> <path> <dir> -- writes stages 1 (base), 2 and 3 of an unmerged path to
# <dir>/1, <dir>/2, <dir>/3. Nonzero when any stage is missing (add/add, modify/delete).
_rb_stages() {
  local n
  for n in 1 2 3; do
    git -C "$1" show ":${n}:$2" > "$3/$n" 2>/dev/null || return 1
  done
}

# _rb_changelog_merge <wt> <path> <out> -- writes the union of both sides to <out> and returns
# 0 only when that union is safe: both sides only ADD lines to the base (a diff of the base
# against each side prints no `<` line; a reworded, moved or deleted base line would come out
# twice), and no line was added by BOTH sides (the union would then carry it twice).
_rb_changelog_merge() {
  local d rc=1
  d="$(mktemp -d)" || return 1
  # Process substitution, not a pipe: under pipefail diff's exit 1 would mask grep's answer.
  if _rb_stages "$1" "$2" "$d" \
     && ! grep -q '^<' < <(diff -a "$d/1" "$d/2"; diff -a "$d/1" "$d/3") \
     && git merge-file --union -p "$d/2" "$d/1" "$d/3" > "$3" \
     && awk '{ n[FILENAME, $0]++; seen[$0] = 1 }
             END { for (l in seen)
                     if (n[ARGV[3], l] > n[ARGV[1], l] && n[ARGV[3], l] > n[ARGV[2], l]) exit 1 }' \
          "$d/2" "$d/3" "$3"; then
    rc=0
  fi
  rm -rf "$d"
  return "$rc"
}

# _rb_abort <wt> <branch> <old tip> <line> -- prints <line>, aborts the stopped rebase, and
# proves the branch is back at <old tip>. Always returns 1.
_rb_abort() {
  local wt="$1" branch="$2" old="$3"
  echo "$4"
  if _rb_git "$wt" rebase --abort >/dev/null 2>&1 && ! _rb_rebasing "$wt" \
     && [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$old" ]; then
    echo "     aborted; ${branch} is back at $(_short "$old")"
  else
    echo "ABORT FAILED ${branch}: run git rebase --abort in ${wt}"
  fi
  return 1
}

# _rb_has <needle> <item>... -- 0 when <needle> is one of the items.
_rb_has() {
  local x="$1" y; shift
  for y in "$@"; do [ "$y" = "$x" ] && return 0; done
  return 1
}

# _rb_changed <wt> -- tracked paths whose worktree copy differs from the index, NUL-terminated
# (-z, so a non-ASCII or quoted path reaches `git add` as itself).
_rb_changed() { git -C "$1" diff --name-only -z 2>/dev/null; }

# _rb_stop <wt> <branch> <old tip> <generator or empty> <git output file> -- one rebase stop.
# Every unmerged path is classified before anything is written, so a refused stop writes
# nothing. The stage set is exact: the unmerged paths plus whatever tracked file the resolver
# or the generator newly changed, marker-scanned, then staged by name. Never `add -u`/`-A`.
_rb_stop() {
  local wt="$1" branch="$2" old="$3" gen="$4" log="$5"
  local p refused="" regen=0 cl_out="" hits
  local -a unmerged=() before=() set=()
  while IFS= read -r -d '' p; do unmerged+=("$p"); done \
    < <(git -C "$wt" diff --name-only --diff-filter=U -z 2>/dev/null)
  if [ "${#unmerged[@]}" -eq 0 ]; then
    _rb_abort "$wt" "$branch" "$old" \
      "STOPPED ${branch} without a conflict: $(grep -m1 -v '^$' "$log" 2>/dev/null)"
    return 1
  fi
  for p in "${unmerged[@]}"; do
    if [ "$p" = "$_RB_GENERATED" ] && [ -n "$gen" ]; then regen=1
    elif [ "$p" = "$_RB_CHANGELOG" ] && cl_out="$(mktemp)" && _rb_changelog_merge "$wt" "$p" "$cl_out"; then :
    elif _union_marked "$wt" "$p"; then refused="${refused}${refused:+, }${p} (merge=union, delete/rename conflict)"
    else refused="${refused}${refused:+, }${p}"
    fi
  done
  if [ -n "$refused" ]; then
    [ -n "$cl_out" ] && rm -f "$cl_out"
    _rb_abort "$wt" "$branch" "$old" "REFUSED ${branch}: conflict in ${refused}"; return 1
  fi
  while IFS= read -r -d '' p; do before+=("$p"); done < <(_rb_changed "$wt")
  if [ -n "$cl_out" ]; then
    cat "$cl_out" > "$wt/$_RB_CHANGELOG"; rm -f "$cl_out"
  fi
  if [ "$regen" = 1 ] && ! ( cd "$wt" && bash "$gen" generate ) >/dev/null 2>&1; then
    _rb_abort "$wt" "$branch" "$old" "GENERATOR FAILED ${branch}: ${_RB_GENERATOR} generate exited non-zero"; return 1
  fi
  set=("${unmerged[@]}")
  while IFS= read -r -d '' p; do
    _rb_has "$p" ${before[@]+"${before[@]}"} || set+=("$p")
  done < <(_rb_changed "$wt")
  if hits="$(_rb_markers "$wt" "${set[@]}")"; then
    _rb_abort "$wt" "$branch" "$old" "MARKERS ${branch}: $(printf '%s' "$hits" | paste -sd, - | sed 's/,/, /g')"
    return 1
  fi
  if ! git -C "$wt" add -- "${set[@]}" 2>/dev/null; then
    _rb_abort "$wt" "$branch" "$old" "FAILED ${branch}: git add of the resolved paths"; return 1
  fi
  echo "     resolved: ${set[*]}"
}

# _rb_final_regen <wt> <branch> <generator> -- after the rebase finished: regenerate once
# more and record the change as its own commit. The only commit the verb makes, and it can
# only run once no rebase is stopped. Every failure line here starts `AFTER REBASE`: the branch
# is already rebased, unlike a stop's refusal, which restored the old tip.
_rb_final_regen() {
  local wt="$1" branch="$2" gen="$3" hits p
  local -a before=() set=()
  _rb_rebasing "$wt" && { echo "AFTER REBASE FAILED ${branch}: a rebase is still stopped, nothing committed"; return 1; }
  while IFS= read -r -d '' p; do before+=("$p"); done < <(_rb_changed "$wt")
  if ! ( cd "$wt" && bash "$gen" generate ) >/dev/null 2>&1; then
    echo "AFTER REBASE GENERATOR FAILED ${branch}: the branch is rebased, ${_RB_GENERATED} not regenerated"
    return 1
  fi
  while IFS= read -r -d '' p; do
    _rb_has "$p" ${before[@]+"${before[@]}"} || set+=("$p")
  done < <(_rb_changed "$wt")
  [ "${#set[@]}" -gt 0 ] || return 0
  if hits="$(_rb_markers "$wt" "${set[@]}")"; then
    echo "AFTER REBASE MARKERS ${branch}: $(printf '%s' "$hits" | paste -sd, - | sed 's/,/, /g') (left unstaged)"; return 1
  fi
  if ! git -C "$wt" add -- "${set[@]}" 2>/dev/null \
     || ! git -C "$wt" commit -q -m "chore(registry): regenerate ${_RB_GENERATED##*/} after rebase" >/dev/null 2>&1; then
    echo "AFTER REBASE FAILED ${branch}: the regenerated ${set[*]} could not be committed; left staged"; return 1
  fi
  echo "     regenerated after the rebase: ${set[*]}"
}

# cmd_rebase <worktree> -- the worktree's branch onto origin/<default>, resolving only the
# conflicts that have one right answer (a regenerated file, a CHANGELOG both sides only added
# to); anything else aborts and is named. Rewrites the local branch only: never pushes.
cmd_rebase() {
  local wt="" arg count=0
  for arg in "$@"; do
    case "$arg" in
      -*) echo "wrap.sh rebase: unknown flag '$arg'" >&2; return 64 ;;
      *) _reject_packed rebase "$arg" || return 64
         count=$(( count + 1 )); wt="$arg" ;;
    esac
  done
  [ "$count" -eq 1 ] || { echo "usage: wrap.sh rebase <worktree>" >&2; return 64; }
  _is_repo "$wt" || { echo "wrap.sh rebase: ${wt} is not a git worktree" >&2; return 64; }
  wt="$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)" && wt="$(cd "$wt" 2>/dev/null && pwd -P)" \
    || { echo "wrap.sh rebase: the worktree path does not resolve" >&2; return 64; }

  local repo gd
  repo="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  repo="${repo%/.git}"; repo="${repo%/}"
  repo="$(cd "$repo" 2>/dev/null && pwd -P)" || { echo "wrap.sh rebase: the main checkout does not resolve" >&2; return 64; }
  [ "$repo" != "$wt" ] || { echo "wrap.sh rebase: ${wt} is the main checkout, not a worktree" >&2; return 1; }
  gd="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  if _rb_rebasing "$wt" || [ -e "$gd/MERGE_HEAD" ] || [ -e "$gd/CHERRY_PICK_HEAD" ]; then
    echo "wrap.sh rebase: a rebase, merge or cherry-pick is already in progress in ${wt}" >&2; return 1
  fi
  local branch def
  branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || { echo "wrap.sh rebase: ${wt} is on a detached HEAD, so there is no branch to rebase" >&2; return 1; }
  def="$(_default_branch "$wt")" || { echo "wrap.sh rebase: no default branch resolved for ${wt}" >&2; return 1; }
  case "$branch" in
    "$def"|main|master)
      echo "wrap.sh rebase: HEAD is ${branch}, the default or a protected branch name" >&2; return 1 ;;
  esac
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ] \
    || { echo "wrap.sh rebase: ${wt} has tracked changes; commit or drop them first" >&2; return 1; }
  _write_guard "$wt" || { echo "wrap.sh rebase: index.lock held by another writer in ${wt}" >&2; return 1; }
  git -C "$wt" fetch -q origin "$def" 2>/dev/null \
    || { echo "wrap.sh rebase: fetch origin ${def} failed" >&2; return 1; }

  if git -C "$wt" merge-base --is-ancestor "origin/${def}" HEAD 2>/dev/null; then
    echo "nothing to rebase: ${branch} already contains origin/${def}"; return 0
  fi
  local old ahead max stops=0 gen="" log
  old="$(git -C "$wt" rev-parse HEAD)"
  ahead="$(git -C "$wt" rev-list --count "origin/${def}..HEAD" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac
  # internal, a test seam: WRAP_REBASE_MAX_STOPS replaces the one-stop-per-commit bound
  max="${WRAP_REBASE_MAX_STOPS:-$(( ahead + 1 ))}"
  [ -f "$wt/$_RB_GENERATOR" ] && gen="$wt/$_RB_GENERATOR"
  log="$(mktemp)" || { echo "wrap.sh rebase: mktemp failed" >&2; return 1; }

  echo "rebase ${branch} onto origin/${def} (${wt})"
  _rb_git "$wt" rebase "origin/${def}" > "$log" 2>&1
  while _rb_rebasing "$wt"; do
    if [ "$stops" -ge "$max" ]; then
      _rb_abort "$wt" "$branch" "$old" "STOP BOUND ${branch}: more than ${max} stop(s)"; rm -f "$log"; return 1
    fi
    stops=$(( stops + 1 ))
    _rb_stop "$wt" "$branch" "$old" "$gen" "$log" || { rm -f "$log"; return 1; }
    _rb_git "$wt" rebase --continue > "$log" 2>&1
  done
  if ! git -C "$wt" merge-base --is-ancestor "origin/${def}" HEAD 2>/dev/null; then
    echo "FAILED ${branch}: the rebase did not run: $(grep -m1 -v '^$' "$log")"; rm -f "$log"; return 1
  fi
  rm -f "$log"
  if [ -n "$gen" ]; then _rb_final_regen "$wt" "$branch" "$gen" || return 1; fi
  echo "rebased ${branch} onto origin/${def}: ${stops} stop(s) resolved, head $(_short "$(git -C "$wt" rev-parse HEAD)") (was $(_short "$old"))"
  echo "not pushed: the branch history changed, so its push needs --force-with-lease"
}

