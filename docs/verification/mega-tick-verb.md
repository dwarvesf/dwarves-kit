# Verification -- mega-tick-verb

`bin/mega tick` records a merged mega sub-goal from gh truth: it audits the PR, checks the goal file's branch, rewrites one ROADMAP line with the sha gh reports, and records the attempt. Every refusal writes nothing. Code at `a2d21783`.

## Green run

The real primary flow, end to end, against real gh. The ledger is a scratch clone of the VimMotion run checkout on a work branch (`run/tick-proof`, `origin/HEAD` set to `develop`). Sub-goal 13's line was put back to the real incident's wrong sha (`merged 2819920`, fixed by hand in commit `8e749b2`). The code root is the real VimMotion checkout. Real gh reads PR 37; nothing is written to the real repo.

```
Command: bash bin/mega tick 01-human-first-upgrade 13-hintkit-labels --pr 37 --megagoals-root docs/megagoals --code-root <VimMotion checkout>
Exit: 0
Output:
AUDIT consolelabs/VimMotion PR #37 MERGED base=develop head=feat/vn-13-hintkit-labels merge=281992a3530ea05c37709663c04ea2514dec0654
BRANCH ok feat/vn-13-hintkit-labels
TICKED 13-hintkit-labels: - [x] 13-hintkit-labels, PR #37, merged 281992a
ATTEMPT none 13-hintkit-labels (no 13-hintkit-labels.task in <VimMotion git dir>/kit-attempts, <scratch ledger>/.git/kit-attempts)
$ diff roadmap.before docs/megagoals/01-human-first-upgrade/ROADMAP.md
50c50
< - [x] 13-hintkit-labels, PR #37, merged 2819920
---
> - [x] 13-hintkit-labels, PR #37, merged 281992a
Verdict: PASS (the wrong sha is repaired from gh truth, a one-line diff)
```

The same scratch ledger, two refusals against real gh (ROADMAP unchanged after both, `diff | wc -l` = 0):

```
Command: bash bin/mega tick 01-human-first-upgrade 44-uat-pack-release-gate --pr 96 --megagoals-root docs/megagoals --code-root <VimMotion checkout>
Exit: 3
Output:
mega tick: REFUSED goals/44-uat-pack-release-gate.md names branch 'feat/vn-44-uat-pack-release-gate' but PR #96's head is 'feat/vn-40-drag-by-labels'; check --pr, or pass --branch-override <reason>
Verdict: PASS (a wrong --pr on an open line is refused)

Command: bash bin/mega tick 01-human-first-upgrade 44-uat-pack-release-gate --pr 102 --megagoals-root docs/megagoals --code-root <VimMotion checkout>
Exit: 1
Output:
mega tick: REFUSED PR #102 is OPEN, not MERGED
Verdict: PASS (the 'merged OPEN' incident class is refused)
```

The suites:

```
Command: bash tests/test-mega-tick.sh
Exit: 0
Output:
test-mega-tick: 191 passed, 0 failed
Verdict: PASS

Command: bash tests/test-mega.sh && bash tests/test-mega-box.sh && bash tests/test-shared-lookups.sh
Exit: 0
Output:
PASS=18 FAIL=0
All mega-box tests passed.
test-shared-lookups: all 15 passed
Verdict: PASS

Command: bash tests/run-all.sh --changed --time
Exit: 1
Output:
run-all: FAILED -> test-operator-pin test-proof-capture-route
run-all: 56 suites run, 0 skipped for missing tooling
Verdict: PASS for this change; both reds are outside it (see "Not proven")
```

## Negative control

Mutation 1: the note reaches awk through `awk -v` instead of `ENVIRON` (the forged-line bug).

```
Command: bash lib/gate/negctl.sh <worktree> "bash tests/test-mega-tick.sh" "bash mut-awk-v.sh"
Exit: 0
Output:
Exit: 0 (green before mutation)   test-mega-tick: 191 passed, 0 failed
Exit: 1 (under mutation, RED expected)   test-mega-tick: 186 passed, 5 failed
NOT ok - C22 literal backslash-n kept on one line (got [0], want [1])
NOT ok - C22 no forged line (got [1], want [0])
NOT ok - C22 one-line diff (got [3], want [2])
NOT ok - C23 backslash annotation byte-exact (got [0], want [1])
NOT ok - C23 one-line diff (got [3], want [2])
Restore: git checkout HEAD -- lib/mega/mega.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Mutation 2: compare the raw `**Branch:**` value, no normalization.

```
Command: bash lib/gate/negctl.sh <worktree> "bash tests/test-mega-tick.sh" "bash mut-raw-branch.sh"
Exit: 0
Output:
Exit: 0 (green before mutation)   test-mega-tick: 191 passed, 0 failed
Exit: 1 (under mutation, RED expected)   test-mega-tick: 180 passed, 11 failed
NOT ok - C2 exit 0 (got [3], want [0])
NOT ok - C2 backticked branch line (missing [BRANCH ok feat/13] in [])
NOT ok - C3 exit 0 (got [3], want [0])
NOT ok - C3 CR-ended branch line (missing [BRANCH ok feat/x] in [])
NOT ok - C21 exit 0 (got [3], want [0])
NOT ok - C21 suffixed branch line (missing [BRANCH ok ci/release-pipeline] in [])
Restore: git checkout HEAD -- lib/mega/mega.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Both mutations were restored; `git status --short` was empty after each.

## Not proven

- `test-operator-pin` is red on this branch because its fix (the `unpinned-ok` marker on `tests/test-shared-lookups.sh`) landed on master after this branch's base, in `04640338`. It goes green on rebase or merge.
- `test-proof-capture-route` failed only inside the parallel `run-all` (signal-timing cases 6 to 9 and 14 under load); run alone it exits 0. It does not touch `lib/mega`.
- No real attempt record was committed in the real-flow run (sub-goal 13 has no record in the real store, so `ATTEMPT none`); the commit path is covered by C1, C30, C36 and C44 against the real `attempt-state.sh`.
- A MERGED PR with a null merge commit is covered only by a stub (C6); no real one was found.
- The dead-pid reclaim race the security review named is the driver's own protocol and is not changed here (implementation notes).

## Rollback

- The change itself: `git revert` the feature commits. No persistent state is migrated; the verb only adds code, a suite and docs.
- A tick the verb wrote: it never commits, so before the commit `git -C <ledger> restore <ROADMAP>`; after it, `git revert` the tick commit or hand-edit the line. An attempt record it moved to `done` has no legal move back; `attempt-state.sh release <id>` drops it, and the merged PR plus the run ledger stay the durable trail.
