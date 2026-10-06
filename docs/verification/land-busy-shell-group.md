# Verification: a pipeline reader under timeout is still the caller's own

The first fix exempted a stdin-pipe process in wrap's own process group. `timeout 120 wrap land <wt> | tail` puts wrap in timeout's group, so the `tail` reader kept the shell's group and still read as a holder (seen when the fix landed itself). The exempt groups are now wrap's own plus the group of any shell above it.

## Green run
```
Command: LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 0
Output: test-wrap-land: all 601 passed
Verdict: PASS, including the timeout shape case and the existing busy holder cases.

Command: bash tests/test-wrap-apply.sh
Exit: 0
Output: test-wrap-apply: all 309 passed
Verdict: PASS.

Command: real shell, scratch repo, cd <wt> && timeout 60 wrap apply --apply --own <wt> --no-pull <repo> | tail -4
Exit: 0
Output: APPLY complete; the worktree directory is gone from the repo
Verdict: PASS against a real gtimeout, lsof, pipeline and git.
```

## Negative control
```
Command: git show HEAD~1:lib/wrap/wrap-apply.sh >| lib/wrap/wrap-apply.sh; LAND_ONLY=busy LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 1
Output: FAIL timeout shape: no busy SKIP for the caller's own pipeline
        FAIL timeout shape: the worktree is gone
        test-wrap-land: 17 passed, 2 FAILED of 19
Verdict: RED with the previous _wt_busy. Restored with git checkout; the busy section is green again (19 of 19).
```

## Not proven
- A reader whose stdin is not a pipe still reads as a holder. A shell other than sh, bash, zsh, fish, dash or ksh above wrap does not widen the exempt groups.
