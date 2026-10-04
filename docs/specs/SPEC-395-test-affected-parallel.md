# Spec: run the selected suites in parallel in bin/test-affected

Generated: 2026-10-04
Status: VALIDATED (design: one runner already does this; no validation fan-out run)
Lane: normal
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 06 (R18, R19; NOTES item 1).

## Problem

`bin/test-affected` runs the suites it selected one after another. The same selection under `tests/run-all.sh` runs four at a time, longest first. A diff that selects 8 to 15 suites pays the sum of their wall times, and the slow suites (a few minutes each) decide the total only when they start early. The kit-speed destination (a 15 to 25 minute loop) is not reachable while the per-change loop is serial.

## Design

- **Parallel batch.** Every selected suite that is not CACHED runs through `xargs -P <jobs>`, the same worker pattern as `tests/run-all.sh` (the script re-invokes itself as `--run-one`). Each worker owns its own log and status files and writes the PASS cache entry the moment its suite passes, so an interrupted run keeps the passes it finished.
- **Longest first.** The schedule sorts by the suite's line in `bin/test-affected.timeouts` (unlisted = 300), then by name. A suite that declares `# serial:` runs alone after the batch drains, as in `run-all`.
- **Job count.** One shared helper, `tests/lib/job-count.sh`, now serves both runners: `TEST_AFFECTED_JOBS` (else `RUN_ALL_JOBS`) is used as is; empty or `auto` gives the platform default (macOS: cores, capped at 4; elsewhere: 1). When the 1-minute load is over the load-warn threshold the count is halved (minimum 1). The threshold comes from `lib/host/load-warn.sh --over`, a new silent mode of the helper that already reads `KIT_LOAD_WARN`, `kit.toml [test].load_warn` and the default, so no caller copies the config lookup. An explicit `TEST_AFFECTED_JOBS` is the operator's override and is never halved.
- **Same behavior per suite.** Cache read and write, the per-suite timeout, `TIMEOUT` versus `FAIL`, the suite-times rows, the run row (total wall) and the exit codes are unchanged. Output is collated after the batch in selection order (sorted by suite name), so the stdout lines and the summary are stable whatever the finish order. One line on stderr says `N suites, J at a time`.
- **No new lock.** `bin/test-affected` never took `tests/lib/run-lock.sh`, and still does not. A suite that takes it itself (`test-wrap-land`) queues behind another holder exactly as before.

## Verification

```
bash tests/test-test-affected.sh          # existing cases still hold under the parallel runner
bash tests/test-test-affected-parallel.sh # verdicts and exit code, TIMEOUT isolation, stable order, longest-first, serial lane, job count and load halving
bash tests/test-test-affected-cache.sh    # cache and history rows unchanged
bash tests/test-run-all-changed.sh        # run-all still reads its job count (shared helper)
bash tests/test-host-load-warn.sh         # the new --over mode, the warning unchanged
# wall: bin/test-affected --no-cache on one fixed selection, master's script vs this one, same verdicts
# negative control: force the job count to 1 in a saved copy; the parallel test fails; restore with cp -f
```
