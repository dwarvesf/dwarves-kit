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

A="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/r"; mkrepo "$A" yes
N="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")/r"; mkrepo "$N" no
HD="$(printf "bash <<'EOT'\ngit push origin feat/work\nEOT")"

expect_block "git push --all in an adopted repo: refused, reason from the parser" "$A" 'git push --all origin' "--all"
expect_block "git push --tags: refused" "$A" 'git push --tags' "--tags"
expect_block "a variable in the push segment: refused" "$A" 'git push origin $BR' "variable"
expect_block "two branches in one push: refused with the count reason" "$A" 'git push origin feat/work feat/other' "more than one branch"
expect_block "a heredoc fed to a shell that pushes: refused" "$A" "$HD" "heredoc"
expect_block "a push under a wrapper: refused" "$A" 'xargs git push origin feat/work' "wrapper"
expect_block "the refusal tells the operator how to push" "$A" 'git push --all' "Push one branch at a time"

expect_pass "the same --all push in a repo that never adopted the kit: passes" "$N" 'git push --all origin'
expect_pass "two branches in a non-adopted repo: passes" "$N" 'git push origin feat/work feat/other'
expect_pass "a heredoc push in a non-adopted repo: passes" "$N" "$HD"
expect_pass "a command with no push: not touched" "$A" 'git status'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
