# Implementation notes -- harvest-sweep

Deltas from SPEC-357 (phase 1, kit-side tasks T1 to T19, T13b, T22). Nothing here repeats what the spec already states.

## 2026-09-29 Sweep tests live in their own suite, not in tests/test-hooks.sh
- Context: the Task Breakdown says tests go "in the harvest section of `tests/test-hooks.sh`", and the negative-control table runs `bash tests/test-hooks.sh`. `tests/test-hooks.sh` has no harvest section; the existing harvest tests live in `tests/test-kit-foldin-hooks.sh`. A full `tests/test-hooks.sh` run takes about 220s, and `negctl.sh` runs its test command three times per control.
- Decision/Change: every sweep test goes in a new `tests/test-harvest-sweep.sh`, which `tests/run-all.sh` picks up by its glob with no registration. Each negative control runs `bash lib/gate/negctl.sh <root> "bash tests/test-harvest-sweep.sh" "<mutate>"`. T18's wrap assertions stay in `tests/test-meta.sh`, as the spec says. The existing hook tests in `tests/test-kit-foldin-hooks.sh` are the T1 regression set.
- Why: about 36 controls at three runs of a 220s suite each would cost over six hours, with no added signal.
- Impact: AC16 reads as `bash tests/test-harvest-sweep.sh && bash tests/test-kit-foldin-hooks.sh && bash tests/test-hooks.sh && bash tests/test-meta.sh`.

## 2026-09-29 Baseline test state before T1
- `tests/test-hooks.sh`: 709/709. `tests/test-kit-foldin-hooks.sh`: 97/97.
- `tests/test-meta.sh`: 878/879. The one failure is `docs/FEATURES.md is fresh`: the generated registry lags the spec files already on this branch. It predates this build; the regenerate runs once at the end of the build, after the new files exist.

## 2026-09-29 Validation preflight and per-task re-audit
- The last validate line for rid `harvest-sweep-spec` is a `skipped` NEEDS REVISION entry, so `/kit:execute`'s preflight would dispatch a validator. By operator decision no further validation round runs: the ledger records `validate skipped "operator decision: last folds approved with no further validation round"`, and Status stays APPROVED.
- The per-task `kit:recheck-verifier` re-audit (execute.md step 2c-1, advisory) is not dispatched per task; each task gets one fresh `kit:task-verifier`, and the whole build gets one integration verification at the end.
