#!/usr/bin/env bash
# test-ship-gate-default-push.sh -- ship-gate refuses a git push that lands on a default branch
# (main, master, production, or the branch the remote HEAD names), in any repo, adopted or not,
# however the destination is spelled: an explicit refspec or one git derives from the current
# branch, push.default, the upstream, or remote.<name>.push. KIT_ALLOW_DEFAULT_PUSH=1 in the
# hook's own environment is the one escape; the same words as a command prefix are not.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
# Pin git config: an operator's global push.default must not change what the fixtures mean.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
ERR="$LOGDIR/stderr"

mkrepo() { # $1=dir $2=default branch $3=adopted(yes/no)
  git init -q -b "$2" "$1"
  git -C "$1" config user.email tieubao@users.noreply.github.com; git -C "$1" config user.name "Han Ngo"
  if [ "$3" = yes ]; then mkdir -p "$1/docs/verification"; echo marker > "$1/docs/verification/README.md"; fi
  echo base > "$1/f"; git -C "$1" add -A; git -C "$1" commit -qm "chore: init"
}
# gate <cwd> <command> [env assignment...] -> echoes the hook's exit code; stderr lands in $ERR
gate() {
  local cwd="$1" cmd="$2"; shift 2
  jq -n --arg cwd "$cwd" --arg cmd "$cmd" '{cwd: $cwd, tool_input: {command: $cmd}}' \
    | env "$@" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$ERR"
  echo $?
}
expect() { # expect <name> <want> <got> [stderr substring]
  if [ "$3" = "$2" ] && { [ -z "${4:-}" ] || grep -qF -- "$4" "$ERR"; }; then ok "$1"
  else no "$1 (want exit $2${4:+ + '$4'}, got $3: $(head -c 300 "$ERR"))"; fi
}
newdir() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; printf '%s/r' "$d"; }

# Non-adopted repo, default branch main (the incident: a scratch clone with no kit marker).
R="$(newdir)"; mkrepo "$R" main no
expect "plain push on main, non-adopted repo -> blocked, names the branch" 2 "$(gate "$R" 'git push')" "lands on 'main'"
expect "refusal names the PR route" 2 "$(gate "$R" 'git push')" "gh pr create --base main"
expect "git push origin main -> blocked" 2 "$(gate "$R" 'git push origin main')"
expect "git push -u origin HEAD on main -> blocked" 2 "$(gate "$R" 'git push -u origin HEAD')"
expect "an earlier unresolvable push does not hide a later default push" 2 "$(gate "$R" 'git push origin nothere; git push')"
expect "KIT_ALLOW_DEFAULT_PUSH=1 in the hook env -> allowed" 0 "$(gate "$R" 'git push' KIT_ALLOW_DEFAULT_PUSH=1)"
expect "KIT_ALLOW_DEFAULT_PUSH=1 as a command prefix -> still blocked" 2 "$(gate "$R" 'KIT_ALLOW_DEFAULT_PUSH=1 git push')"
expect "the escape is logged" 0 "$(grep -q 'ALLOWED | default-push | main' "$LOGDIR/ship-gate.log" && echo 0 || echo 1)"
expect "cd <repo> && git push from another cwd -> blocked (resolves the target repo)" 2 \
  "$(gate "$LOGDIR" "cd $R && git push")" "lands on 'main'"
expect "gh pr create on main -> unchanged (not a git push)" 0 "$(gate "$R" 'gh pr create --fill')"
expect "git push origin @ on main -> blocked (@ is HEAD)" 2 "$(gate "$R" 'git push origin @')"
expect "git push --follow-tags on main -> blocked (option held until the default pass)" 2 "$(gate "$R" 'git push --follow-tags')" "lands on 'main'"
expect "/usr/bin/git push on main -> blocked" 2 "$(gate "$R" '/usr/bin/git push')"
expect "pushd <repo> && git push -> blocked" 2 "$(gate "$LOGDIR" "pushd $R && git push")"
expect "switch -c to a new branch, then push HEAD -> allowed" 0 "$(gate "$R" 'git switch -c feat/new && git push -u origin HEAD')"
HD="$(printf 'git commit -q -F - <<%sEOF%s && git push origin main\nfix: body\nEOF' "'" "'")"
expect "heredoc opener line: the push after it is still read -> blocked" 2 "$(gate "$R" "$HD")"

git -C "$R" switch -qc feat/thing
expect "feature branch: git push origin HEAD:main -> blocked" 2 "$(gate "$R" 'git push origin HEAD:main')"
expect "feature branch: git push origin HEAD:refs/heads/main -> blocked" 2 "$(gate "$R" 'git push origin HEAD:refs/heads/main')"
expect "feature branch: git push origin main -> blocked" 2 "$(gate "$R" 'git push origin main')"
expect "feature branch: HEAD:production -> blocked (fallback name)" 2 "$(gate "$R" 'git push origin HEAD:production')" "lands on 'production'"
expect "git push -u origin HEAD:refs/heads/feature -> allowed" 0 "$(gate "$R" 'git push -u origin HEAD:refs/heads/feature')"
expect "feature branch: plain git push -> allowed" 0 "$(gate "$R" 'git push')"
expect "feature branch: git push -u origin HEAD -> allowed" 0 "$(gate "$R" 'git push -u origin HEAD')"
expect "feature branch: git push origin feat/thing -> allowed" 0 "$(gate "$R" 'git push origin feat/thing')"
expect "feature branch: git push origin HEAD:heads/main -> blocked (git expands heads/)" 2 "$(gate "$R" 'git push origin HEAD:heads/main')"
expect "feature branch: git push --follow-tags origin main -> blocked" 2 "$(gate "$R" 'git push --follow-tags origin main')"
expect "feature branch: git push --delete origin main -> blocked" 2 "$(gate "$R" 'git push --delete origin main')"
expect "checkout main && merge && plain push -> blocked (HEAD is main by then)" 2 \
  "$(gate "$R" 'git checkout main && git merge feat/thing && git push')" "lands on 'main'"
expect "switch main && git push origin HEAD -> blocked" 2 "$(gate "$R" 'git switch main && git push origin HEAD')"

# push.default=upstream with the feature branch tracking main: a plain push lands on main.
git -C "$R" config branch.feat/thing.remote origin; git -C "$R" config branch.feat/thing.merge refs/heads/main
git -C "$R" config push.default upstream
expect "push.default=upstream, upstream main: plain git push -> blocked" 2 "$(gate "$R" 'git push')" "lands on 'main'"
git -C "$R" config --unset push.default
expect "git -c push.default=upstream push, upstream main -> blocked" 2 "$(gate "$R" 'git -c push.default=upstream push')"
git -C "$R" config push.default simple
expect "push.default=simple, upstream main: plain git push -> allowed (git pushes the same name)" 0 "$(gate "$R" 'git push')"
git -C "$R" config --unset branch.feat/thing.merge; git -C "$R" config --unset push.default

# remote.origin.push rewrites a refspec-less push.
git -C "$R" config remote.origin.push HEAD:refs/heads/main
expect "remote.origin.push HEAD:main: plain git push -> blocked" 2 "$(gate "$R" 'git push')"
git -C "$R" config --unset remote.origin.push

# The remote HEAD names a branch outside the fallback list.
D="$(newdir)"; mkrepo "$D" develop no
git -C "$D" switch -qc feat/other
git -C "$D" update-ref refs/remotes/origin/develop HEAD
git -C "$D" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
expect "remote HEAD develop: git push origin HEAD:develop -> blocked" 2 "$(gate "$D" 'git push origin HEAD:develop')" "lands on 'develop'"
git -C "$D" update-ref refs/remotes/upstream/trunk HEAD
git -C "$D" symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/trunk
expect "a second remote's HEAD: git push upstream HEAD:trunk -> blocked" 2 "$(gate "$D" 'git push upstream HEAD:trunk')" "default branch of 'upstream'"
expect "remote HEAD develop: feature push -> allowed" 0 "$(gate "$D" 'git push -u origin HEAD')"

# Adopted repo, default branch master: the old hook exited 0 here ("safety-gate's business").
A="$(newdir)"; mkrepo "$A" master yes
expect "plain push on master, adopted repo -> blocked" 2 "$(gate "$A" 'git push')" "lands on 'master'"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
