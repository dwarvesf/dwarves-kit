#!/usr/bin/env bash
# test-agent-guard.sh - feed canned hook JSON to agent-guard.sh and check the
# exit code (2 blocks, 0 allows) and the two-line message of every block. Temp
# git repos stand in for "on the default branch" and "on a feature branch". No
# network. jq builds the JSON here, so the test is skipped when jq is missing.
# Leaves its temp dir behind; the path is printed.
set -euo pipefail
cd "$(dirname "$0")/.."
GUARD="$PWD/scripts/agent-guard.sh"
DEFB="{{DEFAULT_BRANCH}}"
if ! command -v jq >/dev/null 2>&1; then
    echo "test-agent-guard: jq is needed to build the test JSON, skipping"
    exit 0
fi
BASH_BIN="$(command -v bash)"
T="$(mktemp -d "${TMPDIR:-/tmp}/agent-guard-test.XXXXXX")"
echo "test dir: $T"

mkrepo() { # mkrepo <dir> <branch to stand on>
    mkdir -p "$1"
    git -C "$1" init -q --template=
    git -C "$1" symbolic-ref HEAD "refs/heads/$DEFB"
    git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
    git -C "$1" branch feat/x
    if [ "$2" != "$DEFB" ]; then git -C "$1" symbolic-ref HEAD "refs/heads/$2"; fi
}
mkrepo "$T/on-default" "$DEFB"
mkrepo "$T/on-feat" feat/x
mkdir -p "$T/not-a-repo"
DEF="$T/on-default"
FEAT="$T/on-feat"
NOREPO="$T/not-a-repo"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }

# run_raw <json>: sets rc and writes stderr to $T/err
run_raw() {
    rc=0
    printf '%s' "$1" | "$BASH_BIN" "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
}

hook_json() { # hook_json <cwd> <command>
    jq -n --arg c "$2" --arg d "$1" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'
}

# two_lines: the last run printed exactly the rule line and the Fix line.
two_lines() {
    [ "$(wc -l <"$T/err" | tr -d ' ')" = "2" ] &&
        [ "$(sed -n 1p "$T/err" | cut -c1-13)" = "agent-guard: " ] &&
        [ "$(sed -n 2p "$T/err" | cut -c1-5)" = "Fix: " ]
}

# case_run <label> <block|allow> <cwd> <command> [stderr must contain]
case_run() {
    local label="$1" want="$2" cwd="$3" command="$4" needle="${5:-}"
    run_raw "$(hook_json "$cwd" "$command")"
    if [ "$want" = block ]; then
        if [ "$rc" -eq 2 ]; then ok "$label: blocked (exit 2)"; else bad "$label: expected exit 2, got $rc"; fi
        if two_lines; then ok "$label: two lines, rule then Fix"; else bad "$label: stderr is not rule + Fix"; fi
        if [ -n "$needle" ]; then
            if grep -Fq -- "$needle" "$T/err"; then ok "$label: message names the fix"; else bad "$label: message lacks '$needle'"; fi
        fi
    else
        if [ "$rc" -eq 0 ]; then ok "$label: allowed (exit 0)"; else bad "$label: expected exit 0, got $rc"; fi
        if [ ! -s "$T/err" ]; then ok "$label: silent"; else bad "$label: printed to stderr"; fi
    fi
}

# case_fix <label> <cwd> <command> <the exact Fix line>
case_fix() {
    run_raw "$(hook_json "$2" "$3")"
    if [ "$rc" -eq 2 ] && two_lines && [ "$(sed -n 2p "$T/err")" = "$4" ]; then
        ok "$1: $4"
    else
        bad "$1: rc $rc, wanted '$4', got '$(sed -n 2p "$T/err")'"
    fi
}

PRFIX='Fix: bash scripts/pr-merge.sh --wait'
PUSH_FIX="gh pr create"
COMMIT_FIX="git switch -c <type>/<slug>"

# A bare merge, and the PR number in the fix line.
case_fix "gh pr merge 7" "$FEAT" "gh pr merge 7 --squash" "$PRFIX 7"
case_fix "number after the flags" "$FEAT" "gh pr merge --squash --delete-branch 12" "$PRFIX 12"
case_fix "flag with a value first" "$FEAT" "gh pr merge -R owner/repo 8" "$PRFIX 8"
case_fix "PR url" "$FEAT" "gh pr merge https://github.com/owner/repo/pull/31 --squash" "$PRFIX 31"
case_fix "number after cd and &&" "$FEAT" "cd x && gh pr merge 5" "$PRFIX 5"
case_fix "inside bash -c" "$FEAT" "bash -c \"gh pr merge 5\"" "$PRFIX 5"
case_fix "after an env assignment" "$FEAT" "GH_TOKEN=x gh pr merge 5" "$PRFIX 5"
case_fix "a backslash before the command word (\\gh)" "$FEAT" "\\gh pr merge 5" "$PRFIX 5"
case_run "\\git push origin {{DEFAULT_BRANCH}}" block "$FEAT" "\\git push origin {{DEFAULT_BRANCH}}"
case_fix "no number: the current branch's PR" "$FEAT" "gh pr merge --auto" "$PRFIX \"\$(gh pr view --json number --jq .number)\""
case_fix "a branch word instead of a number" "$FEAT" "gh pr merge feat/y --squash" "$PRFIX \"\$(gh pr view feat/y --json number --jq .number)\""
case_fix "an odd word is not pasted into the fix" "$FEAT" "gh pr merge 'a;b' " "$PRFIX \"\$(gh pr view --json number --jq .number)\""
run_raw "$(hook_json "$FEAT" "gh pr merge 7")"
if grep -Fq "<number>" "$T/err"; then bad "fix line carries the text <number>"; else ok "fix line carries no <number> placeholder"; fi

# Allowed lookalikes.
case_run "pr-merge.sh is the right path" allow "$FEAT" "bash scripts/pr-merge.sh --wait 5"
case_run "pr-merge.sh dry run" allow "$FEAT" "bash scripts/pr-merge.sh --wait --dry-run 5"
case_run "gh pr view" allow "$FEAT" "gh pr view 12 --json state"
case_run "gh pr create" allow "$FEAT" "gh pr create --title x --body y"
case_run "echo mentions gh pr merge" allow "$FEAT" "echo \"gh pr merge\""
case_run "echo mentions gh pr merge 5" allow "$FEAT" "echo \"merge with gh pr merge 5\""
case_run "quoted separator does not split" allow "$FEAT" "echo \"first; gh pr merge 5\""
case_run "a comment body that says pr merge" allow "$FEAT" "gh issue comment 5 --body \"pr merge later\""
case_run "command -v gh" allow "$FEAT" "command -v gh"
case_run "rg mentions git push" allow "$FEAT" "rg 'git push origin $DEFB' docs"
case_run "git log --grep mentions push" allow "$FEAT" "git log --grep \"git push origin $DEFB\""

# Pushes that land on the default branch.
case_run "push origin default" block "$FEAT" "git push origin $DEFB" "$PUSH_FIX"
case_run "push HEAD:default" block "$FEAT" "git push origin HEAD:$DEFB" "$PUSH_FIX"
case_run "force push +default" block "$FEAT" "git push --force origin +$DEFB" "$PUSH_FIX"
case_run "push refs/heads/default" block "$FEAT" "git push origin feat/x:refs/heads/$DEFB" "$PUSH_FIX"
case_run "git -C <dir> push origin default" block "$NOREPO" "git -C $FEAT push origin $DEFB" "$PUSH_FIX"
case_run "bare git push on default" block "$DEF" "git push" "$PUSH_FIX"
case_run "git push origin on default" block "$DEF" "git push origin" "$PUSH_FIX"
case_run "push HEAD while on default" block "$DEF" "git push origin HEAD" "$PUSH_FIX"
case_run "git -C <default repo> push (bare)" block "$NOREPO" "git -C $DEF push" "$PUSH_FIX"
case_run "cd <default repo> && git push" block "$NOREPO" "cd $DEF && git push" "$PUSH_FIX"
case_run "push feature branch" allow "$FEAT" "git push origin feat/x"
case_run "push -u feature branch" allow "$FEAT" "git push -u origin feat/x"
case_run "bare git push on a feature branch" allow "$FEAT" "git push"
case_run "push dry run to default" allow "$FEAT" "git push --dry-run origin $DEFB"
case_run "push default:feature (source is default)" allow "$FEAT" "git push origin $DEFB:feat/y"
case_run "push tags from default" allow "$DEF" "git push --tags"

# Commits on the default branch.
case_fix "commit on default" "$DEF" "git commit -m x" "Fix: $COMMIT_FIX"
case_run "add and commit with a message file" block "$DEF" "git add a && git commit -F msg.txt" "$COMMIT_FIX"
case_run "git -C <default repo> commit" block "$NOREPO" "git -C $DEF commit -m x" "$COMMIT_FIX"
case_run "commit on a feature branch" allow "$FEAT" "git commit -m \"docs: mention gh pr merge\""
case_run "commit message from a heredoc that names gh pr merge" allow "$FEAT" "git commit -F - <<EOF
docs: say gh pr merge is blocked
gh pr merge 5
EOF"
case_run "switch to a new branch, then commit, from default" allow "$DEF" "git switch -c feat/y && git commit -m x"
case_run "checkout -b, then commit, from default" allow "$DEF" "git checkout -b feat/y; git commit -m x"
case_run "checkout an existing branch, then commit, from default" allow "$DEF" "git checkout feat/x && git commit -m x"
case_run "back to default, then commit, from a feature branch" block "$FEAT" "git checkout $DEFB && git commit -m x" "$COMMIT_FIX"
case_run "commit dry run on default" allow "$DEF" "git commit --dry-run"
case_run "commit outside a repo" allow "$NOREPO" "git commit -m x"
case_run "git status on default" allow "$DEF" "git status"
case_run "plain command" allow "$FEAT" "ls -la"

# Probes that once slipped past a text-matching guard.
case_run "file checkout is not a branch switch" block "$DEF" "git checkout README.md; git commit -m x" "$COMMIT_FIX"
case_run "file checkout with && is not a branch switch" block "$DEF" "git checkout README.md && git commit -m x" "$COMMIT_FIX"
case_run "checkout -- <path> is not a branch switch" block "$DEF" "git checkout -- README.md; git commit -m x" "$COMMIT_FIX"
case_run "restore a file from a branch is not a switch" block "$DEF" "git checkout feat/x -- README.md; git commit -m x" "$COMMIT_FIX"
case_run "env -i git commit" block "$DEF" "env -i git commit -m x" "$COMMIT_FIX"
case_run "env VAR=1 git push origin default" block "$FEAT" "env FOO=1 git push origin $DEFB" "$PUSH_FIX"
case_run "timeout 5 git push origin default" block "$FEAT" "timeout 5 git push origin $DEFB" "$PUSH_FIX"
case_run "timeout -k 2 5 git commit" block "$DEF" "timeout -k 2 5 git commit -m x" "$COMMIT_FIX"
case_run "nice -n 5 git commit" block "$DEF" "nice -n 5 git commit -m x" "$COMMIT_FIX"
case_run "sudo -u someone git commit" block "$DEF" "sudo -u someone git commit -m x" "$COMMIT_FIX"
case_run "git push --all" block "$FEAT" "git push --all origin" "every branch"
case_run "git push --mirror" block "$FEAT" "git push --mirror origin" "every branch"
case_run "git push --all dry run" allow "$FEAT" "git push --all --dry-run"
case_fix "gh api merge with -X PUT" "$FEAT" "gh api repos/o/r/pulls/9/merge -X PUT" "$PRFIX 9"
case_fix "gh api merge with --method PUT" "$FEAT" "gh api --method PUT repos/{owner}/{repo}/pulls/9/merge" "$PRFIX 9"
case_run "gh api graphql mergePullRequest" block "$FEAT" "gh api graphql -f query=mutation{mergePullRequest(input:{pullRequestId:X}){clientMutationId}}" "$PRFIX"
case_run "gh api reads a PR" allow "$FEAT" "gh api repos/o/r/pulls/9"
case_run "gh api reads merge status" allow "$FEAT" "gh api repos/o/r/pulls/9/merge"
case_fix "\$g pr merge" "$FEAT" "g=gh; \$g pr merge 7" "$PRFIX 7"
case_fix "\${g} pr merge with no number" "$FEAT" "\${g} pr merge --squash" "$PRFIX \"\$(gh pr view --json number --jq .number)\""
case_run "a variable that is not a merge" allow "$FEAT" "\$EDITOR README.md"

# Bad input never traps a session.
run_raw '{not json'
if [ "$rc" -eq 0 ]; then ok "malformed JSON: allowed (exit 0)"; else bad "malformed JSON: expected exit 0, got $rc"; fi
run_raw ''
if [ "$rc" -eq 0 ]; then ok "empty input: allowed (exit 0)"; else bad "empty input: expected exit 0, got $rc"; fi
run_raw '{"tool_name":"Bash","tool_input":{}}'
if [ "$rc" -eq 0 ]; then ok "no command field: allowed (exit 0)"; else bad "no command field: expected exit 0, got $rc"; fi
run_raw '{"tool_input":{"command":["gh","pr","merge"]}}'
if [ "$rc" -eq 0 ]; then ok "command is not a string: allowed (exit 0)"; else bad "command is not a string: expected exit 0, got $rc"; fi
case_run "cwd is not a directory" allow "$T/missing" "git commit -m x"

# A PATH with only the tools the guard needs, minus one.
mkbin() { # mkbin <dir> <tool>...
    local d="$1" t p
    shift
    mkdir -p "$d"
    for t in "$@"; do
        p="$(command -v "$t" 2>/dev/null || true)"
        if [ -n "$p" ]; then ln -sf "$p" "$d/$t"; fi
    done
}
BLOCK_JSON="$(hook_json "$FEAT" "gh pr merge 5")"
COMMIT_JSON="$(hook_json "$DEF" "git commit -m x")"

mkbin "$T/bin-nojq" bash cat awk tr git
rc=0
printf '%s' "$BLOCK_JSON" | PATH="$T/bin-nojq" "$BASH_BIN" "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l <"$T/err" | tr -d ' ')" = "1" ] && grep -Fq "jq is not installed" "$T/err"; then ok "no jq: allowed with one note"; else bad "no jq: rc $rc"; fi

mkbin "$T/bin-noawk" bash cat jq tr git
rc=0
printf '%s' "$BLOCK_JSON" | PATH="$T/bin-noawk" "$BASH_BIN" "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(wc -l <"$T/err" | tr -d ' ')" = "1" ] && grep -Fq "awk is not installed" "$T/err"; then ok "no awk: allowed with one note"; else bad "no awk: rc $rc"; fi

mkbin "$T/bin-nogit" bash cat jq awk tr
rc=0
printf '%s' "$COMMIT_JSON" | PATH="$T/bin-nogit" "$BASH_BIN" "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 0 ]; then ok "no git: a commit check allows (exit 0)"; else bad "no git: expected exit 0, got $rc"; fi
rc=0
printf '%s' "$BLOCK_JSON" | PATH="$T/bin-nogit" "$BASH_BIN" "$GUARD" >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 2 ] && two_lines; then ok "no git: a bare merge still blocks"; else bad "no git: bare merge rc $rc"; fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
