# Proof of done: test-affected-parallel

Branch `perf/test-affected-parallel` on master 34b0a10e, code commit b81d0b17. Spec: `docs/specs/SPEC-395-test-affected-parallel.md`. Notes: `docs/implementation-notes/test-affected-parallel.md`.

Verdict summary: `bin/test-affected` now runs the selected suites four at a time, longest first. On one 15-suite selection the wall fell from 726 s to 411 s, with identical stdout and the same exit code. Every case in the new suite and in the neighbouring suites is green, and forcing one job turns the parallel suite red (negative control). The host was shared with other sessions the whole time (load average 10 to 50), so the wall numbers are noisy and the second run had the worse load.

## Wall time, before and after

Fixed selection: a clone of master 34b0a10e with one comment line appended to `lib/wrap/wrap-common.sh`, `--base HEAD --no-cache`. That fans out to 15 suites (`test-wrap-*`, 14 parallel plus the `# serial:` `test-wrap-apply`). Master's script is `git show master:bin/test-affected`, mine is the branch copy, each with its own sibling files, both run from the same clone.

| Script | Wall | Exit | 1-min load, start to end | Suites |
|---|---|---|---|---|
| master (serial) | 726 s | 0 | 10.19 to 23.84 | 15 selected, 15 pass |
| branch, `LAND_CACHE=0` (cold, like master) | 411 s | 0 | 49.88 to 24.91 | 15 selected, 15 pass |
| branch, warm `test-wrap-land` cache | 348 s | 0 | 23.84 to 37.13 | 15 selected, 15 pass |

The warm row is not a fair comparison: `test-wrap-land` caches passed sections, so it took 1 s instead of 117 s. It is kept only because it was the first branch run. The cold row is the like-for-like number: 1.77x faster, on a host that was busier than during master's run.

```
Command: bin/test-affected --base HEAD --no-cache      (master script, then branch script, then branch with LAND_CACHE=0)
Exit: 0, 0, 0
Output: master "15 selected, 15 pass, 0 cached, 0 fail, 0 timeout, 0 uncovered"; stdout of master and branch-cold byte-identical (diff exit 0)
        branch stderr: "test-affected: 15 to run, 4 at a time, 1 serial"
Verdict: PASS (same verdicts suite by suite, shorter wall)
```

Per-suite seconds (timing-history rows), master serial then branch cold. Each suite is slower on the branch because four share the host and the load was 25 to 50; the wall still falls because they overlap.

| Suite | Master (s) | Branch cold (s) |
|---|---|---|
| test-wrap-adopt | 93 | 251 |
| test-wrap-land | 117 | 164 |
| test-wrap-merge | 114 | 167 |
| test-wrap-apply (serial lane) | 96 | 124 |
| test-wrap-ci | 43 | 107 |
| test-wrap-carry | 42 | 97 |
| test-wrap-pull | 63 | 85 |
| test-wrap-rebase | 42 | 51 |
| the other seven | 97 together | 132 together |

The serial `test-wrap-apply` (124 s) runs alone after the batch, so it stays on the critical path; the other fourteen share four workers.

## Suites

```
Command: bash tests/test-test-affected-parallel.sh
Exit: 0
Output: test-affected-parallel: 41 passed, 0 failed
Verdict: PASS
```

Cases: (1) per-suite verdicts, FAIL tail, summary and exit codes under 4 jobs; (2) a barrier that only passes while all its sibling suites run at once; (3) a TIMEOUT in one suite leaves the other three PASS and exits 1; (4) the finish order differs from the name order, yet the lines are s1..s4 and two runs print byte-identical output; (5) longest listed limit first (unlisted = 300), unchanged by `TEST_AFFECTED_TIMEOUT_SECS`; (6) a `# serial:` suite starts after every batch suite ended; (7) job count: full on a quiet host, halved with `KIT_LOAD_STUB=50`, not halved under a higher `KIT_LOAD_WARN`, explicit number kept, junk falls back to 1; (8) history rows, run row and cache unchanged.

```
Command: bash tests/test-test-affected.sh ; bash tests/test-test-affected-cache.sh
Exit: 0 ; 0
Output: test-test-affected: 58 passed, 0 failed ; test-affected-cache: 17 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-run-all-changed.sh ; test-run-all-time.sh ; test-run-all-timeout.sh ; test-run-all-times.sh ; test-host-load-warn.sh ; test-bin-forwarders.sh ; test-run-lock.sh
Exit: 0 for each
Output: all 12 passed ; all 4 passed ; all 8 passed ; 29 passed, 0 failed ; 22 passed, 0 failed ; all 48 passed ; all 27 passed
Verdict: PASS
```

The four `run-all` suites first failed after `tests/run-all.sh` began sourcing `tests/lib/job-count.sh` (their fixtures copied `run-all.sh` alone); each fixture now copies the helper, and nothing else in them changed.

## Negative control

Committed first (b81d0b17). Saved `bin/test-affected` to a scratch path, replaced `JOBS="$(job_count "$REQ")"` with `JOBS=1`, ran the parallel suite, restored with `command cp -f` (never `git checkout --`).

```
Command: bash tests/test-test-affected-parallel.sh      (mutant: job count forced to 1)
Exit: 1
Output: test-affected-parallel: 32 passed, 9 failed
        FAIL tests/test-s2.sh (the barrier suite times out), FAIL: rc=1, "stderr says how many run and how wide", "finish order was: end-s1 end-s2 end-s3 end-s4",
        the quiet-host, halving, threshold and explicit-number cases (each saw "1 at a time")
Verdict: PASS (the control fails as it must: the parallel behavior is what the suite pins)
```

```
Command: cp -f <saved copy> bin/test-affected ; cmp bin/test-affected <saved copy>
Exit: 0
Output: identical; git status shows no change to bin/test-affected
Verdict: PASS (restored)
```

## Not proved here

- No full run: `tests/run-all.sh --all` and `KIT_RUN_ALL=1` were not used (45-minute budget, affected suites only).
- One selection, one run per script. The 1.77x holds under uneven load; a quiet host will give a different ratio. The Linux default stays one job (the job-count helper keeps the flake guard), so CI behavior is unchanged.
