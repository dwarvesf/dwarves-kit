# proof-class-one-table: delta note

The proof class names, their rank, and the stateful words both classifiers share now live in `lib/gate/proof-classes.tsv`. `lib/gate/proof-classes.sh` reads it. `proof-ledger.sh classify` (branch diff) and `proof-gate.sh class` (task text) both source the reader.

## Decisions

- Only the exact intersection of the two word lists moved: deploy, rollout, production, migrat, schema, data model, database, backup, restore, persistent, drop table/column, alter table, data loss.
- Words that differ stay in each classifier as local extras. Ledger: `/db/`, `\bseed\b`. Gate: release to, ship to prod, `\bdb\b`, backfill data, `seed`, stateful, `drops` table/column, delete data, incident, triage.
- Zero behavior change by design. The gate's old `drop[s]? ` became the shared `drop ` plus a gate-only `drops `. The union is identical.
- A missing or empty table is FATAL at source time. An empty stateful set would quietly weaken the ship gate.
- `pc_emit` replaces literal `echo inert|behavioral|stateful` and refuses an undeclared class. `proof-gate.sh classes` prints the table, highest rank first (same order as before).
- Rank is declared and checked (inert < behavioral < stateful). No classifier compares ranks yet; the measurement harness does.
- The copy detector flags a code line with four or more table words, or all three class names. One word alone is ordinary code (`deployable`).

## Measurement (old vs new, last 60 first-parent commits on master)

- Ledger, each commit diff against its parent: 0 of 60 changed. Old mix: 44 behavioral, 6 inert, 10 stateful. No move down.
- Gate, each commit subject as task text: 0 of 60 changed. Old mix: 57 behavioral, 3 inert.

## Open questions

- The remaining divergence is real: `seed` (ledger whole word, gate substring), the gate's incident/triage/release words, the ledger's `/db/`. Converging them changes behavior, so it needs its own measured slice.
- Subjects rarely say "stateful", so the plan-time gate mostly answers behavioral. That is pre-existing and unchanged here.
