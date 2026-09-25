# Verification -- wrap-merge-gate-latest-run

`_pr_gate`'s `checks` filter read `.statusCheckRollup` as-is. `gh pr view --json
statusCheckRollup` returns one entry per check RUN, not per check name: a re-run of a check
(a flaky job re-triggered, or a push that re-ran a workflow) leaves both the stale run and
the new run in the array. The gate treated every entry as still-live, so a check that failed
once and later passed still counted as a failure and blocked an otherwise-green PR (forced a
hand merge on dwarvesf/foundation-apps #140: `evidence / evidence` failed at 17:44:08Z on one
run, then passed at 17:45:49Z on a later run of the same check name, and the gate refused the
merge on the stale failure). `gh pr checks` already dedupes to one row per check name; the
fix mirrors that by grouping `checks` on `.name` and keeping only the entry with the latest
`completedAt` (falling back to `startedAt` for a still-running check) before the pass/fail
scan runs.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: all 1057 passed, including the two new latest-run-per-check cases (a check that
failed then passed on a later run is eligible; a check that passed then failed on a later
run still skips).
```

## Negative control
```
Command: in _pr_gate's jq filter (lib/wrap/wrap.sh), revert `checks` to
`(.statusCheckRollup // [])` (drop the group_by/sort_by/last dedupe), rerun
bash tests/test-wrap.sh, then restore the fix.
Exit: 0 (both runs; the suite itself does not fail on assertion failures, only chk/chk_has
lines flip)
Verdict: with the dedupe removed, "merge: a re-run that later passed is eligible, not
blocked by its stale failure" FAILS (the gate reports SKIP on the stale FAILURE entry even
though the same check name's later run passed). "merge: a re-run whose latest attempt failed
after an earlier pass still skips" still PASSES on its own (that fixture has no live SUCCESS
entry left uncontested once you drop the dedupe -- it happens to still contain a FAILURE
conclusion, so an unpatched gate also refuses it, just via the wrong row). Restoring the
fix returns the diff to a clean tree and all 1057 assertions pass again.
```

## Not proven
- Not exercised against a real GitHub PR; the gh calls are stubbed per the existing
  test-wrap.sh fixture.
- The dedupe key is `.name` (workflow job name, e.g. "evidence / evidence"), which is what
  both `gh pr checks` and the GitHub merge button use; a check whose name legitimately
  changes between runs (renamed workflow) is out of scope, same as upstream.
