# Verification -- wrap origin sweep cap

`wrap sweep` and `wrap apply` bound the origin-branch scan on a huge fork. Above `wrap.origin_sweep_max` they keep every origin branch, print the exact skip line, and still judge local branches and worktrees through their existing proofs.

| Claim | Evidence |
|---|---|
| Orca finishes below the 15 second bound and emits no `origin_branch` rows | Orca green run below |
| The exact skip line names the remote-head count | Orca green run below |
| Local branch rows still appear under the cap | Orca green run below |
| The hermetic large-origin regression is sensitive to the fix | Negative control below |
| The final tree passes the full affected suite | Full-suite run below |

## Green run: Orca primary flow

```text
Command: bash lib/wrap/wrap.sh sweep --json --worktrees ~/workspace/orca
Exit: 0
Output:
elapsed_seconds=6.56
stderr:
== ~/workspace/orca
-- worktrees:
-- branches:
     SKIP fix/file-open-paired-focus: currently checked out
     SKIP main: default or protected branch name
-- origin branches:
     SKIP origin sweep: 16596 remote heads over cap
summary={"errors": 0, "keep": 1, "removed": 0, "repos": 1, "skipped": 0, "would_remove": 0}
origin_branch_rows=0
branch_rows=1
worktree_rows=0
Verdict: PASS
```

## Green run: focused sweep suite

```text
Command: bash tests/test-wrap-sweep.sh
Exit: 0
Output:
test-wrap-sweep: all 65 passed
Verdict: PASS
```

## Green run: full affected suite

```text
Command: bash tests/run-all.sh
Exit: 0
Output:
run-all: all 43 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

```text
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-sweep.sh" "git show 19cfc11f:lib/wrap/wrap-apply.sh > lib/wrap/wrap-apply.sh"
Exit: 0
Output:
Mutation: git show 19cfc11f:lib/wrap/wrap-apply.sh > lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS fix1 dead-pid lock reclaim logs stale message and runs repo
    PASS fix1 old lock without pid is reclaimed (exit 0)
    PASS fix1 old lock reclaim logs stale message and runs repo
    PASS fix1 crashed worker exits 2
    PASS fix1 crashed worker emits valid JSON with error row and summary.errors=1
    PASS no-fetch dry run exits 0 with valid JSON
    PASS no-fetch dry run writes no FETCH_HEAD
    PASS no-fetch with --apply is refused (exit 1)

  test-wrap-sweep: 63 passed, 2 FAILED of 65

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation replaced only `lib/wrap/wrap-apply.sh` with its pre-fix revision while keeping the new large-origin regression test. `19cfc11f` is the revision `HEAD^` named when the control ran. The suite went red, the file was restored, and the suite went green again.

## Not proven

- The pre-fix Orca run was not rerun to completion because it had already timed out past 300 seconds.
- This proof does not relax any deletion proof; over the cap every origin branch is kept.
