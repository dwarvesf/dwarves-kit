# Proof of done: wrap waits for the runs a fresh `ci` label starts

2026-09-29. Spec: `docs/specs/SPEC-360-wrap-ci-label-wait.md`. Lane: full. Files: `lib/wrap/wrap.sh`, `tests/test-wrap.sh`, `commands/greenlight.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md`.

On a label-gated repo, `wrap merge --apply` merged dwarvesf/foundation-workers #971 six seconds after it added the `ci` label. The PR already carried completed checks from before the label, so the wait read "0 pending" at once. The label sync now records the keys of the checks already on the PR, and the wait holds, within the grace bound, until a check outside that set appears. The re-gate keys each check name's latest entry on its first real time. gh reports a pending check's `completedAt` as the zero time, and that zero time had let an older SKIPPED entry stand in as the verdict.

| Check | Command | Result |
|---|---|---|
| Green run | `bash tests/test-wrap.sh` | exit 0, `test-wrap: all 1552 passed` (26 new `ci-wait` checks) |
| Structure | `bash tests/test-meta.sh` | exit 0 after the `docs/FEATURES.md` regeneration |
| Negative control 1 (baseline forced to `[]`) | `lib/gate/negctl.sh` | PASS: red run `1543 passed, 9 FAILED of 1552`, exactly T1, T2, T3, T6 |
| Negative control 2 (pre-change `_pr_gate` sort key) | `lib/gate/negctl.sh` | PASS: red run `1546 passed, 6 FAILED of 1552`, exactly T5, T8 |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS

--- ci-gated merge: checks that predate the label do not end the wait
  PASS ci-wait T1: exits 0
  PASS ci-wait T1: labeled the PR
  PASS ci-wait T1: waited for the label's run past the pre-label checks (6 reads)
  PASS ci-wait T1: merged once the new run read green
  PASS ci-wait T2: exits 2
  PASS ci-wait T2: the re-gate names the red run
  PASS ci-wait T2: a red head never merges
  PASS ci-wait T2: the wait read until the run completed (7 reads)
  PASS ci-wait T3: exits 0
  PASS ci-wait T3: the grace bound held three wait reads (6 reads)
  PASS ci-wait T3: merged on the pre-label rollup
  PASS ci-wait T4: exits 0
  PASS ci-wait T4: a label already on is not edited
  PASS ci-wait T4: one wait read, no extra hold (4 reads)
  PASS ci-wait T4: merged
  PASS ci-wait T5: exits 2
  PASS ci-wait T5: a queued run refuses the re-gate
  PASS ci-wait T5: a queued head never merges
  PASS ci-wait T8: exits 2
  PASS ci-wait T8: a queued run with no real time refuses the re-gate
  PASS ci-wait T8: a queued head never merges
  PASS ci-wait T7: a conflicting PR with a pending check still verdicts the conflict
--- ci-gated land: checks that predate the label do not end the wait (T6)
  PASS ci-wait T6 land: exits 0
  PASS ci-wait T6 land: labeled the PR
  PASS ci-wait T6 land: the merge came after the 4th rollup read
  PASS ci-wait T6 land: merged

test-wrap: all 1552 passed
```

## Negative control

Each control ran `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh > $(mktemp <scratch>/run.XXXXXX) 2>&1" "<mutation>"` on the committed feature (`935a5321`). One log per run keeps the red run's failing check names.

```
Mutation 1: the add-branch assignment becomes CI_LABEL_BASE='[]'
Changed: lib/wrap/wrap.sh
Exit: 0 (green before mutation)
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
Red run: test-wrap: 1543 passed, 9 FAILED of 1552
  FAIL ci-wait T1: exits 0
  FAIL ci-wait T1: waited for the label's run past the pre-label checks (6 reads)
  FAIL ci-wait T1: merged once the new run read green
  FAIL ci-wait T2: exits 2
  FAIL ci-wait T2: the re-gate names the red run
  FAIL ci-wait T2: a red head never merges
  FAIL ci-wait T2: the wait read until the run completed (7 reads)
  FAIL ci-wait T3: the grace bound held three wait reads (6 reads)
  FAIL ci-wait T6 land: the merge came after the 4th rollup read
```

```
Mutation 2: _pr_gate's sort key back to sort_by(.completedAt // .startedAt // .createdAt // "")
Changed: lib/wrap/wrap.sh
Exit: 0 (green before mutation)
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
Red run: test-wrap: 1546 passed, 6 FAILED of 1552
  FAIL ci-wait T5: exits 2
  FAIL ci-wait T5: a queued run refuses the re-gate
  FAIL ci-wait T5: a queued head never merges
  FAIL ci-wait T8: exits 2
  FAIL ci-wait T8: a queued run with no real time refuses the re-gate
  FAIL ci-wait T8: a queued head never merges
```

Both red sets match the spec's expected lists exactly. No other check went red. The restore left `lib/wrap/wrap.sh` at HEAD both times.

## Not proven

- Live GitHub: every case drives a stubbed `gh`. The fixture shapes come from live reads: #971's rollup (`detailsUrl` per job) and the round-3 validator's gh 2.101 reads of pending CheckRuns (zero `completedAt`, empty `conclusion`). A live merge on a throwaway label-gated PR was not run.
- `wrap land` still has no re-gate after the wait, so a red or still-queued label-started run lands there (out of scope, spec).
- The residual races the spec names: two workflows on one event, `needs:` chains, the read-to-edit window, StatusContext keys that shift, and a webhook delayed past the grace window.
