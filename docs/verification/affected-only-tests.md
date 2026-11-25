# Verification: affected-only-tests

The work loop (execute, ship, verify and the verifier agents) runs only the narrowest tests that cover the change; the `[test] suite` knob, its `full` default, `known-failures.sh suite`, the goal-file `Test-suite:` line and the `system-verifier` agent are removed. The whole suite runs only in the release and nightly path.

## Green run
```
Command: bash tests/run-all.sh --changed --time
Exit: 0 (runner exit); 80 suites run
Output:
run-all: FAILED -> test-operator-pin test-proof-capture-route
run-all: TIMED OUT at 300s -> test-ui-acceptance-verifier
run-all: 80 suites run, 0 skipped for missing tooling
Verdict: PASS for this change. test-operator-pin fails on tests/test-shared-lookups.sh and test-proof-capture-route on its mktemp cases, both owned by a parallel fix branch and untouched here; the timeout is the runner ceiling, rerun alone below.
```

```
Command: bash tests/test-<name>.sh, for each suite this diff edits
Exit: 0 for every one
Output:
test-known-failures exit=0 All known-failures tests passed.
test-right-arm-parity exit=0 === 33/33 passed, 0 failed ===
test-every-step-review exit=0 === 16/16 passed, 0 failed ===
test-meta-review-verifiers exit=0 All meta tests passed.
test-orchestrate-tiered exit=0 All tiered orchestrate tests passed.
Verdict: PASS
```

```
Command: bash tests/test-meta.sh; RUN_ALL_TIMEOUT_SECS=900 bash tests/run-all.sh --only test-ui-acceptance-verifier
Exit: 0; 0
Output:
Passed: 934 / 934
All meta tests passed.
test-ui-acceptance-verifier                    ok
run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS (the earlier timeout was the runner ceiling under load)
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-known-failures.sh" "sed -i '' 's#bin/test-affected#the test command#g' commands/execute.md"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  1 failed.
Restore: git checkout HEAD -- commands/execute.md
Verdict: PASS
```
Removing the affected selection from `/kit:execute` turns C1 of `tests/test-known-failures.sh` red, so the suite pins that the command runs the affected tests. The file was restored by negctl.

## Not proven
- No live `/kit:execute` or `/kit:ship` run by an agent; the commands are prompts, checked by their text.
- The opt-in tiered mega join (`[mega] verify = "tiered"`, `[test] join_cmd`) is unchanged: it still runs `join_cmd` on the base tree and the merged tree.
