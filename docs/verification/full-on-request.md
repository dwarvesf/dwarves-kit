# Verification: full-on-request

`kit:system-verifier` and the System level of `/kit:verify` are restored, gated on an explicit `--full`; without it the level records `SKIPPED: full suite runs only on request (--full)`. `--full` on execute and ship runs the whole suite in their test step. The affected selection stays the default, and no config key requests the whole suite.

## Green run
```
Command: bash tests/test-right-arm-parity.sh
Exit: 0
Output:
  PASS AC6 [NO-ORPHAN]: system-verifier is dispatched by at least one file under commands/
  PASS AC7: verify.md Step 6 records SKIPPED without --full
  PASS AC7: verify.md Step 6 dispatches kit:system-verifier only with --full
  PASS AC7: no config default stands in for the --full request
  PASS AC7: execute.md runs the whole suite only with --full
  PASS AC7: ship.md runs the whole suite only with --full
=== 43/43 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-every-step-review.sh; bash tests/test-meta-review-verifiers.sh; bash tests/test-operator-pin.sh; bash tests/test-meta.sh
Exit: 0 for each
Output:
=== 17/17 passed, 0 failed ===
All meta tests passed.
operator-pin: 4 passed, 0 failed
Passed: 943 / 943
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (runner), 57 suites run
Output:
run-all: FAILED -> test-known-failures test-operator-pin test-proof-capture-route
Verdict: PASS for this change. test-known-failures C1 is red on master since #1203 (fixed by the dead-code PR); test-operator-pin flagged the new parity asserts, now pinned and green above; test-proof-capture-route fails case 6 (signal handling) and is not touched here.
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-right-arm-parity.sh" "<sed removing the --full gate sentence from commands/verify.md Step 6>"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
    FAIL AC7: verify.md Step 6 records SKIPPED without --full
    FAIL AC7: verify.md Step 6 dispatches kit:system-verifier only with --full
Verdict: PASS
```
Removing the gate sentence turns AC7 red; negctl restored the file.

## Not proven
- No live `/kit:verify --full` dispatch; the command is a prompt, checked by its text.
