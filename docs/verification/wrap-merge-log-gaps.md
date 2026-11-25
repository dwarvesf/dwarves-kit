# Verification -- wrap-merge-log-gaps

Three `wrap` gaps, each reproduced on master by a read-only scout and confirmed red by a new test before its fix.

1. `wrap merge --apply --pr N --with-ci` printed `SKIP #N ...: checks are pending or failing`, then `nothing eligible to merge`, and exited. The eligibility gate calls any pending check WAIT and skips; the `--with-ci` wait runs only for a PR the gate already passed, and the earlier fix covered only an empty rollup.
2. `wrap merge --apply` merged server-side and said nothing about the local checkout, which stayed behind origin. Only `apply` and `land` pulled.
3. `wrap log` run inside another repo's worktree wrote the operator's one activity log, and the only signal (`wrote LAB_LOG.md on the default branch`) named neither the file nor the repo.

## Rule

- A. Under `--with-ci` (or `KIT_WRAP_CI_ON_MERGE=1`), a PR the gate skipped only because a check is still running, with none failing, waits with the usual bounded wait (`KIT_WRAP_CARRY_CHECKS_SECS`), is re-read once GitHub has settled, and is gated again on the same head. `--pr N` and the bare form. A head that moved during the wait keeps the `head moved` refusal (exit 2). A wait that runs out prints `SKIP #N: checks still pending after Ns; left open` and exits 4, the not-merged code. A failing check skips at once with no wait. Without `--with-ci` nothing changes. A dry run only names the wait.
- B. After `merge --apply` merged and verified a PR in a local checkout, that checkout is fast-forwarded through `land`'s own `_land_ff_pull`, with land's guards: only on the default branch, ff-only, never forced. `--no-pull` skips it. A checkout off the default branch, or a pull that cannot fast-forward, prints one `PULL BLOCKED` line. Every line names `wrap apply --apply --pull-only <repo>`. The exit code never changes. A dry run, `--repo <owner>/<name>` and a call that merged nothing never pull. The merge that `apply`'s autoland carry runs in-process never pulls (apply pulls on its own stage, after the carry).
- C. `wrap log` from a git repo other than the log's prints one stderr line: `wrap log: wrote <abs path> (repo <log repo>), outside the current repo <repo>`. The line still goes to the one log; the exit code is unchanged. From the log's own repo, its worktrees or subdirectories, or from outside any git repo, nothing new prints.

## Red, before the fix

Each new case run against the unfixed code. The cases that must hold on both sides (a failing check does not wait, no `--with-ci` does not wait, same-repo log is silent) pass here, which is the point of them.

Fix A, `bash tests/test-wrap-ci.sh` on master code:

```
Command: bash tests/test-wrap-ci.sh
Exit: 1
Output:
    FAIL merge --with-ci pending --pr: exits 0
    FAIL merge --with-ci pending --pr: says it is waiting for the checks
    FAIL merge --with-ci pending --pr: merged once the checks read green
    FAIL merge --with-ci pending --pr: the pending run was read past before the merge
    FAIL merge --with-ci still pending: says it ran out, with the seconds waited
    FAIL merge --with-ci pending, head moves during the wait: exits 2
    FAIL merge --with-ci pending, head moves during the wait: keeps the head-moved refusal
    FAIL merge --with-ci dry run, pending: names the wait --apply would make
    FAIL merge --with-ci bare, pending: lists it eligible after the wait
    FAIL merge --with-ci bare, pending: merged once the checks read green
    FAIL merge --with-ci bare, still pending: exits non-zero
    FAIL merge --with-ci bare, still pending: says it ran out, with the seconds waited
  test-wrap-ci: 196 passed, 12 FAILED of 208
```

Fix B, `bash tests/test-wrap-merge-nopull.sh` on master code:

```
Command: bash tests/test-wrap-merge-nopull.sh
Exit: 1
Output:
    FAIL merge --apply --pr pulls: the checkout's main equals origin's
    FAIL merge --apply --pr pulls: says the checkout was pulled
    FAIL merge --apply --pr --no-pull: says it did not pull and names the command
    FAIL merge --apply --pr off the default branch: says why and names the command
    FAIL merge --apply --pr, main cannot fast-forward: says the pull was refused and names the command
  test-wrap-merge-nopull: 69 passed, 5 FAILED of 74
```

Fix C, `bash tests/test-wrap-log.sh` on master code:

```
Command: bash tests/test-wrap-log.sh
Exit: 1
Output:
    FAIL log from a foreign repo names the file it wrote and the repo it is outside of
    FAIL log from a foreign repo's main checkout says it too
  test-wrap-log: 137 passed, 2 FAILED of 139
```

## Green run

Run on the tip of the branch, merged with origin/master (already up to date at the time of the run).

```
Command: bash tests/test-wrap-ci.sh
Exit: 0
Output:
  test-wrap-ci: all 208 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge-nopull.sh
Exit: 0
Output:
  test-wrap-merge-nopull: all 78 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-log.sh
Exit: 0
Output:
  test-wrap-log: all 139 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge.sh
Exit: 0
Output:
  test-wrap-merge: all 280 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge-gate.sh
Exit: 0
Output:
  test-wrap-merge-gate: 40 passed, 0 FAILED
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge-resync.sh
Exit: 0
Output:
  test-wrap-merge-resync: all 160 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge-stacked.sh
Exit: 0
Output:
  test-wrap-merge-stacked: all 65 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-carry.sh
Exit: 0
Output:
  test-wrap-carry: all 145 passed
Verdict: PASS
```

```
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  Passed: 121 / 121
  All meta tests passed.
  docsreg exit=0
Verdict: PASS
```

The new cases: A, `--pr` pending then green merges, still pending at the bound exits 4 with the seconds waited, head moved during the wait exits 2, pending then red never merges, a failing check exits 4 at once with no wait, one failing plus one pending does not wait, no `--with-ci` does not wait, a dry run names the wait without waiting, the bare form merges after the wait and exits 4 at the bound. B, merge pulls so the checkout's main equals origin's, `--no-pull` stays behind and prints the command, off the default branch prints why and touches nothing, a diverged main refuses without losing the local commit and still exits 0, a dry run, a merge that merged nothing and `--repo` never pull, and the merge called from apply's autoland carry prints no pull line. C, a foreign worktree and a foreign main checkout print the line and still write the one log and nothing into the foreign repo; the log's own subdirectory and worktree, and a call from outside any repo, print nothing new. The ops forwarder that execs `wrap log` from inside the log's repo was also run by hand in a throwaway fixture: from a subdirectory of the log's repo it printed no outside-the-repo line, from another repo it printed it.

## Failures that are not this change

`bash tests/test-wrap-land.sh` and `bash tests/test-wrap.sh` each end with the same five failures, all in the `round-trip` cases of the proof-asset flush section (`the committed tree is clean`, `land's dirty check would pass already`, `the real land exits 0`, `the land still pushed`, `the land still merged`). Those cases exercise `bin/proof-asset` and `land`, not `merge` or `log`. Control: that one section run with `lib/wrap/wrap-merge.sh` and `lib/wrap/wrap-log.sh` restored from origin/master gives the same five. Status: exit 1 on both sides of this branch, so the failures predate it.

```
Command: LAND_CACHE=0 LAND_SECTION=sec_flush bash tests/test-wrap-land.sh   (wrap-merge.sh and wrap-log.sh from origin/master)
Output:
    FAIL round-trip: land's dirty check would pass already
    FAIL round-trip: the real land exits 0
    PASS round-trip: the real flush printed the paste line
    FAIL round-trip: the land still pushed
    FAIL round-trip: the land still merged
  land-section-result: 23 5 28
```

## Negative control

Each fix's control uses `lib/gate/negctl.sh`: the guarded code goes back to its previous revision, the new cases go RED, and the restore is green. A and B ran on the tip (a fixed mutation of the code), C on the commit that added it.

### A: the --with-ci pending wait (mutation: wrap-merge.sh as it was on master)

```
Command: bash tests/test-wrap-ci.sh
Exit: 0 (green before mutation)
Output:
    PASS the worktree was removed
    PASS the branch was deleted
  === the gate verdict is a code: callers do not depend on the reason wording ===
    PASS code gate: a reworded conflict reason still prints on the SKIP line
    PASS code gate: a reworded conflict reason still starts the conflict recovery
    PASS code gate: a reworded pending reason still exits 0
    PASS code gate: a reworded pending reason still reaches the ci label sync
    PASS code gate: the reworded pending case still merges once green
  
  test-wrap-ci: all 208 passed

Mutation: git show 27b7a94b:lib/wrap/wrap-merge.sh > lib/wrap/wrap-merge.sh
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS the worktree was removed
    PASS the branch was deleted
  === the gate verdict is a code: callers do not depend on the reason wording ===
    PASS code gate: a reworded conflict reason still prints on the SKIP line
    PASS code gate: a reworded conflict reason still starts the conflict recovery
    PASS code gate: a reworded pending reason still exits 0
    PASS code gate: a reworded pending reason still reaches the ci label sync
    PASS code gate: the reworded pending case still merges once green
  
  test-wrap-ci: 196 passed, 12 FAILED of 208

Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### B: the post-merge pull (mutation: the call to `_merge_pull_checkout` removed)

```
Command: bash tests/test-wrap-merge-nopull.sh
Exit: 0 (green before mutation)
Output:
    PASS merge --repo notaslug: exits 64
    PASS merge --repo a/b/c: exits 64
    PASS merge --repo /abs/path: exits 64
    PASS merge --repo o/: exits 64
    PASS merge --repo -x/y: exits 64
    PASS merge --repo with no value: exits 64
    PASS merge --repo: an unreadable default branch exits 1
    PASS merge --repo: an unreadable default branch names the slug
  
  test-wrap-merge-nopull: all 78 passed

Mutation: perl -ni -e 'print unless /^      _merge_pull_checkout/' lib/wrap/wrap-merge.sh
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS merge --repo notaslug: exits 64
    PASS merge --repo a/b/c: exits 64
    PASS merge --repo /abs/path: exits 64
    PASS merge --repo o/: exits 64
    PASS merge --repo -x/y: exits 64
    PASS merge --repo with no value: exits 64
    PASS merge --repo: an unreadable default branch exits 1
    PASS merge --repo: an unreadable default branch names the slug
  
  test-wrap-merge-nopull: 73 passed, 5 FAILED of 78

Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### B: the pull stays out of apply's autoland carry (mutation: the caller guard removed)

```
Command: bash tests/test-wrap-merge-nopull.sh
Exit: 0 (green before mutation)
Output:
    PASS merge --repo notaslug: exits 64
    PASS merge --repo a/b/c: exits 64
    PASS merge --repo /abs/path: exits 64
    PASS merge --repo o/: exits 64
    PASS merge --repo -x/y: exits 64
    PASS merge --repo with no value: exits 64
    PASS merge --repo: an unreadable default branch exits 1
    PASS merge --repo: an unreadable default branch names the slug
  
  test-wrap-merge-nopull: all 78 passed

Mutation: perl -ni -e 'print unless /FUNCNAME.*_autoland_carry/' lib/wrap/wrap-merge.sh
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS merge --repo notaslug: exits 64
    PASS merge --repo a/b/c: exits 64
    PASS merge --repo /abs/path: exits 64
    PASS merge --repo o/: exits 64
    PASS merge --repo -x/y: exits 64
    PASS merge --repo with no value: exits 64
    PASS merge --repo: an unreadable default branch exits 1
    PASS merge --repo: an unreadable default branch names the slug
  
  test-wrap-merge-nopull: 76 passed, 2 FAILED of 78

Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### C: the foreign-repo line (mutation: wrap-log.sh as it was on master)

```
Command: bash tests/test-wrap-log.sh
Exit: 0 (green before mutation)
Output:
    PASS log: names the symlink on stderr
    PASS log: the canary outside HOME is byte-identical
    PASS stage: a parent-dir symlink on the worktree copy refuses, exit 1
    PASS stage: names a reason on stderr
    PASS stage: the staging canary outside HOME is byte-identical
    PASS log: a parent-dir symlink on the worktree copy refuses, exit 1
    PASS log: names a reason on stderr
    PASS log: the log canary outside HOME is byte-identical
  
  test-wrap-log: all 139 passed

Mutation: git show HEAD~1:lib/wrap/wrap-log.sh > lib/wrap/wrap-log.sh
Changed: lib/wrap/wrap-log.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS log: names the symlink on stderr
    PASS log: the canary outside HOME is byte-identical
    PASS stage: a parent-dir symlink on the worktree copy refuses, exit 1
    PASS stage: names a reason on stderr
    PASS stage: the staging canary outside HOME is byte-identical
    PASS log: a parent-dir symlink on the worktree copy refuses, exit 1
    PASS log: names a reason on stderr
    PASS log: the log canary outside HOME is byte-identical
  
  test-wrap-log: 137 passed, 2 FAILED of 139

Restore: git checkout HEAD -- lib/wrap/wrap-log.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Judgment calls

- A timeout of the pending wait exits 4, not 2. `apply`'s autoland carry reads any code other than 0 and 4 from `merge --apply --pr` as a failed merge; a PR whose checks are still running at the bound is not merged and nothing failed.
- Fix B reuses `_land_ff_pull` unchanged (it is callable from `wrap-merge.sh`, so the note-only fallback was not needed). The carry guard names `_autoland_carry` on the call stack, because `apply` lands its carry branch through `cmd_merge` in-process; its own test asserts that function still exists.
- Fix C names the repo by the directory that holds `.git`, so a linked worktree reads as its main repo. A log outside any git repo prints `(no git repo)`.

Verdict: PASS
