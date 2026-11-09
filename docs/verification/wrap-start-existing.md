# Verification -- wrap-start-existing

`wrap start <repo> <branch> --existing` opens a worktree on a branch already on origin, with a local branch tracking `origin/<branch>` at its fetched tip. Without the flag `start` is unchanged.

## Green run

The start suite on the repo's harness (real git, bare remotes, no gh), under bash 5 and bash 3.2:

```
Command: bash tests/test-wrap-start.sh
Exit: 0
Output:
  test-wrap-start: all 127 passed
Verdict: PASS
```

```
Command: /bin/bash tests/test-wrap-start.sh
Exit: 0
Output:
  test-wrap-start: all 127 passed
Verdict: PASS
```

The two suites that call `start` or read the usage text:

```
Command: bash tests/test-wrap-ship.sh && bash tests/test-wrap-cli.sh
Exit: 0
Output:
  test-wrap-ship: all 115 passed
  test-wrap-cli: all 22 passed
Verdict: PASS
```

The new cases build a PR branch on a bare origin after the clone, run `start --existing`, check the printed path, the tip, the local branch name and its upstream, then commit in the worktree and run a plain `git push` with no arguments; the origin branch advances and keeps the earlier PR commits. That is the real flow, on real git.

## Negative control

Run after the code was committed (`39f94ea6`), seven mutations in one `negctl.sh --parallel 4` call, each restored by negctl:

```
Command: bash lib/gate/negctl.sh --parallel 4 "$PWD" "bash tests/test-wrap-start.sh" <seven perl mutations of lib/wrap/wrap-start.sh>
Exit: 1 (under mutation, RED expected), one control vacuous, rerun below
Output:
  start from origin/<default> instead of origin/<branch> (happy path):   122 passed, 5 FAILED of 127
  local-branch refusal removed:                                         125 passed, 2 FAILED of 127
  existing-path refusal removed:                                        118 passed, 9 FAILED of 127
  index.lock guard skipped under --existing:                            123 passed, 4 FAILED of 127
  failed-fetch refusals replaced by fall-through:                       124 passed, 3 FAILED of 127
  same-name-on-origin refusal skipped without the flag (default):       121 passed, 6 FAILED of 127
Verdict: PASS (six controls RED, each restored and green again)
```

The seventh mutation (dropping the `return 1` after the absent-branch message) stayed green, correctly: the fetch that follows fails and refuses anyway, so the behavior did not change. The meaningful mutation is the refusal naming the wrong reason, rerun alone:

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-start.sh" "perl -pi -e 's/--existing branch \$\{branch\} does not exist on origin/fetch origin \${branch} failed/' lib/wrap/wrap-start.sh"
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-start: 126 passed, 1 FAILED of 127
  Restore: git checkout HEAD -- lib/wrap/wrap-start.sh
  Exit: 0 (green after restore)
Verdict: PASS
```

negctl ran in mutate mode on the committed branch (no hand control, no guard blocked it). `git status` was clean afterwards.

## Not proven
- No run against real GitHub: the suite uses local bare remotes, and `start` never calls gh.
- `--track` on the worktree add is belt and braces: git tracks a remote start point by default, so removing the flag alone stays green. It only matters under `branch.autosetupmerge=false`, which is not exercised.
- `--existing` combined with `--pick` or `--carry` is not tested; both operate on the created worktree and were not changed.

## Rollback
The change is additive. Revert the feature commit; `--existing` is read only by `cmd_start`, and no other verb passes it.
