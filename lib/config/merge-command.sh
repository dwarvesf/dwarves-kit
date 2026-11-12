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
#       prints the command. exit 0 set, 1 unset, 2 the key could not be read, is written in a form
#       the reader cannot parse, or is not a single simple command: the caller must refuse, never
#       merge the plain way.
#   kit_merge_command_slug <slug> <default-branch>
#       the same, read through `gh api` for a repo with no checkout.
#   kit_merge_default_branch <repo-dir>
#       prints the repo's default branch as GitHub names it (`gh repo view`); empty when gh cannot
#       say, and the callers then fall back to origin/HEAD.
#   kit_merge_exec <repo-dir> <cmd> <pr> [<head-oid>] [<default-branch>] [<repo-url>]
#       runs `<cmd> <pr>` with its output streamed as-is and returns its own exit code. 2 when it
#       could not be started (no default-branch checkout to run it in), 3 when the PR head moved
#       off <head-oid> before the start.
#   kit_merge_verify <repo-dir> <pr> [<repo-url>] [<head-oid>]
#       exit 0 only when GitHub reports the PR MERGED and, given <head-oid>, the merged PR's head
#       is that gated head.
#
# Trust. The command is a line of code the kit runs, so it is read only from places a PR cannot
# change for its own merge:
#   - the project `.kit.toml` as COMMITTED on the default branch (refs/remotes/origin/<default>,
#     fully qualified so a tag or branch named like it cannot stand in), never the working tree,
#     never HEAD, never the PR being merged;
#   - then the operator `kit.toml`, then the kit-root `kit.toml` (project > operator > kit-root).
#   - the script the command names runs from a clean detached checkout of that same commit, not
#     from the working tree the PR (or a stack-merge reconcile) may have changed.
# Who can set the key: anyone who can push to the default branch (project file), or the operator
# (their own kit.toml). Code pushed to the default branch runs on the operator's machine at the
# next merge, without a local pull: the kit fetches the ref itself.
# The fetch of the default branch is best effort. If it fails the local ref may be stale, and a
# key added since the last fetch is not seen; the merge itself needs the network, so a failed
# fetch normally fails the merge too.
# Where the default branch's commit cannot be resolved, a project key cannot be verified: a
# working-tree `[merge] command` then means exit 2, not "unset", and `kit_merge_exec` will not
# run anything (it needs that commit to check out).
# The reader reads one shape: `command = "..."` under a plain `[merge]` header, a double-quoted
# value without a backslash or a `#`. The dotted form (`merge.command = ...`), an inline table
# (`merge = { ... }`), `[[merge]]`, a triple-quoted or single-quoted value, a repeated key and a
# `#` inside the value are all REFUSED (exit 2): the reader cannot read them, and unset would
# mean the plain merge. An empty value is a plain "unset".
# The value must also be one simple command: no `;` `&` `|` `<` `>` backtick `$(` or newline.
# That denylist guards against mistakes. It is NOT a security boundary: whoever can write the
# value can also write the script it names. The PR number is appended as the last argument.
# The command has no timeout; it runs until it exits or the operator interrupts.
#
# Idempotent-source guard.
[ -n "${_KIT_MERGE_CMD_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_MERGE_CMD_SOURCED=1

_KIT_MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config/kit-config.sh
source "$_KIT_MC_DIR/kit-config.sh"

# Every git call here ignores GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE and GIT_COMMON_DIR left in
# the caller's environment (a git hook context exports them) so `-C <repo-dir>` means what it says.
_kit_mc_git() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR git "$@"; }

# kit_merge_default_branch <repo-dir> -- the default branch GitHub names. origin/HEAD can be stale
# (it is set at clone time), so mega-merge and stack-merge ask GitHub.
kit_merge_default_branch() {
  [ -d "${1:-}" ] || return 0
  ( cd "$1" && gh repo view --json defaultBranchRef 2>/dev/null | jq -r '.defaultBranchRef.name // empty' 2>/dev/null ) || :
}

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

# _kit_mc_shape <toml-file> -- exit 0 when the file names `merge` only in the one shape the reader
# reads (or not at all), 1 otherwise. It looks at the raw lines, because the reader returns empty
# for the forms it cannot parse and empty would read as "unset".
_kit_mc_shape() {
  [ -s "$1" ] || return 0
  awk -v q="'" '
    function bad() { exit 1 }
    # key text with leading blanks and one layer of quotes around the first word removed
    function firstword(k,   w) { w = k; sub(/[ \t]*[.=].*$/, "", w); gsub(/"/, "", w); gsub(q, "", w); return w }
    /^[ \t]*#/ { next }
    {
      line = $0
      h = line; sub(/[ \t]+#.*$/, "", h); gsub(/[ \t\r]/, "", h); gsub(/"/, "", h); gsub(q, "", h)
    }
    h ~ /^\[/ {
      if (h ~ /^\[\[merge/) bad()
      if (h == "[merge]") { if (seen++) bad(); insec = 1; ncmd = 0; next }
      if (h ~ /^\[merge\./) bad()
      insec = 0; next
    }
    {
      k = line; sub(/^[ \t]+/, "", k)
      if (!insec) { if (firstword(k) == "merge" && k ~ /[.=]/) bad(); next }
      if (firstword(k) == "command" && k ~ /[.=]/) {
        if (++ncmd > 1) bad()
        sub(/\r$/, "", line)
        if (line !~ /^[ \t]*command[ \t]*=[ \t]*"[^"\\#]*"[ \t]*(#.*)?$/) bad()
      }
    }
  ' "$1"
}

# _kit_mc_resolve <project-toml-file> -- project value, else operator, else kit-root. Exit 0 and
# the value, 1 nothing set, 2 a file names `merge` in a shape the reader cannot read.
_kit_mc_resolve() {
  local f v
  for f in "$1" "$(kit_config_operator)" "$(kit_config_root)"; do
    [ -s "$f" ] || continue
    _kit_mc_shape "$f" || { echo "merge command: $f names [merge] in a form the kit cannot read (use a plain [merge] table with command = \"...\", no # or backslash in the value); refusing to merge" >&2; return 2; }
    v="$(_kit_toml_get "$f" merge command)"
    [ -z "$v" ] || { printf '%s' "$v"; return 0; }
  done
  return 1
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

# _kit_mc_finish <rc-of-_kit_mc_resolve> <value> -- shared tail of the two readers.
_kit_mc_finish() {
  case "$1" in
    0) _kit_mc_emit "$2" ;;
    2) return 2 ;;
    *) return 1 ;;
  esac
}

kit_merge_command() {
  local repo="${1:-}" def="${2:-}" ref tmp v r
  [ -n "$repo" ] && [ -d "$repo" ] || { echo "merge command: no repo dir to read the project merge command from; refusing to merge" >&2; return 2; }
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit-merge-cmd.XXXXXX")" || return 2
  if ref="$(_kit_mc_base_ref "$repo" "$def")"; then
    # ls-tree separates "the file is not there" (exit 0, no line) from a real read failure.
    if ! v="$(_kit_mc_git -C "$repo" ls-tree --name-only "$ref" -- .kit.toml 2>/dev/null)"; then rm -f "$tmp"; return 2; fi
    if [ -n "$v" ]; then
      _kit_mc_git -C "$repo" show "$ref:.kit.toml" >| "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    fi
    v="$(_kit_mc_resolve "$tmp")"; r=$?
    rm -f "$tmp"
    _kit_mc_finish "$r" "$v"; return $?
  fi
  # No default-branch commit to read: operator and kit-root are still read; a project key in the
  # working tree cannot be verified.
  rm -f "$tmp"
  v="$(_kit_mc_resolve /nonexistent)"; r=$?
  if [ "$r" -ne 1 ]; then _kit_mc_finish "$r" "$v"; return $?; fi
  if [ -n "$(_kit_toml_get "$repo/.kit.toml" merge command)" ] || ! _kit_mc_shape "$repo/.kit.toml"; then
    echo "merge command: $repo names [merge] but origin's default branch cannot be read to verify it (run git fetch); refusing to merge" >&2
    return 2
  fi
  return 1
}

kit_merge_command_slug() {
  local slug="${1:-}" def="${2:-}" tmp out err names enc v r
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
  v="$(_kit_mc_resolve "$tmp")"; r=$?
  rm -f "$tmp"
  _kit_mc_finish "$r" "$v"
}

# kit_merge_exec -- see the contract above. The command runs in a clean detached checkout of the
# default branch's commit (the script it names is then the reviewed one), with BASH_ENV, ENV,
# GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_COMMON_DIR, KIT_PROJECT_ROOT, KIT_CONFIG_ROOT and
# KIT_CONFIG_OPERATOR removed from its environment (GH_TOKEN, PATH and the rest are inherited on
# purpose: the script needs gh). `bash -o pipefail` keeps a piped command honest. The checkout and
# its worktree entry are removed on exit and on INT or TERM; the whole run sits in a subshell so
# the caller's own traps are not replaced.
kit_merge_exec() {
  local repo="$1" cmd="$2" pr="$3" head="${4:-}" def="${5:-}" url="${6:-}" ref cur
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
  if [ -z "$ref" ]; then
    echo "merge command: the default branch cannot be resolved (run git fetch), so there is no clean checkout to run the project merge command in; nothing merged" >&2
    return 2
  fi
  (
    tmpd="$(mktemp -d "${TMPDIR:-/tmp}/kit-merge-run.XXXXXX")" || exit 2
    wt="$tmpd/checkout"
    added=0
    cleanup() {
      if [ "$added" = 1 ]; then _kit_mc_git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || :; fi
      rmdir "$tmpd" 2>/dev/null || :
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _kit_mc_git -C "$repo" worktree add -q --detach "$wt" "$ref" >/dev/null 2>&1 \
      || { echo "merge command: cannot check out ${ref} to run the project merge command; nothing merged" >&2; exit 2; }
    added=1
    (
      cd "$wt" || exit 2
      [ -z "$head" ] || export KIT_MERGE_HEAD_COMMIT="$head"
      export KIT_MERGE_PR="$pr"
      exec env -u BASH_ENV -u ENV -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
        -u KIT_PROJECT_ROOT -u KIT_CONFIG_ROOT -u KIT_CONFIG_OPERATOR \
        bash -o pipefail -c "$cmd"' "$@"' kit-merge "$pr"
    )
    exit $?
  )
}

# kit_merge_verify <repo-dir> <pr> [<repo-url>] [<head-oid>] -- a zero exit from the project command
# is not proof: a script may only arm auto-merge, or merge a head the kit never checked
# (KIT_MERGE_HEAD_COMMIT is advisory to the script). Ask GitHub. A project script should pass
# `--match-head-commit "$KIT_MERGE_HEAD_COMMIT"` to its own merge call.
kit_merge_verify() {
  local repo="$1" pr="$2" url="${3:-}" head="${4:-}" js state got
  js="$(cd "$repo" && gh pr view "$pr" ${url:+--repo "$url"} --json state,headRefOid 2>/dev/null)"
  state="$(printf '%s' "$js" | jq -r '.state // empty' 2>/dev/null)"
  if [ "$state" != "MERGED" ]; then
    echo "merge command: the project merge command exited 0 but GitHub reports PR #${pr} as '${state:-unreadable}', not MERGED" >&2
    return 1
  fi
  if [ -n "$head" ]; then
    got="$(printf '%s' "$js" | jq -r '.headRefOid // empty' 2>/dev/null)"
    if [ "$got" != "$head" ]; then
      echo "merge command: PR #${pr} was merged at head ${got:-unreadable}, not the ${head} the kit checked; the project merge command did not honor KIT_MERGE_HEAD_COMMIT" >&2
      return 1
    fi
  fi
}
