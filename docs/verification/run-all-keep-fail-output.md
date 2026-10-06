# Proof of done: run-all keeps a failed suite's full output

## What changed

`tests/run-all.sh` wrote each suite's output to a temp dir, deleted it on exit, and showed only
the lines matching `FAIL` plus the last 8 lines. A failing suite whose cause line never says
FAIL (test-orchestrate-orca printed `[AC1] --backend claude exits 0: expected '0' got '1'`, then
only `FAIL AC1`) lost the one line that names the cause. The nightly reads only run-all's stdout.

Now a failed suite's whole log is copied to `<kit log root>/run-all/<UTC stamp>-<pid>/<suite>.out`
and the path is printed under that suite's FAIL block. The root comes from `kit_resolve_log_dir`
(`lib/telemetry/kit-log-dir.sh`), so `DWARVES_KIT_LOG_DIR` / `KIT_LEDGER_DIR` keep tests hermetic.
The dir is created only when a suite failed. Pass output, timing files, parallelism, exit codes
and the existing FAIL-lines-plus-tail summary are unchanged. A timeout is not a FAIL block and
is not kept.

## Gate table

| Claim | Evidence |
|---|---|
| a failed suite's full output survives, cause line included | case [9] in `tests/test-run-all-timeout.sh` |
| the printed path points at the kept file | case [9] |
| a passing run creates no `run-all` dir | case [10] |
| the other run-all suites still hold | run table below |
| the new case is load-bearing | red run and negative control below |

## Run table

```
Command: bash tests/test-run-all-timeout.sh
Exit: 0
Output:
[9] a failed suite's full output is kept, including a cause line that never says FAIL
  ok: kept file holds the cause line the summary dropped, and its path is printed
[10] a passing run creates no run-all dir
  ok: green run leaves the log root untouched
test-run-all-timeout: all 10 passed
Verdict: PASS
```

```
Command: bash tests/test-run-all-changed.sh; bash tests/test-run-all-time.sh; bash tests/test-run-all-times.sh
Exit: 0
Output:
test-run-all-changed: all 12 passed
test-run-all-time: all 4 passed
run-all-times: 29 passed, 0 failed
Verdict: PASS
```

## Red before the fix

The new test run against `origin/master:tests/run-all.sh`:

```
Command: bash <scratch>/tests/test-run-all-timeout.sh   (run-all.sh = origin/master)
Exit: 1
Output:
[9] a failed suite's full output is kept, including a cause line that never says FAIL
  FAIL: rc=1 kept= out=...
test-run-all-timeout: 9 passed, 1 FAILED
Verdict: RED as expected
```

## Negative control

The mutation restores the master run-all.sh; the block below came from `lib/gate/negctl.sh`, run after the commit.

```
Command: bash lib/gate/negctl.sh <root> "bash tests/test-run-all-timeout.sh" "git show origin/master:tests/run-all.sh > tests/run-all.sh"
Exit: 0 (green before mutation)
Changed: tests/run-all.sh
Exit: 1 (under mutation, RED expected)
Output:
  run-all: FAILED -> test-nofailword
  test-run-all-timeout: 9 passed, 1 FAILED
Restore: git checkout HEAD -- tests/run-all.sh
Exit: 0 (green after restore)
Verdict: PASS
```
