# Verification -- wrap-merge-skip-drafts

`_pr_gate` skips a draft PR before it reads mergeable/mergeStateStatus, so `bin/wrap merge`
never picks a draft first even when GitHub reports it MERGEABLE/CLEAN on a free private repo.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: all 570 passed, including the five new draft-gate cases (a draft skips,
isDraft=false stays eligible, a missing isDraft field stays eligible, a newer draft is
skipped while an older ready PR is picked instead).
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Verdict: 9 suites selected by the two changed files, all 9 passed, 0 skipped for missing
tooling.
```

## Negative control
```
Command: remove the `if (.isDraft == true) then "SKIP draft"` clause from _pr_gate's jq
filter (lib/wrap/wrap.sh), rerun bash tests/test-wrap.sh, then restore the clause.
Exit: 1 (broken), 0 (restored)
Verdict: with the clause removed, "merge: a draft skips" and "merge: the newer draft is
skipped" both FAIL (the draft prints eligible and is picked first). Restoring the clause by
the same targeted edit returns the diff to a clean tree and all 570 tests pass again.
```

## Not proven
- Not exercised against a real GitHub PR; the gh calls are stubbed per the existing
  test-wrap.sh fixture, which already returns the full canned PR JSON regardless of the
  requested --json field list.
