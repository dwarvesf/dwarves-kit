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
#   @@DELETE <branch> <remote>         a push deletes one plain-named remote branch (sends no commit)
#   @@NONE                             fully read, and nothing in the command pushes or opens a PR
#   @@BLOCK <reason>                   the command cannot be accounted for
# Every line starts with @@ and a ref name appears only after a marker word, so a branch called
# DEFAULT or FORCE cannot be mistaken for a marker when the caller matches the line start.
# No output at all means the parser could not decide; the ship-gate refuses that ("no answer").
#
# A default branch is main, master, production, <default-branch-name>, or the branch the target
# remote's HEAD names. A push with no refspec is resolved the way git resolves it:
# remote.<remote>.push when set, else push.default (simple and current push the current branch,
# upstream pushes to branch.<cur>.merge, matching also counts every local default branch).
#
# Accounted for: `git [-C dir] [-c k=v] [--git-dir=x ...] push [options] [remote [refspec...]]`
# and `gh pr create [--head branch]`, each in any number of `;` `&&` `||` `|` segments.
# The command is split at UNQUOTED separators only, and redirections (`2>&1`, `>file`, `&>file`)
# are dropped first: they never change which refs git pushes. A redirect target holding `$`,
# a backtick or a paren is kept, so the substitution rule below still sees it.
# `git push <remote> --delete <name>...` and `<remote> :<name>` delete plain-named branches: no
# commit is sent, so they are @@DELETE, not @@REF; a default branch among the names is still
# @@DEFAULT-PUSH, and a name that is not plain (a `:`, `+`, glob, variable, HEAD) is refused.
# `git push` text inside a QUOTED argument of another command is data, not a push, when it is the
# value of a `--long-option` whose name does not name execution, and nothing in the command can
# run a string (the EXEC list below, a path or variable as a command word, a substitution).
# Refused: --all --mirror --tags --follow-tags --prune, an unknown option, a `--git-dir
# path` space form, a refspec that is globbed or does not resolve to a commit, command
# substitution or variables in a push segment, a wrapper (xargs, sudo, env, bash -c) around git,
# and `git push` text in a quoted argument that is not data by the rule above.
set -uo pipefail
root="${1:-}"; cmd="${2:-}"; cur="${3:-HEAD}"; defname="${4:-}"

block() { printf '@@BLOCK %s\n' "$*"; exit 0; }
# A push option the gate cannot list is held until the default-branch pass has run, so
# `git push --follow-tags origin main` is still reported as a default push.
pend=""
pblock() { [ -n "$pend" ] || pend="$*"; }
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
  case "${pdo:-$(gcfg push.default)}" in
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

# split_segments: the command on stdin -> one line per segment, "<text>\037<masked>\037<words>". It
# splits at UNQUOTED `;` `&` `|` and newlines, drops comments and redirections, and flattens newlines
# inside quotes to spaces. <masked> is <text> with every quoted or escaped character blanked to `_`
# (quote marks kept), so a masked word holding a quote mark or `\` is a quoted word. <words> is the
# segment's shell words with their quotes removed, joined by \036. A quote it cannot close, or a
# redirection with no target, prints the single line @@UNPARSED (bash would not run that command).
split_segments() {
  awk '
    function bad() { print "@@UNPARSED"; failed = 1; exit }
    function put(r, m) { raw = raw r; msk = msk m }
    function addw() { if (inw) { words = words (nw++ ? "\036" : "") wd }; wd = ""; inw = 0 }
    function emit() { addw(); if (raw ~ /[^ \t]/) print raw "\037" msk "\037" words; raw = ""; msk = ""; words = ""; nw = 0 }
    function flat(b,   m) {   # copy a quote body flat into <text>, blanked into <masked>, bare into the word
      gsub(/\n/, " ", b); m = b; gsub(/./, "_", m); qb = b; qm = m
    }
    function close1(j, esc,   d) {   # index of the closing single quote from j, -1 if none
      while (j <= n) { d = substr(s, j, 1); if (esc && d == "\\") { j += 2; continue }; if (d == "\047") return j; j++ }
      return -1
    }
    function close2(j,   d) {
      while (j <= n) { d = substr(s, j, 1); if (d == "\\") { j += 2; continue }; if (d == "\"") return j; j++ }
      return -1
    }
    function word(j,   d, e) {   # end (exclusive) of the shell word that starts at j
      while (j <= n) {
        d = substr(s, j, 1)
        if (d ~ /[ \t\n;&|<>()]/) break
        if (d == "\\") { j += 2; continue }
        if (d == "\047") { e = close1(j + 1, 0); if (e < 0) bad(); j = e + 1; continue }
        if (d == "\"") { e = close2(j + 1); if (e < 0) bad(); j = e + 1; continue }
        j++
      }
      return j
    }
    function redir(amp,   op, nx, st, t) {   # i sits on > or <; skip the operator and its target
      op = substr(s, i, 1); i++; nx = substr(s, i, 1)
      if (op == ">" && (nx == ">" || nx == "|")) i++
      else if (op == "<" && nx == ">") i++
      else if (nx == "&" && !amp) {
        i++
        if (match(substr(s, i), /^[0-9]*-?/) && RLENGTH > 0) { i += RLENGTH; put(" ", " "); return }
      }
      while (substr(s, i, 1) ~ /[ \t]/) i++
      st = i; i = word(i)
      if (i == st) bad()
      t = substr(s, st, i - st)
      if (t ~ /[$`(]/) { put(" " t " ", " " t " "); wd = t; inw = 1; addw() }   # a substitution in the target stays visible
      else put(" ", " ")
    }
    { s = (NR == 1 ? $0 : s "\n" $0) }
    END {
      n = length(s); i = 1; raw = ""; msk = ""; words = ""; nw = 0; wd = ""; inw = 0
      while (i <= n) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (c == "\\") { if (nx != "\n") { put(c nx, "\\_"); wd = wd nx; inw = 1 }; i += 2; continue }
        if (c == "\047" || (c == "$" && nx == "\047")) {
          q = (c == "$"); j = close1(i + 1 + q, q); if (j < 0) bad()
          flat(substr(s, i + 1 + q, j - i - 1 - q))
          put(substr(s, i, 1 + q) qb "\047", substr(s, i, 1 + q) qm "\047"); wd = wd qb; inw = 1
          i = j + 1; continue
        }
        if (c == "\"") {
          j = close2(i + 1); if (j < 0) bad()
          flat(substr(s, i + 1, j - i - 1)); put("\"" qb "\"", "\"" qm "\"")
          wd = wd qb; inw = 1
          i = j + 1; continue
        }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n;&|()]/)) { addw(); while (i <= n && substr(s, i, 1) != "\n") i++; continue }
        if (c == "\n" || c == ";") { emit(); i++; continue }
        if (c == "|") { emit(); i++; if (nx == "|" || nx == "&") i++; continue }
        if (c == "&") {
          if (nx == ">") { addw(); i++; redir(1); continue }
          emit(); i++; if (nx == "&") i++; continue
        }
        if (c == ">" || c == "<") {
          if (nx == "(" || (c == "<" && nx == "<")) { put(c nx, c nx); wd = wd c nx; inw = 1; i += 2; continue }   # process substitution, heredoc: kept as words
          if (match(raw, /(^|[ \t])[0-9]+$/)) {   # N>file: the digits are the fd, not a word
            k = RLENGTH - (substr(raw, RSTART, 1) ~ /[ \t]/ ? 1 : 0)
            raw = substr(raw, 1, length(raw) - k); msk = substr(msk, 1, length(msk) - k); wd = ""; inw = 0
          } else addw()
          redir(0); continue
        }
        if (c == " " || c == "\t") { addw(); put(c, c); i++; continue }
        put(c, c); wd = wd c; inw = 1; i++
      }
      if (!failed) emit()
    }'
}

# Commands that can run a string they are handed (as an argument or on stdin). One unquoted in the
# command means quoted `git push` text may run, so it is never read as data.
EXEC_RE='^(bash|sh|zsh|dash|ksh|mksh|fish|csh|tcsh|eval|exec|source|\.|command|builtin|xargs|sudo|doas|su|runuser|env|nohup|setsid|timeout|nice|stdbuf|ionice|caffeinate|chronic|unbuffer|watch|time|ssh|mosh|parallel|script|flock|tmux|screen|expect|at|batch|perl|python|python2|python3|ruby|node|deno|bun|osascript|awk|gawk|nawk|mawk|sed|gsed|op|mise|direnv|npx|uvx|pipx|make|just|docker|podman|kubectl|git-sh)$'
# `git push` / `gh pr create` text in a segment, quoted or not.
GITPUSH_TXT='(^|[^[:alnum:]_-])git[^[:alnum:]_-](.*[^[:alnum:]_-])?push([^[:alnum:]_-]|$)'
GHPR_TXT='(^|[^[:alnum:]_-])gh[^[:alnum:]_-](.*[^[:alnum:]_-])?pr[^[:alnum:]_-](.*[^[:alnum:]_-])?(create|new)([^[:alnum:]_-]|$)'
# A long option that names execution: its value may be run, so it is not data.
EXECOPT_RE='^--([a-z0-9-]*-)?(exec|eval|command|cmd|run|shell|script|sh)([-=].*)?$'

SEGS="$(printf '%s\n' "$cmd" | split_segments)" || SEGS="@@UNPARSED"
parsed=1
if [ "$SEGS" = "@@UNPARSED" ] || [ -z "$SEGS" ] && [ -n "${cmd//[[:space:]]/}" ]; then
  # Fall back to the plain split (no quote facts): every word counts as unquoted, nothing is data.
  parsed=0; SEGS=""
  while IFS= read -r l; do
    read -ra fw <<< "$l"; ws=""; for t in ${fw[@]+"${fw[@]}"}; do ws="$ws${ws:+$'\036'}$(unq "$t")"; done
    SEGS="$SEGS$l"$'\037'"$l"$'\037'"$ws"$'\n'
  done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
fi
# Pre-pass: can anything in this command run a string? An unquoted EXEC word anywhere, a command word
# that is a path or holds `$` or a backtick, or a substitution anywhere (even inside double quotes).
runner=0
case "$cmd" in *'$('*|*'`'*|*'<('*|*'>('*) runner=1 ;; esac
while IFS=$'\037' read -r seg mseg _; do
  read -ra mw <<< "$mseg"
  c0=1
  for w in ${mw[@]+"${mw[@]}"}; do
    if [ "$c0" = 1 ] && [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then continue; fi
    if [ "$c0" = 1 ]; then case "$w" in if|then|else|elif|while|until|do|'!'|'{') continue ;; esac; fi
    if [ "$c0" = 1 ]; then
      c0=0
      case "$w" in *'$'*|*'`'*|*\\*) runner=1 ;; */*) case "${w##*/}" in git|gh) ;; *) runner=1 ;; esac ;; esac
    fi
    case "$w" in *[\"\'\\]*) continue ;; esac
    [[ ${w##*/} =~ $EXEC_RE ]] && runner=1
  done
done <<< "$SEGS"
[ "$parsed" = 1 ] || runner=1

# quoted_data <masked-words...>: every quoted word is the value of a non-exec --long-option.
quoted_data() {
  local prev="" w
  for w in "$@"; do
    case "$w" in
      *[\"\'\\]*)
        case "$w" in
          --*=*) [[ ${w%%=*} =~ $EXECOPT_RE ]] && return 1 ;;
          *) case "$prev" in --*) [[ $prev =~ $EXECOPT_RE ]] && return 1 ;; *) return 1 ;; esac ;;
        esac ;;
    esac
    prev="$w"
  done
  return 0
}

specs=""      # newline-separated "<remote> <refspec>" lines from every git push segment
gh_heads=""   # newline-separated --head values from gh pr create segments
gh_plain=0    # a gh pr create with no --head ships the current branch
cdirs=""      # distinct -C values
force=0
sawship=0
suspect=0     # a segment carries push text the parser did not classify: never answer @@NONE

while IFS=$'\037' read -r seg mseg wrds; do
  [ -n "${seg//[[:space:]]/}" ] || continue
  IFS=$'\036' read -ra tok <<< "$wrds"
  read -ra mw <<< "$mseg"
  txt=0; [[ $seg =~ $GITPUSH_TXT ]] && txt=1; [[ $seg =~ $GHPR_TXT ]] && txt=1
  # the unquoted words: a quoted word (one holding a quote mark or an escape) is left out
  uw=" "; for w in ${mw[@]+"${mw[@]}"}; do case "$w" in *[\"\'\\]*) ;; *) uw="$uw${w##*/} " ;; esac; done
  # skip leading VAR=value words
  i=0; while [ "$i" -lt "${#tok[@]}" ] && printf '%s' "${tok[$i]}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; do i=$((i+1)); done
  first="${tok[$i]:-}"; first="${first##*/}"   # /usr/bin/git is git
  has_git_push=0; has_gh_create=0
  for ((k=0; k<${#tok[@]}; k++)); do
    [ "${tok[$k]}" = push ] && has_git_push=1
    [ "${tok[$k]}" = create ] && has_gh_create=1
  done
  case "$first" in
    git)
      j=$((i+1)); sub=""; pdo=""
      while [ "$j" -lt "${#tok[@]}" ]; do
        case "${tok[$j]}" in
          -C) cdirs="$cdirs${tok[$((j+1))]:-}"$'\n'; j=$((j+2)) ;;
          -c) case "${tok[$((j+1))]:-}" in
                alias.*) [ "$has_git_push" = 1 ] && block "an alias defined on the command line could be push" ;;
                push.default=*) pdo="${tok[$((j+1))]#push.default=}" ;;
              esac; j=$((j+2)) ;;
          --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--no-pager|-p|-P|--paginate|--bare|--no-replace-objects|--literal-pathspecs|--no-optional-locks|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs) j=$((j+1)) ;;
          -*) [ "$has_git_push" = 1 ] && block "git option '${tok[$j]}' before push is not understood"; j=$((j+1)) ;;
          *) sub="${tok[$j]}"; break ;;
        esac
      done
      # A branch switch earlier in the same command changes what HEAD means for a later push.
      if [ "$sub" = checkout ] || [ "$sub" = switch ]; then
        nb=""
        for ((k=j+1; k<${#tok[@]}; k++)); do
          case "${tok[$k]}" in
            -b|-B|-c|-C|--create|--force-create|--orphan) nb="${tok[$((k+1))]:-}"; break ;;
            --) break ;;
            -*) ;;
            *) nb="${tok[$k]}"; break ;;
          esac
        done
        case "$nb" in '') ;; -|@\{*) cur="@@UNKNOWN" ;; *) cur="$nb" ;; esac
        [ "$txt" = 1 ] && suspect=1
        continue
      fi
      if [ "$sub" != push ]; then   # another git command (a commit message may mention push)
        # push text in the arguments of a git command that can run a string (rebase --exec,
        # submodule foreach, bisect run, an alias) is not data
        case "$sub" in commit|tag|notes|merge|log|show|grep|stash) ;; *) [ "$txt" = 1 ] && suspect=1 ;; esac
        continue
      fi
      # command substitution, subshells, backticks, variables: cannot be resolved
      case "$seg" in *'$'*|*'`'*|*'('*|*')'*) block "a push segment uses a variable or command substitution" ;; esac
      sawship=1
      pos=(); skip=0; del=0
      for ((k=j+1; k<${#tok[@]}; k++)); do
        t="${tok[$k]}"
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$t" in
          --delete|-d) del=1 ;;
          --all|--mirror|--tags|--follow-tags|--prune) pblock "git push $t pushes refs the gate cannot list" ;;
          --force|-f) force=1 ;;
          -u|--set-upstream|-n|--dry-run|-q|--quiet|-v|--verbose|--no-verify|--verify|--progress|--atomic|--force-with-lease|--force-with-lease=*|--force-if-includes|--no-force-with-lease|--thin|--no-thin|--signed|--signed=*|--no-signed|--porcelain|--ipv4|--ipv6|--recurse-submodules=*|--no-recurse-submodules|--receive-pack=*|--exec=*|--repo=*|--push-option=*) ;;
          -o|--push-option|--repo|--receive-pack|--exec) skip=1 ;;
          -[a-zA-Z][a-zA-Z]*)
            case "$t" in *f*) force=1 ;; *) printf '%s' "$t" | grep -Eq '^-[unqv]+$' || pblock "git push option '$t' is not understood" ;; esac ;;
          -*) pblock "git push option '$t' is not understood" ;;
          *) pos+=("$t") ;;
        esac
      done
      if [ "$del" = 1 ]; then
        # --delete makes every name after the remote a deletion (git refuses src:dst there)
        [ "${#pos[@]}" -ge 2 ] || block "git push --delete names no branch"
        for ((k=1; k<${#pos[@]}; k++)); do specs="$specs${pos[0]} $cur :${pos[$k]}"$'\n'; done
      elif [ "${#pos[@]}" -ge 2 ]; then
        for ((k=1; k<${#pos[@]}; k++)); do specs="$specs${pos[0]} $cur ${pos[$k]}"$'\n'; done
      else
        rem="${pos[0]:-$(push_remote)}"
        while IFS= read -r r; do [ -n "$r" ] && specs="$specs$rem $cur $r"$'\n'; done <<< "$(implicit_specs "$rem")"
      fi
      ;;
    gh)
      if ! { [ "$has_gh_create" = 1 ] && [ "${tok[$((i+1))]:-}" = pr ] && [ "${tok[$((i+2))]:-}" = create ]; }; then
        [ "$txt" = 1 ] && suspect=1
        continue
      fi
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
      gi=0; ghw=0; for t in "${tok[@]}"; do [ "$t" = git ] && gi=1; [ "$t" = gh ] && ghw=1; done
      tgit=0; tgh=0
      { [ "$gi" = 1 ] && [ "$has_git_push" = 1 ]; } || [[ $seg =~ $GITPUSH_TXT ]] && tgit=1
      { [ "$ghw" = 1 ] && [ "$has_gh_create" = 1 ]; } || [[ $seg =~ $GHPR_TXT ]] && tgh=1
      [ "$tgit" = 1 ] || [ "$tgh" = 1 ] || continue
      wmsg="git push runs under a wrapper ('$first')"; [ "$tgit" = 1 ] || wmsg="gh pr create runs under a wrapper ('$first')"
      # unquoted git ... push is run by this command (xargs git push, sudo git push)
      case "$uw" in *" git "*) case "$uw" in *" push "*) block "$wmsg" ;; esac ;; esac
      case "$uw" in *" gh "*) case "$uw" in *" create "*|*" new "*) block "$wmsg" ;; esac ;; esac
      # quoted text: data only as a non-exec --long-option value, with nothing able to run it
      if [ "$runner" = 1 ] || ! quoted_data ${mw[@]+"${mw[@]}"}; then block "$wmsg"; fi
      ;;
  esac
done <<< "$SEGS"

if [ "$sawship" != 1 ]; then
  [ "$suspect" = 0 ] && [ "$runner" = 0 ] && printf '@@NONE\n'
  exit 0
fi
distinct_c="$(printf '%s' "$cdirs" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
[ "$distinct_c" -le 1 ] || block "the command pushes from more than one directory"
dest() {   # dest <dst>: the branch name a refspec destination lands on (git expands heads/x and @)
  local d="${1#refs/heads/}"; d="${d#heads/}"
  case "$d" in HEAD|@) d="$cur" ;; esac
  printf '%s' "$d"
}

# Default-branch pass first, over every git push refspec: a later unresolvable refspec must not
# hide an earlier (or later) push to the default branch.
lastcur="$cur"   # the branch HEAD names after every switch in the command (gh pr create reads it)
while read -r rem scur r; do
  [ -n "$r" ] || continue
  r="${r#+}"; cur="$scur"
  case "$r" in *:*) d="$(dest "${r#*:}")" ;; *) d="$(dest "$r")" ;; esac
  [ "$d" = "@@UNKNOWN" ] && pblock "the command switches to a branch the gate cannot name before it pushes"
  if [ "$d" != HEAD ] && is_default "$d" "$rem"; then printf '@@DEFAULT-PUSH %s %s\n' "$d" "$rem"; exit 0; fi
done <<< "$specs"
[ -z "$pend" ] || block "$pend"
if [ "$force" = 1 ]; then printf '@@FORCE\n'; exit 0; fi

resolve() {   # resolve <src> <dst> [remote]: print REF or DELETE, or block
  local src="$1" dst="$2" sha br
  if [ -z "$src" ]; then   # an empty source deletes <dst>; the default pass already refused a default branch
    case "${dst#refs/heads/}" in HEAD|@|heads/HEAD) block "git push deletes '$dst', which is not a plain branch name" ;; esac
    dst="$(dest "$dst")"
    [[ $dst =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] && [ "$dst" != HEAD ] && [ "$dst" != "@@UNKNOWN" ] \
      || block "git push deletes '$dst', which is not a plain branch name"
    printf '@@DELETE %s %s\n' "$dst" "${3:-}"; return 0
  fi
  case "$src$dst" in *'*'*|*'?'*|*'['*) block "refspec '$src:$dst' is a pattern" ;; esac
  src="${src#refs/heads/}"; dst="$(dest "$dst")"
  case "$dst" in main|master) printf '@@DEFAULT\n'; exit 0 ;; esac
  if [ -n "$defname" ] && [ "$dst" = "$defname" ]; then printf '@@DEFAULT\n'; exit 0; fi
  sha="$(git -C "$root" rev-parse --verify -q "${src}^{commit}" 2>/dev/null)" || block "'$src' does not resolve to a commit"
  br="$dst"
  if [ "$src" = HEAD ] || [ "$src" = @ ]; then [ "$cur" = HEAD ] || br="$cur"
  elif git -C "$root" show-ref --verify -q "refs/heads/$src" 2>/dev/null; then br="$src"; fi
  printf '@@REF %s %s\n' "$sha" "$br"
}

while read -r rem scur r; do
  [ -n "$r" ] || continue
  cur="$scur"
  r="${r#+}"
  case "$r" in *:*) resolve "${r%%:*}" "${r#*:}" "$rem" ;; *) resolve "$r" "$r" "$rem" ;; esac
done <<< "$specs"
cur="$lastcur"
while IFS= read -r h; do
  [ -n "$h" ] || continue
  resolve "$h" "$h"
done <<< "$gh_heads"
[ "$gh_plain" = 1 ] && resolve HEAD HEAD
exit 0
