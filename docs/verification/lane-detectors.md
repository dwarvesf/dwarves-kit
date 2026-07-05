# Proof of done: lane-detector-refinements (SPEC-102 / ID-086)

Two `lib/telemetry/lane-telemetry.sh` detectors stop false-flagging, without being blinded to the real
cases they exist to catch.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | boardless no longer flags a tracked run linked by ID/PR (not raw rid) | PASS |
| 2 | boardless still flags a genuinely board-bypassing run (no rid, no board ID/PR) | PASS |
| 3 | shipped-incomplete no longer flags a full-lane non-UI run whose only un-disposed phase is lite `ui-design` | PASS |
| 4 | shipped-incomplete still flags a run missing a REQUIRED gate | PASS |
| 5 | `tests/test-hooks.sh` + `test-lane-telemetry.sh` + `test-meta.sh` + `test-e2e.sh` green | PASS |

## Implementation

- `_boardless`: on-board if the board contains the rid OR any `ID-NNN`/`PR #N` token from the
  run's ledger (metric 9a).
- `_shipped_incomplete`: delegates to `gate-ledger.sh check <lane> <rid>` (required gates only),
  so run-lite phases never trip it (metric 9b). A4 seam pin updated to assert the `check` call.
- 4 pins added in `tests/test-hooks.sh` (where the detector suite lives).

## Confirmation run-table

| Check | Command | Expected | Observed |
|---|---|---|---|
| 9a false-flag now clean | pin `spec-byid` (row keys ID-007, ledger carries ID-007) | not flagged | PASS |
| 9a real still flags | pin `spec-orphan` (no rid/ID on board) | flagged | PASS |
| 9b false-flag now clean | pin `full-noui` (all required ran, ui-design lite absent) | not flagged | PASS |
| 9b real still flags | pin `full-gap` (missing required `review`) | flagged `full-gap (full)` | PASS |
| existing controls preserved | `spec-ghost` flagged, `spec-done` clean | unchanged | PASS |
| suites | `test-hooks` / `test-lane-telemetry` / `test-meta` / `test-e2e` / `test-orchestrate` | all pass | 452 / 453 / All meta / Golden green / ALL PASS |

## Live corpus (captured 2026-07-02, before -> after)

```
boardless runs:          6 -> 3   (kit-telem-02/03/05 cleared via ledger ID match;
                                    cc-hyg-04, kit-clean-01-startwire, kit-telem-04-dashboard
                                    remain -- no board-linked ID/PR in their ledger, a data gap)
shipped-incomplete runs: 15 -> 0   (every real run had disposed its required gates; only the
                                    lite ui-design was un-disposed, which no longer trips it)
```

Negative control (the detectors still fire): removing the ID/PR match re-flags the tracked
runs (9a); reverting `_shipped_incomplete` to the progress-complete delegation re-flags all 15
(9b) -- both proven by the `-real-still-flags` pins, which use a run with a genuine gap.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh        # detector pins 218-268 (incl. the 4 new + updated seam)
bash lib/telemetry/lane-telemetry.sh misfires   # live: boardless shrinks, shipped-incomplete empties
```

Note: the 3 residual boardless runs are legacy (their ledgers carry no board-linked ID/PR token
this detector can match). Fully clearing them for future runs needs the START line itself to carry
a `board=<ID|PR>` field, which neither this sub-goal nor the shipped SG-01 adds today; that is a
distinct follow-up (add a `board=` field to `gate-ledger.sh start`, tracked in the kit-telem-cleanup
NOTES `## Proposed additions`), not something SG-01 already covers.
