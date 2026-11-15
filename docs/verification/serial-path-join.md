# Verification -- serial-path-join

The serial path of a tiered mega-goal joins once per DAG level (spec: `docs/specs/SPEC-421-tiered-verification.md` rule 4; deltas: `docs/implementation-notes/serial-path-join.md`). The join runs at the top of each cycle on the base tree, after the level's merges, and halts the loop on a red result before the next level dispatches.

## Green run

```
Command: bash tests/test-orchestrate-serial-join.sh
Exit: 0
Output:
  PASS level: independent sub-goals are level 0, a dependent of both is level 1
  PASS level: a chain reaches level 2 and a diamond takes its deepest dependency (level 3)
  PASS level: a three-node fan-out cycle ends at once
  PASS serial join: three sub-goals in two levels run the suite twice, once per level, and all dispatch
  PASS serial join: each run is on the base tree in a throwaway worktree, level 0 then level 1
  PASS serial join: no throwaway worktree is left
  PASS serial join: a red level join halts the loop before the next level dispatches, naming the new failure
  PASS serial join: one blocked event for the level
  PASS serial join: a red join leaves no throwaway worktree either
  PASS serial join: level 0 is joined once, after SG-02, not after SG-01
  PASS serial join: a re-run after a red halt joins the level again and dispatches nothing
  PASS serial join: a level-1 node that ran first is joined only after level 0 closes, level 0 then level 1
  PASS serial join: an unreachable origin (stale base) halts the loop without running the suite
  PASS serial join: level 1 with fewer executed checks than level 0 is red even though its failure is known
  PASS serial join: a failure the known-failures list names does not stop the loop
  PASS serial join: a crash with no parsed failure is red, never read as known
  PASS serial join: a tiered run with no join_cmd halts at the first level close
  PASS serial join: SIGTERM mid-join removes the worktree, marks the level blocked and starts nothing more (exit 143)
  PASS serial join: with verify = off no suite runs and nothing about a join is printed
  ---
  All serial join tests passed.
Verdict: PASS (19 checks)
```

```
Command: bash tests/test-orchestrate-tiered.sh
Exit: 0
Output:
  ---
  All tiered orchestrate tests passed.
Verdict: PASS (29 checks)
```

```
Command: bash tests/test-orchestrate.sh
Exit: 0
Output:
  ----
  ALL PASS
Verdict: PASS (82 checks)
```

```
Command: bash tests/test-wave-converge.sh
Exit: 0
Output:
  ---
  All wave-converge tests passed.
Verdict: PASS (9 checks)
```

```
Command: bash tests/test-known-failures.sh
Exit: 0
Output:
  ---
  All known-failures tests passed.
Verdict: PASS (25 checks)
```

The regression check, once as a whole on the final tree:

```
Command: RUN_ALL_JOBS=4 bash tests/run-all.sh --changed --time
Exit: 0
Output:
  run-all: all 78 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

An earlier run of the same command had one red suite, `test-no-scattered-ids`, for a spec id in two `lib` comments; the comments were reworded and the whole run repeated green.

## Fails without the change

The new suite against `lib/queue/orchestrate.sh` as it is on master (`git show origin/master:lib/queue/orchestrate.sh`): 14 of the 19 checks go red (no level table, no join). The checks that stay green are the ones that assert nothing runs (`verify = off`, the fan-out cycle bound on the new helper's absence, the known-list pass-through, no leftover worktree).

```
Command: git show origin/master:lib/queue/orchestrate.sh > lib/queue/orchestrate.sh && bash tests/test-orchestrate-serial-join.sh
Exit: 14
Output:
  FAIL serial green: rc=0 runs=0 dispatched='SG-01 SG-02 SG-03 '
  FAIL serial red: rc=0 runs=0 dispatched='SG-01 SG-02 SG-03 '
  FAIL serial red rerun: rc=0 runs=0 dispatched='SG-01 SG-02 SG-03 '
  FAIL serial order: rc=0 runs=0
  FAIL serial stale: rc=0 runs=0
  FAIL serial crash: rc=0 dispatched='SG-01 SG-02 SG-03 '
  14 failed.
Verdict: PASS (the new tests are red on the old code)
```

## Negative control

`lib/gate/negctl.sh` with `bash tests/test-orchestrate-serial-join.sh` as the test command. Six one-line mutations of the new code; each ran green before, red under the mutation, green after the restore.

| Mutation | Red under mutation |
|---|---|
| A red join in `_serial_join_run` returns 0, so the loop goes on | 6 failed |
| The join is never enabled (`_SERIAL_TIERED` forced to 0) | 12 failed |
| A level joins before every lower level is checked (the `minpending` break removed) | 7 failed |
| The green marker is ignored, so a level joins on every cycle | 2 failed |
| The executed-count floor removed (`--prev-count` dropped) | 1 failed (the count check) |
| The origin-tip check disabled (a stale base is accepted) | 1 failed (the stale-base check) |

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate-serial-join.sh" "bash <mutate-N.sh>"
Exit: 0
Output:
  Exit: 0 (green before mutation)
  Exit: 6 (under mutation, RED expected)
  Exit: 0 (green after restore)
  Verdict: PASS
```

## Reproduce

`bash tests/test-orchestrate-serial-join.sh && bash tests/test-orchestrate-tiered.sh && bash tests/test-orchestrate.sh && bash tests/test-wave-converge.sh && bash tests/test-known-failures.sh`
