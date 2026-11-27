# Verification -- wrap sweep fresh guard and fix round 1

`wrap apply` / `wrap sweep` keep a never-used worker branch even when its only reflog entries are ordinary syncs through `@{u}` or `FETCH_HEAD`. The same round adds the removal-time busy re-check, caller-worktree protection, stale sweep-lock recovery, per-repo worker error rows, and a strict labeled scorer. Zero false deletions is the hard gate.

| Claim | Evidence |
|---|---|
| Fresh branches stay keep in apply and sweep modes, including `merge --ff-only @{u}` and `merge --ff-only FETCH_HEAD` | Labeled scorer runs below |
| Real merge proofs still remove their cases; false deletions are zero in both modes | Labeled scorer runs below |
| A holder entering after the initial snapshot is re-detected immediately before removal | `test-wrap-sweep` green run and probe2 |
| A sweep never removes the worktree the caller stands in | `test-wrap-sweep` green run and probe2 |
| Dead or expired repo locks are reclaimed; a live pid still wins before age | `test-wrap-sweep` green run |
| A crashed per-repo worker produces an error row and exit 2 | `test-wrap-sweep` green run |
| The scorer fails missing, empty, or truncated labels and reports `scored=N/M` | `test-wrap-fresh-guard` green run |
| The fixture is sensitive to the freshness regression rather than vacuously green | Negative control below |

## Green run: labeled scorer, apply mode

```text
Command: bash tests/lib/wrap-labeled-score.sh --mode apply /tmp/wrap-fix1-proof.tYAgrN/sandbox "$PWD"
Exit: 0
Output:
case	expected	observed
fresh-zero	keep	keep
fresh-branch	keep	keep
fresh-sha	keep	keep
fresh-revision	keep	keep
fresh-ff-sync	keep	keep
fresh-rebase	keep	keep
fresh-reset	keep	keep
fresh-rename	keep	keep
fresh-origin-head	keep	keep
fresh-upstream-alias	keep	keep
fresh-ff-upstream	keep	keep
fresh-ff-fetchhead	keep	keep
merged-ff	remove	remove
merged-commit	remove	remove
squash-equiv	remove	remove
merged-more	keep	keep
merged-dirty	keep	keep
merged-untracked	keep	keep
unmerged-gone	keep	keep
detached-head	keep	keep
live-holder	keep	keep
protected-main	keep	keep
protected-master	keep	keep
pr-merged	remove	remove
pr-closed-unmerged	keep	keep
false_deletions=0
false_keeps=0
missing=0
bad_reason=0
scored=25/25
wrap_exit=0
Verdict: PASS
```

## Green run: labeled scorer, sweep mode

```text
Command: bash tests/lib/wrap-labeled-score.sh --mode sweep /tmp/wrap-fix1-proof.tYAgrN/sandbox "$PWD"
Exit: 0
Output:
case	expected	observed
fresh-zero	keep	keep
fresh-branch	keep	keep
fresh-sha	keep	keep
fresh-revision	keep	keep
fresh-ff-sync	keep	keep
fresh-rebase	keep	keep
fresh-reset	keep	keep
fresh-rename	keep	keep
fresh-origin-head	keep	keep
fresh-upstream-alias	keep	keep
fresh-ff-upstream	keep	keep
fresh-ff-fetchhead	keep	keep
merged-ff	remove	remove
merged-commit	remove	remove
squash-equiv	remove	remove
merged-more	keep	keep
merged-dirty	keep	keep
merged-untracked	keep	keep
unmerged-gone	keep	keep
detached-head	keep	keep
live-holder	keep	keep
protected-main	keep	keep
protected-master	keep	keep
pr-merged	remove	remove
pr-closed-unmerged	keep	keep
false_deletions=0
false_keeps=0
missing=0
bad_reason=0
scored=25/25
wrap_exit=0
Verdict: PASS
```

## Green run: focused suites

```text
Command: bash tests/test-wrap-fresh-guard.sh
Exit: 0
Output:
test-wrap-fresh-guard: all 57 passed
Verdict: PASS
```

```text
Command: bash tests/test-wrap-sweep.sh
Exit: 0
Output:
test-wrap-sweep: all 54 passed
Verdict: PASS
```

```text
Command: bash tests/test-wrap-apply.sh
Exit: 0
Output:
test-wrap-apply: all 470 passed
Verdict: PASS
```

```text
Command: bash tests/test-wrap-merge.sh && bash tests/test-wrap-merge-gate.sh && bash tests/test-wrap-merge-nopull.sh && bash tests/test-wrap-merge-resync.sh && bash tests/test-wrap-merge-stacked.sh
Exit: 0
Output:
test-wrap-merge: all 288 passed
test-wrap-merge-gate: 40 passed, 0 FAILED
test-wrap-merge-nopull: all 78 passed
test-wrap-merge-resync: all 160 passed
test-wrap-merge-stacked: all 65 passed
Verdict: PASS
```

```text
Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
test-wrap-land: 18 sections, 18 ran, 0 cached (0 checks credited)
test-wrap-land: all 889 passed
Verdict: PASS
```

## Green run: review probe2

The probe ran `wrap sweep --apply --worktrees --json` from inside `wt-caller`, with the workspace-removal seam spawning a sleeper inside `wt-b2` only after the first busy snapshot. The three review findings all show keep: the late-held worktree, the caller's own worktree, and both fresh fast-forward spellings.

```text
Command: bash probe2.sh <kit> /tmp/wrap-probe2.zGRtNg
Exit: 0
Output:
worktree m-a1 removed :: ancestor of origin/main holder=null wsrm=ok own=3
worktree m-b2 keep :: busy, held by pid 85973 (bash) and 1 more holder=85973 wsrm=null own=2
worktree m-caller keep :: caller's own worktree (leave it) holder=null wsrm=null own=1
worktree f-control keep :: fresh branch, no own commits and no merged PR (leave it) holder=null wsrm=null own=0
worktree f-fetchhead keep :: fresh branch, no own commits and no merged PR (leave it) holder=null wsrm=null own=0
worktree f-upstream keep :: fresh branch, no own commits and no merged PR (leave it) holder=null wsrm=null own=0
Verdict: PASS
```

## NEGATIVE CONTROL

The control copied the kit and made `_branch_never_committed` always return false, then scored the same labeled sandbox through that mutated copy. Both modes exited non-zero and counted exactly the 12 fresh cases as false deletions, so the labeled fixture turns red when the guard is reverted.

```text
Command: WRAP_LABELED_WRAP=/tmp/wrap-fix1-proof.tYAgrN/negative-kit/bin/wrap bash tests/lib/wrap-labeled-score.sh --mode apply /tmp/wrap-fix1-proof.tYAgrN/sandbox "$PWD"
Exit: 1
Output:
fresh-zero	keep	remove
fresh-branch	keep	remove
fresh-sha	keep	remove
fresh-revision	keep	remove
fresh-ff-sync	keep	remove
fresh-rebase	keep	remove
fresh-reset	keep	remove
fresh-rename	keep	remove
fresh-origin-head	keep	remove
fresh-upstream-alias	keep	remove
fresh-ff-upstream	keep	remove
fresh-ff-fetchhead	keep	remove
false_deletions=12
false_keeps=0
missing=0
bad_reason=0
scored=25/25
wrap_exit=0
Result: RED as expected
```

```text
Command: WRAP_LABELED_WRAP=/tmp/wrap-fix1-proof.tYAgrN/negative-kit/bin/wrap bash tests/lib/wrap-labeled-score.sh --mode sweep /tmp/wrap-fix1-proof.tYAgrN/sandbox "$PWD"
Exit: 1
Output:
fresh-zero	keep	remove
fresh-branch	keep	remove
fresh-sha	keep	remove
fresh-revision	keep	remove
fresh-ff-sync	keep	remove
fresh-rebase	keep	remove
fresh-reset	keep	remove
fresh-rename	keep	remove
fresh-origin-head	keep	remove
fresh-upstream-alias	keep	remove
fresh-ff-upstream	keep	remove
fresh-ff-fetchhead	keep	remove
false_deletions=12
false_keeps=0
missing=0
bad_reason=0
scored=25/25
wrap_exit=0
Result: RED as expected
```

## Full suite

```text
Command: bash tests/run-all.sh
Exit: 0
Output:
run-all: all 81 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Not proven

- A live operator checkout. Every run used throwaway local repositories and local bare origins.
- Network behavior. The fixtures use a stub `gh` and never contact GitHub.
- Reflog expiry. A missing or expired branch reflog intentionally fails safe as fresh; exact merged-PR and patch-equivalence proofs can still remove the branch.
