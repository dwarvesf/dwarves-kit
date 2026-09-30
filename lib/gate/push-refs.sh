#!/usr/bin/env bash
# push-refs.sh -- which refs does a shell command push? The ship-gate's fail-closed parser.
#
# Usage: push-refs.sh <repo-root> <command> <current-branch> <default-branch-name>
#
# This is a best-effort reader of a shell string from a PreToolUse hook. It cannot see the truth:
# a native git pre-push hook receives the exact refs on stdin and is the structural fix. Until
# one exists, the rule is FAIL CLOSED: anything the parser cannot fully account for is reported
# as BLOCK, never guessed at.
#
# Output, one line per fact (the exit code is always 0):
#   REF <commit-sha> <branch-name>   one resolved ref the command would push
#   DEFAULT                          a refspec targets the default branch (safety-gate's business)
#   FORCE                            a force push (safety-gate's business)
#   BLOCK <reason>                   the command cannot be accounted for
#
# Accounted for: `git [-C dir] [-c k=v] [--git-dir=x ...] push [options] [remote [refspec...]]`
# and `gh pr create [--head branch]`, each in any number of `;` `&&` `||` `|` segments.
# Refused: --all --mirror --tags --follow-tags --delete --prune, an unknown option, a `--git-dir
# path` space form, a refspec that is empty, globbed, or does not resolve to a commit, command
# substitution or variables in a push segment, a wrapper (xargs, sudo, env, bash -c) around git.
set -uo pipefail
root="${1:-}"; cmd="${2:-}"; cur="${3:-HEAD}"; defname="${4:-}"

block() { printf 'BLOCK %s\n' "$*"; exit 0; }

# Strip one layer of matching quotes from a token.
unq() { local t="$1"; t="${t#[\"\']}"; t="${t%[\"\']}"; printf '%s' "$t"; }

specs=""      # newline-separated refspecs from every git push segment
gh_heads=""   # newline-separated --head values from gh pr create segments
gh_plain=0    # a gh pr create with no --head ships the current branch
cdirs=""      # distinct -C values
force=0
sawship=0

while IFS= read -r seg; do
  [ -n "${seg//[[:space:]]/}" ] || continue
  read -ra raw <<< "$seg"
  tok=(); for t in ${raw[@]+"${raw[@]}"}; do tok+=("$(unq "$t")"); done
  # skip leading VAR=value words
  i=0; while [ "$i" -lt "${#tok[@]}" ] && printf '%s' "${tok[$i]}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; do i=$((i+1)); done
  first="${tok[$i]:-}"
  has_git_push=0; has_gh_create=0
  for ((k=0; k<${#tok[@]}; k++)); do
    [ "${tok[$k]}" = push ] && has_git_push=1
    [ "${tok[$k]}" = create ] && has_gh_create=1
  done
  case "$first" in
    git)
      j=$((i+1)); sub=""
      while [ "$j" -lt "${#tok[@]}" ]; do
        case "${tok[$j]}" in
          -C) cdirs="$cdirs${tok[$((j+1))]:-}"$'\n'; j=$((j+2)) ;;
          -c) case "${tok[$((j+1))]:-}" in alias.*) [ "$has_git_push" = 1 ] && block "an alias defined on the command line could be push" ;; esac; j=$((j+2)) ;;
          --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--no-pager|-p|-P|--paginate|--bare|--no-replace-objects|--literal-pathspecs|--no-optional-locks|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs) j=$((j+1)) ;;
          -*) [ "$has_git_push" = 1 ] && block "git option '${tok[$j]}' before push is not understood"; j=$((j+1)) ;;
          *) sub="${tok[$j]}"; break ;;
        esac
      done
      [ "$sub" = push ] || continue   # another git command (a commit message may mention push)
      # command substitution, subshells, backticks, variables: cannot be resolved
      case "$seg" in *'$'*|*'`'*|*'('*|*')'*) block "a push segment uses a variable or command substitution" ;; esac
      sawship=1
      pos=(); skip=0
      for ((k=j+1; k<${#tok[@]}; k++)); do
        t="${tok[$k]}"
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$t" in
          --all|--mirror|--tags|--follow-tags|--delete|-d|--prune) block "git push $t pushes refs the gate cannot list" ;;
          --force|-f) force=1 ;;
          -u|--set-upstream|-n|--dry-run|-q|--quiet|-v|--verbose|--no-verify|--verify|--progress|--atomic|--force-with-lease|--force-with-lease=*|--force-if-includes|--no-force-with-lease|--thin|--no-thin|--signed|--signed=*|--no-signed|--porcelain|--ipv4|--ipv6|--recurse-submodules=*|--no-recurse-submodules|--receive-pack=*|--exec=*|--repo=*|--push-option=*) ;;
          -o|--push-option|--repo|--receive-pack|--exec) skip=1 ;;
          -[a-zA-Z][a-zA-Z]*)
            case "$t" in *f*) force=1 ;; *) printf '%s' "$t" | grep -Eq '^-[unqv]+$' || block "git push option '$t' is not understood" ;; esac ;;
          -*) block "git push option '$t' is not understood" ;;
          *) pos+=("$t") ;;
        esac
      done
      if [ "${#pos[@]}" -ge 2 ]; then
        for ((k=1; k<${#pos[@]}; k++)); do specs="$specs${pos[$k]}"$'\n'; done
      else
        specs="${specs}HEAD"$'\n'
      fi
      ;;
    gh)
      [ "$has_gh_create" = 1 ] && [ "${tok[$((i+1))]:-}" = pr ] && [ "${tok[$((i+2))]:-}" = create ] || continue
      sawship=1; head=""
      for ((k=i+3; k<${#tok[@]}; k++)); do
        case "${tok[$k]}" in
          --head|-H) head="${tok[$((k+1))]:-}" ;;
          --head=*) head="${tok[$k]#--head=}" ;;
        esac
      done
      if [ -n "$head" ]; then
        case "$head" in *'$'*|*'`'*|*:*|*'*'*) block "gh pr create --head '$head' cannot be resolved" ;; esac
        gh_heads="$gh_heads$head"$'\n'
      else gh_plain=1; fi
      ;;
    echo|printf|cat|grep|rg|sed|awk|'#'*|'') ;;
    *)
      # any other command word carrying git ... push or gh pr create (xargs, sudo, env, bash -c, ...)
      gi=0; for t in "${tok[@]}"; do [ "$t" = git ] && gi=1; done
      if [ "$gi" = 1 ] && [ "$has_git_push" = 1 ]; then block "git push runs under a wrapper ('$first')"; fi
      if [ "$has_gh_create" = 1 ]; then for t in "${tok[@]}"; do [ "$t" = gh ] && block "gh pr create runs under a wrapper ('$first')"; done; fi
      ;;
  esac
done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"

[ "$sawship" = 1 ] || exit 0
distinct_c="$(printf '%s' "$cdirs" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
[ "$distinct_c" -le 1 ] || block "the command pushes from more than one directory"
if [ "$force" = 1 ]; then printf 'FORCE\n'; exit 0; fi

resolve() {   # resolve <src> <dst>: print REF, or block
  local src="$1" dst="$2" sha br
  [ -n "$src" ] || block "an empty source deletes a remote ref"
  case "$src$dst" in *'*'*|*'?'*|*'['*) block "refspec '$src:$dst' is a pattern" ;; esac
  src="${src#refs/heads/}"; dst="${dst#refs/heads/}"
  [ "$dst" = HEAD ] && dst="$cur"
  case "$dst" in main|master) printf 'DEFAULT\n'; exit 0 ;; esac
  if [ -n "$defname" ] && [ "$dst" = "$defname" ]; then printf 'DEFAULT\n'; exit 0; fi
  sha="$(git -C "$root" rev-parse --verify -q "${src}^{commit}" 2>/dev/null)" || block "'$src' does not resolve to a commit"
  br="$dst"
  if [ "$src" = HEAD ]; then [ "$cur" = HEAD ] || br="$cur"
  elif git -C "$root" show-ref --verify -q "refs/heads/$src" 2>/dev/null; then br="$src"; fi
  printf 'REF %s %s\n' "$sha" "$br"
}

while IFS= read -r r; do
  [ -n "$r" ] || continue
  r="${r#+}"
  case "$r" in *:*) resolve "${r%%:*}" "${r#*:}" ;; *) resolve "$r" "$r" ;; esac
done <<< "$specs"
while IFS= read -r h; do
  [ -n "$h" ] || continue
  resolve "$h" "$h"
done <<< "$gh_heads"
[ "$gh_plain" = 1 ] && resolve HEAD HEAD
exit 0
