# Verification: run-lock signal reset

The nightly regression on the Mini failed the signal cases of test-board-sweep, test-board-sweep-mirror, test-proof-capture-route and lib-proof-capture-test-proof-capture, and killed test-ui-acceptance-verifier at its 300s ceiling.

## Root cause

`tests/lib/run-lock.sh` re-runs the runner as `bash "$script" "$@" <&0 &` from a non-interactive shell. That `&` starts the child with INT and QUIT ignored, and an ignored signal stays ignored through every exec below it, so every suite under run-all inherits it. Measured through the real chain (mini.probes stage, launcher, run-all) with a BASH_ENV probe that prints each bash's dispositions: the first `bash tests/run-all.sh` has INT default, its re-exec child and every suite below it have INT=IGN QUIT=IGN. Suites that send INT to their own tool (exit 130 wanted) saw it swallowed. CI sets `CI` and skips the lock, so the suites passed there. The earlier vps-mon fix reset the dispositions at the launcher, which was never where they were lost.

## Green run

Stage function from mini-probes and the real launcher, branch cloned fresh, heartbeat and failure marker redirected so nothing posts.

```
Command: bash tests/test-run-lock.sh
Exit: 0
Output:
  === the locked child gets default INT and QUIT ===
    PASS INT is default in the locked child
    PASS QUIT is default in the locked child
  test-run-lock: all 29 passed
Verdict: PASS
```

```
Command: stage + launcher, KNR_ONLY=board-sweep, KNR_BRANCH=fix/run-lock-signal-reset
Exit: 0
Output:
  2026-11-27 04:56:36 cloned fix/run-lock-signal-reset at 65f34b70
  test-board-sweep-mirror                        ok
  test-board-sweep                               ok
  run-all: all 5 suites passed, 0 skipped for missing tooling
  2026-11-27 04:56:56 PASS
Verdict: PASS
```

```
Command: stage + launcher, KNR_ONLY=proof-capture, KNR_BRANCH=fix/run-lock-signal-reset
Exit: 0
Output:
  run-all: 3 suites, 4 at a time, 0 serial
  run-all: all 3 suites passed, 0 skipped for missing tooling
  2026-11-27 04:58:43 PASS
Verdict: PASS
```

```
Command: stage + launcher, KNR_ONLY=ui-acceptance-verifier, KNR_BRANCH=fix/run-lock-signal-reset
Exit: 0
Output:
  2026-11-27 05:02:19 run-all exit 0
  test-ui-acceptance-verifier                    ok
  run-all: all 1 suites passed, 0 skipped for missing tooling
  2026-11-27 05:02:19 PASS
Verdict: PASS
```

## Negative control

The same stage and launcher on master 25324c31 reproduces the nightly:

```
Command: stage + launcher, KNR_ONLY=test-board-sweep, KNR_BRANCH=master
Exit: 1
Output:
  test-board-sweep-mirror                        FAIL (rc=1)
        !   FAIL INT: exit 0 (want 130)
  test-board-sweep                               FAIL (rc=1)
        !   FAIL INT: exit 0 (want 130)
  run-all: FAILED -> test-board-sweep-mirror test-board-sweep
Verdict: FAIL (red on master, as required)
```

`negctl.sh` on the new test with the old run-lock.sh restored:

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-run-lock.sh" "git show 25324c31:tests/lib/run-lock.sh > tests/lib/run-lock.sh"
Exit: 1 (under mutation)
Output:
  FAIL INT is default in the locked child
  FAIL QUIT is default in the locked child
  test-run-lock: 27 passed, 2 FAILED of 29
  Restore: git checkout HEAD -- tests/lib/run-lock.sh, exit 0 (green after restore)
Verdict: PASS
```

## ui-acceptance ceiling

The suite is not stuck. It takes 178 to 208s alone and 270 to 310s in the four-wide nightly run (suite-times history: 304, 270, 284, 307, 309s), so halving the step limit to 3000 did not clear the 300s default. A hand-set 600s ceiling (2 x the worst clean sample) is added to `bin/test-affected.timeouts`, the same way test-wrap-land is.
