# Sub-goal 01: ledger-event schema (the observatory's contract)

**Merge policy:** auto
**Time budget:** 1-2 hours (doc + contract; small).
**Proof:** run-table: the canonical `ISO8601 | VERB | k=v` schema doc lands · a conformance check confirms the ~10 existing kit stores AND the planned debt (understanding-gate SG-02) + token (kit-face SG-03) marker shapes FIT the schema · negative control: a malformed non-conforming line is REJECTED by the conformance check · each of the 3 outlier adapter contracts (learned-ledger.md=markdown, tide state.sqlite=sqlite, tg-cleanup *.json=json) is specified with a sample record shape.
**Depends on:** none.
Model: sonnet
Effort: medium
**Branch:** feat/lo-01-schema
**PR base:** main

## Outcome

A schema doc formalizing the kit's `ISO8601 | VERB | k=v` append-only marker (under `~/.local/state/dwarves-kit/logs/`) as THE canonical ledger-event schema the whole observatory reads. It confirms the ~10 existing kit stores already conform (schema-uniform per the ledger inventory) and that the two PLANNED ledgers , the debt ledger (understanding-gate SG-02) + the token ledger (kit-face SG-03) , conform ON ARRIVAL because they reuse the same additive-marker convention (SG-01 does NOT wait for them to exist). It specifies the 3 bespoke OUTLIER adapter contracts DuckDB reads via small adapters: learned-ledger.md (markdown), tide state.sqlite (sqlite, DuckDB-native), tg-cleanup *.json (json snapshots, DuckDB-native). This is the contract SG-02's ETL builds its views against.

## Quality bar

ONE schema, not a fourth convention , it NAMES the existing additive-marker shape (already shared by kit-face TOKENS + understanding-gate debt), it does not invent one. The outlier adapters are CONTRACTS (field mapping + a sample record), not code (02 implements). Small + doc-shaped; the conformance check is a grep/parse, not an engine.

## How to close the loop

`/spec` + `/spec-validate` first (pin the exact schema grammar + the 3 adapter field-maps). Then `bash tests/test-schema-conform.sh`: a conforming kit line passes, a malformed line is rejected (NC), each outlier's sample record parses under its adapter contract. Assumptions: ROADMAP 01 + the ledger inventory in the research Addendum.

**Done =** the canonical schema doc + the 3 adapter contracts land, the conformance check passes real kit lines + the planned debt/token marker shapes AND rejects a malformed line (NC), tests green.

## Scope edges

**In:** the schema doc, the 3 adapter contracts (field-map + sample record), the conformance check + its tests.
**Out:** the DuckDB views + the `ledger` CLI (02); the render skill (03); the feedback loop (04).
**Not:** implementing the adapters in code (02 owns that); inventing a new marker convention (reuse the additive-marker shape); changing any producer ledger's format (read-only , the schema DESCRIBES what exists).

## Where to look

`~/.local/state/dwarves-kit/logs/` (the live kit markers), `lib/lane-telemetry.sh` + `lib/gate-ledger.sh` (the marker producers/readers , the shape to formalize), kit-face SG-03 (the TOKENS marker) + understanding-gate SG-02 (the debt marker), `_meta/learned-ledger.md`, `tools/tide/` (state.sqlite), `tools/tg-cleanup/` (*.json), the research Addendum's ledger inventory.

## PR body

Ledger-event schema (the observatory's contract): formalizes the kit `ISO8601 | VERB | k=v` marker as THE canonical schema, confirms the planned debt + token ledgers conform on arrival, and specifies the 3 outlier adapter contracts (learned-ledger.md/markdown, tide/sqlite, tg-cleanup/json). Verify: `bash tests/test-schema-conform.sh` (conforming-passes + malformed-rejected NC + outlier-samples-parse). Roadmap: ops-toolkit `_meta/megagoals/ledger-observatory/ROADMAP.md`.

## Notes

<empty>
