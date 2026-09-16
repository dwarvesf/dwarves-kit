# Proof of done: run-all.sh --time

`tests/run-all.sh --time` appends each suite's elapsed whole seconds to its line in the collated report and prints a `run-all: slowest:` block of the ten worst after it. The worker stamps `date +%s` deltas into `$OUTDIR/<name>.time` next to `<name>.status`; only the collate loop reads them, and only under the flag. The flag is stripped out of the argument list before the positional parsing, so it may sit before or after the mode argument and combines with `--all`, `--only` and `--changed`. Without it the output is byte-identical to the runner before this change, which case 4 below pins by diffing the two runners over one fixture kit.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-run-all-time.sh` | 0 | Verdict: PASS |
| `bash tests/test-run-all-timeout.sh` | 0 | Verdict: PASS |
| `bash tests/test-run-all-changed.sh` | 0 | Verdict: PASS |
| `bash tests/run-all.sh` (bare, diff-scoped) | 0 | Verdict: PASS |
| `bash tests/run-all.sh --all --time` | 0 | Verdict: PASS |

```
test-run-all-time: all 4 passed
test-run-all-timeout: all 6 passed
test-run-all-changed: all 8 passed
run-all: all 10 suites passed, 0 skipped for missing tooling
run-all: all 150 suites passed, 0 skipped for missing tooling
```

The full run also exercised the feature it adds:

```
run-all: slowest:
  93s test-config-seams
  83s test-hooks
  72s test-orchestrate
  58s test-meta
  51s test-wrap
  51s test-spec-reserve
  41s test-runaway-guards
  30s test-tier4-close
  28s test-config-registry
  26s test-install-modules
```

## Negative control

NEGATIVE CONTROL: `git checkout origin/master -- tests/run-all.sh`, then `bash tests/test-run-all-time.sh`. Exit 1, three of four cases red:

```
[1] each suite line carries its own elapsed seconds
  FAIL: rc=0 out=run-all: 2 suites, 4 at a time, 0 serial
test-quickfixture                              ok
test-slowfixture                               ok
[2] a slowest block follows the report, worst first
  FAIL: block= out=run-all: 2 suites, 4 at a time, 0 serial
[3] --time combines with --only
  FAIL: rc=0 out=run-all: 1 suites, 4 at a time, 0 serial
test-slowfixture                               ok
test-run-all-time: 1 passed, 3 FAILED
```

Case 4 stays green under the control by design: it asserts the unflagged output matches `origin/master`, which is trivially true when the runner IS `origin/master`. `git checkout HEAD -- tests/run-all.sh` restored the branch version and the suite returned to `all 4 passed`.

## Not proven

- Sub-second resolution. Seconds come from `date +%s`, so a 0s line means "under a second", not "instant". Apple bash 3.2 has no `EPOCHREALTIME`.
- Timing accuracy under parallelism. The stamp measures each worker's own wall clock, so under `RUN_ALL_JOBS > 1` the numbers include contention and do not sum to the run's wall clock.
- Linux. Every run above was on macOS with the default `RUN_ALL_JOBS`.
