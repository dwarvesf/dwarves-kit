# Verification -- ci-label-probe-fail-closed

In wrap's opt-in ci gate (`--with-ci` or `KIT_WRAP_CI_ON_MERGE=1`), a failed `gh label list` no longer reads as "this repo has no ci label". It refuses the merge or land.

## Change

- Root cause: `_ci_repo_has_label` piped `gh label list` into `jq` and answered 1 for any failure. A transient gh or API error was indistinguishable from a repo without the label, so `_ci_label_sync` returned 1 and the merge ran with no label and no check wait.
- Fix: `_ci_repo_has_label` returns 0 (exact `ci` label), 1 (no label), or 2 (non-zero gh exit, or output that is not a JSON array). Empty output stays 1, because gh answers a no-match search with exit 0 and zero bytes.
- `_ci_label_sync` maps 2 to its existing rc 2 and prints `could not read the repo labels for #N`. Every caller already refuses on rc 2: `merge --apply` (`FAILED merge #N: the ci label could not be set`) and `land` (`MERGE FAILED #N: ...`). The merge dry-run note ignores 2, which is harmless.

## Green run

```
Command: bash tests/test-wrap-ci.sh
Exit: 0
Output:
PASS ci-probefail merge: exits 2
PASS ci-probefail merge: names the unread labels
PASS ci-probefail merge: names the refusal
PASS ci-probefail merge: never merges an unproven head
PASS ci-probefail land: exits 2
PASS ci-probefail land: names the unread labels
PASS ci-probefail land: names the refusal
PASS ci-probefail land: never merges an unproven head
PASS ci-probefail land: no label edit on an unread repo
PASS ci-emptylbl land: exits 0
PASS ci-emptylbl land: merged as before
test-wrap-ci: all 163 passed
Verdict: PASS
```

Adjacent suites: `test-wrap-land.sh` 727 of 727, `test-wrap-carry.sh` 145 of 145, `test-wrap-merge.sh` 410 of 410.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-ci.sh" "git show origin/master:lib/wrap/wrap-ci.sh > lib/wrap/wrap-ci.sh"
Exit: 1 (under mutation, RED expected)
Output:
test-wrap-ci: 155 passed, 8 FAILED of 163
Restore: git checkout HEAD -- lib/wrap/wrap-ci.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation is master's `wrap-ci.sh`. The 8 failures are the `ci-probefail` merge and land cases: on master both merge with no label.

## Reproduce

```bash
bash tests/test-wrap-ci.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-ci.sh" "git show origin/master:lib/wrap/wrap-ci.sh > lib/wrap/wrap-ci.sh"
```

## Not proven

- No retry on a transient error: the run refuses and the user re-runs. `_gh_merge_transient` reads `gh pr merge` stderr, which the probe discards.
- The `wrap-carry.sh` (autoland) path calls the same `_ci_label_sync`, but has no dedicated probe-failure case. Its SKIP message still says "unlabeled".
- Other opt-in gates beyond the label probe (events-feed dating of the label, pinned-head settle) are not part of this change.
