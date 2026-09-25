# Verification -- wrap-merge-gate-latest-run

## Round 1: latest run per check, not every stale run

`_pr_gate`'s `checks` filter read `.statusCheckRollup` as-is. `gh pr view --json
statusCheckRollup` returns one entry per check RUN, not per check name: a re-run of a check
(a flaky job re-triggered, or a push that re-ran a workflow) leaves both the stale run and
the new run in the array. The gate treated every entry as still-live, so a check that failed
once and later passed still counted as a failure and blocked an otherwise-green PR (forced a
hand merge on dwarvesf/foundation-apps #140: `evidence / evidence` failed at 17:44:08Z on one
run, then passed at 17:45:49Z on a later run of the same check name, and the gate refused the
merge on the stale failure). `gh pr checks` already dedupes to one row per check name; the
fix grouped `checks` on `.name` and kept only the entry with the latest `completedAt`
(falling back to `startedAt` for a still-running check).

## Round 2: `.name` alone drops every StatusContext to one group

`statusCheckRollup` mixes two distinct GitHub types: `CheckRun` (`.name`, `.completedAt` /
`.startedAt`, `.conclusion`) and `StatusContext` (`.context`, `.createdAt`, `.state`, **no
`.name` at all**). Round 1's `group_by(.name)` put every `StatusContext` entry into a single
group keyed on `null`, because none of them carry `.name`. Two distinct commit statuses (say
a Pages deploy status that FAILED and an unrelated one that passed) collapsed into that one
`null` group, `sort_by(...) | last` picked whichever sorted last, and a real failing status
could be hidden behind a later, unrelated passing one -- the same class of bug Round 1 fixed,
just for the other rollup type. Fix: `group_by(.name // .context)` keys each type by its own
identifier, and the sort now falls back through `.completedAt // .startedAt // .createdAt` to
cover both types' timestamp fields.

```
def checks: (.statusCheckRollup // [])
  | group_by(.name // .context)
  | map(sort_by(.completedAt // .startedAt // .createdAt // "") | last);
```

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: all 1059 passed, including the two Round 1 cases (a check that failed then passed
on a later run is eligible; a check that passed then failed on a later run still skips) and
the two Round 2 cases (two distinct StatusContext entries, one FAILURE, still skips; a
same-context re-post where an older error is superseded by a newer success is eligible).
```

## Negative control (Round 1, re-confirmed)
```
Command: in _pr_gate's jq filter (lib/wrap/wrap.sh), revert `checks` to
`(.statusCheckRollup // [])` (drop the group_by/sort_by/last dedupe entirely), rerun
bash tests/test-wrap.sh, then restore the fix.
Exit: 1 (broken -- the harness DOES exit non-zero when any assertion fails, see "test-wrap.sh
exit code" below), 0 (restored)
Verdict: with the dedupe removed, "merge: a re-run that later passed is eligible, not
blocked by its stale failure" FAILS. Restoring the fix returns the diff to a clean tree and
all assertions pass again.
```

## Negative control (Round 2, the actual bug this round fixes)
```
Command: in _pr_gate's jq filter, revert `checks` to Round 1's
`(.statusCheckRollup // []) | group_by(.name) | map(sort_by(.completedAt // .startedAt // "") | last)`
(the `.context`/`.createdAt` fallbacks removed, Round 1's fix still present), rerun
bash tests/test-wrap.sh, then restore Round 2's fix.
Exit: 1 (broken), 0 (restored)
Verdict: with `.name`-only grouping, "merge: two distinct StatusContext entries, one
FAILURE, still skips" FAILS -- the gate reports the PR eligible even though one of the two
distinct commit statuses is a live FAILURE (both entries have no `.name`, so they collapse
into one `null` group and only the later-sorted SUCCESS entry survives). "merge: a
same-context re-post (older error, newer success) is eligible" still PASSES on its own
(same `.context` means `.name`-only grouping already happened to key it correctly, by
accident -- both `null`). Exactly the one targeted assertion flips, nothing else moves.
Restoring `.name // .context` returns the diff to a clean tree; full run:
`test-wrap: all 1059 passed`.
```

## `test-wrap.sh` exit code (correction)

An earlier version of this doc claimed the harness "does not fail on assertion failures,
only chk/chk_has lines flip." That was wrong, and stated without checking the actual exit
code. The harness DOES exit non-zero on failure -- its tail:
```
if [ "$FAIL" -gt 0 ]; then echo "test-wrap: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap: all $PASS passed"
```
Confirmed directly: reverting to Round 1's `.name`-only grouping (Round 2's bug still
present) and running `bash tests/test-wrap.sh; echo "EXIT=$?"` printed
`test-wrap: 1058 passed, 1 FAILED of 1059` followed by `EXIT=1`.

## Not proven
- Not exercised against a real GitHub PR; the gh calls are stubbed per the existing
  test-wrap.sh fixture.
- The dedupe key is `.name // .context` (workflow job name, or commit-status context string),
  which is what `gh pr checks` and the GitHub merge button use for the equivalent CheckRun
  case; a check or status whose identifier legitimately changes between runs (a renamed
  workflow, or a status re-posted under a new context string) is out of scope, same as
  upstream GitHub's own dedupe.
