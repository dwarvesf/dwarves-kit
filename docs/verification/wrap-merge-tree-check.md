# Proof of done: `wrap merge` verifies the default branch holds the PR head tree

2026-09-13. Acceptance: after `gh pr merge` reports a PR MERGED, `bin/wrap merge --apply`
fetches the default branch and checks that it actually holds the PR head's tree before
reporting success. A verified merge prints `tree verified`. A real gap prints `TREE MISMATCH,
<n> paths differ` and exits 3 without deleting the branch. An unreadable head object (not a
local commit) prints `tree UNVERIFIABLE ...` and also exits 3, never a silent pass. Lane:
normal. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`, `commands/wrap.md`,
`docs/CHANGELOG.md`.

## The gap this closes

`gh pr merge` reporting `state: MERGED` is GitHub's word, not proof the default branch holds
the reviewed tree. Two known ways it can lie: a `headRefOid` captured before a late push (the
gate read a stale head, `--match-head-commit` still matched because gh re-reads the live head
at merge time in some races), or an armed auto-merge overtaken by a push that lands between
the gate and the actual merge. Operators confirmed by hand three times in one session: pull,
print HEAD, grep the change on main. Before this change, `wrap merge` never checked past
`state == MERGED`.

## What the check does

`_tree_verify <repo> <def> <head_oid>`: fetches `origin/<def>`, then compares trees two ways,
cheapest first.

1. **Whole tree**: `<tip>^{tree}` equals `<head_oid>^{tree}`. True whenever the squash carried
   nothing else onto the default branch, the common case.
2. **Scoped to the PR's own paths**: when the whole tree differs (another PR may have landed
   on the default branch meanwhile, which is not the mismatch this guards against), diff only
   the paths the PR touched (`git diff --name-only <merge-base> <head_oid>`) between the new
   tip and the head. Empty diff on those paths is still a verified merge.

Anything else is a real mismatch, reported with the count of differing paths. A head object
that is not reachable locally (fetch failed, or the branch never existed in this checkout) is
`UNVERIFIABLE`, and treated the same as a mismatch: exit 3, no branch deletion. `wrap merge`
never deletes the branch on any path (a worktree may hold it), so "does not delete the branch"
holds trivially on both the verified and mismatched cases; the test below asserts it directly.

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 376 passed`
Verdict: PASS. 22 new assertions: 1 changed existing assertion (`merge --apply reports the
merge SHA` → `merge --apply reports the merge, tree verified`, since the message format
changed) plus 6 new ones on the happy path fixture, and 3 new cases (mismatch, unverifiable
head, scoped match) with their own assertions.

Command: `bash tests/run-all.sh`
Exit: 0
Output: `run-all: all 140 suites passed, 1 skipped for missing tooling`
Verdict: PASS, no regression.

## Cases the tests bind

Real git repos throughout for the new cases; nothing about tree state is stubbed, because
what a tree actually holds is the whole subject. `gh` stays stubbed (always reports MERGED
via the existing `GH_STUB_VIEW_STATE` default), which is exactly the point: the mismatch and
unverifiable cases are what gh's own word cannot catch.

| Case | Setup | Asserted |
|---|---|---|
| Happy path (existing fixture, extended) | `feat/wrap`'s real commit pushed directly onto the bare remote's `main`, standing in for the squash `gh pr merge` performs on GitHub's side | `merge --apply` exits 0, prints `merged #7 (1a2b3c4d5e6f): tree verified` |
| Real mismatch | a PR branch with a real commit; the remote's `main` never receives it | exits 3, `TREE MISMATCH, 1 paths differ; main does not hold the PR head`, branch still resolves locally |
| Unreachable head | a `headRefOid` that is not a local git object | exits 3, `tree UNVERIFIABLE the PR head is not a local object`, never a false pass |
| Scoped match | another PR's commit lands on `main` first, then the PR's own file is added on top (the real squash shape when the base moved) | exits 0, `tree verified`, proving the scoped-path fallback and not just whole-tree equality |

## Negative control

Command: `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' '<mutation>'`
Mutation: force `_tree_verify` to always report `OK`, which makes every mismatch and
unverifiable case invisible while the happy path stays green.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/^_tree_verify\(\) \{/_tree_verify() { echo OK; return; #NEGCTL/' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Four assertions go RED under that mutation:

```
FAIL tree-verify: a real mismatch exits 3
FAIL tree-verify: mismatch names the count and that main lacks the head
FAIL tree-verify: an unreachable head object exits 3
FAIL tree-verify: names it unverifiable rather than passing silently
```

`tree-verify: mismatch leaves the branch in place` and the scoped-match and happy-path
assertions stay green under the mutation, which is correct: a fake `OK` cannot un-delete a
branch nothing deletes anyway, and a case that should already read `OK` still does. The four
FAILs above are what this control proves: without the real check, gh's MERGED word passes
through unexamined exactly as it did before this change.

## Reproduce

```
git -C ~/.claude/dwarves-kit switch feat/wrap-merge-tree-check
bash tests/test-wrap.sh          # the feature, 376 assertions
bash tests/run-all.sh            # no regression across 140 suites
bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' \
  'perl -i -pe '\''s/^_tree_verify\(\) \{/_tree_verify() { echo OK; return; #NEGCTL/'\'' lib/wrap/wrap.sh'
```

## Amendment: judge the merge on the PR's own diff

2026-09-26. Supersedes "What the check does" above. The scoped-path fallback still
false-alarmed when another PR edited one of this PR's files: ops-toolkit #3422 squash-merged
as `1fcca02` on top of #3420, both PRs added a line to `_meta/LAB_LOG.md`, and main's copy
(both lines) never equals the head's copy (one line). `wrap merge` printed `TREE MISMATCH, 1
paths differ` and exited 3 on a merge that landed correctly.

`_tree_verify <repo> <def> <head_oid> <merge_oid>` now works from the merge commit gh names:

| Step | Check | Result on failure |
|---|---|---|
| 1 | the head and the merge commit are local objects after the fetch | `UNVERIFIABLE` |
| 2 | the merge commit is an ancestor of `origin/<def>` | `UNVERIFIABLE ... is not on origin/<def>` |
| 3 | fast path: the merge commit's tree equals the head's tree | (falls through) |
| 4 | for every path in `diff(base, head)` or `diff(merge^1, merge)`, the zero-context patch (index and `@@` lines dropped) is equal, `base = merge-base(head, merge^1)` | `MISMATCH <paths that differ>` |

Blob equality per path was rejected: it fails the shared-file case, which is the observed
bug. The patch comparison passes a concurrent edit elsewhere in a shared file, and still
flags a squash of a stale head, an altered line (a conflict resolution that rewrote the PR's
line), a missing change, and an unlanded deletion. `--no-renames` makes a rename a delete
plus an add on both sides. Replayed on the real objects, `_meta/LAB_LOG.md` for #3422
compares equal.

The gh stub now answers the fixture remote's HEAD as the merge commit, so the merged-sha
assertions name real commits instead of `1a2b3c4d5e6f`.

| Case | Before | After |
|---|---|---|
| concurrent PR on another path (existing "scoped match") | OK | OK |
| concurrent PR on the same file | MISMATCH 1 (red) | OK |
| squash altered the PR's line in a shared file | MISMATCH | MISMATCH 1 |
| squash of a stale head | MISMATCH 1 | MISMATCH 1 |
| main only got someone else's commit | MISMATCH 1 | MISMATCH 2 (extra path + absent path) |
| gh names a commit that is not on main | not checked | UNVERIFIABLE |
| PR deletes and renames, concurrent PR lands first | OK | OK |
| deletion never landed | MISMATCH | MISMATCH |

### Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 1163 passed`
Before the fix, the same file: `test-wrap: 1159 passed, 4 FAILED of 1163` (the shared-file
case twice, the two-path count, the off-main merge commit).

Command: `bash tests/run-all.sh --all`
Exit: 1
Output: `run-all: FAILED -> test-advisor test-command-triggers test-research-arch-contract test-research-pair-contract`
Verdict: no regression. All four fail identically on the unmodified base `0f75025c`, and none
reads a file this change touched.

### Negative control

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >> <scratch>/negctl.log 2>&1
Exit: 0 (green before mutation)
Mutation: perl ... inserts `merge_oid="$tip"` and a whole-tree `tip == head` check that returns `MISMATCH 1`
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Seven assertions go red under whole-tree comparison: the two-path count, the disjoint scoped
match (twice), the shared-file case (twice), and the deletion and rename case (twice). A first
negctl attempt went red after the restore; the cause is the timing-bound `deploy-wait counts
gh time` assertion, which failed once in four later clean runs, not this check.
