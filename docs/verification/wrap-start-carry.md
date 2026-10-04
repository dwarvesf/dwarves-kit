# Proof of done: `bin/wrap start --carry`

Sessions that edit files on a repo's default branch, then realize the work needs a feature branch, were hand running a stash/worktree/apply dance to move those edits into a fresh worktree. `wrap start` already creates the worktree at `origin/<default>` on a new branch; `--carry [<path>...]` moves the main checkout's own uncommitted edits (tracked and untracked, restricted to the given paths or everything with none given) into that same worktree in one call, via a uniquely named `git stash push -u`, found by that message (never by index, since the stash stack is shared with other sessions), applied inside the worktree, and dropped on a clean apply. A held `index.lock` refuses by name without touching the worktree already created; a conflict keeps the stash entry and names it instead of guessing which side is right; nothing dirty in scope is not a refusal.

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | `--carry` (no paths) moves every dirty tracked and untracked file into the worktree, leaves the main checkout clean, and drops the stash entry | test-wrap.sh case (a) |
| AC2 | `--carry <path>` restricts the move to the given path(s), leaving other dirty files in main | test-wrap.sh case (b) |
| AC3 | nothing dirty in scope prints `nothing to carry` and exits 0, worktree still made | test-wrap.sh case (c) |
| AC4 | a held `index.lock` in the main checkout refuses by name, naming the worktree, without touching the worktree or taking a stash | test-wrap.sh case (d) |
| AC5 | a pre-existing foreign stash entry is untouched, before and after | test-wrap.sh case (e) |
| AC6 | plain `start` (no `--carry`) is unaffected | test-wrap.sh regression case |
| AC7 | usage and docs wiring | `wrap.sh` header, `bin/wrap` header, `commands/wrap.md` name `--carry` |
| AC8 | no regression to the rest of wrap | full `test-wrap.sh` green |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 1055 passed
Verdict: PASS
```

```
Command: bash -n bin/wrap
Exit: 0
Verdict: PASS
```

## Negative control

`_start_carry` and `cmd_start`'s `--carry` parsing are the load-bearing implementation. `git show HEAD~1:lib/wrap/wrap.sh` is the pre-change file (no `--carry` support at all), written over the working copy in place, run, then restored with `git checkout --`.

```
Command: git show HEAD~1:lib/wrap/wrap.sh >| lib/wrap/wrap.sh
Exit: 0
Verdict: reverted (working copy only; nothing committed)
```

```
Command: bash tests/test-wrap.sh
Exit: 1
test-wrap: 1040 passed, 15 FAILED of 1055
Verdict: RED as expected, the 15 failures are every carry case this proof adds:
  FAIL carry: exits 0 on a clean carry
  FAIL carry: still prints only the worktree path on stdout
  FAIL carry: the tracked edit landed in the worktree
  FAIL carry: the untracked file landed in the worktree
  FAIL carry: the main checkout's tracked file is clean
  FAIL carry: the main checkout dropped the untracked file
  FAIL carry: reports what it carried
  FAIL carry <path>: exits 0
  FAIL carry <path>: the named path landed in the worktree
  FAIL carry: nothing dirty exits 0
  FAIL carry: nothing dirty prints the marker
  FAIL carry: the worktree still exists
  FAIL carry: the refusal names index.lock
  FAIL carry: the refusal says the worktree exists
  FAIL carry: the worktree was still created
```

(The reverted script has no `--carry` flag at all, so `cmd_start`'s old `[ $# -eq 2 ]` usage check rejects the extra `--carry` argument outright; every carry-specific assertion fails or errors on a path that never got created. The other 1040 cases, everything not touching `--carry`, still passed unchanged.)

```
Command: git checkout -- lib/wrap/wrap.sh
Exit: 0
Verdict: restored
```

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 1055 passed
Verdict: PASS, green restored
```

`git status --short` was empty before the mutation and empty again after the restore; the negative control never touched anything committed.

## Rollback

The whole feature is the single squash commit `d0e9891e6b5579af1301abd5cc7afa76ec80e5e9` (`feat(wrap): start --carry moves main-checkout edits into the worktree`). Rollback is a straight revert of that commit:

```
git revert d0e9891e6b5579af1301abd5cc7afa76ec80e5e9
```

This removes `--carry` from `cmd_start`, the `_start_carry` function, the usage/doc lines, and the six new test cases in one step; plain `wrap start <repo> <branch>` (AC6, unaffected by design) needs no further change either way.

## Not proven

- No live run against a real, non-fixture repo (the sibling `wrap-start.md` proof did one for plain `start`; `--carry`'s stash/apply/drop sequence is exercised only against the test harness's disposable bare-remote fixtures).
- The apply-conflict path (two overlapping edits landing in the worktree and the stash) is implemented per the same identity-match-and-keep contract as `_unstash`, but has no dedicated test case; the five cases plus the no-carry regression are the ones the calling session's contract named.
