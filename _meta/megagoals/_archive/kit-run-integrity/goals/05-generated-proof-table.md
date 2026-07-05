# Sub-goal 05: generated proof-table

**Merge policy:** auto
**Time budget:** 3-5 hours.
**Proof:** run-table: the generator reads the gate/run ledger for a rid and EMITS the proof-of-done confirmation table (the SPEC-016 table-first shape: acceptance -> confirmation run-table -> reproduce) · when 01's `caught=`/timing markers are present, a CAUGHT + DURATION column is populated; when ABSENT, the table degrades gracefully (the column is omitted / "n/a", no crash , the additive-tolerance property) · the generator writes UNDER `docs/runs/` (a generated path), NEVER overwriting a canonical `proof-of-done.md` (SPEC-016: generators never overwrite the canonical) · a round-trip: generate from a known ledger fixture -> the table matches the ledger's rows. A COVERAGE-DELTA row names covered vs uncovered.
**Depends on:** 02 (branches off master-with-02). SOFT data-dependency on 01 (surfaces its `caught=` column) but NO code dependency , additive-tolerant, builds in parallel with 01.
Model: sonnet
Effort: high
**Branch:** feat/kri-05-proof-table
**PR base:** master (post-02-merge)

## Outcome

The proof-of-done confirmation table is GENERATED from the ledger, never hand-authored. Today a proof's run-table is typed by hand (effectiveness-audit: proof-of-done is a forcing function but its run-table is manual, and the gate run-ledger that COULD back it is "CEREMONY as built" , written, never read). This makes the ledger a CONSUMER: a generator reads the gate/run ledger for a rid and emits the run-table in the SPEC-016 table-first format, populating a CAUGHT + DURATION column from 01's `caught=`/timing markers when they exist and degrading gracefully when they do not (additive-tolerance). It writes to a GENERATED path (`docs/runs/`), never overwriting the canonical `proof-of-done.md` (SPEC-016's generator rule). The point: a proof table's evidence rows are generated from telemetry, not asserted by hand.

## Quality bar

GENERATE, never hand-author (the hard constraint): the generator is the only author of its output, and it writes under `docs/runs/`, never the canonical `proof-of-done.md` (SPEC-016). ADDITIVE-TOLERANCE is load-bearing: it reads 01's markers when present and works fine when absent (so it merges in parallel with 01 and TIER-4's no-orphan check can confirm it actually surfaces 01's `caught=`). Reuse the ledger reader (`lane-telemetry` / `gate-ledger`'s read helpers), do not re-parse the pipe-log by hand. The output matches the SPEC-016 table-first shape the kit's proofs already use (do not invent a new proof format).

## How to close the loop

`bash lib/lane-classify.sh classify "generate the proof-of-done confirmation table from the gate/run ledger"` then run that lane. Mostly execution against a known schema (a generator), so `/spec` + `/spec-validate` (a light spec; the schema is SPEC-016 + gate-ledger's format , pin the input rid -> output table mapping + the CAUGHT/DURATION column's present/absent behavior). Then `/kit:test-plan` + a round-trip test against a ledger fixture (with AND without 01's markers , the additive-tolerance case) + the writes-to-docs/runs-not-canonical assertion. Record gates via `bash lib/gate-ledger.sh record`. Capture the COVERAGE-DELTA row. Assumptions: ROADMAP `## Assumptions` (05 reads whatever markers exist; degrades gracefully).

**Done =** the generator emits the SPEC-016 table-first proof run-table from a rid's ledger, the CAUGHT/DURATION column populates from 01's markers when present and is graceful when absent (additive-tolerance proven both ways), output lands under `docs/runs/` and never overwrites the canonical, a round-trip against a fixture matches, COVERAGE-DELTA row + gates recorded, committed at phase boundaries.

## Scope edges

**In:** the proof-table generator (rid -> SPEC-016 table under `docs/runs/`), the ledger-read reuse, the CAUGHT/DURATION column (present + absent behavior), the round-trip test + the not-canonical assertion + coverage-delta.
**Out:** 01's emit itself (05 consumes it); the canonical proof-of-done authoring workflow (05 generates the run-table, does not replace the human's acceptance/reproduce prose); 06 docs.
**Not:** a hand-authored table (generate); overwriting the canonical `proof-of-done.md` (write under `docs/runs/`); a new proof format (SPEC-016 shape); re-parsing the pipe-log by hand (reuse the reader); requiring 01 to be merged first (additive-tolerant).

## Where to look

`docs/specs/SPEC-016*` + `tools/*/docs/proof-of-done.md` exemplars referenced in ops-toolkit CLAUDE.md (`zedra-deploy`, `spec-to-cli` single-feature; `growatt-pull`, `mac-mini-substrate` multi-feature index) for the table-first shape + the "generators write under docs/runs/, never the canonical" rule, `lib/gate-ledger.sh` + `lib/lane-telemetry.sh` (the ledger reader to reuse; 01's new `caught=` marker), `lib/verif-counts.sh` (an existing ledger->summary generator pattern to mirror).

## PR body

Generated proof-table: the proof-of-done confirmation run-table is generated from the gate/run ledger, not hand-authored. Reads a rid's ledger, emits the SPEC-016 table-first shape under `docs/runs/` (never overwriting the canonical proof-of-done.md), and populates a CAUGHT/DURATION column from the gate-outcome markers (01) when present, degrading gracefully when absent (additive-tolerant, so it builds in parallel with 01). Makes the write-only gate ledger a consumer. Verify: round-trip against a fixture (with + without 01's markers) + not-canonical assertion + coverage-delta. Roadmap: ops-toolkit `_meta/megagoals/kit-run-integrity/ROADMAP.md`.

## Notes

<empty>
