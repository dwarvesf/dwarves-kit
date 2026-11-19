#!/usr/bin/env bash
# test-ship-gate-cd-var.sh -- a line-start `cd $W` resolves to the path W holds when W is set once,
# earlier, by a plain literal assignment the shell runs unconditionally. Every other shape keeps
# today's fallback, the session cwd. Live sample: `W=<worktree>` on its own line, `cd $W && ...`,
# then a feature push, run from a session cwd on main, was judged against main and blocked.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
ERR="$LOGDIR/stderr"

mkrepo() { # $1=dir $2=default branch
  git init -q -b "$2" "$1"
  git -C "$1" config user.email dev@users.noreply.github.com; git -C "$1" config user.name "Dev Tester"
  echo base > "$1/f"; git -C "$1" add -A; git -C "$1" commit -qm "chore: init"
}
newdir() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; printf '%s/r' "$d"; }
# lines <line>...: the arguments joined by newlines (one multi-line Bash command)
lines() { printf '%s\n' "$@"; }
# HOOK_HOME, when set, is the HOME the hook runs with (the tilde rows).
HOOK_HOME=""
run_hook() { # run_hook <cwd> <command> [env assignment...]
  local cwd="$1" cmd="$2"; shift 2
  jq -n --arg cwd "$cwd" --arg cmd "$cmd" '{cwd: $cwd, tool_input: {command: $cmd}}' \
    | env ${HOOK_HOME:+HOME="$HOOK_HOME"} "$@" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" \
        bash "$KIT/hooks/ship-gate.sh"
}
gate() { run_hook "$1" "$2" >/dev/null 2>"$ERR"; echo $?; }        # -> exit code; stderr in $ERR
cddir() { run_hook "$1" "$2" DWARVES_KIT_PRINT_CDDIR=1 2>/dev/null; }  # -> the resolved cd target
expect() { # expect <name> <want> <got> [stderr substring]
  if [ "$3" = "$2" ] && { [ -z "${4:-}" ] || grep -qF -- "$4" "$ERR"; }; then ok "$1"
  else no "$1 (want exit $2${4:+ + '$4'}, got $3: $(head -c 300 "$ERR"))"; fi
}
want_cd() { if [ "$3" = "$2" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi; }

# Fixtures. M: the session checkout, on main, not adopted. W: a worktree of M on a feature branch.
M="$(newdir)"; mkrepo "$M" main
W="$M/.claude/worktrees/thing"; git -C "$M" worktree add -q -b fix/thing "$W" 2>/dev/null
mkdir -p "$W/sub"
WS="$M/.claude/worktrees/a b"; git -C "$M" worktree add -q -b fix/space "$WS" 2>/dev/null
F="$(newdir)"; mkrepo "$F" main; git -C "$F" switch -qc feat/elsewhere   # a session cwd on a feature branch
N="$(newdir)"; mkrepo "$N" main                                            # a repo on main
U="$(newdir)"; git init -q -b main "$U"                                    # a repo with no commits
NOTREPO="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
H="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1                    # the hook's HOME for tilde rows
git -C "$M" worktree add -q -b fix/home "$H/r" 2>/dev/null

# --- resolves: the live sample and the shapes it stands for -----------------------------------------
S="$NOTREPO/scratch"; C=learning/x
LIVE="$(lines "S=$S" "W=$W" 'cd $W && git status --short | head; git branch --show-current' \
  "C=$C" 'cp $S/catalog.md $C/catalog.md && git check-ignore -q $C/sources/raw/all.tsv && echo raw-ignored' \
  'git add $C/catalog.md && git commit -q -m "docs(x): extend the catalog" && git push -q 2>&1 | tail -2; git log --oneline -1')"
want_cd "live sample: the cd target resolves to the worktree" "$W" "$(cddir "$M" "$LIVE")"
expect "live sample: W=<feature worktree>, cd \$W, push from a main cwd -> allowed" 0 "$(gate "$M" "$LIVE")"
expect "reverse: W=<repo on main>, cd \$W && git push -q from a feature cwd -> blocked" 2 \
  "$(gate "$F" "$(lines "W=$N" 'cd $W && git push -q')")" "lands on 'main'"
want_cd "cd \${W} resolves" "$W" "$(cddir "$M" "$(lines "W=$W" 'cd ${W} && git push -q')")"
want_cd "cd \"\$W\" resolves" "$W" "$(cddir "$M" "$(lines "W=$W" 'cd "$W" && git push -q')")"
want_cd "cd \"\${W}\" resolves" "$W" "$(cddir "$M" "$(lines "W=$W" 'cd "${W}" && git push -q')")"
want_cd "an assignment after a top-level ; resolves" "$W" "$(cddir "$M" "$(lines "S=$S; W=$W" 'cd $W && git push -q')")"
want_cd "pushd \$W resolves like cd" "$W" "$(cddir "$M" "$(lines "W=$W" 'pushd $W && git push -q')")"
expect "cd \$W; git push -q (a ; after the target) -> allowed" 0 "$(gate "$M" "$(lines "W=$W" 'cd $W; git push -q')")"
expect "cd \$W || exit 1 (an || after the target) -> allowed" 0 "$(gate "$M" "$(lines "W=$W" 'cd $W || exit 1' 'git push -q')")"
HOOK_HOME="$H"
want_cd "unquoted W=~/r expands to \$HOME/r" "$H/r" "$(cddir "$M" "$(lines 'W=~/r' 'cd $W && git push -q')")"
expect "unquoted W=~/r, push from a main cwd -> allowed" 0 "$(gate "$M" "$(lines 'W=~/r' 'cd $W && git push -q')")"
HOOK_HOME=""

# --- falls back: each shape keeps today's verdict, the session cwd (main) ---------------------------
# fb <name> <line>...: the cd target prints empty, and the push from M (main) is still refused. A wrong
# resolve to the feature worktree would flip the verdict to allowed.
fb() {
  local name="$1"; shift; local cmd; cmd="$(lines "$@")"
  want_cd "fallback: $name (no cd target)" "" "$(cddir "$M" "$cmd")"
  expect "fallback: $name (judged on main, blocked)" 2 "$(gate "$M" "$cmd")" "lands on 'main'"
}
fb "double-quoted value" "W=\"$W\"" 'cd $W && git push -q'
fb "single-quoted value" "W='$W'" 'cd $W && git push -q'
fb "unquoted value with a space (an env prefix to a command)" "W=$WS" 'cd $W && git push -q'
fb "double-quoted value with a space" "W=\"$WS\"" 'cd $W && git push -q'
fb "a backslash in the value" "W=${WS// /\\ }" 'cd $W && git push -q'
fb "a \$ in the value" 'W=$PWD' 'cd $W && git push -q'
fb "a relative value" 'W=.claude/worktrees/thing' 'cd $W && git push -q'
fb "a quoted tilde value" "W=\"~/r\"" 'cd $W && git push -q'
fb "two assignments" "W=$N" "W=$W" 'cd $W && git push -q'
fb "an assignment after &&" "true && W=$W" 'cd $W && git push -q'
fb "an assignment on a line after a trailing &&" 'false &&' "W=$W" 'cd $W && git push -q'
fb "export W=" "export W=$W" 'cd $W && git push -q'
fb "readonly W=" "readonly W=$W" 'cd $W && git push -q'
fb "local W=" "local W=$W" 'cd $W && git push -q'
fb "an env prefix W=<path> true" "W=$W true" 'cd $W && git push -q'
fb "a backgrounded assignment" "W=$W &" 'cd $W && git push -q'
fb "an assignment inside double quotes" 'echo "' "W=$W" '"' 'cd $W && git push -q'
fb "an assignment inside a comment" "# x; W=$W" 'cd $W && git push -q'
fb "an assignment inside \$( )" 'X=$(' "W=$W" ')' 'cd $W && git push -q'
fb "an assignment inside backticks" 'X=`' "W=$W" '`' 'cd $W && git push -q'
fb "an assignment inside a subshell" '(' "W=$W" ')' 'cd $W && git push -q'
fb "an assignment inside a brace group" '{' "W=$W" '}' 'cd $W && git push -q'
fb "an assignment inside an if body" 'if false; then' "W=$W" 'fi' 'cd $W && git push -q'
fb "an assignment inside a loop body" 'for i in; do' "W=$W" 'done' 'cd $W && git push -q'
fb "an assignment inside a function body" 'f() {' "W=$W" '}' 'cd $W && git push -q'
fb "an eval reassignment" "W=$W" "eval W=$N" 'cd $W && git push -q'
fb "an eval that builds the name" "WT=$W" 'A=W; B=T' "eval \$A\$B=$N" 'cd $WT && git push -q'
fb "a sourced file before the cd" "W=$W" '. ./set-w.sh' 'cd $W && git push -q'
fb "unset before the cd" "W=$W" 'unset W' 'cd $W && git push -q'
fb "a mid-line cd (W=..; cd \$W on one line)" "W=$W; cd \$W && git push -q"
fb "cd \$W/sub (a suffix)" "W=$W" 'cd $W/sub && git push -q'
fb "cd \${W:-x} (an operator)" "W=$W" 'cd ${W:-x} && git push -q'
fb "cd \$W 2>/dev/null (more than the target)" "W=$W" 'cd $W 2>/dev/null && git push -q'
fb "a non-repo target" "W=$NOTREPO" 'cd $W && git push -q'
fb "a repo with no commits" "W=$U" 'cd $W && git push -q'
fb "an assignment after the cd" 'cd $W && git push -q' "W=$W"
fb "a cd in a pipeline" "W=$W" 'cd $W | cat' 'git push -q'
fb "a backgrounded cd" "W=$W" 'cd $W & git push -q'
fb "a cd on a line after a trailing |" "W=$W" 'echo x |' 'cd $W && git push -q'
fb "a second cd" "W=$W" 'cd $W' "cd $M" 'git push -q'
fb "popd after the cd" "W=$W" 'cd $W' 'popd' 'git push -q'
fb "a push before the cd" "W=$W" 'git push -q' 'cd $W'
fb "git -C <other> after the cd" "W=$W" "cd \$W && git -C $M push -q"
fb "GIT_DIR=<other> after the cd" "W=$W" "cd \$W && GIT_DIR=$M/.git git push -q"
fb "IFS set in the command" 'IFS=/' "W=$W" 'cd $W && git push -q'
fb "a shell-managed name (RANDOM)" "RANDOM=$W" 'cd $RANDOM && git push -q'
fb "a shell-managed name (_)" "_=$W" 'cd $_ && git push -q'
fb "whole-word NAME: WW=<path> does not set W" "WW=$W" 'cd $W && git push -q'
fb "the value names W again" "W=$W/W" 'cd $W && git push -q'
fb "a heredoc before the cd line" "W=$W" 'cat <<EOF' 'cd $W; echo $(date)' 'EOF' 'git push -q'
fb "a cd line inside a multi-line quote" "W=$W" 'git commit -m "x' 'cd $W"' 'git push -q'
HOOK_HOME="$H"
fb "HOME reassigned before a tilde value" "HOME=$NOTREPO" 'W=~/r' 'cd $W && git push -q'
HOOK_HOME=""

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
