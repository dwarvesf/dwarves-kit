# Sub-goal 02: lane-telemetry detector refinements (false-flag fixes)

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table , one pinned test per detector: boardless no longer flags a tracked run (before=flagged, after=clean); shipped-incomplete no longer flags a full-lane non-UI run whose only un-disposed phase is a lite one. Both negative controls (a genuinely boardless run / a genuinely incomplete run) STILL flag.
**Depends on:** none (independent detector bugs; benefits from 01's START data but does not require it).
Model: sonnet
Effort: medium
**Branch:** feat/kit-clean-02-detectors
**PR base:** master

## Outcome

Two `lib/lane-telemetry.sh` detectors stop false-flagging, so `misfires` output is trustworthy. The SPEC-073 eval found (metric 9): (a) **boardless** flags a TRACKED run because it matches the board by raw rid, but board rows key on `ID-NNN`/`PR #N` (so `kit-telem-01-ledger` was wrongly flagged); (b) **shipped-incomplete** flags a full-lane NON-UI run because the `ui-design` (lite) phase is un-disposed. Fix: boardless matches a run to its board row by PR/ID; shipped-incomplete treats lite phases as disposed (or requires an explicit `ui-design skipped` only when the lane genuinely needs UI). Both keep flagging the REAL cases they exist to catch.

## Quality bar

Fix the false-positive without blinding the detector to true positives , each fix ships with BOTH the false-flag-now-clean pin AND a real-case-still-flags negative control. Do not rewrite the detectors; adjust the match key (boardless) and the lite-phase disposition (shipped-incomplete) surgically.

## How to close the loop

Kit-adopted repo: read `AGENTS.md` first; classify + record gates via `lib/gate-ledger.sh` before push.

```
cd dwarves-kit
bash lib/lane-telemetry.sh misfires        # the corpus this reads; confirm the false flags are gone
bash tests/test-lane-telemetry.sh          # extend with the two detector pins + negative controls
```

Proof run-table at `docs/verification/lane-detectors.md`. Extend `tests/test-lane-telemetry.sh` (SG-04's suite) with: boardless-false-flag-now-clean, boardless-real-still-flags, shipped-incomplete-false-flag-now-clean, shipped-incomplete-real-still-flags.

**Done =** both detectors no longer false-flag the two cases metric 9 named, each fix has a pinned test AND a real-case negative control that still flags, and `tests/test-lane-telemetry.sh` stays green.

## Handoff on completion

1. Flip 02's ROADMAP box, PR # + SHA.
2. HOT `HANDOFF.md`: next per roadmap; carry which match-key was chosen for boardless.
3. WARM `DECISIONS.md`: the boardless match-key + the lite-phase disposition rule.
4. Report IN records, EXIT.

## Scope edges

**In:** the boardless + shipped-incomplete detector logic in `lib/lane-telemetry.sh` + their pins.
**Out:** the render subcommand (shipped, SG-04); start-wiring (01); classifier (05).
**Not:** new detectors; a detector-config system; changing the misfire OUTPUT format.

## Where to look

`lib/lane-telemetry.sh` (`_boardless`, `_shipped_incomplete`), `tests/test-lane-telemetry.sh`, dwarves-kit board ID-086, `docs/research/2026-07-02-effectiveness-eval.md` (metric 9, the two false-flag cases).

## PR body

Fix two lane-telemetry false-flags: boardless matches a run to its board row by PR/ID (not raw rid); shipped-incomplete treats lite phases as disposed. Each with a real-case negative control. ID-086 (`#kit-telem-followup`). Verify: `bash tests/test-lane-telemetry.sh`. Proof: `docs/verification/lane-detectors.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telem-cleanup/ROADMAP.md`.

## Notes

<empty>
