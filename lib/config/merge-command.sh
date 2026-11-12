#!/usr/bin/env bash
# merge-command.sh -- the project's own PR merge command (`[merge] command`).
#
# WHY: a repo may require its own merge script (it refuses a draft, a red or pending check, a
# conflict, a one-way door without a second approval). Every place the kit merges a PR itself
# (wrap land, wrap merge, mega-merge, stack-merge) asks this file first. With `[merge] command`
# unset the callers keep their plain `gh pr merge`; with it set they run the project command
# instead and never fall back to the plain merge when it refuses.
#
# Contract (safe under set -euo pipefail, no output on load):
#   kit_merge_command <repo-dir>          -> prints the command; 0 set, 1 unset
#   kit_merge_command_slug <slug> <def>   -> same, read through `gh api` for a repo with no checkout;
#                                            2 when the read failed for a reason other than "no file"
#   kit_merge_exec <repo-dir> <cmd> <pr> [<head-oid>]
#                                         -> runs `<cmd> <pr>` in <repo-dir>, output streamed as-is,
#                                            returns the command's own exit code
#
# Trust: the command comes from the project `.kit.toml` as COMMITTED on the default branch
# (origin/<default>, else HEAD), never from the working tree and never from the PR being merged.
# A PR that edits the key therefore cannot change how it is merged; the edit takes effect once it
# is on the default branch. Order: project (committed) > operator kit.toml > kit-root kit.toml.
# The value is a shell command line; a literal `#` cannot appear in it (the toml reader strips it).
#
# Idempotent-source guard.
[ -n "${_KIT_MERGE_CMD_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_MERGE_CMD_SOURCED=1

_KIT_MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config/kit-config.sh
source "$_KIT_MC_DIR/kit-config.sh"

# _kit_mc_base_ref <repo-dir> -- the ref whose committed .kit.toml counts: origin's default
# branch when the clone knows it, else HEAD.
_kit_mc_base_ref() {
  local repo="$1" ref
  ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" || ref=""
  if [ -z "$ref" ]; then
    for ref in origin/main origin/master; do
      git -C "$repo" rev-parse --verify -q "$ref" >/dev/null 2>&1 && { printf '%s' "$ref"; return 0; }
    done
    ref=HEAD
  fi
  printf '%s' "$ref"
}

# _kit_mc_resolve <project-toml-text-file> -- project value, else operator, else kit-root.
_kit_mc_resolve() {
  local v=""
  [ -s "$1" ] && v="$(_kit_toml_get "$1" merge command)"
  [ -n "$v" ] || v="$(KIT_PROJECT_ROOT=/nonexistent kit_config_get merge.command)"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

kit_merge_command() {
  local repo="${1:-}" tmp rc=1
  [ -n "$repo" ] && [ -d "$repo" ] || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit-merge-cmd.XXXXXX")" || return 1
  kit_config_show_at "$repo" "$(_kit_mc_base_ref "$repo")" >| "$tmp" 2>/dev/null || : >| "$tmp"
  _kit_mc_resolve "$tmp" && rc=0
  rm -f "$tmp"
  return "$rc"
}

kit_merge_command_slug() {
  local slug="${1:-}" def="${2:-}" tmp out rc=1
  [ -n "$slug" ] && [ -n "$def" ] || return 2
  tmp="$(mktemp "${TMPDIR:-/tmp}/kit-merge-cmd.XXXXXX")" || return 2
  if out="$(gh api -H 'Accept: application/vnd.github.raw' "repos/${slug}/contents/.kit.toml?ref=${def}" 2>&1)"; then
    printf '%s\n' "$out" >| "$tmp"
  elif printf '%s' "$out" | grep -q 'HTTP 404'; then
    : >| "$tmp"    # no .kit.toml on the default branch: the project sets nothing
  else
    rm -f "$tmp"; return 2
  fi
  _kit_mc_resolve "$tmp" && rc=0
  rm -f "$tmp"
  return "$rc"
}

# kit_merge_exec <repo-dir> <cmd> <pr> [<head-oid>] -- the PR number rides as the last argument
# (`bash scripts/pr-merge.sh 12`); the head the kit pinned is exported as KIT_MERGE_HEAD_COMMIT
# for a script that wants to pin it. Output goes straight to the caller's stdout and stderr.
kit_merge_exec() {
  local repo="$1" cmd="$2" pr="$3" head="${4:-}"
  case "$pr" in ''|*[!0-9]*) echo "merge command: <pr> must be a bare PR number (got '$pr')" >&2; return 64 ;; esac
  [ -n "$cmd" ] && [ -d "$repo" ] || { echo "merge command: no command or no repo dir" >&2; return 64; }
  ( cd "$repo" && KIT_MERGE_PR="$pr" KIT_MERGE_HEAD_COMMIT="$head" bash -c "$cmd"' "$@"' kit-merge "$pr" )
}
