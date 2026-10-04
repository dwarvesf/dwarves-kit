# Verification -- land-sections

`tests/test-wrap-land.sh` is now ten section functions behind a driver (`tests/lib/land-sections.sh`). `LAND_ONLY=<ERE>` selects sections, `LAND_JOBS` (default 4) runs them as parallel child processes that each own a TMPD, and a per-section pass cache skips unchanged sections. Same 435 checks, same final line. No production code under `lib/wrap/` changed.

## Green run
| Run | Command | Exit | Result | Wall | Load at start |
|---|---|---|---|---|---|
| Serial, master file (baseline) | `bash tests/test-wrap-land.sh` on c466f3fc | 0 | all 435 passed | 112 s | 14 |
| Serial, new file | `LAND_JOBS=1 LAND_CACHE=0 bash tests/test-wrap-land.sh` | 0 | all 435 passed | 116 s | 22 |
| Parallel x4, new file, bash 5.3 | `LAND_CACHE=0 bash tests/test-wrap-land.sh` | 0 | all 435 passed | 46 s | 12 |
| Parallel x4, new file, /bin/bash 3.2 | `/bin/bash tests/test-wrap-land.sh` (cache empty) | 0 | all 435 passed | 97 s | 31 |
| One section | `LAND_CACHE=0 LAND_ONLY=prgate bash tests/test-wrap-land.sh` | 0 | all 27 passed | 7.2 s | 14 |
| Cached rerun, nothing changed | `bash tests/test-wrap-land.sh` | 0 | 10 sections, 0 ran, 10 cached (435 checks credited) | 0.26 s | 20 |

The machine is shared, so wall times move with load; the serial and parallel x4 rows were run back to back. Both bash versions print the same 435 PASS lines as the master file (sorted PASS-line diff against the baseline run is empty).

```
Command: LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 0
Verdict: PASS (test-wrap-land: 10 sections, 10 ran, 0 cached (0 checks credited); all 435 passed; bash 5.3 and /bin/bash 3.2)
```

```
$ LAND_CACHE=0 LAND_ONLY=prgate bash tests/test-wrap-land.sh | tail -3
test-wrap-land: LAND_ONLY='prgate' selected 1 of 10 sections
test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
test-wrap-land: all 27 passed
```

## Cache
| Step | Result |
|---|---|
| Run twice, no change | second run: `10 sections, 0 ran, 10 cached (435 checks credited)`, `all 435 passed`, 0.26 s |
| Append one comment line to `lib/wrap/wrap-land.sh` | `10 sections, 10 ran, 0 cached (0 checks credited)`, `all 435 passed`, no `SKIP` line |
| `git checkout -- lib/wrap/wrap-land.sh`, rerun | `10 sections, 0 ran, 10 cached` again (the old keys still match) |
| `LAND_CACHE=0`, or `CI=1` | every section runs; `CI=1 LAND_CACHE=1` opts back in |
| Cache file holds `garbage`, `PASS 0`, `PASS abc` or `FAIL 18`; cache dir unwritable; key path is a directory | the section runs; none is credited |
| `LAND_ONLY=zzz` | exit 64, `matches no section` |

```
Command: bash tests/test-wrap-land.sh (twice), then the same after one comment line is added to lib/wrap/wrap-land.sh
Exit: 0
Verdict: PASS (unchanged tree: all 10 sections cached, 435 credited; changed lib: all 10 rerun)
```

## Negative control
Commit first, then break `lib/wrap/wrap-land.sh` by inserting `return 0` as the first line of `_land_pr_checks_gate`, and run the full suite with the cache ON (the default).

| Run | Sections | Failing checks | Final line |
|---|---|---|---|
| Broken tree, first run | 10 ran, 0 cached | PG3 x4, PG4b x3, PG4c x3 (10 checks, the same set master fails) | `425 passed, 10 FAILED of 435`, exit 1 |
| Broken tree, second run | 9 cached (408 credited), 1 ran | the same 10 | `425 passed, 10 FAILED of 435`, exit 1 |

The failing section (`prgate`) is never recorded and is rerun every time. The nine sections that pass under the broken tree are cached under the broken tree's key, so they cannot be credited once the tree is restored.

```
Command: bash tests/test-wrap-land.sh with _land_pr_checks_gate returning 0 immediately
Exit: 1 (as expected under the break)
Verdict: PASS (the same 10 checks fail as on master; no failing section is credited from cache; final line reads FAILED)
```
`lib/wrap/wrap-land.sh` was restored with `git checkout -- lib/wrap/wrap-land.sh`; `git status` was clean.

## Other suites
| Command | Exit | Result |
|---|---|---|
| `bash tests/test-wrap.sh` (sums every `tests/test-wrap-*.sh`; shares `tests/lib/wrap-stub.sh`; counts PASS lines, so it sets `LAND_CACHE=0`) | 0 | all 2019 passed (land 435) |
| `bash tests/test-proof-negctl.sh` (`negctl.sh` now exports `LAND_CACHE=0`) | 0 | all 38 passed |
| `bash tests/test-mutation-smoke.sh` (`mutation-smoke.sh` now exports `LAND_CACHE=0`) | 0 | 32 passed |
| `bash tests/test-meta.sh` | 0 | all meta tests passed |

`tests/lib/wrap-stub.sh` is unchanged. The only other consumer of the land suite is `bin/test-affected`, which runs it whole and reads the exit code.

## Not proven
- The master file's one-line final summary is the only output contract kept. The `LAND_ONLY` and `sections ... cached` lines are new and print before it.
- The cache key hashes all of `lib/`, `bin/`, `tests/lib/`, `commands/wrap.md`, the suite file, bash and git versions. A tool the suite calls from `PATH` (`jq`, `sed`) is not in the key.
- A serial run at load 22 hit a pre-existing flake: a detached `git maintenance` raced `land_cached`'s `cp -R` and two checks went red. The suite now disables `maintenance.auto` and `gc.auto` for its own git calls; the runs above came after that change.
- Old cache entries are never pruned (about 10 bytes each, gitignored under `tests/.cache/`).
- An interrupt kills the driver's `xargs` and its direct children only; a grandchild `wrap land` process may finish on its own.
