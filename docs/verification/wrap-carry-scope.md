# Verification -- wrap-carry-scope

`wrap start --carry` now reports a failed stash push, and a pathspec carry keeps files staged outside the pathspec out of the new worktree.

| Claim | Evidence |
|---|---|
| A failed `git stash push` exits 2 and prints git's error, never `nothing to carry` | Green run, case (g) |
| A file staged outside the pathspec stays in main and never reaches the worktree | Green run, case (h) |
| The `carried:` line lists only the named paths | Green run, case (h) |
| The new cases depend on the fix | Negative control |

## Green run

```
Command: bash tests/test-wrap-start.sh
Exit: 0
Output:
--- (g) an unmerged index entry in main: a failed stash push is not 'nothing to carry'
  PASS carry: a failed stash push exits 2
  PASS carry: a failed stash push never says nothing to carry
  PASS carry: a failed stash push shows git's own error
  PASS carry: a failed stash push names the cause and the worktree
  PASS carry: a failed stash push left the edit in main
  PASS carry: a failed stash push left no stash entry
--- (h) staged outside the pathspec stays in main and never reaches the worktree
  PASS carry staged-outside: exits 0
  PASS carry staged-outside: the named file landed
  PASS carry staged-outside: the named directory landed
  PASS carry staged-outside: the worktree status holds only the named paths
  PASS carry staged-outside: the staged edit never reached the worktree
  PASS carry staged-outside: the staged new file never reached the worktree
test-wrap-start: all 143 passed
Verdict: PASS
```

`bash tests/test-wrap-cli.sh` and `bash tests/test-wrap-carry.sh` also exit 0 on this branch.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-start.sh" "git show origin/master:lib/wrap/wrap-start.sh >| lib/wrap/wrap-start.sh"
Exit: 1 under the mutation, 0 after restore
Output:
Exit: 0 (green before mutation)
  test-wrap-start: all 143 passed
Exit: 1 (under mutation, RED expected)
  test-wrap-start: 135 passed, 8 FAILED of 143
Restore: git checkout HEAD -- lib/wrap/wrap-start.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation put the old `wrap-start.sh` back. Eight assertions went red, and the restore turned the file green again.

## Not proven

- A live shared checkout. Every run used throwaway repos made by the test file.
- A carry with no paths. Its behavior is unchanged, and the existing cases still cover it.
- A conflicted apply with files staged outside the pathspec. The restore runs there too, but no case forces that pair.
- The installed copy. This proof ran in the worktree; the installed kit picks the fix up on its next update.
