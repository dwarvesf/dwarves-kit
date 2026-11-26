#!/usr/bin/env bash
# test-ship-gate-refs-block.sh -- _refs_block in hooks/ship-gate.sh: a push the gate cannot
# account for (lib/gate/push-refs.sh says BLOCK or gives no answer, a heredoc fed to a shell hides
# a push, or several branches go at once) is refused with "pushes refs the gate cannot account
# for" in an adopted repo, and passes in a repo that never adopted the kit. Drives the hook with
# crafted stdin, the same harness as test-ship-gate-fail-closed.sh.set -uo pipefail
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

# Shapes that are not unaccounted pushes: a redirection is not a refspec, `git push` text in a quoted
# --long-option value of another command is data, and --delete of plain names sends no commit.
expect_pass "redirect after the refspec, piped to tail" "$A" 'git push -q -u origin feat/work 2>&1 | tail -2'
expect_pass "redirect to a file" "$A" 'git push -u origin feat/work >/tmp/kit-push.log 2>&1'
expect_pass "quoted --spec holding git push and a ;" "$A" 'orca orchestration worker-start --task t1 --spec "1. edit the hook; 2. git push -u origin feat/work and open a PR"'
expect_pass "quoted --spec holding git push, no separator" "$A" 'orca orchestration worker-start --spec "edit the hook, then git push the branch"'
expect_pass "a commit message that mentions a push" "$A" 'git commit -qm "wip; git push later"'
expect_pass "--delete of two plain-named branches" "$A" 'git push origin --delete feat/old1 feat/old2'
expect_pass "an empty-source delete of a plain name" "$A" 'git push origin :feat/old1'

# Negative controls: each still refuses.
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
# Push text is data only inside a commit/tag message or an allowlisted Orca prompt option; a git
# global option, a pager or external-diff hook, an unknown program, or a ( ) { } group never is.
expect_block "git -c core.pager carrying push text" "$A" 'git -c core.pager="git push origin feat/other" log' "no answer"
expect_block "git grep -O carrying push text" "$A" 'git grep -O"git push origin feat/other" x' "no answer"
expect_block "an external diff carrying push text" "$A" 'GIT_EXTERNAL_DIFF="git push origin feat/other" git diff --ext-diff' "no answer"
expect_block "push text as a commit pathspec, not the message" "$A" 'git commit -qm ok "git push origin feat/other"' "no answer"
expect_block "an unknown program's quoted --spec" "$A" 'mytool --spec "git push origin feat/other"' "wrapper ('mytool')"
expect_block "an orca --spec beside a ( ) group" "$A" 'orca worker-start --spec "git push origin feat/other" && (true)' "wrapper ('orca')"
expect_block "a push inside ( )" "$A" '( git push origin feat/other )' "cannot account for"
expect_block "a push inside { }" "$A" '{ git push origin feat/other; }' "cannot account for"
# The hook allows @@NONE only when its own quote-blanked engage view sees no unquoted push: a parser
# that wrongly answers @@NONE for a real push is still refused.
STUB="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
cp -R "$KIT/lib" "$KIT/hooks" "$STUB/"
printf '#!/usr/bin/env bash\necho @@NONE\n' > "$STUB/lib/gate/push-refs.sh"
rc="$(jq -n --arg cwd "$A" --arg cmd 'git push -u origin feat/work' '{cwd: $cwd, tool_input: {command: $cmd}}' \
  | CLAUDE_PLUGIN_ROOT="$STUB" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$STUB/hooks/ship-gate.sh" >/dev/null 2>"$ERR"; echo $?)"
if [ "$rc" = 2 ] && grep -qF "engage check sees a push" "$ERR"; then ok "a wrong @@NONE for an unquoted push is refused"
else no "a wrong @@NONE for an unquoted push should refuse (got $rc: $(head -c 300 "$ERR"))"; fi

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
expect_lane "unproven branch: a push after ;" 'git status; git push -u origin feat/work'
expect_lane "unproven branch: a push after &&" 'git status && git push -u origin feat/work'
expect_lane "unproven branch: a delete plus a real push" 'git push origin --delete feat/old1 && git push -u origin feat/work'
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
