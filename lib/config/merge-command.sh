#!/usr/bin/env bash
# merge-command.sh -- the project's own PR merge command (`[merge] command`).
#
# WHY: a repo may require its own merge script (it refuses a draft, a red or pending check, a
# conflict, a one-way door without a second approval). Every place the kit merges a PR itself
# (wrap land, wrap merge, mega-merge, stack-merge) asks this file first. With `[merge] command`
# unset the callers keep their plain squash merge; with it set they run the project command
# instead and never fall back to the plain merge when it refuses or cannot be read.
#
# Contract (safe under set -euo pipefail, no output on load):
#   kit_merge_command <repo-dir> [<default-branch>]
#       prints the command. exit 0 set, 1 unset, 2 the key could not be read or is not a single
#       simple command: the caller must refuse, never merge the plain way.
#   kit_merge_command_slug <slug> <default-branch>
#       the same, read through `gh api` for a repo with no checkout.
#   kit_merge_exec <repo-dir> <cmd> <pr> [<head-oid>] [<default-branch>] [<repo-url>]
#       runs `<cmd> <pr>` with its output streamed as-is and returns its own exit code. 2 when it
#       could not be started (no base checkout), 3 when the PR head moved off <head-oid>.
#   kit_merge_verify <repo-dir> <pr> [<repo-url>]
#       exit 0 only when GitHub reports the PR MERGED.
#
# Trust. The command is a line of code the kit runs, so it is read only from places a PR cannot
# change for its own merge:
#   - the project `.kit.toml` as COMMITTED on the default branch (refs/remotes/origin/<default>,
#     fully qualified so a tag or branch named like it cannot stand in), never the working tree,
#     never HEAD, never the PR being merged; best-effort `git fetch` of that branch first;
#   - then the operator `kit.toml`, then the kit-root `kit.toml` (project > operator > kit-root).
#   - the script the command names runs from a clean detached checkout of that same commit, not
#     from the working tree the PR (or a stack-merge reconcile) may have changed.
# Where the default branch's commit cannot be resolved, a project key cannot be verified: a
# working-tree `[merge] command` then means exit 2, not "unset".
# The value must be one simple command: no `;` `&` `|` `<` `>` backtick `$(` or newline, and no
# `#` (the toml reader strips it). The PR number is appended as the last argument.
#
# Idempotent-source guard.
[ -n "${_KIT_MERGE_CMD_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_MERGE_CMD_SOURCED=1

_KIT_MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config/kit-config.sh
source "$_KIT_MC_DIR/kit-config.sh"

# Every git call here ignores a GIT_DIR / GIT_WORK_TREE left in the caller's environment (a git
# hook context exports them) so `-C <repo-dir>` means what it says.
_kit_mc_git() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR git "$@"; }

# _kit_mc_base_ref <repo-dir> [<default-branch>] -- the fully qualified remote-tracking ref of
# the default branch; exit 1 when none resolves. Never a short name, never HEAD.
_kit_mc_base_ref() {
  local repo="$1" def="${2:-}" ref
  if [ -n "$def" ]; then
    ref="refs/remotes/origin/$def"
  else
    ref="$(_kit_mc_git -C "$repo" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)" || ref=""
    if [ -z "$ref" ]; then
      for ref in refs/remotes/origin/main refs/remotes/origin/master; do
        _kit_mc_git -C "$repo" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1 && break
        ref=""
      done
    fi
  fi
  [ -n "$ref" ] || return 1
  _kit_mc_git -C "$repo" fetch -q origin "+refs/heads/${ref#refs/remotes/origin/}:$ref" >/dev/null 2>&1 || :
  _kit_mc_git -C "$repo" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1 || return 1
  printf '%s' "$ref"
}

# _kit_mc_resolve <project-toml-file> -- project value, else operator, else kit-root.
_kit_mc_resolve() {
  local v=""
  [ -s "$1" ] && v="$(_kit_toml_get "$1" merge command)"
  [ -n "$v" ] || v="$(KIT_PROJECT_ROOT=/nonexistent kit_config_get merge.command)"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# _kit_mc_emit <value> -- prints a valid value and returns 0; a value that is not one simple
# command prints a reason on stderr and returns 2.
_kit_mc_emit() {
  local v="$1" nl=$'\n'
  case "$v" in
    *[\;\&\|\<\>\`]*|*'$('*|*"$nl"*)
      echo "merge command: '[merge] command' must be one simple command (no ; & | < > backtick \$( or newline); refusing to merge" >&2
      return 2 ;;
  esac
  printf '%s' "$v"
}

kit_merge_command() {
  local repo="${1:-}" def="${2:-}" ref tmp rc=1 v
  [ -n "$repo" ] && [ -d "$repo" ] || { echo "merge command: no repo dir to read the project merge command from; refusing to merge" >&2; return 2; }
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit-merge-cmd.XXXXXX")" || return 2
  if ref="$(_kit_mc_base_ref "$repo" "$def")"; then
    # ls-tree separates "the file is not there" (exit 0, no line) from a real read failure.
    if ! v="$(_kit_mc_git -C "$repo" ls-tree --name-only "$ref" -- .kit.toml 2>/dev/null)"; then rm -f "$tmp"; return 2; fi
    if [ -n "$v" ]; then
      _kit_mc_git -C "$repo" show "$ref:.kit.toml" >| "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    fi
    if v="$(_kit_mc_resolve "$tmp")"; then _kit_mc_emit "$v"; rc=$?; fi
  else
    # No default-branch commit to read: operator and kit-root are still trusted; a project key in
    # the working tree cannot be verified.
    if v="$(_kit_mc_resolve /nonexistent)"; then _kit_mc_emit "$v"; rc=$?
    elif [ -n "$(_kit_toml_get "$repo/.kit.toml" merge command)" ]; then
      echo "merge command: $repo sets [merge] command but origin's default branch cannot be read to verify it (run git fetch); refusing to merge" >&2
      rc=2
    fi
  fi
  rm -f "$tmp"
  return "$rc"
}

kit_merge_command_slug() {
  local slug="${1:-}" def="${2:-}" tmp out err names rc=1 enc
  [ -n "$slug" ] && [ -n "$def" ] || return 2
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit-merge-cmd.XXXXXX")" || return 2
  err="$(mktemp "${TMPDIR:-/tmp}/kit-merge-err.XXXXXX")" || { rm -f "$tmp"; return 2; }
  enc="$(jq -rn --arg d "$def" '$d|@uri')"
  if out="$(gh api -H 'Accept: application/vnd.github.raw' "repos/${slug}/contents/.kit.toml?ref=${enc}" 2>"$err")"; then
    printf '%s\n' "$out" >| "$tmp"
  elif grep -q 'HTTP 404' "$err"; then
    # A 404 is also what a token without contents access gets. Believe "no file" only when the
    # directory listing of the same ref is readable and does not hold it.
    if names="$(gh api "repos/${slug}/contents/?ref=${enc}" --jq '.[].name' 2>/dev/null)" \
       && ! printf '%s\n' "$names" | grep -qxF .kit.toml; then
      : >| "$tmp"
    else
      rm -f "$tmp" "$err"; return 2
    fi
  else
    rm -f "$tmp" "$err"; return 2
  fi
  rm -f "$err"
  if out="$(_kit_mc_resolve "$tmp")"; then _kit_mc_emit "$out"; rc=$?; fi
  rm -f "$tmp"
  return "$rc"
}

# kit_merge_exec -- see the contract above. The command runs in a clean detached checkout of the
# default branch's commit (the script it names is then the reviewed one), with the git and kit
# environment that could redirect it removed. `bash -o pipefail` keeps a piped command honest.
kit_merge_exec() {
  local repo="$1" cmd="$2" pr="$3" head="${4:-}" def="${5:-}" url="${6:-}" ref="" tmpd wt cur rc
  case "$pr" in [1-9]|[1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) echo "merge command: <pr> must be a bare PR number (got '$pr')" >&2; return 64 ;; esac
  [ -n "$cmd" ] && [ -d "$repo" ] || { echo "merge command: no command or no repo dir" >&2; return 64; }
  if [ -n "$head" ]; then
    cur="$(cd "$repo" && gh pr view "$pr" ${url:+--repo "$url"} --json headRefOid 2>/dev/null | jq -r '.headRefOid // empty' 2>/dev/null)"
    if [ "$cur" != "$head" ]; then
      echo "merge command: PR #${pr} head is ${cur:-unreadable}, not the ${head} the kit checked; nothing merged" >&2
      return 3
    fi
  fi
  ref="$(_kit_mc_base_ref "$repo" "$def")" || ref=""
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/kit-merge-run.XXXXXX")" || return 2
  wt="$tmpd/checkout"
  if [ -n "$ref" ]; then
    _kit_mc_git -C "$repo" worktree add -q --detach "$wt" "$ref" >/dev/null 2>&1 \
      || { echo "merge command: cannot check out ${ref} to run the project merge command; nothing merged" >&2; rmdir "$tmpd" 2>/dev/null; return 2; }
  else
    wt="$repo"   # only an operator or kit-root command reaches here (kit_merge_command's rule)
  fi
  (
    cd "$wt" || exit 2
    [ -n "$head" ] && export KIT_MERGE_HEAD_COMMIT="$head"
    export KIT_MERGE_PR="$pr"
    exec env -u BASH_ENV -u ENV -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
      -u KIT_PROJECT_ROOT -u KIT_CONFIG_ROOT -u KIT_CONFIG_OPERATOR \
      bash -o pipefail -c "$cmd"' "$@"' kit-merge "$pr"
  ); rc=$?
  if [ -n "$ref" ]; then
    _kit_mc_git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || :
    rmdir "$tmpd" 2>/dev/null || :
  else
    rmdir "$tmpd" 2>/dev/null || :
  fi
  return "$rc"
}

# kit_merge_verify <repo-dir> <pr> [<repo-url>] -- a zero exit from the project command is not
# proof: a script may only arm auto-merge. Ask GitHub.
kit_merge_verify() {
  local repo="$1" pr="$2" url="${3:-}" state
  state="$(cd "$repo" && gh pr view "$pr" ${url:+--repo "$url"} --json state 2>/dev/null | jq -r '.state // empty' 2>/dev/null)"
  if [ "$state" != "MERGED" ]; then
    echo "merge command: the project merge command exited 0 but GitHub reports PR #${pr} as '${state:-unreadable}', not MERGED" >&2
    return 1
  fi
}
