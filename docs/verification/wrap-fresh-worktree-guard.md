# Verification -- wrap-fresh-worktree-guard

`wrap apply` no longer treats a never-used branch created off the default line as merged merely because its tip is reachable from `origin/<default>`. The labeled sandbox proves the fresh worktree and branch stay, while real merge proofs still remove their cases.

| Claim | Evidence |
|---|---|
| A fresh worktree at `origin/main` is kept with the exact reason | Green run and scorer rows |
| The same holds after the sandbox origin advances and the repo fetches | After-fetch scorer rows |
| Fast-forward, merge-commit, patch-equivalent and exact-head-PR cases still remove | Green run and scorer rows |
| The labels and scorer can catch the regression, including SHA and revision-source fresh branches | Negative control |
| The change does not break the existing apply contract | `test-wrap-apply` green |
| The affected repo suites are green with zero skips | Full `run-all` below |

## Green run

```text
Command: bash tests/test-wrap-fresh-guard.sh
Exit: 0
Output:
test-wrap-fresh-guard: all 28 passed
Verdict: PASS
```


## Labeled scorer: before advancing origin

```text
Command: bash tests/lib/wrap-labeled-score.sh /tmp/wrap-fresh-proof.fYFnL6/fixture "$PWD"
Exit: 0
Output:
case	expected	observed
fresh-zero	keep	keep
fresh-branch	keep	keep
fresh-sha	keep	keep
fresh-revision	keep	keep
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
wrap_exit=0
scorer_rc=0
Verdict: PASS
```

The raw dry-run names the fresh-worktree skip as `fresh branch, no own commits and no merged PR (leave it)`; the integrated test asserts that exact string.

## Labeled scorer: after advancing origin and fetching

The sandbox advanced `origin/main` by moving the local bare ref to the prepared `next-main` commit, then fetched it in the clone. No push to any default branch was used.

```text
Command: bash tests/lib/wrap-labeled-score.sh /tmp/wrap-fresh-proof.fYFnL6/fixture "$PWD"
Exit: 0
Output:
case	expected	observed
fresh-zero	keep	keep
fresh-branch	keep	keep
fresh-sha	keep	keep
fresh-revision	keep	keep
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
wrap_exit=0
scorer_rc=0
Verdict: PASS
```

## Negative control

The control copied the kit and made `_branch_never_committed` always return false. Both fresh labels then flipped to observed removals, so the fixture is sensitive to the regression rather than vacuously green.

```text
Command: WRAP_LABELED_WRAP=/tmp/wrap-fresh-proof.fYFnL6/negative-kit/bin/wrap bash tests/lib/wrap-labeled-score.sh /tmp/wrap-fresh-proof.fYFnL6/fixture "$PWD"
Exit: 1
Output:
fresh-zero	keep	remove
fresh-branch	keep	remove
false_deletions=4
false_keeps=0
missing=0
wrap_exit=0
Verdict: PASS
```

## Full suite

```text
Command: bash tests/run-all.sh
Exit: 0
Output:
test-branch-merged                             ok
test-branch-merged-callers                     ok
test-meta-docs-registry                        ok
test-wrap-apply                                ok
test-wrap-fresh-guard                          ok
test-wrap-scan                                 ok
run-all: all 55 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Not proven

- A live operator checkout. Every run used throwaway local repositories and a local bare origin.
- Network behavior. The fixture uses a stub `gh` and never contacts GitHub.
- Reflog expiry. A missing or expired branch reflog intentionally fails safe as fresh; exact merged-PR and patch-equivalence proofs can still remove the branch.
