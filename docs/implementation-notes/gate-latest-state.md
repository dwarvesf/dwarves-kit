# Implementation notes: gate-latest-state

Delta from the brief. Two changes: `check()` decides on the latest GATE row per phase, and a new GATE state `rejected` for a NEEDS-REVISION close.

## Measurement before the change

Read-only run of the old and new predicate over every real ledger on this host (916 files), counts only.

| Scope | Old pass | New pass | Flips pass to fail |
|---|---|---|---|
| 192 ledgers with a START lane, required phases of that lane | 128 | 128 | 0 |
| 724 ledgers with no START line, checked under each of the 5 lanes | n/a | n/a | 0 under every lane |
| Any phase, any ledger: ran or override earlier, latest row not ran or override | n/a | n/a | 2 ledgers (phases `validate`, `design-record`, last state `skipped`) |

Neither of those 2 ledgers passes the old check, so no run flips. The predicate matched the real old `check()` on all 192 lane-bearing ledgers (128 pass, 64 fail).

## Decisions not in the brief

- The `MISSING-GATE` text keeps "no ran/override entry in the ledger". The cache replays it and two tests pin it. For a phase whose latest row is skipped or rejected the wording is loose but the verdict is right.
- `record` accepts `rejected` (it is the only writer path for the new state). `record-batch` and `plan-record` do not take it: they stay `ran|skipped|override`.
- Resume of a half-written close from an older kit: a `skipped` line carrying `NEEDS-REVISION:` is folded to `rejected` by `_vr_norm`, and `_vr_w` accepts it for the `rejected` record, so a resume neither refuses nor duplicates the line.
- `descent` and `progress` treat `rejected` as disposed, like a skip with a reason. Treating it as undisposed would flag `design-record` as recorded before `validate` on every NEEDS-REVISION close, since both are written in one block. `progress` shows the phase as a cross.
- `design-record skipped "critical: ..."` and both `incomplete` writes stay `skipped`, as the brief says.
- `lane-telemetry` counts `rejected` with `skipped` (same TSV column, so no layout change); the legend says so.
- Bench `GATE_STATE` maps `rejected` to `fail`, the status the viewer already draws. The dashboard counts it apart: a new `rejected` metric, a fifth verdict-mix segment, a REJECTED chip, a stepper glyph.

## Left alone, outside the slice

- `lib/mega/mega-report.py` `cell()` draws a rejected gate as `-` (not recorded). It reads the old states by name.
- `lib/gate/proof-table-gen.py` builds `covered` from any `ran` or `override` row, so it still has the stale-ran reading that `check()` lost. The acceptance line it prints calls the real `check()`, so the verdict is right.
- `lib/stats` gate-yield and ceremony lenses treat the outcome as opaque text; a `rejected` row falls outside their ran, override, skipped counts.
- `docs/design/kit-uml.html` is rendered from `docs/SYSTEM-DESIGN.md` and still lists three states until the next render.
