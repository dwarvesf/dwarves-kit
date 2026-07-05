# Sub-goal 04: lane-run dashboard

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** 2-3 captured renders (the ASCII dashboard from real corpus data, committed as text captures in the proof; a markdown snapshot under docs/research/) , visual surface, so multiple captures, not one.
**Depends on:** 01 (durable data) + 03 (the audit shapes what is worth rendering).
Model: sonnet
Effort: medium
**Branch:** feat/kit-telem-04-dashboard
**PR base:** feat/kit-telem-03-laneaudit (stacked on 03)

## Outcome

Lane usage is visible: `lane-telemetry.sh render` (new subcommand) draws the task-type -> lane -> gate routing diagram with run counts from the durable ledgers, and a dated markdown snapshot lands under `docs/research/`. Lane usage is tracked, not guessed , the narrowed remainder of ops-toolkit ID-150 (the record+aggregate half already exists per SPEC-061).

## Quality bar

ASCII + markdown only, zero new dependencies , it must render over ssh on the Mini. Empty/missing data degrades gracefully (a fresh install renders an honest "no runs recorded", never a crash or fake zeros). Boring beats clever.

## How to close the loop

SDD: `/spec` + `/spec-validate` first (ops board ID-150's reconciled row is the brief). Then:

```
cd dwarves-kit && bash lib/lane-telemetry.sh render          # real-corpus render, captured x2 (full + filtered)
bash lib/lane-telemetry.sh render </dev/null                 # graceful-empty negative control (empty/temp LOG_DIR)
bash tests/test-lane-telemetry.sh                            # render cases pinned
```

Captures land in the proof at `docs/verification/lane-dashboard.md` + the snapshot at `docs/research/2026-07-02-lane-usage-snapshot.md`. Gate-ledger records per phase.

**Done =** `render` produces the routing diagram + counts from the real corpus (2-3 captures committed), the graceful-empty control passes, and the snapshot doc exists.

## Handoff on completion

1. Flip 04's ROADMAP box, PR # + SHA. NOTES line for the ops ID-150 flip at close.
2. HOT `HANDOFF.md`: next = 05 if unmerged, else the TIER-4 close gate.
3. WARM `DECISIONS.md`: render-shape decisions (what was deliberately left out).
4. Report IN records, EXIT.

## Scope edges

**In:** the `render` subcommand, captures, the snapshot doc, tests.
**Out:** collecting/aggregating (exists); storage (01); rule changes (03).
**Not:** a web UI; charts/images; a new binary; per-repo dashboards.

## Where to look

`lib/lane-telemetry.sh` (report/misfires shape to extend), the durable corpus, 03's findings (what matters), ops board ID-150's reconciled Notes.

## PR body

`lane-telemetry.sh render`: task-type -> lane -> gate routing diagram + run counts over the durable ledgers; graceful-empty control; snapshot at `docs/research/2026-07-02-lane-usage-snapshot.md`. Narrowed remainder of ops-toolkit ID-150. Stacked on #<03's PR>; review after it. Roadmap: ops-toolkit `_meta/megagoals/kit-telemetry/ROADMAP.md`.

## Notes

<empty>
