# Verification -- adopt-row-codes

`wrap adopt` exits on a machine code (`ok`, `skip`, `fail`) set where each row is built. The printed ADOPT SUMMARY text is unchanged. `adopted; <FAILED line>` is an explicit `fail`.

## Green run

```
Command: bash tests/test-wrap-adopt-codes.sh
Exit: 0
Output:
  PASS 2: exit codes match the real kit
  PASS 2: failure count matches
  PASS 2: the reworded FAILED row still fails
  test-wrap-adopt-codes: all 20 passed
Verdict: PASS
```

The existing adopt suite, unedited, with its pins:

```
Command: bash tests/test-wrap-adopt.sh
Exit: 0
Output:
  test-wrap-adopt: all 210 passed
Verdict: PASS
```

The suites that source the edited `tests/lib/wrap-stub.sh`:

```
Command: bash tests/test-wrap-cli.sh && bash tests/test-wrap-ladder.sh
Exit: 0
Output:
  test-wrap-cli: all 22 passed
  test-wrap-ladder: all 43 passed
Verdict: PASS
```

```
Command: bash tests/test-operator-pin.sh
Exit: 0
Output:
  operator-pin: 4 passed, 0 failed
Verdict: PASS
```

## Negative control

Run after the commit (`8c52952f`), each mutation restored with `git checkout -- lib/wrap/wrap-adopt.sh`.

```
Command: bash tests/test-wrap-adopt-codes.sh   (reader put back to comparing the row words)
Exit: 1
Output:
  FAIL 2: exit codes match the real kit
  FAIL 2: failure count matches
  test-wrap-adopt-codes: 18 passed, 2 FAILED of 20
Verdict: PASS (the test goes red under the old behavior)
```

```
Command: bash tests/test-wrap-adopt-codes.sh   (adopted; FAILED row coded ok)
Exit: 1
Output:
  FAIL 1: adopted-with-FAILED exits 1
  FAIL 1: six failures
  test-wrap-adopt-codes: 18 passed, 2 FAILED of 20
Verdict: PASS (the explicit fail code is pinned)
```
