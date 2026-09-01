# Spec: the `ledger` tool (DuckDB lens + agent-callable CLI)
Generated: 2026-07-04
Status: VALIDATED
Lane: full
Depends-on: SPEC-126 (ledger-event-schema + adapter-contracts)

## Problem

SG-01 pinned the schema (`ledger-event-schema.md`) and the 3 outlier adapter contracts
(`adapter-contracts.md`) but shipped no code that reads them. The ledgers are still
write-only: there is no way for the agent to ask "show me the kit gate history", "which
tide moves happened", "join the two". This sub-goal builds the read side: a DuckDB LENS
over all four source shapes in place, plus an agent-callable `ledger show/query/rebuild`
CLI that returns machine-parseable structured output. The DuckDB db is a derivable,
disposable lens; the FILES stay canonical (delete-and-rematerialize is a named proof).

## Solution

### Approaches considered

1. **DuckDB views over the files in place + reuse lane-telemetry for the kit read
   (CHOSEN).** One materialization step builds a small DuckDB db from four readers:
   (a) the kit corpus via lane-telemetry's own `_rows()` parser (mandated reuse, no
   re-parse), (b) tide's `state.sqlite` via DuckDB-native `ATTACH (TYPE sqlite)`,
   (c) tg-cleanup's `*.json` via DuckDB-native `read_json_auto`, (d) `learned-ledger.md`
   via a small markdown-table adapter. A read-only CLI queries the db. Matches the
   ROADMAP's binding DuckDB-as-lens principle and the icy-ops/growatt-pull read-only
   shape.
2. **A custom parser/engine per store, no DuckDB.** Rejected: re-implements the kit parse
   (contract forbids), loses SQL/JOIN for free, and the ROADMAP Addendum explicitly says
   "ETL = a handful of views + a refresh, NOT a custom engine."
3. **A synced/persistent db that stays in step with the files.** Rejected by the Quality
   bar: the db must be a disposable lens, never a second source of truth. On-demand
   rematerialize, no sync, no write-back.

### Chosen: approach 1.

## Design

Design-bearing (new component + data-model shape + 2 resolved forks). This block is the
design record (ADR-0031 §1); non-empty by construction.

### Resolved open-forks (ROADMAP `## Open forks`)

- **Fork 1 (harness language):** **Python + uv.** Han's stack default for ad-hoc
  non-daemon transforms; DuckDB SQL does the transform, a thin `uv run` Typer CLI is the
  surface. Reconsider Go ONLY if this hardens into a scheduled daemon (it does not in
  Phase 1).
- **Fork 2 (refresh trigger):** **On-demand.** No daemon, no launchd (minimum-infra).
  `ledger rebuild` re-materializes explicitly; any `show`/`query` on a missing db lazily
  rebuilds first. The agent triggers the refresh when it queries.

### The db is a lens (delete-and-rematerialize)

- Materialized to `$LEDGER_OBSERVATORY_DB` (default `~/.cache/ledger-observatory/
  ledger.duckdb`), NEVER in the repo, gitignored regardless.
- `rebuild` = delete the db file, re-create every table from the canonical files.
- Deleting the db loses nothing; the next command rebuilds it. No write path back to any
  source ledger (read-only-by-contract).

### Source roots are overridable (for tests + host portability)

Env vars point each reader at its source, defaulting to the live locations; tests point
them at fixtures:

| Reader | Env override | Default |
|---|---|---|
| kit corpus | `DWARVES_KIT_LOG_DIR` (lane-telemetry's own) | `~/.local/state/dwarves-kit/logs` |
| tide sqlite | `LEDGER_OBS_TIDE_DB` | `~/.local/state/tide/state.sqlite` (skip if absent) |
| tg-cleanup json | `LEDGER_OBS_TGCLEANUP_DIR` | `tools/tg-cleanup` (skip if no `*.json`) |
| learned-ledger | `LEDGER_OBS_LEARNED_MD` | `_meta/learned-ledger.md` |
| kit lib | `DWARVES_KIT_LIB` | `~/.claude/dwarves-kit/lib` |

A missing source is skipped with an empty table (never a hard error): a host without tide
or tg-cleanup data still gets a working `kit_runs` + `learned` lens.

### DuckDB via the Python wheel only (no INSTALL/LOAD)

The Homebrew CLI cannot install json/sqlite extensions offline; the `duckdb` Python
package bundles them. See impl-notes. No `INSTALL`/`LOAD` statement anywhere.

## Technical Design

### The view/table set

The materialized db carries these tables (populated at rebuild):

| Table | Source | Reader | Notes |
|---|---|---|---|
| `kit_runs` | kit `runs/<rid>.log` corpus | lane-telemetry `_rows()` TSV | run-level: `rid, repo, lane, classified, type, ctype, gates_ran, gates_skip, gates_ovr, lane_misroute, type_misroute, shipped, review, first_ts, last_ts` |
| `tide_moves` | tide `state.sqlite` `moves` | DuckDB `ATTACH (TYPE sqlite)` | column names unchanged; `undone_at IS NULL` = active |
| `tide_tier_b_calls` | tide `state.sqlite` `tier_b_calls` | same ATTACH | token/cost rows |
| `tg_dialogs` | tg-cleanup `*.json` | DuckDB `read_json_auto` | `category` carried from the object key for keep/kill files |
| `learned` | `learned-ledger.md` | markdown-table adapter | `date, item, kind, home, status` per the contract |

`kit_runs` columns map 1:1 onto lane-telemetry's `_rows` TSV order (15 fields). The reuse
is the parser, not a re-derivation.

**Unmaterialized tide tables (named, not a gap, spec-validate item 3).** The adapter
contract lists 5 tide tables; SG-02 materializes only `tide_moves` + `tide_tier_b_calls`
(the observability-relevant ones: file moves + token/cost calls). `meta`,
`review_queue`, `learned_verdicts` are intentionally NOT materialized here (not needed
for the ledger lens; a later sub-goal can add them by the same ATTACH pattern).

**Deterministic ordering (spec-validate item 1).** `show` emits rows in a pinned,
deterministic order (`ORDER BY` a stable key per table, else all columns), so AC4's
"byte-identical after delete-and-rematerialize" is CONTRACTUAL, not incidental on this
host's scan order. The adapters also sort their rows before load (kit by `rid`, learned
by input order, tg by `source_file,dialog_id`). The rematerialize test compares `show`
output, which carries the ORDER BY.

### The `ledger` CLI (agent-callable, read-only)

`uv run ledger <cmd>`; every command takes `--json` (default) | `--table`:

- `ledger show <name> [--limit N]` , dump a named table's rows.
- `ledger query "<sql>" ` , arbitrary READ-ONLY SQL (incl. cross-ledger JOINs). A
  write-shaped statement (INSERT/UPDATE/DELETE/CREATE/DROP/ATTACH/COPY/...) is refused
  before execution (read-only-by-contract guard) AND the DuckDB connection is opened
  `read_only=True` on the materialized db (belt + braces).
- `ledger rebuild` , delete + re-materialize the db from the files; prints per-table row
  counts.
- `ledger tables` , list materialized table names + row counts (convenience).

`--json` emits a JSON array of row objects (agent-consumable); `--table` emits a
box-drawn table (human glance). Structured output is the contract; the agent consumes
`--json`.

### Read-only enforcement (THREE independent layers, spec-validate HIGH-1)

1. **Statement guard:** `query` rejects any statement whose first keyword is not a read
   verb (`SELECT`/`WITH`/`FROM`/`VALUES`/`TABLE`/`DESCRIBE`/`SHOW`/`EXPLAIN`/`SUMMARIZE`),
   OR that contains a mutating keyword, OR that is MULTI-STATEMENT (`;`-separated). `PRAGMA`
   is deliberately NOT allowlisted (its assignment form writes a file). This is the early,
   explicit refusal, before touching DuckDB.
2. **Connection mode:** the query connection opens the materialized db `read_only=True`
   (no catalog/row mutation).
3. **No filesystem access:** the query connection also sets
   `enable_external_access=False`, so no statement can write the filesystem even if it
   reached DuckDB (blocks `COPY ... TO`, `PRAGMA profiling_output=...`, `read_csv`, a
   sneaky `ATTACH`). This is the real backstop `read_only=True` alone does NOT provide.

Rebuild uses a separate connection (external access ON, it needs the sqlite ATTACH) scoped
to materialization only; the sqlite ATTACH is `READ_ONLY`. No layer can write back to a
SOURCE ledger: rebuild reads sources and writes only the derivable db; query cannot write
the db (read_only) NOR the filesystem (external access off).

**Why three, not two (HIGH-1, caught at review):** the guard checks only the FIRST
statement's verb, but DuckDB runs every `;`-separated statement; a read-verb-first chain
like `PRAGMA profiling_output='<a source .json>'; SELECT 1` slipped past a two-layer
(guard + read_only) design and overwrote a real source file, because `read_only=True` does
not gate filesystem writes. The multi-statement rejection + PRAGMA de-allowlisting + the
`enable_external_access=False` backstop each independently close it.

## Task Breakdown

- [ ] T1: uv package scaffold (`pyproject.toml`, `src/ledger_observatory/`, `duckdb` +
  `typer` deps, `[project.scripts] ledger`), `.gitignore` (db cache + pycache), `tool.toml`.
- [ ] T2: adapters module , kit reader (lane-telemetry `_rows` subprocess -> rows),
  tide reader (ATTACH sqlite), tg-cleanup reader (read_json_auto), learned-ledger
  markdown parser; each returns rows + is skip-safe on a missing source.
- [ ] T3: materialize module , build/rebuild the db (the 5 tables), delete-and-recreate,
  lazy-rebuild-on-missing; read-only query connection + the statement guard.
- [ ] T4: CLI , `show/query/rebuild/tables` with `--json`/`--table`; structured output.
- [ ] T5: over-test suite `tests/test-ledger-cli.sh` , the 6 contract-mandated cases +
  the COVERAGE-DELTA row.
- [ ] T6: README (tool front door) + SKILL.md pointer; per-feature proof index +
  verification log; MANIFEST/INVENTORY rows.

## After state

- `tools/ledger-observatory/` is a runnable uv package; `uv run ledger rebuild` then
  `ledger show kit_runs --json` returns structured rows on this host.
- A cross-ledger JOIN (`kit_runs` x `tide_moves`) runs via `ledger query`.
- Deleting the db + re-running yields identical output; no source ledger is mutated.
- `tests/test-ledger-cli.sh` is green with a recorded COVERAGE-DELTA.

## Acceptance Criteria (global)

| # | Criterion (measurable) | Verify |
|---|---|---|
| AC1 | `ledger rebuild` materializes the db (>=1 table, row counts printed) from the files | T5/R-rebuild |
| AC2 | `ledger show <name>` returns structured rows in BOTH `--table` and `--json` | T5/R-show |
| AC3 | `ledger query "<sql>"` runs a cross-ledger JOIN (kit_runs x tide_moves) returning rows | T5/R-join |
| AC4 | delete-and-rematerialize: delete the db, re-run, output byte-identical | T5/R-remat |
| AC5 | cross-format read correctness across all 4 shapes (pipe-log + sqlite + json + markdown) | T5/R-formats |
| AC6 | read-only negative control: a query leaves every source ledger byte-identical (checksum before/after) | T5/R-nc |
| AC7 | a write-shaped `query` is refused (guard) and cannot mutate the db | T5/R-guard |
| AC8 | COVERAGE-DELTA row recorded in the proof (covered + uncovered named) | proof-of-done |

## Verification

```bash
cd ~/workspace/<owner>/ops-toolkit/tools/ledger-observatory
uv sync
uv run ledger rebuild
uv run ledger show kit_runs --json | head
bash tests/test-ledger-cli.sh
```

## Test plan

Over-test (the contract mandates it). `tests/test-ledger-cli.sh` builds a self-contained
fixture set (a fake `$DWARVES_KIT_LOG_DIR/runs/` with hand-written kit ledgers, a
generated tide `state.sqlite`, synthetic tg-cleanup json in BOTH shapes, a fixture
`learned-ledger.md`), points every source env var at it, and asserts hand-verified VALUES
(not just non-empty counts, spec-validate item 2).

| Case | Category | Asserts (hand-verified values) | AC |
|---|---|---|---|
| R-rebuild | materialize | `ledger rebuild` prints per-table counts; `kit_runs`/`tide_moves`/`tg_dialogs`/`learned` all non-zero from the fixtures | AC1 |
| R-show-json | structured out | `ledger show learned --json` is valid JSON whose row has the exact fixture `item` value | AC2 |
| R-show-table | structured out | `ledger show learned --table` renders the same row in box form (column header present) | AC2 |
| R-join | cross-ledger JOIN | `ledger query "SELECT k.repo, count(m.id) ... kit_runs k JOIN tide_moves m ..."` returns the expected joined count | AC3 |
| R-remat | delete-and-remat | capture `show kit_runs` output, delete the db file, re-run, diff = empty (byte-identical, ORDER BY makes it contractual) | AC4 |
| R-formats-kit | cross-format (pipe-log) | a known `rid` from the fixture kit log appears in `kit_runs` with the expected lane | AC5 |
| R-formats-sqlite | cross-format (sqlite) | a known `tide_moves.content_sha` fixture value is present | AC5 |
| R-formats-json | cross-format (json) | a known tg dialog `title` + its carried `category` (from the object-of-arrays key) are present | AC5 |
| R-formats-md | cross-format (markdown) | the fixture learned-ledger `item` + `home` parse correctly | AC5 |
| R-nc | read-only NC | sha256 every source file before + after a `query`; all identical | AC6 |
| R-guard | write-guard | `ledger query "DELETE FROM kit_runs"` exits non-zero, refused; a follow-up `show` proves the db row count is unchanged | AC7 |

COVERAGE-DELTA row: recorded in the proof, naming what is covered (all 4 formats, JOIN,
delete-and-remat, read-only NC, write-guard) and what is left uncovered (per-EVENT kit
granularity by the reuse mandate; the 3 unmaterialized tide tables; live-host large-corpus
performance; concurrent rebuild races, single-writer on-demand model).

## Edge Cases

- A source is absent (no tide db / no tg-cleanup json / fresh host) -> that table is
  empty, the rest still work (skip-safe).
- lane-telemetry sourcing quirk (no main-guard) -> `|| true; set +e` shape (impl-notes).
- `GATE` reason field contains `|` / malformed `cost=` (schema edge cases 1+4) -> handled
  upstream by lane-telemetry's own parser; `kit_runs` inherits its tolerance.
- tg-cleanup JSON has two shapes (array vs object-of-arrays) -> the reader normalizes
  both, carrying `category` from the object key.
- learned-ledger is a transient queue (rows removed on flush) -> a snapshot, possibly
  0 rows; not an error.

## Failure modes

- DuckDB Python wheel missing the sqlite scanner on some future host -> adapter falls
  back to stdlib `sqlite3` for tide (defensive path).
- The materialized db is corrupt/locked -> `rebuild` deletes + recreates (idempotent).

## Out of Scope

- The render skill (SG-03), the feedback/anomaly loop (SG-04), the full README/proof
  docs polish (SG-05).
- Per-EVENT kit rows (one row per GATE line): `kit_runs` is run-level by the reuse
  mandate; a per-event view would require re-parsing (forbidden). Named, not a gap.
- Any write path to a source ledger; any daemon/scheduled refresh.

## Decision Log

- **Build:** harness = Python + uv (fork 1). Implements: T1.
- **Build:** refresh = on-demand, lazy-rebuild-on-missing (fork 2). Implements: T3.
- **Build:** kit read reuses lane-telemetry `_rows` (no re-parse). Implements: T2.
- **Build:** read-only enforced THREE ways (statement guard incl. multi-statement + PRAGMA
  rejection, `read_only=True`, `enable_external_access=False`). Implements: T3/T4. (HIGH-1)
- DuckDB via Python wheel only, no INSTALL/LOAD (env constraint, impl-notes). (validation)
- db is a derivable cache path, gitignored, delete-and-rematerialize. (rationale)

## Review

- **spec-validate (6 lenses, 2026-07-04):** VERDICT VALIDATED. Blocking lens
  (design-record) PASS: `## Design` real, forks 1+2 resolved. 3 advisory items folded in
  before execute: (1) deterministic ORDER BY -> Design + `show` impl; (2) value-asserting
  tests -> Test plan; (3) name the 3 unmaterialized tide tables -> Technical Design.
- **review-team (security + architecture + contract-fidelity, 2026-07-04):** VERDICT FIX
  -> RESOLVED. Found HIGH-1: a read-verb-first multi-statement `PRAGMA profiling_output`
  chain bypassed the two-layer (guard + `read_only=True`) design and overwrote a real
  source `.json` (demonstrated via the shipped CLI), because `read_only=True` does not gate
  filesystem writes. FIXED three ways (multi-statement rejection + PRAGMA de-allowlist +
  `enable_external_access=False` backstop); new regression `R-guard-pragma` proves the
  attack is refused and the source file byte-identical. Also folded: MED-3 (per-table tide
  copy, no all-or-nothing loss), LOW-2 (`bash -c` argv hardening), the `maxsplit=1`
  deprecation. MED-4 (TSV field-count assertion) accepted as a documented lens tradeoff.
- **fresh-context verifier (V-model right arm, 2026-07-04):** VERDICT PASS. Independently
  re-ran `uv sync` + the suite (22/22, exit 0), spot-checked an AC on its own scratch
  fixture, judged the tests falsifiable (hand-verified values), confirmed no source
  mutation in the code path.

## Open questions

None blocking. Forks 1 + 2 resolved above; fork 3 (anomaly thresholds) is SG-04's, out of
scope here.
