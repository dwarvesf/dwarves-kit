# Verification -- wrap-start-pick

`wrap start <repo> <branch> --pick <b>...` creates the worktree at `origin/<default>` and cherry-picks each named branch's commits past its merge base, in order.

## Green run
```
Command: bin/wrap start <scratch>/repo feat/integrate --pick w1 --pick w2   (scratch repo: origin main plus branches w1 with one commit and w2 with two)
Exit: 0
Output:
path=<scratch>/repo/.claude/worktrees/integrate
picked w1: 1 commits
picked w2: 2 commits
5f92b2c feat: add c
4dd6412 feat: add b
84df616 feat: add a
a0f53ae chore: init
Verdict: PASS. Stdout carries only the worktree path; the new branch holds both branches' commits in argument order on top of origin/main.
```
Tests: `bash tests/test-wrap-start.sh` prints `test-wrap-start: all 93 passed`; the neighbouring `test-wrap-carry.sh`, `test-wrap-cli.sh` and `test-no-scattered-ids.sh` also pass.

## Negative control
```
Command: bash lib/gate/negctl.sh <wt> "bash tests/test-wrap-start.sh" "git show origin/main:lib/wrap/wrap-start.sh > lib/wrap/wrap-start.sh"
Exit: 0 (green after restore)
Output:
  test-wrap-start: 23 passed, 70 FAILED of 93
Restore: git checkout HEAD -- lib/wrap/wrap-start.sh
Verdict: PASS
```
With the pre-change `wrap-start.sh`, every `--pick` case fails; restoring the change brings the suite back to green.

## Not proven
- A pick against a GitHub-hosted origin; the run used a local bare origin.
- Interaction with a live concurrent writer in the main checkout during the picks.
