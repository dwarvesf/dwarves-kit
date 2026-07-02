# SPEC-102: lane-telemetry detector refinements (false-flag fixes)

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

Two `lib/lane-telemetry.sh` detectors false-flag, so `misfires` is noisy (SPEC-073 eval
metric 9, ID-086):

- **boardless** (`_boardless`) matches a run to the board by the raw rid
  (`grep -qF "$rid" "$board"`). Real board rows key on `ID-NNN` / `PR #N`, not the rid, so a
  tracked run whose row exists (e.g. `kit-telem-*`, `kit-clean-01-startwire` -> ID-085) is
  wrongly flagged.
- **shipped-incomplete** (`_shipped_incomplete`) asks `gate-ledger.sh progress` whether the
  run is "complete". `progress` counts ALL plan phases including run-lite ones, so a full-lane
  NON-UI run whose only un-disposed phase is the lite `ui-design` trips the detector (and by
  the same mechanism nearly every real run flags, because lite phases are rarely recorded).

## Solution

Both fixes are surgical adjustments to the detector's match/disposition key; neither detector
is rewritten, and neither is blinded to the real case it exists to catch.

### boardless: match by rid OR ledger-carried ID/PR (metric 9a)

A run is on-board if the board file contains the rid (unchanged; the `[run <rid>]` convention
still works) **OR** any `ID-NNN` / `PR #N` token that appears in the run's own ledger. Real
runs carry their board item's ID/PR in a gate/action reason (verified: `kit-telem-02..05`
carry `ID-067`/`ID-085`/...); matching those against the board clears the tracked runs while a
genuinely board-bypassing run (no rid, no board-linked token) still flags.

### shipped-incomplete: judge by required gates only (metric 9b)

Replace the `progress ... | grep complete` delegation with `gate-ledger.sh check <lane> <rid>`.
`check` is the ship-gate's own contract: it passes iff every REQUIRED (measure-twice) gate has
a `ran`/`override` entry, and it ignores run-lite phases entirely. So a run that disposed its
required gates but never recorded the lite `ui-design` is no longer flagged, while a run that
shipped without a required gate (the real case, e.g. `spec-ghost` missing spec+build) still
flags. Definition: shipped-incomplete = shipped but would not pass its own ship-gate.

This retires the A4 "complete" cross-lib seam (the detector no longer delegates via the literal
`complete`); the seam pin is updated to assert the new seam (the detector calls `gate-ledger.sh
check`). `progress` is untouched, so its `complete (n/n)` display and every `progress` pin are
unaffected.

## Verification

```bash
cd dwarves-kit
bash lib/lane-telemetry.sh misfires   # the false flags are gone; real cases remain
bash tests/test-hooks.sh              # detector pins (218-244) + the 4 new pins green
bash tests/test-lane-telemetry.sh     # report/render green
```

Pins (added where the detector suite already lives, `tests/test-hooks.sh`):
- **boardless-false-flag-now-clean**: a run whose ledger carries `ID-NNN` present on the board
  is NOT flagged (the PR/ID match).
- **boardless-real-still-flags**: a run with no rid-on-board and no board-linked ID/PR token IS
  flagged (negative control).
- **shipped-incomplete-false-flag-now-clean**: a full-lane run with every required gate disposed
  but the lite `ui-design` un-disposed is NOT flagged.
- **shipped-incomplete-real-still-flags**: a run missing a required gate IS flagged (the existing
  `spec-ghost` control, preserved).

## After state

- `_boardless` matches by rid OR ledger ID/PR; `_shipped_incomplete` delegates to
  `gate-ledger.sh check` (required gates only).
- `tests/test-hooks.sh` A4 seam pin asserts the new seam; 4 detector pins added.
- `docs/verification/lane-detectors.md` carries the run-table + negative controls.

## Open questions

Legacy runs whose ledger carries no board-linked ID/PR (`kit-clean-01-startwire`, `cc-hyg-04`)
remain boardless-flagged: a data gap (the run recorded no ID), not a detector bug. Fully clearing
future runs needs the START line to carry a `board=<ID|PR>` field, which neither this sub-goal nor
the shipped SG-01 adds; that is a distinct follow-up (TIER-4 advisor P6-2, tracked in the
kit-telem-cleanup NOTES `## Proposed additions`), not something SG-01 already covers. Noted, not
fixed here.
