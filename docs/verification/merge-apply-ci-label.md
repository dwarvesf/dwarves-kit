# Proof of done: `wrap merge --apply` arms the `ci` label on label-gated repos

2026-09-29. Acceptance: #809 armed `cmd_land` and `_autoland_carry` with the ci-label
sync, but a standalone `wrap merge --apply` still read the empty statusCheckRollup an
unlabeled head reports, passed the gate on `mergeStateStatus=CLEAN`, and merged the
untested head. The merge path now runs the same `_ci_label_sync` before its pinned merge
and waits out the runs the label starts via `_ci_checks_wait`, then re-reads and re-gates
that head so a check the label revealed failing refuses. A repo without the label merges
as it always did, and a label that will not set refuses the merge. Lane: bug. Files:
`lib/wrap/wrap.sh`, `tests/test-wrap.sh`.

## How it works

After the eligibility loop picks the merge candidate and before the pinned
`gh pr merge`, `cmd_merge` calls `_ci_label_sync "$url" "$first_eligible"`. On a
label-gated repo (rc 0) it runs `_ci_checks_wait`, then re-reads the PR through
`_pr_detail_settled` and re-runs `_pr_gate` on the fresh head: the eligibility verdict
above was read on a rollup the label had not populated yet, so the gate gets a second
pass on the head the label actually tested. A moved head or a non-OK verdict refuses the
merge (exit 2). A repo with no `ci` label (rc 1) skips the whole block; a label that
cannot be set (rc 2) refuses rather than merging untested. The ordering matches
`_autoland_carry`'s label -> wait -> gate -> merge, so a carry PR passing through
`cmd_merge --apply --pr` and a hand-run `wrap merge --apply` now take the same door.

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 1526 passed`
Verdict: PASS. Three new cases under `=== merge --apply: the ci label gate arms CI
before the merge ===`: the label goes on before the merge and the pending run is waited
out (five `pr view` reads: eligibility, sync, two wait polls, re-gate); an unset label
refuses the merge with no `pr merge` call (negative); a check the label revealed failing
is refused by the post-label re-gate. Every pre-existing merge case runs the ungated path
on a repo the stub reports has no `ci` label, which is the unchanged-behavior control.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 879 / 879`
Verdict: PASS.

## Negative control

Command: `bash lib/gate/negctl.sh . 'bash tests/test-wrap.sh' 'git show HEAD~1:lib/wrap/wrap.sh > lib/wrap/wrap.sh'`
Mutation: restore the pre-change `wrap.sh`, so `cmd_merge` never calls
`_ci_label_sync` and the untested head merges again.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: git show HEAD~1:lib/wrap/wrap.sh > lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Verdict: PASS.
