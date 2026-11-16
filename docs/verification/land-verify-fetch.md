# Verification -- land-verify-fetch

`wrap land`'s tree verify no longer drops git's fetch error: it retries once, falls back to the common git dir, and names the stderr.

| Claim | Evidence |
|---|---|
| A transient first fetch failure is retried and the verify passes | Green run, case 1 |
| A fetch that fails only under the worktree falls back to the main repo and passes | Green run, case 2 |
| A persistent failure is UNVERIFIABLE and carries git's stderr on one line | Green run, cases 3 and 4 |
| The new cases depend on the fix | Negative control |

## Green run

```
Command: bash tests/test-wrap-merge.sh
Exit: 0
Output:
--- _tree_verify fetch: retried once, then the main repo, and a final failure names git's own stderr
  PASS tree-verify fetch: a transient first failure is retried and verifies
  PASS tree-verify fetch: a worktree-only failure falls back to the main repo
  PASS tree-verify fetch: a persistent failure is UNVERIFIABLE
  PASS tree-verify fetch: the reason carries git's stderr on one line
test-wrap-merge: all 275 passed
Verdict: PASS
```

`bash tests/test-wrap-land.sh` (871 passed) and `bash tests/test-config-registry.sh` (60/60) also exit 0.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-merge.sh" "git show origin/master:lib/wrap/wrap-land.sh >| lib/wrap/wrap-land.sh"
Exit: 1 under the mutation, 0 after restore
Output:
Exit: 0 (green before mutation)
  test-wrap-merge: all 275 passed
Exit: 1 (under mutation, RED expected)
  test-wrap-merge: 272 passed, 3 FAILED of 275
Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- The real cause of the field failure. The fetch error was never captured, and a worktree fetch after a worktree-side merge did not fail in a local probe. The next occurrence prints git's own message.
- A live land in consolelabs/foundations.
