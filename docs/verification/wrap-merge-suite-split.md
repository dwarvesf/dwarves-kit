# Verification -- wrap-merge-suite-split

The head-resync cases move out of `tests/test-wrap-merge.sh` into `tests/test-wrap-merge-resync.sh`. No assertion changes: the same 431 checks run, in two suites that each sit well under the per-suite ceiling. The nightly `test-wrap-merge` TIMEOUT (250s) on 2026-11-14 was suite growth plus load noise, not a hang.

## Root cause

| Evidence | Number |
|---|---|
| Nightly `test-wrap-merge` wall time, 11-04 to 11-12 (before the resync section) | 117 to 131 s |
| Nightly wall time on 11-13 (first run holding the resync section, master 98a77e7) | 253 s, killed at the 250 s ceiling |
| Suite alone, same host, before the split | 76 s and 80 s (two runs) |
| Resync section alone | about 30 s of that, 31 cases each running `merge --apply` on a fresh fixture repo |
| Slowest single case in the resync section | 5 s; no hang, no sleep (the settle sleep is stubbed) |
| Other suites vs ceiling, nightly rows only | next worst is `test-wrap-apply` at 0.70 of its ceiling; every other wrap suite is at or under 0.50 |
| Earlier `test-wrap-merge` TIMEOUT rows in suite-times.tsv | 11-09, 11-10, 11-12 (dev runs under host load), so the 250 s ceiling had no headroom for a loaded host |

## Green run

```
Command: bash tests/test-wrap-merge.sh
Exit: 0
Output:
  test-wrap-merge: all 271 passed
  real 41.76
Verdict: PASS
```

```
Command: bash tests/test-wrap-merge-resync.sh
Exit: 0
Output:
  test-wrap-merge-resync: all 160 passed
  real 30.86
Verdict: PASS
```

271 + 160 = 431, the PASS count of the unsplit suite. Both also pass under `/bin/bash` (3.2). With both suites run twice at once (4 concurrent): 44 s and 36 s.

Neighbours the change touches:

```
Command: tests/test-test-affected.sh, -parallel, -cache, test-suites-collect, test-run-all-times, test-meta-docs-registry
Exit: 0 each
Output:
  test-test-affected: 74 passed, 0 failed
  test-affected-parallel: 41 passed, 0 failed
  test-affected-cache: 17 passed, 0 failed
  test-suites-collect: all 12 passed
  run-all-times: 37 passed, 0 failed
  Passed: 120 / 120
Verdict: PASS
```

`docs/reference/FEATURES.md` is regenerated (`feature-registry.sh check --fix`): the wrap command lists one more suite.

## Negative control

The moved cases still guard the code. Mutation: in `lib/wrap/wrap-merge.sh` line 259, `gh pr close ... ; rc=$?` replaced by `true; rc=0` (the resync never closes the PR). Restored with `git checkout`.

```
Command: bash tests/test-wrap-merge-resync.sh   (mutated)
Exit: 1
Output:
  FAIL resync #116: one close
  FAIL resync #115: the handler reopens
  test-wrap-merge-resync: 131 passed, 29 FAILED of 160
Verdict: RED, as required

Command: bash tests/test-wrap-merge-resync.sh   (restored)
Exit: 0
Output:
  test-wrap-merge-resync: all 160 passed
```

Selection control: with an edit to `lib/wrap/wrap-merge.sh`, `bin/test-affected --list` names both `tests/test-wrap-merge.sh` and `tests/test-wrap-merge-resync.sh` (module pick), so the split does not drop the resync cases from a changed-files run.

## Not verified

A real nightly run on the Mini (the job runs the merged master; it was not kicked). The per-suite ceiling for the new suite is 250 s (`bin/test-affected.timeouts`), matching the old one; the old suite's 250 s is unchanged and now holds about 6x headroom alone.
