#!/usr/bin/env bash
# kit-verb: push-refs | fail-closed parser that names which refs a shell command pushes, used by the ship-gate
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
#   @@REF <commit-sha> <branch-name>   one resolved ref the command would push
#   @@DEFAULT-PUSH <branch> <remote>   a git push lands on a default branch (the ship-gate refuses it)
#   @@DEFAULT                          gh pr create names a default branch as its head
#   @@FORCE                            a force push (safety-gate's business)
#   @@BLOCK <reason>                   the command cannot be accounted for
# Every line starts with @@ and a ref name appears only after a marker word, so a branch called
# DEFAULT or FORCE cannot be mistaken for a marker when the caller matches the line start.
#
# A default branch is main, master, production, <default-branch-name>, or the branch the target
# remote's HEAD names. A push with no refspec is resolved the way git resolves it:
# remote.<remote>.push when set, else push.default (simple and current push the current branch,
# upstream pushes to branch.<cur>.merge, matching also counts every local default branch).
#
# Accounted for: `git [-C dir] [-c k=v] [--git-dir=x ...] push [options] [remote [refspec...]]`
# and `gh pr create [--head branch]`, each in any number of `;` `&&` `||` `|` segments.
# Refused: --all --mirror --tags --follow-tags --delete --prune, an unknown option, a `--git-dir
# path` space form, a refspec that is empty, globbed, or does not resolve to a commit, command
# substitution or variables in a push segment, a wrapper (xargs, sudo, env, bash -c) around git.
set -uo pipefail
root="${1:-}"; cmd="${2:-}"; cur="${3:-HEAD}"; defname="${4:-}"

block() { printf '@@BLOCK %s\n' "$*"; exit 0; }
gcfg() { git -C "$root" config --get "$1" 2>/dev/null || true; }

# The remote a push with no remote argument goes to, the order git reads it in.
push_remote() {
  local r
  r="$(gcfg "branch.$cur.pushRemote")"; [ -n "$r" ] || r="$(gcfg remote.pushDefault)"
  [ -n "$r" ] || r="$(gcfg "branch.$cur.remote")"
  printf '%s' "${r:-origin}"
}

# The branch <remote>/HEAD names, empty when it cannot be read.
remote_head() {
  local h; h="$(git -C "$root" symbolic-ref -q --short "refs/remotes/$1/HEAD" 2>/dev/null || true)"
  [ -n "$h" ] && printf '%s' "${h#"$1"/}"
}

# implicit_specs <remote>: the refspecs a push without one uses, one per line.
implicit_specs() {
  local r="$1" conf up b
  conf="$(git -C "$root" config --get-all "remote.$r.push" 2>/dev/null || true)"
  if [ -n "$conf" ]; then printf '%s\n' "$conf"; return; fi
  up="$(gcfg "branch.$cur.merge")"; up="${up#refs/heads/}"
  case "$(gcfg push.default)" in
    nothing) ;;
    upstream|tracking) if [ "$cur" = HEAD ]; then printf 'HEAD\n'; else printf 'HEAD:%s\n' "${up:-$cur}"; fi ;;
    matching)
      printf 'HEAD\n'
      for b in main master production "$defname" "$(remote_head "$r")"; do
        [ -n "$b" ] && git -C "$root" show-ref --verify -q "refs/heads/$b" 2>/dev/null && printf '%s:%s\n' "$b" "$b"
      done ;;
    *) printf 'HEAD\n' ;;   # simple (git's default) and current push the branch of the same name
  esac
}

is_default() {   # is_default <branch> <remote>
  case "$1" in main|master|production) return 0 ;; esac
  [ -n "$defname" ] && [ "$1" = "$defname" ] && return 0
  [ -n "$1" ] && [ "$1" = "$(remote_head "$2")" ]
}

# Strip one layer of matching quotes from a token.
unq() { local t="$1"; t="${t#[\"\']}"; t="${t%[\"\']}"; printf '%s' "$t"; }

specs=""      # newline-separated "<remote> <refspec>" lines from every git push segment
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
        for ((k=1; k<${#pos[@]}; k++)); do specs="$specs${pos[0]} ${pos[$k]}"$'\n'; done
      else
        rem="${pos[0]:-$(push_remote)}"
        while IFS= read -r r; do [ -n "$r" ] && specs="$specs$rem $r"$'\n'; done <<< "$(implicit_specs "$rem")"
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
dest() {   # dest <dst>: the branch name a refspec destination lands on
  local d="${1#refs/heads/}"
  [ "$d" = HEAD ] && d="$cur"
  printf '%s' "$d"
}

# Default-branch pass first, over every git push refspec: a later unresolvable refspec must not
# hide an earlier (or later) push to the default branch.
while read -r rem r; do
  [ -n "$r" ] || continue
  r="${r#+}"
  case "$r" in *:*) d="$(dest "${r#*:}")" ;; *) d="$(dest "$r")" ;; esac
  if [ "$d" != HEAD ] && is_default "$d" "$rem"; then printf '@@DEFAULT-PUSH %s %s\n' "$d" "$rem"; exit 0; fi
done <<< "$specs"
if [ "$force" = 1 ]; then printf '@@FORCE\n'; exit 0; fi

resolve() {   # resolve <src> <dst>: print REF, or block
  local src="$1" dst="$2" sha br
  [ -n "$src" ] || block "an empty source deletes a remote ref"
  case "$src$dst" in *'*'*|*'?'*|*'['*) block "refspec '$src:$dst' is a pattern" ;; esac
  src="${src#refs/heads/}"; dst="$(dest "$dst")"
  case "$dst" in main|master) printf '@@DEFAULT\n'; exit 0 ;; esac
  if [ -n "$defname" ] && [ "$dst" = "$defname" ]; then printf '@@DEFAULT\n'; exit 0; fi
  sha="$(git -C "$root" rev-parse --verify -q "${src}^{commit}" 2>/dev/null)" || block "'$src' does not resolve to a commit"
  br="$dst"
  if [ "$src" = HEAD ]; then [ "$cur" = HEAD ] || br="$cur"
  elif git -C "$root" show-ref --verify -q "refs/heads/$src" 2>/dev/null; then br="$src"; fi
  printf '@@REF %s %s\n' "$sha" "$br"
}

while read -r _ r; do
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
