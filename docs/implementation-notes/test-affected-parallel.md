# Implementation note: test-affected-parallel

Delta from `docs/specs/SPEC-395-test-affected-parallel.md` only; the spec carries the design.

## Two things the spec did not name

- **`# serial:` suites keep their own lane.** `tests/run-all.sh` runs a suite that declares `# serial:` alone, after the parallel batch. The old serial `bin/test-affected` gave every suite that for free, so dropping the rule would have been a silent regression for `test-wrap-apply`, `test-runs-dashboard` and `test-lint-scattered-ids`. The batch now splits the same way.
- **The cache entry is written by the worker, not at collation.** A run interrupted halfway keeps the passes it already finished, which the serial loop also did. The worker gets the cache dir through `TA_CDIR` and the key as an argument, so a cache dir with spaces in its path never goes through `xargs` word splitting.

## Shared helper, and the four fixtures it touched

The job count (default, cap of 4, the Linux default of 1) moved out of `tests/run-all.sh` into `tests/lib/job-count.sh` so both runners share one rule. `tests/run-all.sh` now sources it, so every fixture that copies `run-all.sh` into a throwaway kit must copy the helper too: `test-run-all-time`, `test-run-all-changed`, `test-run-all-timeout` and `test-run-all-times` (two spots) got that one line. Nothing else in those suites changed.

`bin/test-affected` tolerates a missing helper by running one suite at a time. That is a degraded mode for a copied binary, not a supported layout.

## Load halving reads one place

`lib/host/load-warn.sh --over` is a new silent mode: exit 0 when the 1-minute load is over the threshold, 1 otherwise or when it cannot be read. The threshold lookup (`KIT_LOAD_WARN`, then `kit.toml [test].load_warn`, then 16) was already there; the new mode reuses it, so `bin/test-affected` carries no copy. The warning mode keeps its contract of always exiting 0.

An explicit numeric `TEST_AFFECTED_JOBS` is the operator's number and is never halved. Unset or `auto` takes the shared default and the halving.

## Output

Stdout is the old one: one line per suite in selection order (sorted by suite name), the same `PASS`, `CACHED`, `FAIL` and `TIMEOUT` labels, the same summary line. The one addition is a stderr line, `test-affected: N to run, J at a time`, with `(halved: ...)` and `, K serial` when they apply. On a terminal each finished suite also prints one `.` on stderr, as `run-all` does, so a long batch is not silent.

A worker that dies without writing its status file reports `FAIL` with `no status written; the worker died`, never a pass.

## Not changed

- The selection (`--list`), the cache key, the per-suite timeout numbers and the timing-history rows.
- No lock is taken. `bin/test-affected` never held `tests/lib/run-lock.sh`.
