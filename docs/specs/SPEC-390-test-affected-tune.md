# Spec: tune test-affected selection and timeouts

Generated: 2026-10-04
Status: VALIDATED (design: obvious, data-driven mapping and one data file; no validation fan-out run)
Lane: normal
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 03 (D4: per-suite timeout = 2 x measured p95, floor 60 s). Premise correction R4: `bin/test-affected` already picks `tests/test-meta.sh` only when a changed path is a meta input, so the work is mapping those inputs to the SG-02 area suites, not removing an `always` line.

## Problem

A changed path that is a meta input picks the `tests/test-meta.sh` runner, and `tests/run-all.sh` expands that into all eight area suites. `test-meta-docs-registry` alone takes about 145 s, so a one-line doc edit pays for every area. Separately, a suite that is slow but green can hit a flat 300 s ceiling under load and report as a failure, and the two runners keep their own timeout numbers (`bin/test-affected` a flat 300, `tests/run-all.sh` a `test-meta*) 900` arm).

## Design

- **Per-area mapping.** A meta input picks the area suites that read it. Two sources, both deterministic, no model call: (1) the existing reference scan already picks any area suite that names the path or a long basename; (2) a new `meta_areas` table in `bin/test-affected` lists what the areas read by glob or scan (file loops, `git ls-files` scans, the installer run, the registry inputs), derived from the suites' own paths. A meta input neither source attributes still picks the runner, never nothing. A path every area scan excludes (the dated archives) picks no area.
- **No always-run area suite.** The registry freshness pin is mapped by its inputs, and `hooks/ship-gate.sh` already refuses a push that moves a registry input without a fresh `docs/FEATURES.md`. The tree-wide lints that guard every diff keep their own `# always:` header.
- **One timeout file.** `bin/test-affected.timeouts`: `<suite> <seconds>` lines, 2 x the p95 of five parallel full runs on this host, floor 60, with the load average recorded in its header. `bin/test-affected` and `tests/run-all.sh` both read it at runtime (run-all drops its hardcoded 900 arm). `TEST_AFFECTED_TIMEOUT_SECS` and `RUN_ALL_TIMEOUT_SECS` still override every suite. A suite with no line gets 300 s.
- **TIMEOUT is not FAIL.** `bin/test-affected` prints `TIMEOUT <suite> (limit Ns)`, counts it apart in the summary, and still exits 1. `tests/run-all.sh` already prints `TIMEOUT (Ns)` with the limit and now takes that limit from the file.

## Verification

```
bash tests/test-test-affected.sh          # mapping, fallback, archive exclusion, TIMEOUT, overrides
bash tests/test-run-all-timeout.sh        # run-all reads the data file; TIMEOUT line carries the data-file limit
bash tests/test-run-all-changed.sh        # --changed still expands a runner pick
# replay: bin/test-affected --list over the last 10 merged PRs, before vs after; zero missed area suites
# negative control: delete one meta_areas arm; the replay reports a miss; restore; the miss is gone
```
