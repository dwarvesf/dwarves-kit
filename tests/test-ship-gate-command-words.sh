#!/usr/bin/env bash
# test-ship-gate-command-words.sh -- ship-gate engages on the COMMAND words of a ship step, not on
# prose. `gh pr create` and its alias `gh pr new` engage; the same words inside the quoted text of
# an inert command (echo, printf, a git commit message) do not. Any quoting the gate cannot read
# with certainty engages. Observable: the fixture repo is adopted and its spec has no Lane header,
# so an engaged gate exits 2 and a gate that stays out of the way exits 0.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1

R="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/r" || exit 1
git init -q -b master "$R"
git -C "$R" config user.email t@t.example; git -C "$R" config user.name t
mkdir -p "$R/docs/specs" "$R/docs/verification"; echo marker > "$R/docs/verification/README.md"
git -C "$R" add -A; git -C "$R" commit -qm init
git -C "$R" switch -qc feat/cmdwords
printf '# Spec: x\nStatus: DRAFT\n' > "$R/docs/specs/SPEC-001-cmdwords.md"
git -C "$R" add -A; git -C "$R" commit -qm spec

gate() { # <cwd> <command> -> echoes the hook's exit code
  jq -n --arg cwd "$1" --arg cmd "$2" '{cwd: $cwd, tool_input: {command: $cmd}}' \
    | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1
  echo $?
}
engages() { [ "$(gate "$R" "$2")" = 2 ] && ok "$1 -> engaged" || no "$1 -> should engage (exit 2)"; }
inert()   { [ "$(gate "$R" "$2")" = 0 ] && ok "$1 -> not engaged" || no "$1 -> should not engage (exit 0)"; }

# Real ship steps still engage.
engages "gh pr create"                      'gh pr create --fill'
engages "gh pr new (alias)"                 'gh pr new --fill'
engages "cd x && gh pr create"              "cd $R && gh pr create --fill"
engages "git -C dir push"                   "git -C $R push -u origin HEAD"
engages "env-prefixed gh pr create"         'GH_TOKEN=x gh pr create --fill'
engages "env-prefixed gh pr new"            'FOO=1 gh pr new --fill'
engages "git commit -m then gh pr new"      'git commit -qm "x" && gh pr new --fill'
engages "printf then a real gh pr create"   'printf "done\n" && gh pr create --fill'
engages "quoted title on a real command"    'gh pr create --title "gh pr create"'
engages "after an echo with a ;"            "echo 'a' ; gh pr create"
engages "after an echo with ||"             "echo 'a' || gh pr new"
engages "after an echo with a single &"     "echo 'a' & gh pr create"
engages "after a harmless pipe"             "printf 'x' | cat; gh pr create"
engages "after a redirect"                  "echo 'a' > f && gh pr create"
engages "apostrophe inside double quotes"   "echo \"it's\" && gh pr create && echo \"ok\""
engages "escaped quote inside double quotes" 'echo "a\" b" ; gh pr create'
engages "joined single-quote escape"        "echo 'x'\\''y' ; gh pr create"
engages "inside a then branch"              "printf 'x'; if true; then gh pr new; fi"
engages "after a git commit"                "git commit -qm 'x' ; gh pr create"

# Prose inside an inert command's quotes does not.
inert "printf single-quoted"                "printf 'next run gh pr create now\n'"
inert "echo double-quoted"                  'echo "then gh pr create"'
inert "echo mentions the alias"             "echo 'use gh pr new'"
inert "git commit message"                  'git commit -qm "docs: mention gh pr create"'
inert "multi-line commit message"           'git commit -qm "docs: x
second line: gh pr new
third"'
inert "echo then an unrelated command"      "echo 'gh pr create' && git status"

# Anything that could still run the quoted text, or that the gate cannot read, engages.
engages "substitution before the quote"     "echo \$(sh -c 'gh pr create')"
engages "backtick before the quote"         "echo \`sh -c 'gh pr new'\`"
engages "process substitution"              "echo x > >(bash -c \"gh pr create\")"
engages "written to a file, then run"       "echo 'gh pr create' > /tmp/s.sh; sh /tmp/s.sh"
engages "printf -v, then run the variable"  "printf -v c 'gh pr create'; \$c"
engages "piped into env sh"                 "printf 'gh pr create' | env sh"
engages "piped into a read loop"            "echo 'gh pr create' | while read c; do \$c; done"
engages "redirect hides nothing after it"   "echo 'x' 2>&1 ; sh -c 'gh pr new'"
engages "echo piped into a shell"           "echo 'gh pr create' | bash"
engages "printf piped into xargs"           "printf 'gh pr new' | xargs sh -c"
engages "command substitution in echo"      'echo "$(gh pr create)"'
engages "backtick substitution in echo"     'echo "`gh pr new`"'
engages "bash -c"                           "bash -c 'gh pr create'"
engages "eval"                              'eval "gh pr new"'
engages "unbalanced quote"                  "echo 'gh pr create"
engages "ANSI-C quote then a real command"  "echo \$'it\\'s' ; gh pr create ; echo 'x'"
engages "escaped quote then a real command" "echo \\' ; gh pr create ; echo '"
engages "comment apostrophe hides nothing" "echo hi # it's
gh pr create
echo 'x'"
engages "nested double quotes"             'echo "$(echo "gh pr create")"'

# gh global flags may sit between gh and pr.
engages "gh -R owner/repo pr create"        'gh -R owner/repo pr create --fill'
engages "gh --repo x pr create"             'gh --repo owner/repo pr create --fill'
engages "gh --repo=x pr new"                'gh --repo=owner/repo pr new --fill'
engages "env-prefixed gh -R pr create"      'GH_TOKEN=x gh -R a/b pr create --fill'
engages "cd x && gh -R pr create"           "cd $R && gh -R a/b pr create --fill"
engages "command gh -R pr new"              'command gh -R a/b pr new --fill'
engages "two global flags before pr"        'gh --repo a/b --hostname h.example pr create'
engages "quoted gh command word"            '"gh" -R a/b pr create'
inert "gh -R phrase in echo"                "echo 'then gh -R a/b pr create'"
inert "gh -R phrase in commit message"      'git commit -qm "docs: gh --repo a/b pr create"'
inert "gh pr list is not a ship step"       'gh -R a/b pr list'

# A `<<X` inside quotes opens no heredoc: the lines after it still run.
engages "single-quoted <<X hides gh"        "echo '<<X'
gh pr create --fill
X"
engages "double-quoted <<X hides gh"        'echo "<<X"
gh pr create --fill
X'
engages "single-quoted <<X hides push"      "echo '<<X'
git -C $R push -u origin HEAD
X"
engages "printf of a quoted <<X"            "printf '%s' '<<X'
gh pr new --fill
X"
engages "quoted <<-X"                       "echo '<<-X'
gh pr create
X"
engages "double-quoted marker in single quotes"  "echo '<<\"X\"'
gh pr create
X"
engages "multi-line quote holds <<X"        "echo 'a
<<X
b'
gh pr create
X"
engages "<<X after a closed substitution"   'echo "$(echo hi) <<X"
gh pr create
X'
engages "comment apostrophe, quoted <<X"    "echo hi # it's
echo '<<X'
gh pr create
X"
engages "ANSI-C quote, quoted <<X"          "echo \$'it\\'s' '<<X'
gh pr create
X"
engages "here-string is no heredoc"         'cat <<<x
gh pr create
x'
engages "arithmetic shift is no heredoc"    'echo $((1<<X))
gh pr create
X'
engages "backslash-quoted marker"           'cat <<\X
gh pr create
X'
engages "quoted <<X in a substitution"      'echo "$(echo "<<X")"
gh pr create
X'

engages "heredoc opener line ends in a quote" "cat <<X 'a
b'
gh pr create
X"
engages "case inside a substitution"        'echo "$(case a in a) echo hi;; esac) <<X"
gh pr create
X'
engages "backtick holds a nested quote"     'echo "`echo "<<X"`"
gh pr create
X'
engages "doubt outlasts the line that set it" "echo \$'a\\'b'
echo '<<B'
gh pr create
B"
engages "variable marker"                   'cat <<$M
gh pr create
$M'
engages "escaped < before <X"               'echo \<<X
gh pr create
X'
engages "dollar-brace holding a quote"      'echo "${x:-"<<X"}"
gh pr create
X'

engages "single-quoted marker in double quotes" 'echo "<<'"'X'"'"
gh pr create
X'
engages "indented terminator ends nothing"  "cat <<X
  X
<<Y
X
gh pr create
Y"
engages "dash heredoc ends on tabs only"    "cat <<-X
	X
gh pr create
X"
engages "two heredocs on one line"          "cat <<A <<B
a
A
<<C
B
gh pr create
C"
engages "opener inside an open substitution" 'cat <<X "$(echo
gh pr create)"
body
X'
engages "dollar-brace outside quotes"       'echo ${x:-<<X }
gh pr create
X'
engages "dollar-bracket arithmetic"         'echo $[1<<X ]
gh pr create
X'
engages "comment after a subshell"          '(true)#<<X
gh pr create
X'
engages "unquoted heredoc runs a substitution" 'cat <<EOF
$(gh pr create --fill)
EOF'
engages "unquoted heredoc runs a backtick"  'cat <<EOF
`gh pr new`
EOF'
engages "quoted body ending in a backslash" "cat <<'EOF'
path C:\\
EOF
gh pr create"
engages "terminator closes a substitution"  'x=$(cat <<EOF
hi
EOF)
gh pr create'
engages "quoted pr word"                    'gh "pr" create --fill'
engages "quoted create word"                'gh pr "create" --fill'

# Real heredocs are still stripped, and a ship step after one still engages.
inert "heredoc body prose"                  "cat <<'EOF'
next run gh pr create now
git push origin main
EOF"
inert "commit message heredoc"              "git commit -qF - <<EOF
docs: mention gh pr create and git push
EOF"
inert "commit message in a substitution"    'git commit -m "$(cat <<'"'EOF'"'
mention gh pr create and git push
EOF
)"'
inert "quoted <<X, nothing else"            "echo '<<X'
X"
inert "quoted <<X, quoted prose after it"   "echo '<<X'
echo 'gh pr create'
X"
engages "ship step after a heredoc"         "cat <<EOF > /dev/null
body
EOF
gh pr create --fill"
engages "ship step on the opener line"      "git commit -F - <<EOF && gh pr create --fill
body
EOF"

# `git stash push` saves a stash; it pushes nothing, so it does not engage. A real push beside it does.
inert "git stash push"                      'git stash push -u -m "msg" -- a b'
inert "git -C dir stash push"               "git -C $R stash push -m x"
inert "global options before stash push"    "git -C $R -c core.quotepath=false --no-pager stash push -- a"
inert "cd, stash push, then status"         "cd $R && git stash push -u -m \"msg\" -- p1 p2 && git status --short planning/"
engages "stash push, then a real push"      'git stash push && git push origin HEAD:main'
engages "push after a plain git stash"      'git stash && git push -u origin HEAD'
engages "git -C stash push (dir 'stash')"   'git -C stash push -u origin HEAD'
engages "--git-dir space form, then push"   'git --git-dir stash push -u origin HEAD'
engages "stash push words inside a quote"   'git -C "a stash push " push -u origin HEAD'
git -C "$R" branch stash
printf '# Spec: x\nStatus: DRAFT\n' > "$R/docs/specs/SPEC-002-stash.md"
engages "push a branch named stash"         'git push origin stash'

# A quoted or escaped separator does not end the git command; push may end a substitution or a command.
engages "quoted ; in the -C dir"            'git -C "a;b" push -u origin HEAD'
engages "quoted & in the -C dir"            'git -C "a&b" push -u origin HEAD'
engages "single-quoted | in the -C dir"     "git -C 'a|b' push -u origin HEAD"
engages "escaped ; in the -C dir"           'git -C a\;b push -u origin HEAD'
engages "quoted ; inside a substitution"    'x="$(git -C "a;b" push origin HEAD)"'
engages "quoted ; inside backticks"         'echo `git -C "a;b" push`'
engages "push inside backticks"             'echo `git push`'
engages "push ends a substitution"          'x=$(git push)'
engages "push args inside a substitution"   'x=$(git push origin HEAD)'
engages "push then ;"                       'git push;echo hi'
engages "push then &&"                      'git push&&echo hi'
engages "push then |"                       'git push|cat'
engages "\${IFS} as the separator"          'x=$(git${IFS}push${IFS}origin${IFS}HEAD)'
engages "bare \${IFS} separator"            'git${IFS}push${IFS}origin${IFS}HEAD'
engages "\${IFS:0:1} separator"             'git${IFS:0:1}push origin HEAD'
engages "\$IFS separator"                   'git$IFS push origin HEAD'
inert "prose about pushing"                 'echo "remember to push"'
inert "git status"                          'git status'
inert "stash push, quoted ; in the message" 'git stash push -m "a;b"'
inert "stash push inside backticks"         'echo `git stash push`'
inert "stash push ends a substitution"      'x=$(git stash push)'
inert "stash push with \${IFS}"             'git${IFS}stash${IFS}push'
engages "-C value is a stash push subst"     'git -C $(git stash push) push origin HEAD'
engages "-C value is a stash push backtick"  'git -C `git stash push` push origin HEAD'
engages "--git-dir= value is a stash subst"  'git --git-dir=$(git stash push) push origin HEAD'
inert "quoted ; then push in a commit msg"  'git commit -qm "a; then push it"'

# Homebrew bash 5 on macOS 27 segfaults in a forked child at random, which flips the engage verdict
# (a dead sed fails a capture and the gate falls back to the unblanked command). The hook silences
# os_log for its process tree. A shim sed on PATH records the environment its child sees.
SPY="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
REAL_SED="$(command -v sed)"
printf '#!/bin/bash\necho "${OS_ACTIVITY_MODE:-unset}" >> "%s/seen"\nexec "%s" "$@"\n' "$SPY" "$REAL_SED" > "$SPY/sed"
chmod +x "$SPY/sed"
: > "$SPY/seen"
jq -n --arg cwd "$R" --arg cmd 'git status' '{cwd: $cwd, tool_input: {command: $cmd}}' \
  | env -u OS_ACTIVITY_MODE PATH="$SPY:$PATH" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1
if [ -s "$SPY/seen" ] && ! grep -qv '^disable$' "$SPY/seen"; then ok "hook children run with os_log silenced"
else no "hook children should see OS_ACTIVITY_MODE=disable (saw: $(sort -u "$SPY/seen" | tr '\n' ' '))"; fi

# A forked child that dies must not let a push through. Shims on PATH stand in for the crash: each
# exits 139 with no output when it is the tool that builds one view of the command, and runs the real
# tool otherwise. The hook has to engage anyway: a dead view can only add engagement.
DEAD="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
for tool in sed awk grep; do
  real="$(command -v $tool)"
  case "$tool" in
    sed)  pat='*IFS*|*git-stash-push*' ;;   # the ${IFS} view and the stash-push view
    awk)  pat='*"function inert"*' ;;       # the gh view (inert-quote blanking)
    grep) pat='*"(bash|sh|zsh)"*|*"^@@REF "*' ;;   # the heredoc-to-shell check and the @@REF scan
  esac
  printf '#!/bin/bash\ncase "$*" in %s) exit 139 ;; esac\nexec "%s" "$@"\n' "$pat" "$real" > "$DEAD/$tool"
  chmod +x "$DEAD/$tool"
done
gate_dead() { # <cwd> <command> -> the hook's exit code with the dying tools first on PATH
  jq -n --arg cwd "$1" --arg cmd "$2" '{cwd: $cwd, tool_input: {command: $cmd}}' \
    | PATH="$DEAD:$PATH" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1
  echo $?
}
dead_engages() { [ "$(gate_dead "$R" "$2")" = 2 ] && ok "dead capture: $1 -> engaged" || no "dead capture: $1 -> should engage (exit 2)"; }
dead_engages "\${IFS} push (ifs view)"          'git${IFS}push${IFS}origin${IFS}HEAD'
dead_engages "quoted ; in the -C dir (views)"   'git -C "a;b" push -u origin HEAD'
dead_engages "quoted ; inside backticks"        'echo `git -C "a;b" push`'
dead_engages "\${IFS[*]} push (ifs view, glob form)"  'git${IFS[*]}push${IFS[*]}origin${IFS[*]}HEAD'
dead_engages "\${IFS[0]} push (ifs view, index form)" 'git${IFS[0]}push${IFS[0]}origin${IFS[0]}HEAD'
dead_engages "heredoc to bash holding a push (shell check)" "$(printf "bash <<'EOF'\ngit push origin HEAD\nEOF")"
# A single-branch push names its branch through an @@REF line. With that scan dead the gate must still
# judge the PUSHED branch (spec 'lane', no Lane header), not the checked-out one (chore/idle).
L="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/l" || exit 1
git init -q -b master "$L"; git -C "$L" config user.email t@t.example; git -C "$L" config user.name t
mkdir -p "$L/docs/specs" "$L/docs/verification"; echo marker > "$L/docs/verification/README.md"
git -C "$L" add -A; git -C "$L" commit -qm init
git -C "$L" switch -qc feat/lane
printf '# Spec: x\nStatus: DRAFT\n' > "$L/docs/specs/SPEC-001-lane.md"; git -C "$L" add -A; git -C "$L" commit -qm spec
git -C "$L" switch -qc chore/idle
[ "$(gate "$L" 'git push origin feat/lane')" = 2 ] && ok "pushed branch other than the checked-out one is judged" || no "setup: pushing feat/lane should be refused (exit 2)"
[ "$(gate_dead "$L" 'git push origin feat/lane')" = 2 ] && ok "dead capture: single-branch push (@@REF scan) -> engaged" || no "dead capture: single-branch push (@@REF scan) -> should engage (exit 2)"
dead_engages "gh pr create (gh view)"           'gh pr create --fill'
dead_engages "gh pr new after cd (gh view)"     "cd $R && gh pr new --fill"
M="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/m" || exit 1
git init -q -b main "$M"; git -C "$M" config user.email t@t.example; git -C "$M" config user.name t
echo base > "$M/f"; git -C "$M" add -A; git -C "$M" commit -qm init
[ "$(gate_dead "$M" 'git push origin main')" = 2 ] && ok "dead capture: push to main still refused" || no "dead capture: push to main should still be refused (exit 2)"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
