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

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
