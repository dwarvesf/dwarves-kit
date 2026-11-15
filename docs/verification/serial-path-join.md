# Verification -- serial-path-join

The serial path of a tiered mega-goal joins once per DAG level (spec: `docs/specs/SPEC-421-tiered-verification.md` rule 4; deltas: `docs/implementation-notes/serial-path-join.md`). The join runs after the level's merges, on the base tree, and halts the loop before the next level on a red result.

## Green run

```
Command: bash tests/test-orchestrate-serial-join.sh
Exit: 0
Output:
  PASS level: independent sub-goals are level 0, a dependent of both is level 1
  PASS level: a dependency cycle ends (capped), never loops
  PASS serial join: three sub-goals in two levels run the suite twice, once per level, and all dispatch
  PASS serial join: each run is on the base tree in a throwaway worktree, level 0 then level 1
  PASS serial join: no throwaway worktree is left
  PASS serial join: a red level join halts the loop before the next level dispatches, naming the new failure
  PASS serial join: one blocked event for the level
  PASS serial join: level 0 is joined once, after SG-02, not after SG-01
  PASS serial join: a failure the known-failures list names does not stop the loop
  PASS serial join: a crash with no parsed failure is red, never read as known
  PASS serial join: a tiered run with no join_cmd halts at the first level close
  PASS serial join: SIGTERM mid-join removes the worktree, marks the level blocked and starts nothing more (exit 143)
  PASS serial join: with verify = off no suite runs and nothing about a join is printed
  ---
  All serial join tests passed.
Verdict: PASS (13 checks)
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

## Fails without the change

The new suite against the previous `lib/queue/orchestrate.sh` (`git show HEAD~1:lib/queue/orchestrate.sh`): 10 of the 13 checks go red (the level helper is missing and no join runs), the `verify = off` and no-leftover-worktree checks stay green.

```
Command: git show <base>:lib/queue/orchestrate.sh > lib/queue/orchestrate.sh && bash tests/test-orchestrate-serial-join.sh
Exit: 1
Output:
  FAIL level: cycle did not end
  FAIL serial green: rc=0 runs=0 dispatched='SG-01 SG-02 SG-03 '
  FAIL serial red: rc=0 runs=0 dispatched='SG-01 SG-02 SG-03 '
  FAIL serial crash: rc=0 dispatched='SG-01 SG-02 SG-03 '
  FAIL serial nocmd: rc=0 runs=0
  FAIL serial interrupt: rc=0 left=0 events '' dispatched='SG-01 SG-02 SG-03 '
  10 failed.
Verdict: PASS (the new tests are red on the old code)
```

## Negative control

`lib/gate/negctl.sh` with `bash tests/test-orchestrate-serial-join.sh` as the test command, three mutations of the new code, each restored and re-run green.

| Mutation | Result under mutation |
|---|---|
| A red level join returns 0 (`_serial_join` final `return 1` becomes `return 0`) | RED, 3 failed (the loop runs on through the red level, two blocked events, a crash is not halted) |
| The join never fires (`_SERIAL_TIERED` forced to 0) | RED, 8 failed (no suite run, nothing halts, no interrupt, no join_cmd refusal) |
| The join fires after every sub-goal (the unchecked-sibling guard removed) | RED, 4 failed (level 0 is joined after SG-01, the red level is joined late) |

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate-serial-join.sh" "bash <mutate-N.sh>"
Exit: 0
Output:
  Exit: 0 (green before mutation)
  Exit: 2 (under mutation, RED expected)
  Exit: 0 (green after restore)
  Verdict: PASS
```

## Reproduce

`bash tests/test-orchestrate-serial-join.sh && bash tests/test-orchestrate-tiered.sh && bash tests/test-orchestrate.sh && bash tests/test-wave-converge.sh`
