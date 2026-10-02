# Verification -- wrap-runner-parallel

`tests/test-wrap.sh` runs its suites concurrently (`WRAP_JOBS`, default 4) and prints them in glob order with the same summed counts.

| Check | Command | Exit | Verdict |
|-------|---------|------|---------|
| Green run | `bash tests/test-wrap.sh` | 0 | PASS: `test-wrap: all 2019 passed`, 2:21 wall |
| Green run (system bash 3.2) | `/bin/bash tests/test-wrap.sh` | 0 | PASS: `test-wrap: all 2019 passed` |
| Negative control | `exit 1` inserted in `tests/test-wrap-cli.sh`, then `bash tests/test-wrap.sh` | 1 | RED: runner exits 1, prints the FAILED-format line on stderr |

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS (test-wrap: all 2019 passed)
```

## Negative control
```
Command: bash tests/test-wrap.sh (with `exit 1` as the first command of tests/test-wrap-cli.sh)
Exit: 1
Verdict: RED as expected (stderr: test-wrap: 1997 passed, 0 FAILED of 1997)
```
Revert -> RED -> restore: a suite that exits nonzero without printing a FAIL line still fails the runner, same as the serial runner. Restored with `git checkout -- tests/test-wrap-cli.sh`.

## Not proven
- Wall-time gain on other machines; the 2:21 figure is one run on one Mac with WRAP_JOBS=4.
