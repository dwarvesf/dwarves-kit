# Proof of done: ledger-observatory feature `etl-cli` (SG-02)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `etl-cli` feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-127-etl-cli.md`](../specs/SPEC-127-etl-cli.md) |

## Test design

`tests/test-ledger-cli.sh` builds a self-contained fixture set for ALL 4 source shapes
(kit pipe-log via `$DWARVES_KIT_LOG_DIR/runs/`, a generated tide `state.sqlite`, synthetic
tg-cleanup json in BOTH shapes, a fixture `learned-ledger.md`), points every source env
var at it, and asserts hand-verified VALUES (not non-empty counts). The test-plan cases
map onto AC1-AC8 (SPEC-127), plus a HIGH-1 regression (`R-guard-pragma`). No live source is
read; no source is mutated.

## Confirmation run (recorded)

Command: `bash tests/test-ledger-cli.sh` , run 2026-07-03T19:58:05Z (UTC clock), exit 0.

```
== R-rebuild: materialize the db from the files ==
PASS  R-rebuild kit_runs>0 / tide_moves>0 / tg_dialogs>0 / learned>0
== R-show: structured output, both formats ==
PASS  R-show-json (value) / R-show-table (value) / R-show-table (box)
== R-join: a real cross-ledger JOIN (kit_runs x tide_moves) ==
PASS  R-join rows / R-join key (lane full) / R-join count = 2
== R-remat: delete-and-rematerialize is byte-identical (files canonical) ==
PASS  R-remat identical output
== R-formats: cross-format read correctness across all 4 shapes (values) ==
PASS  R-formats-kit (pipe-log) / lane / sqlite / json title / json category / json array-shape / markdown
== R-nc: read-only negative control (a query mutates NO source) ==
PASS  R-nc every source byte-identical after queries
== R-guard: a write-shaped query is refused and cannot mutate ==
PASS  R-guard DELETE refused (exit 3) / DROP refused (exit 3) / db intact after refusal
== R-guard-pragma: the PRAGMA/multi-statement filesystem-write bypass is closed (HIGH-1) ==
PASS  R-guard-pragma multi-statement PRAGMA refused (exit 3)
PASS  R-guard-pragma lone PRAGMA refused (exit 3)
PASS  R-guard-pragma COPY TO refused (exit 3)
PASS  R-guard-pragma source file byte-identical (no write escaped)

== 26 passed, 0 failed ==
```

## Negative controls (falsifiability, load-bearing)

| NC | What | Result |
|---|---|---|
| NC1 read-only | `R-nc` sha256s every source file before + after 2 queries (incl. a cross-ledger JOIN) | all byte-identical , a query mutates NO source |
| NC2 write-guard | `R-guard` issues `DELETE FROM kit_runs` + `DROP TABLE learned` | both refused (exit 3); a follow-up count proves the db is unmutated |
| NC3 delete-and-remat | `R-remat` captures `show kit_runs`, deletes the db file, re-runs (lazy rebuild from files), diffs | byte-identical , the files are canonical, the db is disposable |
| NC4 falsifiability | point `LEDGER_OBS_TIDE_DB` at an absent db | `tide_moves` = 0 and the JOIN count = 0, so `R-formats-sqlite` + `R-join` (assert values 2) go RED , the assertions are real, not vacuous |
| NC5 HIGH-1 write bypass | `R-guard-pragma` fires the exact review-found attack: `PRAGMA enable_profiling='json'; PRAGMA profiling_output='<source.json>'; SELECT 1`, plus a lone PRAGMA + a `COPY TO` | all refused (exit 3); the source `.json` sha256 is byte-identical before/after , the filesystem-write bypass is closed three ways (multi-statement rejection + PRAGMA de-allowlist + `enable_external_access=False`) |

NC4, captured 2026-07-03 (absent tide source):

```
tide_moves rows (expect 0, absent source): [{"n":0}]
JOIN count (expect 0, no tide moves -> the R-join assertion of 2 FAILS): [{"n":0}]
```

## Independent verification (fresh-context verifier)

A separate fresh-context V-model verifier re-ran `uv sync` + the suite (`22 passed, 0
failed`, exit 0), independently spot-checked an AC on its own scratch fixture (rebuild ->
JSON counts; a `DELETE` query refused exit 3, db unmutated), judged the tests falsifiable
(hand-verified values), and confirmed no source-mutation path in the code (sqlite ATTACH is
`READ_ONLY`; `rebuild` deletes only the derivable cache db; `query` is `read_only=True`).
VERDICT: PASS.

## COVERAGE-DELTA

**Covered:** all 4 source formats read correctly (pipe-log via lane-telemetry reuse +
sqlite + json both shapes + markdown), structured output both `--json` and `--table`, a
real cross-ledger JOIN (kit_runs x tide_moves), the delete-and-rematerialize property
(byte-identical), the read-only negative control (checksum before/after), the write-guard
THREE ways (statement guard incl. multi-statement + PRAGMA rejection, `read_only=True`,
`enable_external_access=False`) incl. the HIGH-1 filesystem-write bypass regression, and a
falsifiability NC (absent source turns the value assertions RED).

**Left uncovered (named, not hidden):** (1) per-EVENT kit granularity , `kit_runs` is
run-level because the reuse mandate forbids re-parsing lane-telemetry to per-GATE rows;
(2) the 3 unmaterialized tide tables (`meta`, `review_queue`, `learned_verdicts`) , not
needed for the lens, addable by the same ATTACH pattern later; (3) large-corpus performance
on the live host (functional correctness only, no perf budget); (4) concurrent-rebuild
races , the on-demand model assumes a single writer (no daemon, per fork 2).

## Post-ship fix: schema-drift guard (2026-07-04)

A TIER-4 architecture review found a real latent bug: `adapters.py`'s column-name
lists (`KIT_COLUMNS`/`TG_COLUMNS`/`LEARNED_COLUMNS`) and `materialize.py`'s
`CREATE TABLE` DDL (`_KIT_DDL`/`_TG_DDL`/`_LEARNED_DDL`) were two independently
hand-synced definitions of the same 3 table schemas, with nothing checking they
agreed on column names/order , a same-length reordering of one without the other
would silently mislabel every column loaded into DuckDB. Ironic for a tool whose
whole thesis is killing silent drift.

**Fix (single source of truth):** `src/ledger_observatory/schemas.py` now holds
exactly one `(name, type)` spec per table (`KIT_SCHEMA`/`TG_SCHEMA`/
`LEARNED_SCHEMA`). `adapters.py`'s column-name lists and `materialize.py`'s DDL
strings both derive from it (`schemas.column_names()` / `schemas.ddl()`); there is
no second hand-written place either can drift from.

**Defense-in-depth:** `materialize._load_python_table()` also calls
`schemas.assert_parity(cols, ddl)` immediately before every `CREATE TABLE`, so
even a future edit that re-forks the two representations (e.g. a DDL string
hand-edited without going through `ddl()`) raises loudly at load time instead of
silently mislabeling columns.

**AC9 (new):** the adapter column-name list and the DDL column names/order agree
for all 3 Python-sourced tables, and disagreement is structurally impossible to
introduce silently (single source) + would raise loudly even if it were
(load-time guard).

### Confirmation run (recorded)

Command: `bash tests/test-schema-parity.sh` , exit 0.

```
== P-parity: adapters.*_COLUMNS matches materialize.*_DDL column names/order today ==
OK kit_runs: 15 columns, names/order match
OK tg_dialogs: 14 columns, names/order match
OK learned: 5 columns, names/order match
assert_parity: all 3 real table pairs accepted
PASS  P-parity all 3 tables' adapter columns match their DDL, assert_parity accepts them

== N-drift (load-bearing negative control): assert_parity RAISES on a reordered pair ==
RAISED: schema drift: adapter columns ['rid', 'repo', 'lane'] != DDL columns ['repo', 'rid', 'lane']
PASS  N-drift reordered columns REJECTED (AssertionError raised)

== N-drift-missing (negative control): assert_parity RAISES on a dropped column ==
RAISED: schema drift: adapter columns ['date', 'item', 'kind', 'home', 'status'] != DDL columns ['date', 'item', 'kind', 'home']
PASS  N-drift-missing dropped column REJECTED (AssertionError raised)

== R-load: rebuild() actually calls the guard (not just importable) ==
RAISED: forced: parity guard was invoked
PASS  R-load rebuild() invokes assert_parity on the real load path

== 4 passed, 0 failed ==
```

### Negative controls (load-bearing)

| NC | What | Result |
|---|---|---|
| N-drift | `schemas.assert_parity()` called with a deliberately reordered DDL (same columns, `rid`/`repo` swapped) , simulates the exact original bug shape (same-length reordering) | `AssertionError` raised, not silently accepted |
| N-drift-missing | `schemas.assert_parity()` called with a DDL missing one column (`status` dropped) | `AssertionError` raised |
| R-load | `schemas.assert_parity` monkeypatched to always-raise, then `materialize.rebuild()` invoked against a fixture | the forced exception propagates out of `rebuild()`, proving the guard is actually wired into the load path, not dead code |

### Regression (full suite re-run alongside the fix)

All 5 suites green after the fix, same run: `test-schema-conform.sh` 11/11,
`test-ledger-cli.sh` 26/26, `test-render-skill.sh` 30/30, `test-feedback.sh` 39/39,
`test-schema-parity.sh` 4/4 , 110/110 total, 0 failed.

### Reproduce (fix)

```bash
cd ~/workspace/tieubao/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-schema-parity.sh   # 4 passed, 0 failed; exit 0
```

### Rollback (fix)

Additive-to-refactor, no behavior change on valid input: `schemas.py` is a new file;
`adapters.py`/`materialize.py` changes only replace 3 hand-written column-name lists and
3 hand-written DDL strings with calls that produce byte-identical values (proven by
`P-parity`, which asserts today's real pairs still match). Rollback = `git revert` this
fix's commit(s); `KIT_COLUMNS`/`TG_COLUMNS`/`LEARNED_COLUMNS`/`_KIT_DDL`/`_TG_DDL`/
`_LEARNED_DDL` return to their prior hand-written literals with no other code needing to
change (grep confirmed no other module imports these symbols).

## Reproduce

```bash
cd ~/workspace/tieubao/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-ledger-cli.sh    # 22 passed, 0 failed; exit 0
bash tests/test-schema-parity.sh # 4 passed, 0 failed; exit 0 (schema-drift guard)
```

## Rollback

Additive-only branch (new package + tests + docs under `tools/ledger-observatory/`; the
one moved file is SG-01's proof -> `docs/verification/schema.md`, content preserved). No
existing runtime, daemon, or source ledger is touched. Rollback = `git revert` the branch,
or delete the package; the materialized db is a gitignored cache (`git clean` / `rm` the
cache path), nothing else references it yet.
