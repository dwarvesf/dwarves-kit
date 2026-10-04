# Implementation note: workflow-sweep

Delta from `docs/specs/SPEC-392-workflow-sweep.md` only; the spec carries the design.

## History reads live in run-all, not a new bin/ file

The goal allowed a run-all verb or a `bin/` script. A new `bin/` entry would have touched the bin census in `tests/test-bin-forwarders.sh` and the contract lint. The helper is `tests/lib/suite-times.sh`, reached as `bash tests/run-all.sh --times p95|expected|tune [--write]`. The verb is handled before the `--all` refusal and the run lock, because it reads a log and runs no suite. The spec's `bin/suite-times` wording is superseded by this.

## The mega dispatch call lives in the driver

The spec guessed the call would be a documented line only. `lib/queue/orchestrate.sh` `cmd_run` now calls `lib/host/load-warn.sh` once per real run (a `--dry-run` preview stays quiet), `|| true`. `commands/mega.md` Step 5 also names the helper. The orchestrate suites were not run (test budget); the call is one fail-open line and `tests/test-host-load-warn.sh` greps for it.

## Choices worth knowing

- **Exit-0 runs only feed p95 and the median.** A 124 line holds the ceiling, and a red line holds a crash time. Either would pull the ceiling up for the wrong reason.
- **`expected` is an estimate.** The log has no per-run wall time, so it takes `max(longest median, sum of medians / jobs)` over the suites about to run. It prints nothing when no suite has history.
- **One timestamp, one load per run.** Every line of a run carries the run's append time and the 1-minute load sampled before the first suite starts, not a per-suite load.
- **`tune` keeps a line only when it carries a `#` comment.** `test-wrap-land 600` had its reason in the header, not on the line, so it now carries an inline comment. Without it the first `tune --write` would have overwritten the hand-set number. A suite with a timeouts line and no history keeps its old number. `tune` with no passing history changes nothing.
- **Config registry rows for all three knobs ship in the load-warn commit.** `KIT_LOAD_WARN`, `KIT_SUITE_TIMES_FILE` and `KIT_SUITE_TIMES_CAP` share one registry section, so they landed together. `KIT_LOAD_STUB` is allowlisted as a test seam.
- **AGENTS.md was not edited.** Its known-hash list in `tests/test-adopt.sh` pins it (R2). The landing pointer lives in `commands/ship.md` and `commands/mega.md` instead.
- **`commands/ship.md` keeps its PR-body steps.** Only the hand publish line became the `bin/wrap land <worktree>` pointer; a plain `git push origin <branch>` stays for the non-worktree case.
- **The 2026-09-30 retro has no action item this sweep covers.** Its host-contention note is a "what hurt" line, not an action row. Three actions in the 2026-10-01 retro are closed.
