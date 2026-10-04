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

## Convergence-gate fixes: delta

- **Cache key.** `bin/test-affected` now records `<suite>\t<changed path>` for every changed path that picked a suite (`$TMP/pickers`) and hashes each one into that suite's key. A key that already hashed a path the suite names is unchanged. The cost: a suite's cache entry now also depends on which other changed paths picked it, so the same suite picked by a different diff misses once. That is the safe direction.
- **Runner expansion.** `expand_runner` copies the rule in `tests/run-all.sh` (the `# runner-suites:` names, else the sibling glob). It runs after selection, so `--list`, the cache and the timeouts all see the area suites; the runner itself is never listed. In the pickers file the expanded suite keeps the original changed path, not the "runner ..." reason text.
- **tune.** A suite's new limit is the candidate (`max(60, 2 x p95)`, 5 or more exit-0 samples) only when it is not lower than the current line, or with `--allow-lower`; an exit-124 row raises the limit to at least its seconds, with or without samples. A kill row of N seconds only guarantees the limit is N, which kills the suite again; a higher number needs a real measurement or a hand-set comment line. The brief wording was "at least the limit it was killed at", and that is what is implemented. A suite with no line is added only with 5 samples or a kill.
- **Header.** `tune --write` replaces everything from a `# Rule:` line up to `# One hand-set` (or the first blank line) with a generated Rule and Source block, so the stale "three full parallel runs" text goes on the first write, and later writes replace the generated block in place. A header with no `# Rule:` line gets the block appended after its comments.
- **History rows.** Run rows reuse the six-field format: the suite field is `run:<entry>`, the seconds field is total wall, and two extra fields carry `kind=run` and `selected=<N>`. Suite statistics skip `run:` rows. `--times runs` prints the last 20 run rows and computes p50 and p95 over those 20, per entry point, not over the whole log.
- **Where rows are written.** `bin/test-affected` calls the helper only when `tests/lib/suite-times.sh` sits next to its own `bin/`, so fixture kits that copy only the binary write nothing. `tests/test-test-affected.sh` points `KIT_SUITE_TIMES_FILE` at a temp dir because it runs the real binary from a fixture repo.
- **Load warning in run-all.** One call before the parallel phase, guarded by the helper existing, for every mode. The warning goes to stderr like the other callers.
- **ledger-key reference.** The reference scan skips lines whose first character is `#`, so the name sits on a code line in `tests/test-lane-telemetry.sh`. `lib/gate/ledger-key.sh` is not in this branch's base, so the pick was checked with a temporary untracked file.
