# Verification -- host-test-slots

Every suite worker of `tests/run-all.sh` and `bin/test-affected` takes a slot of a host-wide counting semaphore (`tests/lib/host-slots.sh`) before it runs one suite. Concurrent runs from several worktrees share the slots, so their per-run caps no longer add up. Trigger: five agent sessions ran the suite at once on a 14-core Mac Mini, 20 suites in parallel, load 150.

## Green run

The slot suite, under bash 5 and bash 3.2:

```
Command: bash tests/test-host-slots.sh
Exit: 0
Output:
  PASS all 5 holders finished (enter 5, leave 5)
  PASS max concurrency is exactly 2 (saw 2)
  PASS every slot released afterwards (left: 0)
  PASS acquire got the slot a dead pid held
  PASS a fresh pid-less slot is still waited on
  PASS an old pid-less slot is reclaimed
  PASS the waiter has not entered while the holder is alive
  PASS the waiter entered only after the holder left
  PASS a waiter notes its wait once in the log given (lines: 1)
  PASS no slot dir is created
  PASS second acquire in the same process tree returns at once
  PASS two sessions with different TMPDIR share one slot dir (<user-tmp>/dwarves-kit-test-slots)
  === 12/12 passed, 0 failed ===
Verdict: PASS
```

```
Command: /bin/bash tests/test-host-slots.sh
Exit: 0
Output:
  === 12/12 passed, 0 failed ===
Verdict: PASS
```

Both runners, end to end, with the gate on:

```
Command: KIT_TEST_HOST_SLOTS=4 bin/test-affected --no-cache
Exit: 0
Output:
  PASS tests/test-test-affected-parallel.sh
  PASS tests/test-test-affected-replay.sh
  PASS tests/test-test-affected.sh
  test-affected: 18 selected, 18 pass, 0 cached, 0 fail, 0 timeout, 0 uncovered
Verdict: PASS
```

## Negative control

Run after each change was committed, each mutation restored with `git checkout -- tests/lib/host-slots.sh`:

| Mutation | Expected | Result |
|---|---|---|
| `host_slot_acquire() { return 0; }` | concurrency case red | `FAIL max concurrency is exactly 2 (saw 5)`, 6/11 passed |
| slot dir from `${TMPDIR:-/tmp}` only, no `getconf DARWIN_USER_TEMP_DIR` | shared-dir case red | `FAIL two sessions with different TMPDIR share one slot dir`, 11/12 passed |

Both restored to green (12/12).
