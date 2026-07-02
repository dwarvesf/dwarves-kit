# Proof of done: mega-start-wiring (SPEC-101 / ID-085)

The automated mega dispatch (`lib/orchestrate.sh cmd_run`) emits a `gate-ledger start`
per sub-goal, so mega-dispatched runs are tracked (real lane/type) in `lane-telemetry`,
not `?`. Root cause of the SPEC-073 eval's untracked-run finding.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | The driver emits a `gate-ledger start` per dispatched sub-goal (mirrors assign.md) | PASS |
| 2 | A dispatched run carries a START line with a real `lane=`/`type=` (not `?`) | PASS |
| 3 | `lane-telemetry report` counts the run under its lane, `untracked (no START): 0` | PASS |
| 4 | Negative control: a goal file with no `**Branch:**` emits NO START (run stays `?`) | PASS |
| 5 | `--dry-run` emits no START (side-effect-free) | PASS |
| 6 | `tests/test-orchestrate.sh` + `tests/test-meta.sh` green | PASS |

## Implementation

- `lib/orchestrate.sh`: new `_emit_start <dir> <id>` helper, called in `cmd_run` after the
  `executing` event and before the session spawns. Derives the rid from the goal file's
  `**Branch:** <type>/<slug>` (`${branch#*/}`), classifies lane + type from the sub-goal
  title (chosen == classified, no human override in the automated path), calls
  `gate-ledger.sh start`. Advisory + non-fatal: no goal file / no `**Branch:**` -> WARN + skip.
- `tests/test-orchestrate.sh`: TEST 14 pins the START line, the no-branch negative control,
  and the dry-run side-effect-free case.
- Docs: `README.md` orchestrate entry + `commands/mega.md` Step 5 note the START emission.

## Confirmation run-table

| Check | Command | Expected | Observed |
|---|---|---|---|
| START emitted + tracked | `orchestrate.sh run <fixture>` (isolated `DWARVES_KIT_LOG_DIR`) | ledger has a START with `lane=full type=spec-feature` | `START \| lane=full classified=full type=spec-feature ctype=spec-feature repo=dwarves-kit` |
| counted, not `?` | `lane-telemetry.sh report` | `untracked (no START): 0`, run under `full` | `runs: 1 ... untracked (no START): 0`; `full 1 ...` |
| negative control | run with a goal file lacking `**Branch:**` | WARN, no START, run left `?` | WARN emitted; `runs/` dir not created |
| dry-run | `orchestrate.sh run <fixture> --dry-run` | no START | no `runs/` dir |
| suites | `bash tests/test-orchestrate.sh`; `bash tests/test-meta.sh` | all pass | ALL PASS; 578/578 |

## Run detail (captured 2026-07-02)

Positive run (isolated log dir, mock `claude`):

```
[orchestrate] [telemetry] SG-01 START recorded (rid=kit-clean-fx1-startwire lane=full type=spec-feature).
[orchestrate] running SG-01 in a fresh session ...
[orchestrate] STOP: SG-02 is a gate sub-goal ...

# ledger runs/kit-clean-fx1-startwire.log:
2026-07-02T14:26:04Z | START | lane=full classified=full type=spec-feature ctype=spec-feature repo=dwarves-kit

# lane-telemetry report:
runs: 1   lane-misrouted: 0   type-misrouted: 0   shipped: 0   untracked (no START): 0
lane          runs   mis  gates  skip   ovr  ships
full             1     0      0     0     0      0
```

Negative control (goal file with no `**Branch:**`):

```
[orchestrate] [telemetry] WARN: SG-01 goal file has no '**Branch:**' header; cannot derive rid, skipping START (run will be '?' in lane-telemetry).
--- runs dir contents (expect empty) ---
(no runs dir)
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-orchestrate.sh   # TEST 14: START pins + negative control + dry-run
bash tests/test-meta.sh          # integrity + doc-impact
# live: a fixture megagoal with a goal file carrying **Branch:**, run under an isolated
# DWARVES_KIT_LOG_DIR + a mock CLAUDE_CMD, then `lane-telemetry.sh report` (untracked = 0).
```

Note: pre-existing already-`?` runs in the operator's real corpus are not backfilled (this
fix tracks runs going forward); no telemetry re-run is in scope (needs days of real usage).
