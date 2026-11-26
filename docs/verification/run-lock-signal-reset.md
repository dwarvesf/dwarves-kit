# Verification: run-lock signal reset

The nightly regression on the Mini failed the signal cases of test-board-sweep, test-board-sweep-mirror, test-proof-capture-route and lib-proof-capture-test-proof-capture, and killed test-ui-acceptance-verifier at its 300s ceiling.

## Root cause

`tests/lib/run-lock.sh` re-runs the runner as `bash "$script" "$@" <&0 &` from a non-interactive shell. That `&` starts the child with INT and QUIT ignored, and an ignored signal stays ignored through every exec below it, so every suite under run-all inherits it. Measured through the real chain (mini.probes stage, then the launcher, then run-all): the first `bash tests/run-all.sh` has INT default, the re-exec child has INT=IGN QUIT=IGN, and so does every suite. Suites that send INT to their own tool (exit 130 wanted) saw it swallowed. CI sets `CI` and skips the lock, so the suites passed there. The earlier vps-mon fix reset the dispositions at the launcher, which was never where they were lost.

## Green run

Real stage function and real launcher, branch cloned fresh, heartbeat and failure marker redirected:

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-run-lock.sh` | 0 | test-run-lock: all 29 passed |
| stage + launcher, KNR_ONLY=board-sweep | 0 | all 5 suites passed (incl. test-board-sweep, test-board-sweep-mirror) |
| stage + launcher, KNR_ONLY=proof-capture | 0 | all 3 suites passed (incl. test-proof-capture-route, lib-proof-capture-test-proof-capture) |
| stage + launcher, KNR_ONLY=ui-acceptance-verifier | 0 | passed in 208s alone, under the new 600s ceiling |

## Negative control

| Run | Result |
|-----|--------|
| stage + launcher, KNR_ONLY=test-board-sweep on master 25324c31 | FAIL test-board-sweep-mirror and test-board-sweep: `FAIL INT: exit 0 (want 130)` |
| `negctl.sh` on tests/test-run-lock.sh with the old run-lock.sh restored | RED, 27 passed 2 FAILED (INT and QUIT not default), green again after restore |

## ui-acceptance ceiling

The suite is not stuck. It takes 178 to 208s alone and 270 to 310s in the four-wide nightly run (suite-times history: 304, 270, 284, 307, 309s), so halving the step limit to 3000 did not clear the 300s default. A hand-set 600s ceiling (2 x the worst clean sample) is added to `bin/test-affected.timeouts`.
