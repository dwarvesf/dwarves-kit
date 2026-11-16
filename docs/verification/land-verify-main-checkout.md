# Verification -- land-verify-main-checkout

`wrap land` verifies the merge against the main checkout, and its tidy accepts a worktree that `gh pr merge --delete-branch` already removed.

| Claim | Evidence |
|---|---|
| With the worktree gone at merge time, the tree verify reports `tree verified`, never `UNVERIFIABLE ... cannot change to` | Green run, rmwt cases |
| The tidy then finishes: origin branch deleted, local branch gone, `worktree=removed`, exit 0 | Green run, rmwt cases |
| The new cases depend on the fix | Negative control |
| `_tree_verify` fetch retry and stderr cases still pass without the common-dir fallback | `bash tests/test-wrap-merge.sh`: all 274 passed |

## Green run

```
Command: LAND_ONLY=happy LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 0
Output:
  PASS rmwt: the worktree was gone before the verify (the stub removed it at merge)
  PASS rmwt: the verify is never UNVERIFIABLE for a missing worktree directory
  PASS rmwt: the verify never cd's into the vanished worktree
  PASS rmwt: the verify still proves the tree (verified)
  PASS rmwt: land exits 0
  PASS rmwt: the tidy reports the worktree already removed
  PASS rmwt: the local branch is deleted
  PASS rmwt: the origin branch is deleted
  PASS rmwt: the summary says the worktree is removed
test-wrap-land: all 41 passed
Verdict: PASS
```

The full `bash tests/test-wrap-land.sh` also exits 0 (all 880 passed).

## Negative control

```
Command: git show HEAD~1:lib/wrap/wrap-land.sh >| lib/wrap/wrap-land.sh; LAND_ONLY=happy LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 1 under the mutation, 0 after restore
Output:
  PASS rmwt: the worktree was gone before the verify (the stub removed it at merge)
  FAIL rmwt: the verify is never UNVERIFIABLE for a missing worktree directory
  FAIL rmwt: the verify never cd's into the vanished worktree
  FAIL rmwt: the verify still proves the tree (verified)
  FAIL rmwt: land exits 0
  FAIL rmwt: the tidy reports the worktree already removed
  FAIL rmwt: the local branch is deleted
  FAIL rmwt: the origin branch is deleted
  FAIL rmwt: the summary says the worktree is removed
test-wrap-land: 33 passed, 8 FAILED of 41
Restore: cp the fixed lib/wrap/wrap-land.sh back
Exit: 0 (green after restore)
Verdict: PASS
```
