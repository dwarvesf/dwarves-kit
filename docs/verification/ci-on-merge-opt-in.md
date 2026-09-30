# Proof of done: the `ci` label gate is opt-in on `merge` and `land`

Lane: normal. Files: `lib/wrap/wrap.sh`, `commands/greenlight.md`, `tests/test-wrap.sh`. Every run below is on `ce473f10`.

`wrap land` and `wrap merge --apply` no longer sync the `ci` label or wait on its runs by default; `--with-ci` or `KIT_WRAP_CI_ON_MERGE=1` arms the gate (the env var is the only switch `wrap apply`'s autoland reads). Off, an empty rollup is mergeable and the label endpoints are never called, the pre-#809 merge shape.

| Check | Command | Result |
|---|---|---|
| Green run | `bash tests/test-wrap.sh` | exit 0, `test-wrap: all 1581 passed` |
| Structure | `bash tests/test-meta.sh` | exit 0, `Passed: 887 / 887` |
| Hooks | `bash tests/test-hooks.sh` | exit 0, `Passed: 719 / 719` |
| NC: default flipped back to on | `lib/gate/negctl.sh` | PASS; red run `1577 passed, 4 FAILED of 1581`, exactly the four ci-off assertions |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS

  PASS ci-gated merge: added the ci label          (merge --apply --with-ci)
  PASS ci-off merge: the repo labels are never probed
  PASS ci-off merge: no pr edit runs
  PASS ci-off merge: the empty rollup is mergeable again
  PASS ci-gated land: added the ci label           (land --with-ci)
  PASS ci-off land: the repo labels are never probed
  PASS ci-off land: no pr edit runs
  PASS ci-off land: merged as before

test-wrap: all 1581 passed
```

The #809/#813 cases all run opted-in now (the flag on the merge and land happy paths, `KIT_WRAP_CI_ON_MERGE=1` on the rest, including the two autoland cases), so the on-path is unchanged and still covered.

## Negative control

```
Command: bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "sed -i '' 's/^KIT_WRAP_CI_ON_MERGE=.*/KIT_WRAP_CI_ON_MERGE=1/' lib/wrap/wrap.sh"
Exit: 0 (green before mutation) / 1 (under mutation) / 0 (green after restore)
Verdict: PASS

Mutation: the env default back to 1, the old always-on behavior.
test-wrap: 1577 passed, 4 FAILED of 1581
  FAIL ci-off merge: the repo labels are never probed
  FAIL ci-off merge: no pr edit runs
  FAIL ci-off land: the repo labels are never probed
  FAIL ci-off land: no pr edit runs
```

The red set is exactly the new off-default checks; a regression to always-on cannot pass the suite.
