# Verification -- wrap-merge-proof-append

An own PR in a repo that does not declare `merge=union` (circle, vps-mon, foundation-ops) goes CONFLICTING on `docs/proof-of-done.md` once a sibling PR squash-merges. `wrap merge --apply --pr <n>` refused the re-merge (`conflicts beyond the union-marked files, aborted`), the squash fallback then said `does not contain origin/main; the conflict is not the carried-base case`, and the verb ended on `nothing eligible to merge.`. Cause: `_rb_resolve` only resolved CHANGELOG.md by pure append; any other conflicting file, a proof file included, was refused unless git's union driver had already resolved it, and that needs a `.gitattributes` line the foreign repos lack. Now a `docs/proof-of-done.md` (or `<dir>/docs/proof-of-done.md`) that both sides purely appended to resolves by keeping both sides, through the same purity test as CHANGELOG.md.

## Green run

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
  test-wrap-land                                 ok (128s)
  test-wrap-merge                                ok (115s)
  test-wrap-rebase                               ok (23s)
  test-wrap-ship                                 ok (30s)
  run-all: all 18 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

New cases in `tests/test-wrap-merge.sh` (local bare remotes, stub gh, a fixture with no `.gitattributes`), driven through `merge --apply --pr`: the re-merge pushes, re-gates, merges, keeps both rows, leaves no markers. Refusals by name, branch and remote untouched, no `pr merge`: a real conflict in `a.txt` beside the proof file, and an edit to an existing proof row.

## Negative control

Run after the code was committed (`f420adae`), the resolver reverted to its parent:

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-merge.sh" "git show HEAD~1:lib/wrap/wrap-rebase.sh > lib/wrap/wrap-rebase.sh"
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-merge: 426 passed, 5 FAILED of 431
  Restore: git checkout HEAD -- lib/wrap/wrap-rebase.sh
  Exit: 0 (green after restore)
Verdict: PASS
```

The 5 failures are the proof-file cases (push, re-gate, merge, no longer refused, both rows kept); the foreign-conflict refusals stay green on both sides.

## Not proven
- Real GitHub: the fixture stubs gh, so GitHub's own CONFLICTING verdict and settle timing were not exercised.
- The squash fallback still prints `does not contain origin/main; the conflict is not the carried-base case` after a refused re-merge; that line is accurate but follows the real `REFUSED` line, which names the file.
- `wrap land` and `wrap rebase` share the resolver and gain the same proof-file rule; their suites pass, but no new case targets them.

## Rollback
Revert the commit; no state or config changes, the rule lives in `_rb_append_file` and `_rb_resolve` in `lib/wrap/wrap-rebase.sh`.
