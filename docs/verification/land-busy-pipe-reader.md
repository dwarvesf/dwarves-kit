# Verification: a caller pipeline reader never counts as a worktree holder

`wrap land <wt> | tail -6`, run from a shell standing in `<wt>`, starts `tail` with `<wt>` as its cwd. The busy check read it as a live holder, so land merged the PR and left the worktree. A later `wrap apply --own` removed it once `tail` had exited. `_wt_busy` now treats a process in the run's own process group with a pipe on stdin as the caller's own.

## Green run
```
Command: LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 0
Output: test-wrap-land: 14 sections, 14 ran, 0 cached (0 checks credited)
        test-wrap-land: all 598 passed
Verdict: PASS. The new pipe reader case (land removes the worktree and branch) passes with the existing busy holder cases.

Command: bash tests/test-wrap-apply.sh
Exit: 0
Output: test-wrap-apply: all 309 passed
Verdict: PASS. The new apply --own pipe reader case passes beside the cwd and open-file holder cases.

Command: real shell, scratch repo, cd <wt> && wrap apply --apply --own <wt> --no-pull <repo> | tail -6 | cut
Exit: 0
Output: APPLY complete; the worktree directory is gone from the repo
Verdict: PASS against a real lsof, real pipeline, real git.
```

| Holder | Same process group | stdin | Result |
|---|---|---|---|
| `\| tail` reader of the run | yes | pipe | not busy, removed |
| background `sleep` in the same shell | yes | /dev/null | busy, kept |
| background job from an earlier call | no | any | busy, kept |
| open-file holder | no | file | busy, kept |

## Negative control
```
Command: git show HEAD~1:lib/wrap/wrap-apply.sh >| lib/wrap/wrap-apply.sh; LAND_ONLY=busy LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 1
Output: FAIL pipe reader: no busy SKIP for the caller's own pipeline
        FAIL pipe reader: land reports the removal
        FAIL pipe reader: the worktree is gone
        FAIL pipe reader: the local branch is deleted
        test-wrap-land: 12 passed, 4 FAILED of 16
Verdict: RED with the old _wt_busy. Restored with git checkout; the busy section is green again (16 of 16).
```

## Not proven
- A pipeline whose reader has no stdin pipe (a reader fed by a file redirect) still reads as a holder.
- The dirty and tip-moved guards are untouched here; their existing cases still pass.
