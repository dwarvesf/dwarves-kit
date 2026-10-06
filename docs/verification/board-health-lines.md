# Verification -- board health lines match the approved mock

The first live health post carried per-repo inline lists that wrapped; the approved mock shows one short line per item. `lib/sync/sweep/board-health` now builds a hub line with its Hermes mirror comparison (`--hub`), named board lines (`--board`), one archived total, and at most three triage-threshold fault lines (`--triage-open`, `--triage-days`). `--faults-only` keeps only faults, and the warning mark is reserved for faults. `board sweep` forwards the flags as `--health-hub`, `--health-board`, `--health-faults-only`, `--health-triage-open`, `--health-triage-days`.

## Gate table

| Claim | Evidence |
|---|---|
| the hub line shows active, parked, and the mirror count, `= hub` when equal | green run, case hub line |
| a mirror that differs is a fault line and flags attention | green run; negative control 1 |
| a named board shows its status mix and stale count, or its done count when idle | green run, case kanban lines |
| the archived line is one total and is absent on a baseline run | green run, case kanban lines |
| boards over the triage threshold give at most three fault lines, then `+N more boards over threshold` | green run, case over threshold; negative control 2 |
| `--faults-only` shows nothing when clean and only the fault when not | green run, case faults only |
| an operator line that opens with the warning mark is a fault | green run, case operator warning |
| the sweep forwards the new flags | green run, case sweep |

## Green run

```
Command: bash tests/test-board-health.sh
Exit: 0
Output:
  ok   the line is shown once, in place
  ok   --health-hub and --health-board reach the leg
  ok   --health-faults-only reaches the leg
  ok   board health run --help

board-health: 95 passed, 0 failed
Verdict: PASS
```

## Negative controls

Each mutation was applied on a committed tree and reverted with `git checkout --`.

```
Control 1: the mirror comparison always says equal (`if mirrored == ...` became `if True`)
Command: bash tests/test-board-health.sh
Exit: 1
Output:
  FAIL a mirror that differs is a fault line (got 'null', want '⚠️ crew: 3 active, 1 parked · Hermes mirror 6 open ≠ hub')
  FAIL and flags attention (got 'false', want 'true')
board-health: 93 passed, 2 failed
```

```
Control 2: the fault list is not capped at three (`over[:3]` became `over`)
Command: bash tests/test-board-health.sh
Exit: 1
Output:
  FAIL three board lines plus the tail, no more (got '6', want '4')
board-health: 94 passed, 1 failed
```

## Reproduce

```
bash tests/test-board-health.sh
```
