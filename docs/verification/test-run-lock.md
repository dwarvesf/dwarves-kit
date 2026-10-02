# Verification -- test-run-lock

A per-user mkdir lock (`tests/lib/run-lock.sh`) queues the top-level test runners so only one heavy kit run executes at a time on a host.

| Check | Command | Result |
|---|---|---|
| New lock suite | `bash tests/test-run-lock.sh` | `test-run-lock: all 27 passed` |
| Land suite unchanged | `bash tests/test-wrap-land.sh` | `test-wrap-land: all 435 passed` |
| Wrap runner unchanged | `bash tests/test-wrap.sh` | `test-wrap: all 2019 passed` |
| run-all passes args through the lock | `bash tests/run-all.sh --only run-lock` | `run-all: all 1 suites passed` |
| Negative control | acquire made a no-op | `test-run-lock: 21 passed, 6 FAILED of 27` |

## Green run
```
Command: bash tests/test-run-lock.sh
Exit: 0
Verdict: PASS (test-run-lock: all 27 passed)
```

## Negative control
```
Command: tests/lib/run-lock.sh acquire loop replaced by "while false"; bash tests/test-run-lock.sh
Exit: 1
Verdict: RED (test-run-lock: 21 passed, 6 FAILED of 27: acquire, wait line, give-up, non-owner release)
```
The helper was restored with `git checkout -- tests/lib/run-lock.sh` and the suite is green again.

## Not proven
- Contention between two real `run-all.sh` runs on one host: covered by the holder/waiter case with a stand-in job, not by two full suites.
- A recycled pid reads as a live holder; that case ends at the `KIT_TEST_LOCK_WAIT` give-up, not a failed run.
