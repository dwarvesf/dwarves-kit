# Proof of done: ci-timeout-test-env

CI run 40235193048 failed two suites. `test-run-all-timeout` case 8 expects a 1 s ceiling from the timeouts file, but the macOS job exports `RUN_ALL_TIMEOUT_FLOOR_SECS=300`, which raised it to 300 s, so the slow fixture passed and the case went red. `test-mktemp-template-guard` flagged the new `mktemp -d` in that suite for missing its `|| exit 1` guard (rule R3). The suite now unsets the floor before its cases, its fixture also copies `tests/lib/run-lock.sh` (the `run-all.sh: line 63` noise), and the call carries its guard.

## Green run

```
Command: env RUN_ALL_TIMEOUT_FLOOR_SECS=300 bash tests/test-run-all-timeout.sh; bash tests/test-run-all-timeout.sh; bash tests/test-mktemp-template-guard.sh
Exit: 0
Output:
floor-run rc=0
plain=0
=== 11 passed, 0 failed ===
Verdict: PASS
```

## Negative control

Mutation: `git show origin/master:tests/test-run-all-timeout.sh > tests/test-run-all-timeout.sh`, run by `lib/gate/negctl.sh` after the commit, with the floor exported as on the macOS job.

- With the old suite, case 8 fails: `FAIL: rc=0 out=.../k6/tests/run-all.sh: line 63: ...` (the 1 s ceiling was floored to 300 s).
- Restore: `git checkout HEAD -- tests/test-run-all-timeout.sh`, then green again. Exit: 0 (green after restore).

## Rollback

Revert the squash commit. Case 8 then fails again on any run that exports the floor, which is the macOS CI job.

Verdict: PASS
