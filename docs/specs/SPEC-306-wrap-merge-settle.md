# SPEC-306: wrap merge waits for GitHub to settle on the head it pushed

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
**Proof:** `docs/verification/wrap-merge-settle.md`; `tests/test-wrap.sh`, the settle and no-checkout blocks.

## Problem

`bin/wrap merge --apply --pr N <repo>` misfired three times in one session (ops-toolkit PRs #3154, #3155, #3168).

1. The PR conflicted only on union-marked files. wrap re-merged `origin/<default>` into the branch, pushed, and read mergeability at once. GitHub computes mergeability asynchronously after a push. It served UNKNOWN, or the old head with its old CONFLICTING verdict. The old settle loop waited only on UNKNOWN, five reads over ten seconds, so wrap printed `SKIP #N after the re-merge: not mergeable (CONFLICTING)` and `nothing eligible to merge`. Ten to twenty seconds later GitHub reported MERGEABLE and a hand `gh pr merge --squash --match-head-commit <head>` succeeded. A second `wrap merge` re-merged, pushed, and hit the same race.
2. A branch that no local checkout held printed `no local checkout holds <branch>`, then the carried-base fallback refused with `<branch> does not contain origin/main; the conflict is not the carried-base case`. `git merge-tree --write-tree origin/main origin/<branch>` resolved cleanly; only `_meta/LAB_LOG.md`, a `merge=union` file, differed.

## Contract

- `_pr_detail_settled <url> <n> [<pushed-oid> <prior-oid>]` polls `gh pr view` every 2s, bounded by `KIT_WRAP_SETTLE_SECS` (default 60, non-numeric falls back to 60). It returns the last read either way.
  - Without a pushed oid, it waits while `mergeable` reads UNKNOWN.
  - With one, it waits while the head is still the prior oid, or the head is the pushed oid and `mergeable` reads UNKNOWN or CONFLICTING. A head that is neither ends the wait at once.
- The first detail read of every PR goes through the no-oid form, so a first read of UNKNOWN is re-read before any SKIP.
- After wrap's own re-merge push, the re-gate calls the oid form with the pushed head and the pre-push head. A final head other than the pushed one refuses with `SKIP #N after the re-merge: head is <short>, not the pushed <short>` and takes no fallback. Otherwise `_pr_gate` judges, and a still-CONFLICTING verdict prints the existing `not mergeable (CONFLICTING)` line and reaches the squash fallback unchanged.
- The merge stays pinned with `--match-head-commit` to the pushed head.
- `_union_remerge` on a branch no checkout holds fetches it, requires the fetched tip to equal the PR head, and runs the same merge, abort, dedupe and push in a scratch detached worktree at that head. The push is `HEAD:refs/heads/<branch>`, a fast-forward. The scratch worktree is removed afterwards, pass or fail. A checkout that holds the branch keeps every existing guard (tip identity, dirty, index.lock).

## Design record

Variant 2 is not a defect in the fallback. The carried-base fallback refuses a head that lacks the base on purpose: only a head that already contains `origin/<default>` has the tree a squash would produce, so commit-tree reproduces a merge there and invents one anywhere else. The defect sits one step earlier. The union re-merge is the designed recovery for a branch that lacks the base, and it refused because it required a local checkout. A scratch detached worktree gives it one without touching any operator checkout, and reuses the merge, the union driver, the kanban dedupe and the abort path unchanged. `merge-tree` plus `commit-tree` would also avoid a checkout, but it skips the dedupe step, so a duplicated board row could land.

The settle wait treats CONFLICTING as unsettled only after wrap's own push. A PR wrap did not push keeps its first CONFLICTING verdict, because nothing says GitHub is behind on it. The bound is an env knob rather than a constant so the tests can shrink it; 60s covers the observed 10 to 20s lag with margin. Polling with a fixed 2s step keeps the old cadence.

## Test plan

| Case | Setup (gh stubbed, real git) | Expected |
|---|---|---|
| Late settle | re-merge push; reads: UNKNOWN on old head, CONFLICTING on pushed head, MERGEABLE on pushed head | eligible, merged, 4 detail reads, `--match-head-commit <pushed>` |
| Stuck CONFLICTING | pushed head reads CONFLICTING forever, bound 6s | `SKIP #N after the re-merge: not mergeable (CONFLICTING)`, 5 detail reads, never merges #N |
| Moved head | UNKNOWN on old head, then MERGEABLE on a foreign head | `head is 4444444, not the pushed`, wait stops at 3 reads, no merge |
| Unregistered push | the old head forever, bound 4s | `head is <old>, not the pushed`, no merge |
| First read UNKNOWN | dry run, UNKNOWN then MERGEABLE | eligible, no `not mergeable (UNKNOWN)` |
| No checkout | local branch deleted, head lacks main | scratch worktree named, re-merged and pushed, merged and tree verified, scratch worktree gone, operator checkout clean on main |
| Fallback refusal kept | checkout dirty, head lacks main | the existing `does not contain origin/main` refusal, no `pr create`, no push |

Negative control: the new cases run against the pre-change `lib/wrap/wrap.sh` and fail.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.

## After state

`wrap merge --apply` merges a union-conflicted PR in one call once GitHub settles, and a branch no checkout holds recovers through the same re-merge.

Not covered: the wait ends on a settled mergeability verdict, not on CI. A repo whose checks restart on the pushed head still gets `SKIP ... checks are pending or failing` from that call, and the next `wrap merge` call merges it once the checks go green.
