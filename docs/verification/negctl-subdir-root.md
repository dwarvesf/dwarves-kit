# Verification -- negctl-subdir-root

`lib/gate/negctl.sh` restored a mutation with a toplevel-relative path while its cwd was the caller's subdirectory root, so the checkout failed and the mutated file stayed in the tree. The restore now runs from `git rev-parse --show-toplevel`. Type: stateful (a tool that mutates the working tree).

## Green run
```
Command: bash tests/test-proof-negctl.sh   (and bash tests/test-meta.sh)
Exit: 0
Output:
  [55] a SUBDIRECTORY root: the restore resolves toplevel-relative paths, the file is never left mutated
    ok: subdir root restored, tree clean
  test-proof-negctl: all 56 passed
  Passed: 930 / 930   (tests/test-meta.sh)
Verdict: PASS
```

## Negative control
```
Command: bash <copy of the new negctl.sh> "$PWD" "bash tests/test-proof-negctl.sh" "git show origin/master:lib/gate/negctl.sh > lib/gate/negctl.sh"
Exit: 0 (under mutation the suite exits 1)
Output:
  Mutation: git show origin/master:lib/gate/negctl.sh > lib/gate/negctl.sh
  Changed: lib/gate/negctl.sh
  Exit: 1 (under mutation, RED expected)
    Changed: tools/app/lib.sh
    Verdict: FAIL: restore failed: git checkout HEAD -- tools/app/lib.sh
    test-proof-negctl: 55 passed, 1 FAILED
  Restore: git checkout HEAD -- lib/gate/negctl.sh
  Exit: 0 (green after restore)
Verdict: PASS
```
The old script (the pre-fix commit) fails case 55 exactly as the field bug did: restore FAIL and `tools/app/lib.sh` left modified. `lib/gate/negctl.sh` was restored and the tree is clean.

## Rollback
`git revert` of the fix commit. The change touches only the restore checkout's cwd.

## Not proven
- `--parallel` with a subdirectory root: its throwaway worktrees are of the toplevel, so tests there run at the toplevel, not the subdirectory. Unchanged by this fix.
- The negative control ran negctl from a copy of itself: mutating `lib/gate/negctl.sh` in place under the running script made bash die with a syntax error (a first attempt, tree restored). Targeting the live file needs the out-of-repo copy.
