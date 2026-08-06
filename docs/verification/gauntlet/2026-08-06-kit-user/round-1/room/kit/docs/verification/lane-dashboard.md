# Proof of done: lane-telemetry render (SPEC-099, kit-telemetry SG-04)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | render prints header + type->lane table + ASCII flow + gate coverage | `test-lane-telemetry.sh`: header/`routing flow`/`gate coverage` all present | PASS |
| AC2 | run counts correct | test: 3-run seeded corpus -> "3 runs"; type rows sum to 3 | PASS |
| AC3 [filter] | `render <lane>` narrows to matching runs; coverage respects it | test: `render full` -> "2 runs", "filter=full", excludes the normal-lane run | PASS |
| AC4 [filter no-match] | honest message, no crash | test: `render nosuchlane` -> "no runs match" | PASS |
| AC5 [graceful-empty NC] | empty LOG_DIR -> honest "no runs recorded", no crash | test: temp empty dir -> "no runs recorded", no error/unbound/syntax token | PASS |
| AC6 [no regression] | suites green; report/misfires/trace unchanged | `test-meta` 578/578, `test-hooks` 438/438 | PASS |

## Implementation

- `lib/telemetry/lane-telemetry.sh` -- new `render()` (reuses `_rows()`); dispatch `render) render "$@"`;
  usage + header comment updated. Optional positional filter narrows table + flow + coverage.
- `tests/test-lane-telemetry.sh` (new) -- 13 pins incl. the graceful-empty + filter-exclusion
  negative controls.
- `docs/research/2026-07-02-lane-usage-snapshot.md` -- dated capture (full + filtered).
- `.github/workflows/test.yml` -- new suite wired into CI.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-lane-telemetry.sh` | 0 | 18/18 passed (incl. metachar-literal, coverage-dedup, filter-over-inclusion pins) |
| `bash tests/test-meta.sh` | 0 | 578/578 passed |
| `bash tests/test-hooks.sh` | 0 | 438/438 passed |
| `NO_COLOR=1 bash lib/telemetry/lane-telemetry.sh render` | 0 | full routing diagram (captured in the snapshot doc) |
| `NO_COLOR=1 bash lib/telemetry/lane-telemetry.sh render full` | 0 | filtered to the 5 full-lane runs |
| `DWARVES_KIT_LOG_DIR=<empty> bash lib/telemetry/lane-telemetry.sh render` | 0 | "no runs recorded yet" (graceful) |

## Run detail (capture 1: full render, real corpus)

See `docs/research/2026-07-02-lane-usage-snapshot.md` for the committed full + filtered
captures. Shape:

```
Lane routing  (N runs, window <first> .. <last>)
  task-type            lane       runs  gates r/s/o    ships
  ...
  routing flow (task-type -> lane -> gates):
    <types> --> <lane> (K runs)
  gate coverage (runs recording each phase as ran):
    <phase> <count>
```

## Reproduce

```
bash tests/test-lane-telemetry.sh
bash lib/telemetry/lane-telemetry.sh render          # full
bash lib/telemetry/lane-telemetry.sh render full     # filtered
```
