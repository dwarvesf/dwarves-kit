# Sub-goal 01: ledger durability + per-gate override reasons

**Merge policy:** auto
**Time budget:** 2-4 hours.
**Proof:** run-table , records survive a simulated reinstall (negative control: the OLD path's wipe no longer loses data) · a blanket override (N identical reasons in one call) is REJECTED · `lane-telemetry.sh report`/`misfires` read the new path · existing kit-harden logs migrated.
**Depends on:** none. FIRST: 02/03/04's corpus lives in the wipeable dir until this lands.
Model: sonnet
Effort: high
**Branch:** feat/kit-telem-01-ledger
**PR base:** master

## Outcome

Kit run telemetry is durable: the gate/proof run ledgers live outside the plugin-reinstall blast zone (today `~/.claude/dwarves-kit/logs`, recreated on reinstall , the 2026-07-01 reinstall wiped everything), with the existing kit-harden corpus migrated in. Override hygiene is enforced: a per-gate override requires its own reason; one pasted reason stamped across all gates is rejected (the sole surviving pre-July run did exactly that, defeating the audit trail).

## Quality bar

Telemetry that cannot survive a reinstall cannot feed `/kit:retro`, that is the whole defect. Migration is additive (never deletes the old dir); reinstall is SIMULATED via an env-pointed temp dir, never by touching the live plugin dir.

## How to close the loop

SDD: `/spec` + `/spec-validate` first (board row dwarves-kit ID-082 is the brief). Then:

```
cd dwarves-kit && bash tests/test-ledger-durability.sh   # survive-reinstall NC · blanket-override rejected · telemetry reads new path · migration
```

Proof run-table at `docs/verification/ledger-durability.md`. Record gates via `lib/gate-ledger.sh` (this sub-goal moves the ledger it writes to , sequence the migration so the run's own records survive).

**Done =** `test-ledger-durability.sh` green with the reinstall-simulation negative control, blanket-override rejection proven, and the kit-harden logs present at the new path.

## Handoff on completion

1. Flip 01's ROADMAP box, PR # + SHA; flip kit board ID-082 -> shipped IN this PR.
2. HOT `HANDOFF.md`: next = 02 (eval) or 03 (audit); first action = `/spec` from its board row. Pointer: the migrated corpus path.
3. WARM `DECISIONS.md`: the new ledger path + migration decision.
4. Report IN records, EXIT.

## Scope edges

**In:** ledger storage path + migration, override-reason enforcement, `lane-telemetry.sh` path update, tests.
**Out:** what the data MEANS (02/03); the dashboard (04).
**Not:** a new telemetry schema; cloud/remote storage; deleting the old dir.

## Where to look

`lib/gate-ledger.sh` (LOG_DIR line ~28), `lib/proof-ledger.sh`, `lib/lane-telemetry.sh`, the plugin install/reinstall path (what recreates `~/.claude/dwarves-kit`), kit board row ID-082.

## PR body

Durable run-ledger storage (survives plugin reinstall; kit-harden corpus migrated) + per-gate override reasons (blanket overrides rejected). Board ID-082; audit R1. Verify: `bash tests/test-ledger-durability.sh`. Proof: `docs/verification/ledger-durability.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telemetry/ROADMAP.md`.

## Notes

<empty>
