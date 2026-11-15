# Verification -- tiered-verification

Tiered verification for mega-goal runs: node scope `affected`, a lead-committed known-failures list, and one full-suite join per wave on the merged tree (spec: `docs/specs/SPEC-421-tiered-verification.md`).

## Green run

The spec's `## Verification` commands, on the final tree:

```
Command: bash tests/test-known-failures.sh
Exit: 0
Output:
  PASS C4: a red run with no executed count in the log is fail
  PASS C5: exit 1 with no parsed failure is fail
  PASS C5: without failure_line at the base a red run is a plain failure
  All known-failures tests passed.
Verdict: PASS (21 checks, cases C1 to C5)
```

```
Command: bash tests/test-orchestrate-tiered.sh
Exit: 0
Output:
  PASS C7: a head that moved after the join is refused, the join reruns (4 suite runs) and only the rejoined head merges
  PASS C8: verify = tiered with WAVE_ROLLING=1 exits non-zero before any dispatch
  PASS C9: with verify = off the orchestrator output equals the committed golden
  All tiered orchestrate tests passed.
Verdict: PASS (17 checks, cases C6 to C9)
```

```
Command: bash tests/test-orchestrate.sh
Exit: 0
Output:
  ALL PASS
Verdict: PASS (83 checks)
```

```
Command: bash tests/test-config-registry.sh
Exit: 0
Output:
  === 60/60 passed ===
Verdict: PASS
```

The regression check, `RUN_ALL_JOBS=3 RUN_ALL_TIMEOUT_FLOOR_SECS=600 bash tests/run-all.sh --changed --time` (122 suites, host load over 100): 119 ok, 3 red. The three were fixed in the last commit and rerun alone:

```
Command: bash tests/test-no-scattered-ids.sh; bash tests/test-whole-spec-dispatch.sh; bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  test-no-scattered-ids: all 9 passed
  === 37/37 passed, 0 failed ===
  Passed: 120 / 120
Verdict: PASS (the causes were an id in a lib comment, execute.md over its 30000-byte cap, and a stale FEATURES.md)
```

The T0 golden (`tests/fixtures/orchestrate-golden/off.txt`) was captured from the unmodified `orchestrate.sh` in the first commit; C9 diffs a fresh run against it and passes after the edits.

## Negative control

`lib/gate/negctl.sh` with `bash tests/test-known-failures.sh` as the test command; the mutation makes `read` use the branch copy (`git show HEAD:<path>`) instead of the base copy.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-known-failures.sh" "bash <mutate.sh>"
Exit: 0
Output:
  Exit: 0 (green before mutation)
  Exit: 2 (under mutation, RED expected)
  2 failed.
  Exit: 0 (green after restore)
  Verdict: PASS
```

The mutated run fails exactly C2:

```
FAIL C2: read -> 'Skim settings panel wrong|Brand new break|'
FAIL C2: classify newfail -> 'known'
```

## Test plan coverage
| Row | Run / skip reason |
|---|---|
| 1 | node-runs-affected: `tests/test-known-failures.sh`, "C1" checks. Resolver and doc wiring only: the node steps are agent prompts, see implementation notes D6 |
| 2 | known-failures-read-at-base: `tests/test-known-failures.sh`, "C2" checks; red under the negative control |
| 3 | known-failures-edit-guarded: `tests/test-known-failures.sh`, "C3" checks |
| 4 | known-failure-no-retry: `tests/test-known-failures.sh`, "C4" checks |
| 5 | crash-not-masked: `tests/test-known-failures.sh`, "C5" checks |
| 6 | join-once-merged-tree: `tests/test-orchestrate-tiered.sh`, "C6" checks (semantic pair red, two suite runs, nothing merged) |
| 7 | join-head-moved-refused: `tests/test-orchestrate-tiered.sh`, "C7" checks (hook refusal plus rerun, `mega-merge.sh --expect-head`) |
| 8 | rolling-refused: `tests/test-orchestrate-tiered.sh`, "C8" checks |
| 9 | tiered-off-golden: `tests/test-orchestrate-tiered.sh`, "C9" checks against `tests/fixtures/orchestrate-golden/off.txt` |

## Reproduce

`bash tests/test-known-failures.sh && bash tests/test-orchestrate-tiered.sh && bash tests/test-orchestrate.sh && bash tests/test-config-registry.sh`
