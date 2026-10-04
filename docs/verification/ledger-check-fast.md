# Verification: ledger-check-fast

Proof of done for the `gate-ledger.sh check` verdict cache (SPEC-391). Baseline is `lib/gate/gate-ledger.sh` on `master` (202b00af), extracted with `git archive master lib kit.toml` into a scratch directory so master and the branch run side by side against the same ledgers.

Host: the Mini under load from other sessions (load average 25 to 55 during every measurement, listed beside each number). Wall times therefore carry noise; the A/B runs interleave master and branch so load hits both alike, and the CPU column (user plus sys) does not depend on load.

## Profile (before)

`BASH_XTRACEFD=7 PS4='+ $EPOCHREALTIME ...' bash -x gate-ledger.sh check full <rid> 7>| trace` (the lane derivation runs under `2>/dev/null`, so plain `bash -x` hides it), counted by source line:

| Step | Spawns |
|---|---|
| `normalize_phase` pipeline, 4 per required phase, 12 phases | 48 |
| `_ld_array` `grep -Eq`, once per phase name | 14 |
| `lane_rows` `grep -qxF`, once per phase | 13 |
| `check` ledger `awk`, once per required phase | 12 |
| `kit.toml` reads (`_kit_toml_get` `awk`) | 10 |
| `dirname`, `tr` at startup | 6 |
| Total on master | 103 |

After the change: 55 on a miss (the `normalize_phase` fast path) plus 10 cache bookkeeping spawns (70 traced), 21 on a hit.

## Recorded run

Output parity against master over a fixture set: 5 lanes (tiny, normal, full, bug, backfill) x 6 ledger shapes (all ran, all override, all skipped, one gate missing, every other gate, no gates) plus an empty ledger, a ledger with a non-ledger line, an absent ledger, a ledger of another lane, an unknown lane (`mega`), a wrong-case lane, a missing rid and a missing lane, each with and without `--kit-lanes`, from the worktree (project `.kit.toml` tracked and clean) and from a non-git directory. Each case runs master once, then the branch cold (cache removed), warm and warm again; stdout, stderr and exit code are compared byte for byte.

```
Command: bash parity.sh        # cache removed before every case
Exit: 0
Output: cases=236 (each: master vs cold, warm, warm2) diffs=0
Verdict: PASS (708 comparisons, empty diff)
```

```
Command: KEEP=1 bash parity.sh   # cache kept across cases, so later cases hit entries written earlier
Exit: 0
Output: cases=236 (each: master vs cold, warm, warm2) diffs=0
        entries in cache at end: 96
Verdict: PASS (708 comparisons, empty diff; 96 cached entries prove the hits were real)
```

## Recorded run

Timing, 10 interleaved rounds of `check full ledger-check-fast` (the 12-gate full lane, the real log dir and the real `.kit.toml`), from `timing2.sh`. `warm` = cache hit, `cold` = cache removed before the call (a miss plus the cache write).

```
Command: bash timing2.sh full ledger-check-fast
Exit: 0
Output: uptime before: 43.73 39.43 54.97   after: 39.00 38.56 54.48
        master       wall median= 277ms max= 629ms | cpu median= 293ms
        after-warm   wall median= 122ms max= 182ms | cpu median= 111ms
        after-cold   wall median= 288ms max= 515ms | cpu median= 246ms
Verdict: PASS (warm median 122 ms, under 200 ms; master 277 ms on the same host and load)
```

A second set, 10 sequential calls each at a lighter load (bench: one script, `bash gate-ledger.sh check full ledger-check-fast`):

```
Command: bash bench.sh 10 <gate-ledger.sh> check full ledger-check-fast
Exit: 0
Output: load 27.59 34.12 81.26   branch, warm : median=85ms  max=92ms   (82..92)
        load 25.70 33.62 80.81   master       : median=223ms max=254ms  (213..254)
Verdict: PASS (warm median 85 ms; master 223 ms)
```

A third set, taken on a saturated host (load 57 to 61, other sessions running their suites), to show the ratio holds under contention: master 939 ms (max 1273) against 275 ms warm (max 502), CPU 414 ms against 127 ms. An earlier saturated run with this sub-goal's own suites in parallel gave 862 ms against 398 ms. These sets are not the pass criterion (200 ms is a wall bound on a normal host); the goal's "about 2.2 s" is this regime, spawn latency on a saturated host, and it did not reproduce on a quiet one.

Cold (a miss) is about equal to master in wall time and 16% lower in CPU: the `normalize_phase` saving is paid back by the key, the cache read and the write. Misses happen once per ledger change.

## Recorded run

The suite that encodes parity, the four invalidation controls and the corrupt-cache cases:

```
Command: bash tests/test-gate-ledger-check-cache.sh
Exit: 0
Output: PASS P1 warm output + exit code equal cold across 25 lane x ledger cases
        PASS P1 every warm call is a cache hit (no rewrite)
        PASS N1 appending the missing gate flips fail -> pass
        PASS N2 editing [lane.normal] flips pass -> fail (new required phase)
        PASS N3 editing gate-ledger.sh changes the result (cached message not replayed)
        PASS N4 an inode swap at the same size and mtime flips fail -> pass
        PASS N5 an in-place same-size rewrite inside the mtime second is seen
        PASS C1 garbage cache: correct answer ... C8 cache path is a directory: correct answer
        Passed: 34 / 34
Verdict: PASS
```

## Negative control

The four invalidation controls are N1 to N4 above: each warms a verdict, changes one key input, and the result flips (fail to pass, pass to fail, new message, fail to pass). N4 pins its own precondition (same size, different inode) before it flips.

The suite itself must go red when the cache is wrong. The branch was committed first (db456963), then `lib/gate/gate-ledger.sh` was mutated, the suite run, and the file restored with `command cp -f` from a saved copy (`git diff --quiet` clean after each):

```
Command: mutate "ck_id" to drop the inode from the key; bash tests/test-gate-ledger-check-cache.sh
Exit: 1
Output: FAIL N4 an inode swap at the same size and mtime flips fail -> pass
        Passed: 33 / 34
Verdict: PASS (RED as required)
```

```
Command: mutate "ck_fp" to a constant; bash tests/test-gate-ledger-check-cache.sh
Exit: 1
Output: FAIL N2 editing [lane.normal] flips pass -> fail (new required phase)
        FAIL N3 editing gate-ledger.sh changes the result (cached message not replayed)
        FAIL N6 removing the operator overlay invalidates the entry
        Passed: 31 / 34
Verdict: PASS (RED as required)
```

```
Command: mutate the 2 s write guard out of _check_cache_put; bash tests/test-gate-ledger-check-cache.sh
Exit: 1
Output: FAIL N5 a ledger touched under 2 s ago is not cached
        Passed: 33 / 34
Verdict: PASS (RED as required)
```

```
Command: mutate the key to drop the --kit-lanes field; bash tests/test-gate-ledger-check-cache.sh
Exit: 1
Output: FAIL N6 --kit-lanes and the overlay answer differently, cold and warm
        Passed: 33 / 34
Verdict: PASS (RED as required)
```

## Recorded run

Corrupt cache: C1 to C8 in the suite write garbage, a wrong-identity entry, a matching key with a malformed result, an empty phase list, shell metacharacters in the phase list, a truncated file, an empty file and a directory at the cache path. Each time `check` returns master's exact answer and no temp file is left (C10).

```
Command: bash tests/test-gate-ledger-check-cache.sh | grep -E 'C[0-9]+ '
Exit: 0
Output: PASS C1 garbage cache: correct answer
        PASS C2 entry with the wrong identity: correct answer
        PASS C3 matching key, malformed result: correct answer
        PASS C4 matching key, empty phase list: correct answer
        PASS C5 matching key, junk in the phase list: correct answer
        PASS C6 truncated cache: correct answer
        PASS C7 empty cache: correct answer
        PASS C8 cache path is a directory: correct answer
        PASS C9 a good cache is written again after the fallbacks
        PASS C10 no temp file is left behind in the log dir
Verdict: PASS
```

## Recorded run

The suites `bin/test-affected --list` picks for the diff (every suite that references `gate-ledger.sh`, `lane-telemetry.sh`, or sits in `lib/gate`), run on the committed head, three at a time, `tests/test-meta.sh` (the runner) replaced by its area suites. `test-ship-gate-impl-notes` first ran red (case 8, see the implementation note) and green after the pin was rewritten.

```
Command: bash runsuites.sh <60 suites from bin/test-affected --list>
Exit: 0 for every suite the runner recorded (58, including test-meta-docs-registry rerun on the head with this proof present: exit 0 in 183 s); test-wave-rid-check and test-weekend-batch finished with an all-pass recap, their runner exit lines were lost when the batch was cut off
Output: test-hooks 826/826, test-lane-telemetry 67/67, test-gate-ledger-check-cache 34/34,
        test-meta-docs-registry 120/120, test-ship-gate-impl-notes 16/16, test-ship-gate-fail-closed,
        test-ship-gate-coverage-map, test-gate-ledger-history, test-gate-ledger-plan-record,
        test-gate-ledger-report, test-gate-opt-in, test-gate-opt-out, test-gate-outcome,
        test-gate-validate-round, test-gate-vocab-recording, test-ledger-durability,
        test-ledger-substrate, test-meta-goal-ledger, test-lane-classify, test-lanes-data,
        test-mega-merge, test-config-stamp, test-e2e, and the rest of the list, all exit 0
Verdict: PASS (no suite red on the head)
```

## Not proven

- A same-size, same-inode, same-second rewrite is invisible to the key by design; the 2 s write guard covers the realistic window (record, check, edit, check). A forger who restores the mtime can append a `ran` line anyway.
- `tests/run-all.sh --all` was not run (the sub-goal's test budget forbids it).
- The first-call (miss) path is not faster in wall time; the lane derivation still costs 55 spawns there. Rewriting `lane-data.sh` without spawns is out of scope (SPEC-391).
