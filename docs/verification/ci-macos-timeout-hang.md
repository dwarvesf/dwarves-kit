# Proof of done: ci-macos-timeout-hang

## What changed

On macos-latest `test-bin-forwarders` and `test-stats-no-persist` ran into the 300 s ceiling in run 40230793961, having passed before `tests/lib/timeout.sh` existed. The perl fallback is the one thing that changed how they run: it moved the command into a new process group and signalled that group. The fallback now keeps the command in the caller's group and, at the limit, prints the live process tree under the command, so a stuck suite names what it waits on. The hang itself did not reproduce on a Mac (see the notes), so this record proves the wrapper behavior, not the CI outcome. Details: `docs/implementation-notes/ci-macos-timeout-hang.md`.

## Gate table

| Claim | Evidence |
|---|---|
| the fallback runs the command in the caller's process group | `test-run-all-timeout` case 11, negative control |
| 124, a process-tree dump and no surviving descendant on a timeout; exit codes and stdin pass through | case 11 block |
| the macOS job's suites run through the fallback and pass with no `timeout` on PATH | stock-macOS blocks |
| the two suites that hung pass through the fallback here | stock-macOS blocks |
| no regression | `run-all.sh --changed` block, Ubuntu 24.04 and 26.04 blocks |

## Run blocks

Stock macOS case: `$NOTIMEOUT` is a directory of symlinks to every tool on PATH except `timeout` and `gtimeout` (loop in the round-one record `docs/verification/ci-green-master.md`).

```
Command: PATH="$NOTIMEOUT" bash tests/test-run-all-timeout.sh
Exit: 0
Output:
  ok: a TERM-ignoring command is killed after the grace period (6s)
test-run-all-timeout: all 16 passed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-test-affected.sh
Exit: 0
Output:
  ok: a red suite is not reported as TIMEOUT
test-test-affected: 74 passed, 0 failed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-test-affected-cache.sh
Exit: 0
Output:
  ok: history grew across runs
test-affected-cache: 17 passed, 0 failed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-test-affected-parallel.sh
Exit: 0
Output:
  ok: second run: 3 cached, the red one re-runs
test-affected-parallel: 41 passed, 0 failed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-bin-forwarders.sh
Exit: 0
Output:
  ok: stats forwarder prints the CLI usage
test-bin-forwarders: all 48 passed, 0 skipped
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-stats-no-persist.sh
Exit: 0
Output:
  PASS  honest-zero: empty ledger returns cleanly + the projection is deterministic (delete output, re-run, same answer)
== 5 passed, 0 failed, 0 skipped ==
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-run-all-changed.sh
Exit: 0
Output:
  ok: KIT_RUN_ALL=1 runs the full glob
test-run-all-changed: all 12 passed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-run-all-time.sh
Exit: 0
Output:
  ok: no --time, no change
test-run-all-time: all 4 passed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-run-all-times.sh
Exit: 0
Output:
  ok: only the red suite ran, red stays red, exit 1 both times
run-all-times: 37 passed, 0 failed
Verdict: PASS
```

```
Command: PATH="$NOTIMEOUT" bash tests/test-run-all-tmpdir.sh
Exit: 0
Output:
  ok: non-zero exit, one clear line, no false pass
test-run-all-tmpdir: all 2 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0
Output:
  3s test-meta-plugin-hooks
run-all: all 16 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro <kit-ci-ubuntu | kit-ci-2604> bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/<suite>.sh'
Exit: 0
Output:
test-run-all-timeout rc=0   (ubuntu 24.04)
test-test-affected rc=0     (ubuntu 24.04)
test-run-all-timeout rc=0   (ubuntu 26.04)
test-test-affected rc=0     (ubuntu 26.04)
Verdict: PASS
```

## Negative control

Run after the fix was committed. The mutation puts `setpgrp(0, 0)` back in the forked child, the old behavior; case 11 goes red on the process-group check and everything else stays green.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-run-all-timeout.sh" "sed -i.bak 's/if (!$pid) { exec @ARGV; exit 127 }/if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }/' tests/lib/timeout.sh && rm -f tests/lib/timeout.sh.bak"
Command: bash tests/test-run-all-timeout.sh
Exit: 0 (green before mutation)
Output:
    ok: kept file holds the cause line the summary dropped, and its path is printed
  [10] a passing run creates no run-all dir
    ok: green run leaves the log root untouched
  [11] the perl fallback of tests/lib/timeout.sh (forced, so it runs where GNU timeout exists too)
    ok: the command runs in the caller's process group
    ok: stdin reaches the command
    ok: exit 7 stays 7, a SIGKILL death is 137
    ok: 124 on a timeout, the live process tree is printed, no descendant survives
    ok: a TERM-ignoring command is killed after the grace period (6s)
  test-run-all-timeout: all 16 passed

Mutation: sed -i.bak 's/if (!$pid) { exec @ARGV; exit 127 }/if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }/' tests/lib/timeout.sh && rm -f tests/lib/timeout.sh.bak
Changed: tests/lib/timeout.sh
Exit: 1 (under mutation, RED expected)
Output:
    ok: kept file holds the cause line the summary dropped, and its path is printed
  [10] a passing run creates no run-all dir
    ok: green run leaves the log root untouched
  [11] the perl fallback of tests/lib/timeout.sh (forced, so it runs where GNU timeout exists too)
    FAIL: caller=92118 command=11394
    ok: stdin reaches the command
    ok: exit 7 stays 7, a SIGKILL death is 137
    ok: 124 on a timeout, the live process tree is printed, no descendant survives
    ok: a TERM-ignoring command is killed after the grace period (6s)
  test-run-all-timeout: 15 passed, 1 FAILED

Restore: git checkout HEAD -- tests/lib/timeout.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert `fix/ci-macos-timeout-hang`. It touches `tests/lib/timeout.sh` and `tests/test-run-all-timeout.sh` only. Nothing is deployed.
