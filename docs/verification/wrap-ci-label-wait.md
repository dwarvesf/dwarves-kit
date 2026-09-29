# Proof of done: wrap waits for the runs a fresh `ci` label starts

2026-09-29. Spec: `docs/specs/SPEC-360-wrap-ci-label-wait.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`, `commands/greenlight.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md`. This record covers the feature (`935a5321`) plus the review fix batch (`bc476674`). Every run below is on `bc476674`.

The branch was then rebased onto origin/master `9c2dcb34`, which left `lib/wrap/wrap.sh` and `tests/test-wrap.sh` byte-identical. The pre-rebase SHAs map to: `935a5321` -> `573fc8a4`, `bc476674` -> `e07ab780`. On the rebased head, `bin/test-affected --base origin/master` selected 7 suites and all 7 passed, `tests/test-wrap.sh` passed 1573/1573, and `tests/test-meta.sh` passed 879/879.

On a label-gated repo, `wrap merge --apply` merged dwarvesf/foundation-workers #971 six seconds after it added the `ci` label. The PR already carried completed checks from before the label, so the wait read "0 pending" at once. Now:
- The label sync records the keys of the checks already on the PR. It refuses when it cannot read the PR.
- The wait holds, within the grace bound, until a check appears that is outside that set and not SKIPPED.
- A merge after a hold that saw nothing new needs a `CLEAN` merge state.
- The re-gate sorts every pending check last in its name group and keys the rest on their first real time. gh reports a pending check's `completedAt` as the zero time, and a SKIPPED run from an earlier or later `labeled` event had stood in as the verdict.

| Check | Command | Result |
|---|---|---|
| Green run | `bash tests/test-wrap.sh` | exit 0, `test-wrap: all 1573 passed` |
| Structure | `bash tests/test-meta.sh` | exit 0, `Passed: 879 / 879` |
| NC1: snapshot forced to `[]` | `lib/gate/negctl.sh` | PASS; red run `1558 passed, 15 FAILED of 1573`: T1, T2, T3, T3b, T6, T10, T11, T13 |
| NC2: pre-change `_pr_gate` sort key | `lib/gate/negctl.sh` | PASS; red run `1563 passed, 10 FAILED of 1573`: T5, T8, all four pending-last unit cases |
| NC3: review fix 1 reverted (only no-real-time pending sorts last) | `lib/gate/negctl.sh` | PASS; red run `1571 passed, 2 FAILED of 1573`: the later-SKIPPED case and the stuck-running case |
| NC4: the sync's reset on entry removed | `lib/gate/negctl.sh` | PASS; red run `1572 passed, 1 FAILED of 1573`: T13 |

Each red set is exactly the list above; no other check went red. Every control restored `lib/wrap/wrap.sh` to HEAD, and the post-restore run was green.

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS

  PASS gate pending-last: a later SKIPPED does not stand in for a running check
  PASS gate pending-last: an older SKIPPED does not stand in for a queued check
  PASS gate pending-last: a stuck running entry blocks even behind a newer SUCCESS
  PASS gate pending-last: a stuck entry with no real time blocks behind a newer SUCCESS
--- ci-gated merge: checks that predate the label do not end the wait
  PASS ci-wait T1: waited for the label's run past the pre-label checks (6 reads)
  PASS ci-wait T1: merged once the new run read green
  PASS ci-wait T2: the re-gate names the red run
  PASS ci-wait T2: the wait read until the run completed (7 reads)
  PASS ci-wait T3: the grace bound held three wait reads (6 reads)
  PASS ci-wait T4: one wait read, no extra hold (4 reads)
  PASS ci-wait T5: a queued run refuses the re-gate
  PASS ci-wait T8: a queued run with no real time refuses the re-gate
  PASS ci-wait T7: a conflicting PR with a pending check still verdicts the conflict
  PASS ci-wait T3b: names the non-CLEAN refusal
  PASS ci-wait T9: names the refusal
  PASS ci-wait T10: a new SKIPPED check did not end the hold (5 reads)
  PASS ci-wait T11: a pre-label check that completed still held the grace wait (6 reads)
  PASS ci-wait T12: new checks on a shared URL ended the wait at once (4 reads)
--- ci-gated land: checks that predate the label do not end the wait (T6)
  PASS ci-wait T6 land: the merge came after the 4th rollup read
--- autoland on a ci-gated repo: one grace hold, not two (T13)
  PASS autoland ci-wait T13: the grace hold ran once (18 reads)

test-wrap: all 1573 passed
```

(Excerpt: each case's exit-code and no-merge checks passed too; 47 `ci-wait` and pending-last checks in all.)

## Negative control

Each control ran `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh > $(mktemp <scratch>/run.XXXXXX) 2>&1" "<mutation>"` on `bc476674`. One log per run keeps the red run's failing check names.

```
NC1 mutation: the add-branch assignment becomes CI_PRELABEL_KEYS='[]'
Exit: 0 (green before mutation) / 1 (under mutation) / 0 (green after restore)
Verdict: PASS
test-wrap: 1558 passed, 15 FAILED of 1573
  FAIL ci-wait T1: exits 0
  FAIL ci-wait T1: waited for the label's run past the pre-label checks (6 reads)
  FAIL ci-wait T1: merged once the new run read green
  FAIL ci-wait T2: exits 2
  FAIL ci-wait T2: the re-gate names the red run
  FAIL ci-wait T2: a red head never merges
  FAIL ci-wait T2: the wait read until the run completed (7 reads)
  FAIL ci-wait T3: the grace bound held three wait reads (6 reads)
  FAIL ci-wait T3b: exits 2
  FAIL ci-wait T3b: names the non-CLEAN refusal
  FAIL ci-wait T3b: never merges on pre-label checks alone
  FAIL ci-wait T10: a new SKIPPED check did not end the hold (5 reads)
  FAIL ci-wait T11: a pre-label check that completed still held the grace wait (6 reads)
  FAIL ci-wait T6 land: the merge came after the 4th rollup read
  FAIL autoland ci-wait T13: the grace hold ran once (18 reads)
```

```
NC2 mutation: _pr_gate's sort key back to sort_by(.completedAt // .startedAt // .createdAt // "")
Exit: 0 / 1 / 0
Verdict: PASS
test-wrap: 1563 passed, 10 FAILED of 1573
  FAIL gate pending-last: a later SKIPPED does not stand in for a running check
  FAIL gate pending-last: an older SKIPPED does not stand in for a queued check
  FAIL gate pending-last: a stuck running entry blocks even behind a newer SUCCESS
  FAIL gate pending-last: a stuck entry with no real time blocks behind a newer SUCCESS
  FAIL ci-wait T5: exits 2
  FAIL ci-wait T5: a queued run refuses the re-gate
  FAIL ci-wait T5: a queued head never merges
  FAIL ci-wait T8: exits 2
  FAIL ci-wait T8: a queued run with no real time refuses the re-gate
  FAIL ci-wait T8: a queued head never merges
```

```
NC3 mutation: the sort key back to [(if (pending and rtime == "") then 1 else 0 end), rtime]
Exit: 0 / 1 / 0
Verdict: PASS
test-wrap: 1571 passed, 2 FAILED of 1573
  FAIL gate pending-last: a later SKIPPED does not stand in for a running check
  FAIL gate pending-last: a stuck running entry blocks even behind a newer SUCCESS
```

```
NC4 mutation: the CI_PRELABEL_KEYS='[]' reset at the top of _ci_label_sync removed
Exit: 0 / 1 / 0
Verdict: PASS
test-wrap: 1572 passed, 1 FAILED of 1573
  FAIL autoland ci-wait T13: the grace hold ran once (18 reads)
```

## Not proven

- Live GitHub: every case drives a stubbed `gh`. The fixture shapes come from live reads: #971's rollup (`detailsUrl` per job) and the round-3 validator's gh 2.101 reads of pending CheckRuns (zero `completedAt`, empty `conclusion`). A live merge on a throwaway label-gated PR was not run.
- `wrap land` still has no re-gate after the wait. A red or still-queued run started by the label lands there (out of scope, spec).
- The CLEAN rule after a NONEW hold does not carry into autoland. Its `cmd_merge --pr` runs its own sync with the label already on, so its snapshot is `[]` (spec Failure modes).
- The residual races the spec names: two workflows on one event, `needs:` chains, the read-to-edit window, StatusContext keys that shift, and a webhook delayed past the grace window.
