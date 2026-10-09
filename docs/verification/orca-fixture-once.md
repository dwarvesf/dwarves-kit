# Verification -- orca-fixture-once

`tests/test-orchestrate-orca.sh` builds its fixture tree once and clones it per case, and `to_gate_pending` replays its ticks once and copies the finished state to each caller. No assertion changed.

## Green run
```
Command: bash tests/test-orchestrate-orca.sh
Exit: 0
Output:
PASS view-fallback
PASS mutation-check
Results: 30 passed, 0 failed
(wall 71s on the Mini; history p95 before the change: 288s)
Verdict: PASS
```

## Negative control
```
Command: sed -i '' '366s/{print lf; exit}/{if(lf=="gate")lf="auto"; print lf; exit}/' lib/queue/orchestrate.sh && bash tests/test-orchestrate-orca.sh
Exit: 1
Output:
FAIL AC2: four task-create: expected '4' got '3' | ...
FAIL AC7: one gate-create on the accept Task: expected '1' got '0' | SG-03 is HELD: no match for /^HELD gate gate_/ ...
FAIL AC16: a pending gate keeps the runner ticking: expected '0' got '1' | ...
FAIL status-and-dry-run: dry-run names the accept Task: no match for /task SG-03:accept/ ...
FAIL gate-per-dispatch: rework blocks: expected 'BLOCKED rework' got 'BLOCKED no self-claim' | ...
Results: 25 passed, 5 failed
Verdict: PASS (RED as expected)
```
The mutation parses every `gate` sub-goal as `auto` in `orchestrate.sh`. AC7, AC16 and gate-per-dispatch all consume the shared `to_gate_pending` state, and all three went red, so the copied state still catches a broken gate. Restored with `git checkout -- lib/queue/orchestrate.sh`; `git status` clean after.

## Not proven
- The before figure is a p95 under shared load, the after figure one run on a quieter host: not a controlled A/B.
- Case isolation holds by construction (each caller gets its own `cp -R` copy with paths rewritten); no control mutates the shared tree from one case and checks another.
