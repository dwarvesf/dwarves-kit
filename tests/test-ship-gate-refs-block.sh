#!/usr/bin/env bash
# test-ship-gate-refs-block.sh -- _refs_block in hooks/ship-gate.sh: a push the gate cannot
# account for (lib/gate/push-refs.sh says BLOCK or gives no answer, a heredoc fed to a shell hides
# a push, or several branches go at once) is refused with "pushes refs the gate cannot account
# for" in an adopted repo, and passes in a repo that never adopted the kit. Drives the hook with
# crafted stdin, the same harness as test-ship-gate-fail-closed.sh.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
ERR="$LOGDIR/stderr"
MSG='pushes refs the gate cannot account for'

mkrepo() { # $1=dir $2=adopted(yes/no) -> repo on feat/work with one extra branch
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  if [ "$2" = yes ]; then mkdir -p "$1/docs/verification"; echo marker > "$1/docs/verification/README.md"; fi
  echo base > "$1/f"; git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" branch feat/other; git -C "$1" switch -qc feat/work
}
gate() { # $1=repo $2=command -> exit code; stderr in $ERR
  jq -n --arg cwd "$1" --arg cmd "$2" '{cwd: $cwd, tool_input: {command: $cmd}}' \
    | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$ERR"
  echo $?
}
expect_block() { # $1=label $2=repo $3=command $4=reason substring
  local rc; rc="$(gate "$2" "$3")"
  if [ "$rc" = 2 ] && grep -qF -- "$MSG" "$ERR" && grep -qF -- "$4" "$ERR"; then ok "$1"
  else no "$1 (want exit 2 + '$MSG' + '$4'; got $rc: $(head -c 300 "$ERR"))"; fi
}
expect_pass() { # $1=label $2=repo $3=command
  local rc; rc="$(gate "$2" "$3")"
  if [ "$rc" = 0 ] && ! grep -qF -- "$MSG" "$ERR"; then ok "$1"
  else no "$1 (want exit 0, no refusal; got $rc: $(head -c 300 "$ERR"))"; fi
}

A="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/r" || exit 1; mkrepo "$A" yes
N="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/r" || exit 1; mkrepo "$N" no
HD="$(printf "bash <<'EOT'\ngit push origin feat/work\nEOT")"

expect_block "git push --all in an adopted repo: refused, reason from the parser" "$A" 'git push --all origin' "--all"
expect_block "git push --tags: refused" "$A" 'git push --tags' "--tags"
expect_block "a variable in the push segment: refused" "$A" 'git push origin $BR' "variable"
expect_block "two branches in one push: refused with the count reason" "$A" 'git push origin feat/work feat/other' "more than one branch"
expect_block "a heredoc fed to a shell that pushes: refused" "$A" "$HD" "heredoc"
expect_block "a push under a wrapper: refused" "$A" 'xargs git push origin feat/work' "wrapper"
expect_block "the refusal tells the operator how to push" "$A" 'git push --all' "Push one branch at a time"

# The one-command rule: a push is answered only as the whole Bash call, with fd redirects that write
# no file and one trailing pipe into tail/head/cat/grep. A redirection is not a refspec, and --delete
# of plain names sends no commit.
expect_pass "redirect after the refspec, piped to tail" "$A" 'git push -q -u origin feat/work 2>&1 | tail -2'
expect_pass "2>&1 on the push" "$A" 'git push -u origin feat/work 2>&1'
expect_pass ">/dev/null 2>&1 on the push" "$A" 'git push -u origin feat/work >/dev/null 2>&1'
expect_pass "one pipe into grep with a literal pattern" "$A" "git push -u origin feat/work 2>&1 | grep -v 'remote:'"
expect_block "redirect to a file" "$A" 'git push -u origin feat/work >/tmp/kit-push.log 2>&1' "only command"
expect_block "a pipe into tee" "$A" 'git push -u origin feat/work 2>&1 | tee /tmp/kit-push.log' "only command"
expect_block "a pipe into sed" "$A" "git push -u origin feat/work 2>&1 | sed 's/a/b/'" "only command"
expect_block "two pipes" "$A" 'git push -u origin feat/work 2>&1 | grep x | tail -1' "only command"
expect_block "a pipe with a variable argument" "$A" 'git push -u origin feat/work 2>&1 | tail -n $N' "only command"
# Review round 5: writers outside .git and the environment, closed by the one-command rule.
expect_block "a ~/.gitconfig write, then a push" "$A" 'echo x >> ~/.gitconfig; git push -u origin feat/work' "only command"
expect_block "an XDG git config write, then a push" "$A" 'echo x >> ~/.config/git/config; git push -u origin feat/work' "only command"
expect_block "export GIT_CONFIG_GLOBAL, then a push" "$A" 'export GIT_CONFIG_GLOBAL=/tmp/kit-g; git push -u origin feat/work' "only command"
expect_block "GIT_CONFIG_GLOBAL= prefix on the push" "$A" 'GIT_CONFIG_GLOBAL=/tmp/kit-g git push -u origin feat/work' "only command"
expect_block "cd, then a push" "$A" 'cd . && git push -u origin feat/work' "only command"
expect_block "a push in a subshell" "$A" '(git push -u origin feat/work)' "cannot account for"
expect_pass "--delete of two plain-named branches" "$A" 'git push origin --delete feat/old1 feat/old2'
expect_pass "an empty-source delete of a plain name" "$A" 'git push origin :feat/old1'

# Negative controls: each still refuses. `git push` text outside a push segment is never data: in a
# quoted --spec, a commit message, an echo, a git option or an env value, it refuses (long text goes
# through a file instead).
expect_block "quoted --spec holding git push and a ;" "$A" 'orca orchestration worker-start --task t1 --spec "1. edit the hook; 2. git push -u origin feat/work and open a PR"' "wrapper ('orca')"
expect_block "quoted --spec holding git push, no separator" "$A" 'orca orchestration worker-start --spec "edit the hook, then git push the branch"' "wrapper ('orca')"
expect_block "a commit message that mentions a push" "$A" 'git commit -qm "wip; git push later"' "no answer"
# The second security review's bypasses (each moved a bare origin's master when the gate passed).
expect_block "review F1: a delete, then push text piped into bash" "$A" "git push origin --delete feat/old1; echo 'git push origin feat/other:master' | bash" "only command"
expect_block "review F1c: a delete, then push text run as a script on PATH" "$A" "git push origin --delete feat/old1; echo 'git push origin feat/other:master' > p; chmod +x p; PATH=.:/usr/bin:/bin p" "only command"
expect_block "review F2: an alias written by printf, then run" "$A" "printf '[alias]\\n\\tx = !git push origin feat/other:master\\n' >> .git/config; git x" "no answer"
expect_block "review F2b: a post-commit hook written by echo" "$A" "echo 'git push origin feat/other:master' > .git/hooks/post-commit; chmod +x .git/hooks/post-commit; git commit -q --allow-empty -m 'chore: y'" "no answer"
expect_block "review F3: GIT_EDITOR carries the push" "$A" "GIT_EDITOR='git push origin feat/other:master;:' git commit -q --allow-empty -e -m 'chore: then git push'" "no answer"
expect_block "review F3b: git options in a variable" "$A" "X='-c a.b=git push origin feat/other:master'; git \$X" "no answer"
expect_block "a real push beside push text piped into bash" "$A" "git push -u origin feat/work; echo 'git push origin feat/other:master' | bash" "only command"
expect_block "a real push beside push text a ; exposed" "$A" 'git commit -qm "wip; git push origin feat/other:master" && git push -u origin feat/work' "only command"
expect_block "a real push beside a log format naming a push" "$A" 'git log -1 --format="%s about git push" && git push -u origin feat/work' "only command"
# A git step that can run a string refuses the push beside it, push text or not.
expect_block "commit -c core.editor carrying push text, then a real push" "$A" "git commit -c core.editor='git push origin feat/other:master' --amend; git push -u origin feat/work" "only command"
expect_block "git -c core.editor carrying push text, then a real push" "$A" "git -c core.editor='git push origin feat/other:master' commit --amend; git push -u origin feat/work" "only command"
expect_block "an editor env prefix, then a real push" "$A" 'GIT_EDITOR=vim git commit --amend && git push -u origin feat/work' "only command"
expect_block "rebase --exec, then a real push" "$A" "git rebase -x 'make' master && git push -u origin feat/work" "only command"
expect_block "an unknown git subcommand (an alias), then a real push" "$A" 'git sync && git push -u origin feat/work' "only command"
expect_block "commit -e, then a real push" "$A" 'git commit -e -m x && git push -u origin feat/work' "only command"
expect_block "add, commit, then a real push" "$A" 'git add -A && git commit -qm "fix: x" && git push -u origin feat/work' "only command"
# A push option that names a program runs it (locally via sh for a path or file:// remote).
expect_block "--receive-pack= on a delete" "$A" "git push origin --delete feat/old1 --receive-pack='git push origin feat/other:master; git-receive-pack'" "runs a command"
expect_block "--exec= on a delete" "$A" "git push origin --delete feat/old1 --exec='git push origin feat/other:master; git-receive-pack'" "runs a command"
expect_block "--receive-pack space form on an empty-source delete" "$A" "git push --receive-pack 'git push origin feat/other:master; git-receive-pack' origin :feat/old1" "runs a command"
expect_block "--receive-pack= on a real push" "$A" "git push --receive-pack='git push origin feat/other:master; git-receive-pack' origin feat/work" "runs a command"
expect_block "--repo replaces the remote" "$A" "git push --repo='ext::sh -c true' feat/work" "replaces the remote"
expect_block "an ext:: transport-helper remote" "$A" "git push 'ext::sh -c true' feat/work" "transport helper"
expect_block "--recurse-submodules=on-demand" "$A" 'git push --recurse-submodules=on-demand origin feat/work' "submodule refs"
expect_block "git --exec-path before push" "$A" 'git --exec-path=/tmp/kit-x push origin feat/work' "the gate cannot read"
expect_block "git -c core.sshCommand on the push" "$A" "git -c core.sshCommand='sh -c true' push origin feat/work" "the gate cannot read"
# Review round 4: a step that changes what a later push does (a config write, a remote edit, a write
# into .git) refuses any push beside it, and a delete must be the only step in the command.
expect_block "review H2: config receivepack, then a delete" "$A" "git config remote.origin.receivepack 'git pu\"\"sh --receive-pack=git-receive-pack origin feat/other:master; git-receive-pack'; git push origin --delete feat/old1" "only command"
expect_block "review H2, ref form: config receivepack, then a real push" "$A" "git config remote.origin.receivepack 'git pu\"\"sh --receive-pack=git-receive-pack origin feat/other:master; git-receive-pack'; git push -u origin feat/work" "only command"
expect_block "remote set-url, then a real push" "$A" 'git remote set-url --push origin /tmp/kit-elsewhere.git; git push -u origin feat/work' "only command"
expect_block "a write into .git, then a real push" "$A" 'echo x >> .git/config; git push -u origin feat/work' "only command"
expect_block "a delete beside a harmless step" "$A" 'git push origin --delete feat/old1 && git status' "only command"
expect_block "a config read, then a real push" "$A" 'git config user.name && git push -u origin feat/work' "only command"
expect_pass "a push to a URL ending in .git" "$A" 'git push -u https://example.invalid/r.git feat/work'
# Review round 5 cases (verbatim): each needs a second step, so the one-command rule refuses it.
expect_block "review S1: GIT_CONFIG_* env sets receivepack, then a push" "$A" $'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.receivepack GIT_CONFIG_VALUE_0=\'git pu""sh --receive-pack=git-receive-pack origin feat/other:master; git-receive-pack\'; git push origin feat/work' "only command"
expect_block "review S1b: GIT_CONFIG_* env sets a push refspec, then a push" "$A" $'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.push GIT_CONFIG_VALUE_0=refs/heads/feat/other:refs/heads/master; git push origin feat/other' "only command"
expect_block "review S2: HOME moved and ~/.gitconfig written, then a push" "$A" $'unset GIT_CONFIG_GLOBAL; export HOME=..; printf \'[remote "origin"]\\n\\tpush = refs/heads/feat/other:refs/heads/master\\n\' > ~/.gitconfig; git push origin feat/other' "only command"
expect_block "review S2b: XDG_CONFIG_HOME moved and its git config written, then a push" "$A" $'unset GIT_CONFIG_GLOBAL; export HOME=../nohome XDG_CONFIG_HOME=../x; mkdir -p ../x/git; printf \'[remote "origin"]\\n\\tpush = refs/heads/feat/other:refs/heads/master\\n\' > ../x/git/config; git push origin feat/other' "only command"
expect_block "review S3: a pre-push hook written into .git, then a push" "$A" $'printf \'#!/bin/sh\\n[ -n "$Z" ] || Z=1 git pu""sh origin feat/other:master\\nexit 0\\n\' > .gi""t/hooks/pre-push; chmod +x .gi""t/hooks/pre-push; git push origin feat/work' "only command"
expect_block "review S4: a symlink to .git and its config written, then a push" "$A" $'ln -s .g""it ../gd; printf \'[remote "origin"]\\n\\tpush = refs/heads/feat/other:refs/heads/master\\n\' >> ../gd/config; git push origin feat/other' "only command"
expect_block "review S5: export GIT_DIR, then a push" "$A" $'export GIT_DIR=../o.git; git push origin feat/other' "only command"
expect_block "a delete beside a script run" "$A" 'git push origin --delete feat/old1 && bash ./cleanup.sh' "only command"
expect_block "a delete with a VAR=value prefix" "$A" 'GIT_SSH_COMMAND=x git push origin --delete feat/old1' "only command"
expect_block "a delete beside an unquoted \$ word in git" "$A" 'git push origin --delete feat/old1; git log $X' "only command"
expect_block "a for-loop delete: the variable stays unresolved" "$A" "$(printf 'for b in feat/old1 feat/old2; do\n  git push origin --delete "$b"\ndone')" "variable"
expect_block "--delete of a glob" "$A" "git push origin --delete 'feat/*'" "not a plain branch name"
expect_block "--delete of HEAD" "$A" 'git push origin --delete HEAD' "not a plain branch name"
expect_block "bash -c runs the quoted push" "$A" 'bash -c "git push origin feat/other"' "wrapper ('bash')"
expect_block "bash -c with a ; inside the quote" "$A" 'bash -c "cd /tmp; git push origin feat/other"' "wrapper ('bash')"
expect_block "a quoted push positional to an unknown tool" "$A" 'mytool "git push origin feat/other"' "wrapper ('mytool')"
expect_block "a quoted push as an --exec value" "$A" 'mytool --exec "git push origin feat/other"' "wrapper ('mytool')"
expect_block "a quoted --spec in a command that pipes into sh" "$A" 'orca worker-start --spec "git push origin feat/other" | sh' "wrapper ('orca')"
expect_block "echo piped into bash" "$A" 'echo "git push origin feat/other" | bash' "no answer"
expect_block "git rebase --exec runs a push" "$A" 'git rebase --exec "git push origin feat/other" master' "no answer"
# Push text in a git option, a pager or external-diff hook, an unknown program, or a ( ) { } group.
expect_block "git -c core.pager carrying push text" "$A" 'git -c core.pager="git push origin feat/other" log' "no answer"
expect_block "git grep -O carrying push text" "$A" 'git grep -O"git push origin feat/other" x' "no answer"
expect_block "an external diff carrying push text" "$A" 'GIT_EXTERNAL_DIFF="git push origin feat/other" git diff --ext-diff' "no answer"
expect_block "push text as a commit pathspec, not the message" "$A" 'git commit -qm ok "git push origin feat/other"' "no answer"
expect_block "an unknown program's quoted --spec" "$A" 'mytool --spec "git push origin feat/other"' "wrapper ('mytool')"
expect_block "an orca --spec beside a ( ) group" "$A" 'orca worker-start --spec "git push origin feat/other" && (true)' "wrapper ('orca')"
expect_block "a push inside ( )" "$A" '( git push origin feat/other )' "cannot account for"
expect_block "a push inside { }" "$A" '{ git push origin feat/other; }' "cannot account for"
# An answer that names no branch and no delete (a marker the hook does not know) is refused.
STUB="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
cp -R "$KIT/lib" "$KIT/hooks" "$STUB/"
printf '#!/usr/bin/env bash\necho @@NONE\n' > "$STUB/lib/gate/push-refs.sh"
rc="$(jq -n --arg cwd "$A" --arg cmd 'git push -u origin feat/work' '{cwd: $cwd, tool_input: {command: $cmd}}' \
  | CLAUDE_PLUGIN_ROOT="$STUB" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$STUB/hooks/ship-gate.sh" >/dev/null 2>"$ERR"; echo $?)"
if [ "$rc" = 2 ] && grep -qF "parser named no branch" "$ERR"; then ok "an unknown parser answer for a real push is refused"
else no "an unknown parser answer for a real push should refuse (got $rc: $(head -c 300 "$ERR"))"; fi

U="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/r" || exit 1; mkrepo "$U" yes
mkdir -p "$U/docs/specs"; printf '# Spec: x\nStatus: DRAFT\nLane: full\n' > "$U/docs/specs/SPEC-001-work.md"
git -C "$U" add -A; git -C "$U" commit -qm spec
expect_lane() { # $1=label $2=command: refused by the lane gates, not waved through
  local rc; rc="$(gate "$U" "$2")"
  if [ "$rc" = 2 ] && grep -qF -- "requires gates that have not run" "$ERR"; then ok "$1"
  else no "$1 (want exit 2 + lane refusal; got $rc: $(head -c 300 "$ERR"))"; fi
}
expect_lane "unproven branch: a plain push" 'git push -u origin feat/work'
expect_lane "unproven branch: the redirect form" 'git push -q -u origin feat/work 2>&1 | tail -2'
expect_block "unproven branch: a push after ;" "$U" 'git status; git push -u origin feat/work' "only command"
expect_block "unproven branch: a push after &&" "$U" 'git status && git push -u origin feat/work' "only command"
expect_block "unproven branch: a delete plus a real push" "$U" 'git push origin --delete feat/old1 && git push -u origin feat/work' "only command"
rc="$(gate "$N" 'git push &>/dev/null origin master')"
if [ "$rc" = 2 ] && grep -qF "lands on 'master'" "$ERR"; then ok "&> before the refspec no longer hides a default push"
else no "&> before the refspec should refuse the default push (got $rc: $(head -c 300 "$ERR"))"; fi
rc="$(gate "$N" 'bash -c "git push origin master"')"
if [ "$rc" = 2 ] && grep -qF "lands on 'master'" "$ERR"; then ok "a default push wrapped in bash -c is refused in any repo"
else no "a default push wrapped in bash -c should refuse in any repo (got $rc: $(head -c 300 "$ERR"))"; fi
rc="$(gate "$N" 'bash -c "cd /tmp; git push origin master"')"
if [ "$rc" = 2 ] && grep -qF "lands on 'master'" "$ERR"; then ok "a wrapped default push after a quoted ; is refused in any repo"
else no "a wrapped default push after a quoted ; should refuse in any repo (got $rc: $(head -c 300 "$ERR"))"; fi
rc="$(gate "$N" 'git push origin --delete feat/old1 master')"
if [ "$rc" = 2 ] && grep -qF "lands on 'master'" "$ERR"; then ok "--delete naming the default branch is a default push"
else no "--delete naming the default branch should refuse (got $rc: $(head -c 300 "$ERR"))"; fi

expect_pass "the same --all push in a repo that never adopted the kit: passes" "$N" 'git push --all origin'
expect_pass "two branches in a non-adopted repo: passes" "$N" 'git push origin feat/work feat/other'
expect_pass "a heredoc push in a non-adopted repo: passes" "$N" "$HD"
expect_pass "a command with no push: not touched" "$A" 'git status'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
