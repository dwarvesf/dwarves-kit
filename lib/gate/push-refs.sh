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
# Accounted for: `git [-C dir] [-c push.default=x] [--git-dir=x ...] push [options] [remote
# [refspec...]]` and `gh pr create [--head branch]`. The command is split at UNQUOTED separators only.
# One-command rule: a push or PR is answered only when it is the whole Bash call. Allowed beside it:
# fd redirects that write no file (`2>&1`, `>&2`, `>/dev/null`, `2>/dev/null`) and one trailing pipe
# into tail, head, cat or grep with literal arguments. Another step, a file redirect, a VAR=value
# prefix, cd, a group or a subshell refuses. The default-branch pass runs first, so a compound
# command that pushes to a default branch is still reported as @@DEFAULT-PUSH in any repo.
# `git push <remote> --delete <name>...` and `<remote> :<name>` delete plain-named branches: no
# commit is sent, so they are @@DELETE, not @@REF; a default branch among the names is still
# @@DEFAULT-PUSH, and a name that is not plain (a `:`, `+`, glob, variable, HEAD) is refused.
# Refused: --all --mirror --tags --follow-tags --prune, an unknown option, a `--git-dir
# path` space form, a refspec that is globbed or does not resolve to a commit, command
# substitution or variables in a push segment, a wrapper (xargs, sudo, env, bash -c) around git,
# a push option or git option that runs a program (--receive-pack, --exec, --repo, -c other than
# push.default, --exec-path, a `::` remote, --recurse-submodules=on-demand).
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

# split_segments: the command on stdin -> one line per segment,
# "<text>\037<masked>\037<words>\037<file-redirect 0|1>\037<separator after it>". It
# splits at UNQUOTED `;` `&` `|` and newlines, drops comments and redirections, and flattens newlines
# inside quotes to spaces. <masked> is <text> with every quoted or escaped character blanked to `_`
# (quote marks kept), so a masked word holding a quote mark or `\` is a quoted word. <words> is the
# segment's shell words with their quotes removed, joined by \036. <file-redirect> is 1 when the
# segment redirects to or from any file but /dev/null (an fd copy like 2>&1 is not a file). The
# separator is ; nl | || |& & && or end. A quote it cannot close, or a
# redirection with no target, prints the single line @@UNPARSED (bash would not run that command).
split_segments() {
  awk '
    function bad() { print "@@UNPARSED"; failed = 1; exit }
    function put(r, m) { raw = raw r; msk = msk m }
    function addw() { if (inw) { words = words (nw++ ? "\036" : "") wd }; wd = ""; inw = 0 }
    function emit(t) { addw(); if (raw ~ /[^ \t]/) print raw "\037" msk "\037" words "\037" fr "\037" t; raw = ""; msk = ""; words = ""; nw = 0; fr = 0 }
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
      if (t != "/dev/null") fr = 1
      if (t ~ /[$`(]/) { put(" " t " ", " " t " "); wd = t; inw = 1; addw() }   # a substitution in the target stays visible
      else put(" ", " ")
    }
    { s = (NR == 1 ? $0 : s "\n" $0) }
    END {
      n = length(s); i = 1; raw = ""; msk = ""; words = ""; nw = 0; wd = ""; inw = 0; fr = 0
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
        if (c == "\n") { emit("nl"); i++; continue }
        if (c == ";") { emit(";"); i++; continue }
        if (c == "|") { emit((nx == "|" || nx == "&") ? c nx : c); i++; if (nx == "|" || nx == "&") i++; continue }
        if (c == "&") {
          if (nx == ">") { addw(); i++; redir(1); continue }
          emit(nx == "&" ? "&&" : "&"); i++; if (nx == "&") i++; continue
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
      if (!failed) emit("end")
    }'
}

# `git push` / `gh pr create` text in a segment, quoted or not.
GITPUSH_TXT='(^|[^[:alnum:]_-])git[^[:alnum:]_-](.*[^[:alnum:]_-])?push([^[:alnum:]_-]|$)'
GHPR_TXT='(^|[^[:alnum:]_-])gh[^[:alnum:]_-](.*[^[:alnum:]_-])?pr[^[:alnum:]_-](.*[^[:alnum:]_-])?(create|new)([^[:alnum:]_-]|$)'
SEGS="$(printf '%s\n' "$cmd" | split_segments)" || SEGS="@@UNPARSED"
parsed=1
if [ "$SEGS" = "@@UNPARSED" ] || [ -z "$SEGS" ] && [ -n "${cmd//[[:space:]]/}" ]; then
  # Fall back to the plain split (no quote facts). A push read this way is never answered.
  parsed=0; SEGS=""
  while IFS= read -r l; do
    read -ra fw <<< "$l"; ws=""; for t in ${fw[@]+"${fw[@]}"}; do ws="$ws${ws:+$'\036'}$(unq "$t")"; done
    SEGS="$SEGS$l"$'\037'"$l"$'\037'"$ws"$'\037'1$'\037'"?"$'\n'
  done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')"
fi

specs=""      # newline-separated "<remote> <refspec>" lines from every git push segment
gh_heads=""   # newline-separated --head values from gh pr create segments
gh_plain=0    # a gh pr create with no --head ships the current branch
cdirs=""      # distinct -C values
force=0
sawship=0
# The one-command rule: a push is answered (@@REF, @@DELETE, @@FORCE) only when it is the whole Bash
# call. Allowed beside it: fd redirects that write no file (2>&1, >&2, >/dev/null), and one trailing
# pipe into tail, head, cat or grep with literal arguments. Anything else (another step, a file
# redirect, a VAR=value prefix, cd, a group, a subshell) refuses, so a step that rewrites git config,
# a hook, the environment or the directory cannot ride along with a push.
nseg=0; nshipc=0
segI=(); segFr=(); segFirst=(); segText=(); segTerm=(); segShip=()
while IFS=$'\037' read -r seg mseg wrds fr term; do
  [ -n "${seg//[[:space:]]/}" ] || continue
  [ "$nseg" -gt 0 ] && [ "$nshipc" != "$ship0" ] && segShip[$((nseg - 1))]=1   # the previous segment shipped
  ship0="$nshipc"
  IFS=$'\036' read -ra tok <<< "$wrds"
  # skip leading VAR=value words
  i=0; while [ "$i" -lt "${#tok[@]}" ] && printf '%s' "${tok[$i]}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; do i=$((i+1)); done
  first="${tok[$i]:-}"; first="${first##*/}"   # /usr/bin/git is git
  segI[$nseg]="$i"; segFr[$nseg]="$fr"; segFirst[$nseg]="$first"; segText[$nseg]="$seg"; segTerm[$nseg]="$term"; segShip[$nseg]=0
  nseg=$((nseg + 1))
  has_git_push=0; has_gh_create=0
  for ((k=0; k<${#tok[@]}; k++)); do
    [ "${tok[$k]}" = push ] && has_git_push=1
    [ "${tok[$k]}" = create ] && has_gh_create=1
  done
  case "$first" in
    git)
      j=$((i+1)); sub=""; pdo=""; gcx=""
      while [ "$j" -lt "${#tok[@]}" ]; do
        case "${tok[$j]}" in
          -C) cdirs="$cdirs${tok[$((j+1))]:-}"$'\n'; j=$((j+2)) ;;
          -c) case "${tok[$((j+1))]:-}" in
                alias.*) [ "$has_git_push" = 1 ] && block "an alias defined on the command line could be push" ;;
                push.default=*) pdo="${tok[$((j+1))]#push.default=}" ;;
                *) gcx="${tok[$((j+1))]:-}" ;;   # core.sshCommand, core.hooksPath ... : refused on a push below
              esac; j=$((j+2)) ;;
          --exec-path=*) gcx="${tok[$j]}"; j=$((j+1)) ;;   # moves where git finds the programs it runs
          --git-dir=*|--work-tree=*|--namespace=*|--no-pager|-p|-P|--paginate|--bare|--no-replace-objects|--literal-pathspecs|--no-optional-locks|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs) j=$((j+1)) ;;
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
        continue
      fi
      [ "$sub" = push ] || continue   # another git command (a commit message may mention push)
      [ -z "$gcx" ] || pblock "git ${gcx%%=*} on a push runs config the gate cannot read"
      # command substitution, subshells, backticks, variables: cannot be resolved
      case "$seg" in *'$'*|*'`'*|*'('*|*')'*) block "a push segment uses a variable or command substitution" ;; esac
      case "$mseg" in *'{'*|*'}'*) block "a push segment sits in a { } group or brace expansion" ;; esac
      sawship=1; nshipc=$((nshipc + 1))
      pos=(); skip=0; del=0
      for ((k=j+1; k<${#tok[@]}; k++)); do
        t="${tok[$k]}"
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$t" in
          --delete|-d) del=1 ;;
          --all|--mirror|--tags|--follow-tags|--prune) pblock "git push $t pushes refs the gate cannot list" ;;
          --force|-f) force=1 ;;
          -u|--set-upstream|-n|--dry-run|-q|--quiet|-v|--verbose|--no-verify|--verify|--progress|--atomic|--force-with-lease|--force-with-lease=*|--force-if-includes|--no-force-with-lease|--thin|--no-thin|--signed|--signed=*|--no-signed|--porcelain|--ipv4|--ipv6|--recurse-submodules=check|--recurse-submodules=no|--no-recurse-submodules|--push-option=*) ;;
          -o|--push-option) skip=1 ;;   # a push option is data the server reads
          # the program git runs for the remote side: locally via sh for a path or file:// remote
          --receive-pack=*|--exec=*) pblock "git push ${t%%=*} runs a command" ;;
          --receive-pack|--exec) pblock "git push $t runs a command"; skip=1 ;;
          --repo=*) pblock "git push --repo replaces the remote the gate reads" ;;
          --repo) pblock "git push --repo replaces the remote the gate reads"; skip=1 ;;
          --recurse-submodules=*) pblock "git push $t pushes submodule refs the gate cannot list" ;;
          -[a-zA-Z][a-zA-Z]*)
            case "$t" in *f*) force=1 ;; *) printf '%s' "$t" | grep -Eq '^-[unqv]+$' || pblock "git push option '$t' is not understood" ;; esac ;;
          -*) pblock "git push option '$t' is not understood" ;;
          *) pos+=("$t") ;;
        esac
      done
      # a transport-helper remote (ext::<command>, fd::, ...) runs a program
      case "${pos[0]:-}" in *::*) pblock "git push to '${pos[0]}' runs a transport helper" ;; esac
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
      [ "$has_gh_create" = 1 ] && [ "${tok[$((i+1))]:-}" = pr ] && [ "${tok[$((i+2))]:-}" = create ] || continue
      sawship=1; nshipc=$((nshipc + 1)); head=""
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
    echo|printf|cat|grep|rg|'#'*|'') ;;   # print-only; sed and awk can run a command, so they fall through
    *)
      # any other command word carrying git ... push or gh pr create (xargs, sudo, env, bash -c, ...)
      gi=0; ghw=0; for t in "${tok[@]}"; do [ "$t" = git ] && gi=1; [ "$t" = gh ] && ghw=1; done
      tgit=0; tgh=0
      { [ "$gi" = 1 ] && [ "$has_git_push" = 1 ]; } || [[ $seg =~ $GITPUSH_TXT ]] && tgit=1
      { [ "$ghw" = 1 ] && [ "$has_gh_create" = 1 ]; } || [[ $seg =~ $GHPR_TXT ]] && tgh=1
      [ "$tgit" = 1 ] || [ "$tgh" = 1 ] || continue
      wmsg="git push runs under a wrapper ('$first')"; [ "$tgit" = 1 ] || wmsg="gh pr create runs under a wrapper ('$first')"
      # A wrapped body (bash -c "cd x; git push origin main") is read once more, only for the
      # default-branch rule, which holds in every repo while the wrapper refusal holds in adopted ones.
      if [ -z "${PUSH_REFS_NESTED:-}" ]; then
        for w in "${tok[@]}"; do
          case "$w" in *[[:space:]]*) [[ $w =~ $GITPUSH_TXT ]] || continue ;; *) continue ;; esac
          dp="$(PUSH_REFS_NESTED=1 bash "${BASH_SOURCE[0]}" "$root" "$w" "$cur" "$defname" 2>/dev/null | grep -m1 '^@@DEFAULT-PUSH ')"
          [ -n "$dp" ] && { printf '%s\n' "$dp"; exit 0; }
        done
      fi
      block "$wmsg"
      ;;
  esac
done <<< "$SEGS"
[ "$nseg" -gt 0 ] && [ "$nshipc" != "$ship0" ] && segShip[$((nseg - 1))]=1
# The one-command rule, checked over the recorded segments: segment 0 is the only push or PR, with no
# VAR=value prefix and no file redirect; at most one more segment, reached by a plain pipe, running
# tail/head/cat/grep with literal arguments; the last segment ends the call.
one_ok=1
{ [ "$parsed" = 1 ] && [ "$nshipc" = 1 ] && [ "$nseg" -ge 1 ] && [ "$nseg" -le 2 ] && [ "${segShip[0]:-0}" = 1 ]; } || one_ok=0
{ [ "${segI[0]:-1}" = 0 ] && [ "${segFr[0]:-1}" = 0 ]; } || one_ok=0
if [ "$nseg" = 2 ]; then
  [ "${segTerm[0]}" = "|" ] || one_ok=0
  case "${segFirst[1]}" in tail|head|cat|grep) ;; *) one_ok=0 ;; esac
  { [ "${segI[1]}" = 0 ] && [ "${segFr[1]}" = 0 ]; } || one_ok=0
  case "${segText[1]}" in *'$'*|*'`'*|*'('*|*')'*|*'<'*|*'>'*) one_ok=0 ;; esac
fi
[ "$nseg" -ge 1 ] && case "${segTerm[$((nseg - 1))]}" in end|';'|nl) ;; *) one_ok=0 ;; esac

[ "$sawship" = 1 ] || exit 0
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
[ "$one_ok" = 1 ] || block "a push must be the only command in the call (allowed beside it: 2>&1 or >/dev/null, and one pipe into tail, head, cat or grep)"
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
