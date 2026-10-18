# Proof of done: /kit:debug records the debug gate

## What changed

The `bug` lane requires a `debug` gate (`gate-ledger.sh required bug` prints `build debug`), but no command recorded it. `commands/debug.md` now records `gate-ledger.sh record <rid> debug ran "<one-line root cause>"` in Phase 4 step 6, after the fix is verified. The 3-fix wall section says outright not to record the gate, so an escalation leaves it open. `docs/WORKFLOW.md`, `docs/workflow-paths.md`, `lib/gate/README.md` and the generated `docs/FEATURES.md` row follow.

## Gate table

| Claim | Evidence |
|---|---|
| debug.md records the debug gate once, in Phase 4, with the root cause | `tests/test-gate-vocab-recording.sh` AC7, AC8 |
| the escalation path carries no record call | AC8 |
| the real `check bug` blocks without it and passes with it | AC9 |
| no regression in the touched suites | `run-all.sh --changed` plus single reruns below |
| the test goes red when the record line is removed | negative control below |

## Run table

```
Command: bash tests/test-gate-vocab-recording.sh
Exit: 0
Output:
  PASS the debug record is inside Phase 4, before the 3-fix wall section
  PASS the 3-fix wall section carries no gate-ledger record call
  PASS exactly one debug ran record in the whole file
  PASS check bug blocks on an escalated run (no debug record, exit != 0)
  PASS check bug passes once debug ran is recorded (exit 0)
=== Summary: 31/31 passed ===
Verdict: PASS
```

```
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
Passed: 120 / 120
Verdict: PASS
```

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-gate-vocab-recording.sh" "<delete every line containing 'debug ran' from commands/debug.md>"
Exit: 1 (under mutation, RED expected)
Output:
    FAIL exactly one debug ran record in the whole file
  === Summary: 27/31 passed ===
Restore: git checkout HEAD -- commands/debug.md
Exit: 0 (green after restore, 31/31)
Verdict: PASS
```

The mutation also failed the three AC7 record assertions (literal call, root-cause evidence, rid resolution). The file was restored from HEAD and the suite is green again.

## Not proven

- The prose is read by a model; the suite proves the instruction is present and placed on the resolution path, not that a live agent follows it.
- `run-all.sh --changed` hit its 300s runner ceiling on four slow suites; `test-config-registry` was rerun alone (59/59).
