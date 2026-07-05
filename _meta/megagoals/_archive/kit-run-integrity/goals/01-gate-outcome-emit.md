# Sub-goal 01: gate-outcome emit (`caught=` + `START`/`END` timing)

**Merge policy:** auto
**Time budget:** 3-4 hours.
**Proof:** run-table: a gate run emits a `caught=true` marker when the gate is a non-pass (block / findings / non-zero) and `caught=false` on a clean pass · a `START`/`END` timing bracket brackets the gate and a duration is derivable · the marker is ADDITIVE , existing readers (`check()`, `override()`, `_rows()`, the ship-gate) behave IDENTICALLY with the new marker present (a byte-for-byte / row-for-row equivalence check on their output before vs after) · a round-trip: emit -> read back the outcome + duration for a rid. A COVERAGE-DELTA row names covered vs uncovered.
**Depends on:** 02 (branches off master-with-02 so its own /spec cannot collide).
Model: opus
Effort: high
**Branch:** feat/kri-01-gate-outcome
**PR base:** master (post-02-merge)

## Outcome

Gate runs become MEASURABLE. Today `gate-ledger.sh record <rid> <phase> <ran|skipped> [reason]` records that a gate RAN, not whether it CAUGHT anything or how long it took (effectiveness-audit: "Gate run-ledger = CEREMONY as built"). Add an OUTCOME emit on the SAME additive-marker convention the ledger already uses (`ISO8601 | MARKER | k=v` , the line TOKENS/SPEC-110 and DEBT/ADR-0031 already ride): `caught=<true|false>` (did the gate catch a defect) + a `START`/`END` timing bracket so a gate's duration is derivable. REUSE `gate-ledger.sh` , a new additive marker (e.g. `OUTCOME` / a `START`+`END` pair) beside TOKENS + DEBT, keyed so that every existing reader (which matches `$2=="GATE"` or START) IGNORES it. No new marker file, no new convention.

## Quality bar

ADDITIVE is the load-bearing property: the new marker must not change what `check()`, `override()`, `descent()`, `_rows()`, or the ship-gate read , prove it with an equivalence check (their output is identical with the marker present vs absent). Reuse the ledger's existing atomic-append + `now()` + rid discipline; do not fork a second telemetry path. `caught=` is derived from the gate's OWN recorded state (open-fork 2 default: non-pass -> true, clean pass -> false), not re-computed. The timing bracket is unconditional. Keep it a handful of lines added to `gate-ledger.sh` + the emit points, not a subsystem.

## How to close the loop

`bash lib/lane-classify.sh classify "add an additive gate-outcome + timing marker to gate-ledger.sh reusing its marker convention"` then run that lane. Design-ish (marker shape + catch-detection): a short `## Design` (or fold into the spec) pinning the marker name, its `k=v` fields (`caught`, `dur_ms` or START/END pair), where START/END wrap, and how `caught` is derived , resolve open-fork 2 (catch-detection signal). `/spec` + `/spec-validate`. Then `/kit:test-plan` + the additive-equivalence test + the round-trip read-back. Record each gate via `bash lib/gate-ledger.sh record`. Capture the COVERAGE-DELTA row. Assumptions: ROADMAP `## Assumptions` + open-fork 2.

**Done =** a gate emits `caught=<bool>` + a START/END timing bracket on the existing additive-marker convention, every existing reader is byte/row-identical with the marker present (additive-equivalence proven), the outcome + duration read back per rid, COVERAGE-DELTA row recorded, gates ledgered, committed at phase boundaries.

## Scope edges

**In:** the new additive marker in `lib/gate-ledger.sh` (verb + reader helper), the emit at the gate boundaries (START/END wrap + the `caught=` derivation), the additive-equivalence test + round-trip test + coverage-delta.
**Out:** 05's generator that CONSUMES this marker (05 reads it; it is the first consumer); 02/03/04; docs (06).
**Not:** a new marker file or a second telemetry convention (reuse the existing line); changing any existing reader's behavior; re-computing `caught` independently of the gate's recorded state; a full timing/profiling subsystem.

## Where to look

`lib/gate-ledger.sh` (READ the header comment block: the `record`, TOKENS/SPEC-110, DEBT/ADR-0031 additive markers are the exact pattern to mirror , note how they are "ignored by check()/override()/descent()/_rows() which key on $2==GATE|START|ACTION"; `now()`, the atomic append, the rid derivation), `lib/proof-gate.sh` + `hooks/ship-gate.sh` (gate boundaries where START/END + the outcome should wrap; confirm the equivalence check covers the ship-gate's read), `lib/lane-telemetry.sh` (how markers are consumed , the reader side must tolerate the new marker).

## PR body

Gate-outcome emit: gate runs now record an OUTCOME, not just ran/skipped. A new ADDITIVE marker on gate-ledger's existing `ISO8601 | MARKER | k=v` convention (beside TOKENS + DEBT) carries `caught=<true|false>` (did the gate catch a defect) + a START/END timing bracket (gate duration). Existing readers are byte/row-identical with it present (additive-equivalence proven). Makes the gate layer measurable (feeds 05's generated proof-table). Verify: additive-equivalence + round-trip + coverage-delta. Roadmap: ops-toolkit `_meta/megagoals/kit-run-integrity/ROADMAP.md`.

## Notes

<empty>
