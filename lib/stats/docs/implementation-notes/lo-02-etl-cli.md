# Implementation notes: SG-02 the `ledger` tool (ETL + CLI)

The DELTA from the spec (`SPEC-127-etl-cli.md`) + SG-01's contracts. Not a mirror:
only decisions the spec did not pin, deviations (with why), tradeoffs, and constraints
the spec/contract missed. Reference, don't restate.

## 2026-07-04 Environment constraint: DuckDB extensions must come from the Python wheel, not the CLI

**Context.** The design (ROADMAP + adapter-contracts) says "DuckDB reads sqlite + json
natively." Two ways to run DuckDB here: the Homebrew `duckdb` CLI (v1.5.4) or the
`duckdb` Python package (also 1.5.4, pulled by `uv add duckdb`).

**Decision.** The tool runs DuckDB via the **Python package only**. Verified live on
this host: `import duckdb; con.sql("read_json_auto(...)")` and
`ATTACH '...' (TYPE sqlite)` both work with **no network install**. The Python wheel
ships json (core) and autoloads `sqlite_scanner` from its bundled set.

**Why.** The Homebrew CLI has NO cached json/sqlite extension for v1.5.4 (cache only
has v1.2.2/v1.3.0), and `INSTALL sqlite`/`INSTALL json` hang (no network in this
environment). A CLI-based tool would be un-runnable here. The Python harness (open-fork
1 = Python+uv anyway) sidesteps this entirely.

**Impact.** No `LOAD`/`INSTALL` statement anywhere. `read_json_auto` + `ATTACH (TYPE
sqlite)` are used directly; if a future host lacks the bundled scanner the adapter falls
back to stdlib `sqlite3`/`json` (defensive, see the adapter module).

## 2026-07-04 Reusing lane-telemetry for the kit read (the mandated reuse)

**Context.** The contract is emphatic: REUSE `lib/lane-telemetry.sh` for the kit-side
pipe-log read; do NOT re-implement the `ISO8601 | VERB | payload` parse.

**Decision.** The kit reader shells out to lane-telemetry's own `_rows()` awk state
machine (the SPEC-061 parser) and ingests its TSV into a DuckDB `kit_runs` table. The
invocation is `bash -c 'source <lane-telemetry.sh> >/dev/null 2>&1 || true; set +e;
_rows'`.

**Why the `|| true; set +e` shape.** lane-telemetry.sh has no
`[[ ${BASH_SOURCE} == $0 ]]` guard: sourcing it runs `main "$@"`, which with no valid
subcommand returns 64 AND the script's own `set -euo pipefail` re-arms errexit, so a
naive `source` aborts the subshell before `_rows` is callable. `|| true` swallows main's
64; `set +e` re-disables errexit so `_rows`' internal non-zero steps don't abort. Proven
to emit the 70-row live kit table.

**Granularity tradeoff (a real deviation to record).** lane-telemetry's `_rows()` is
RUN-level (one row per `<rid>.log`, with `ran/skip/ovr` gate COUNTS), not per-event. So
`kit_runs` exposes run-level facts, not one row per individual GATE line. This is the
honest consequence of the reuse mandate: re-parsing to per-event rows would be exactly
the "re-implement the parse" the contract forbids. The cross-ledger JOIN and all queries
are expressed at run granularity (e.g. `kit_runs` x `tide_moves`), which satisfies the
contract's "a cross-ledger JOIN works" without forking the parser. Documented as a
known scope edge, not a gap.

## 2026-07-04 The db is a temp/derivable lens (delete-and-rematerialize)

**Decision.** The materialized DuckDB db lives at a derivable cache path
(`$LEDGER_OBSERVATORY_DB`, default `~/.cache/ledger-observatory/ledger.duckdb`), NEVER
in the repo. `ledger rebuild` deletes + re-creates it from the canonical files; a query
on a missing db lazily rebuilds first. Deleting the file loses nothing. This is the
named delete-and-rematerialize property, tested directly.

## 2026-07-04 HIGH-1 (review): the read-only guard needed a THIRD layer (filesystem)

**Context.** The initial design enforced read-only two ways: a statement guard +
`read_only=True`. A security review found this insufficient.

**The bypass (demonstrated via the shipped CLI).**
`ledger query "PRAGMA enable_profiling='json'; PRAGMA profiling_output='<a source .json>';
SELECT 1"` overwrote a real tg-cleanup source file, because: (a) the guard checked only
the FIRST statement's verb (`PRAGMA`, then-allowlisted); (b) DuckDB executes every
`;`-separated statement; (c) `read_only=True` gates the db's catalog/rows but NOT
filesystem writes, and `PRAGMA profiling_output` writes a file. Direct violation of the
binding "never write back to a source ledger."

**Fix (defense in depth, all three).**
1. `enable_external_access=False` on the query connection , the real backstop: blocks
   `COPY TO`, `PRAGMA profiling_output`, `read_csv`, sneaky `ATTACH`. Verified SELECT/JOIN/
   DESCRIBE/WITH still work. NOT set on the rebuild connection (it needs the sqlite ATTACH).
2. Reject MULTI-STATEMENT input in `is_read_only` (a `;` after the single trailing one ->
   refuse). A read-verb first statement can't vouch for the rest.
3. Drop `pragma` from the read allowlist entirely (DESCRIBE/SHOW cover read introspection).

**Regression.** `R-guard-pragma` in the suite issues the exact attack + a lone PRAGMA + a
`COPY TO`, asserts all refused (exit 3), and sha256s the source file before/after
(byte-identical). Suite went 22 -> 26 green.

**Also folded from the same review.** MED-3: `_load_tide` now copies each tide table
independently (a missing sibling no longer discards a good one). LOW-2: the kit reader's
`bash -c` passes the script path as `$1` argv, never string-interpolated. `re.split(...
maxsplit=1)` fixes a DeprecationWarning. MED-4 (assert the lane-telemetry TSV field count)
accepted as a documented lens tradeoff, not fixed.

## 2026-07-04 Post-ship: the double-defined schema drift bug (TIER-4 review finding)

**Context.** A TIER-4 architecture review found that `adapters.py`'s column-name lists
(`KIT_COLUMNS`/`TG_COLUMNS`/`LEARNED_COLUMNS`) and `materialize.py`'s `CREATE TABLE` DDL
(`_KIT_DDL`/`_TG_DDL`/`_LEARNED_DDL`) were two independently hand-synced definitions of
the same 3 table schemas. Nothing checked they agreed on column names/order, so a
same-length reordering of one without the other would silently mislabel every column
loaded into DuckDB , ironic for a tool whose whole thesis is killing silent drift.

**Decision.** Chose the single-source-of-truth fix over a load-time-assertion-only
fallback: added `schemas.py` holding exactly one `(name, type)` spec per table.
`adapters.py`'s column lists and `materialize.py`'s DDL strings both derive from it, so
there is structurally no second place to drift from. Kept a load-time
`schemas.assert_parity()` call in `_load_python_table()` too, as belt-and-suspenders
against a future edit that re-forks the two representations (e.g. a DDL string
hand-edited without going through `ddl()`); this is defense-in-depth, not the primary
fix.

**Why not assertion-only.** An assertion-only fix (keep the two hand-written lists,
just check they match at load time) would still leave two places to edit on every future
column change, i.e. still relies on a human remembering to update both plus the
assertion catching it. Single-sourcing removes the second edit site entirely; the
assertion is now genuinely a backstop, not the only guard.

**Regression test (`tests/test-schema-parity.sh`).** Proves both directions: (1) POSITIVE
, today's real `adapters.*_COLUMNS`/`materialize.*_DDL` pairs match for all 3 tables; (2)
NEGATIVE (load-bearing) , `schemas.assert_parity()` called with a deliberately reordered
DDL (same columns, two swapped) and with a DDL missing one column both raise
`AssertionError`; (3) `materialize.rebuild()` is proven to actually invoke the guard (not
dead code) by monkeypatching `assert_parity` to always-raise and confirming the exception
propagates out of `rebuild()`.

**Scope.** The tide tables (`tide_moves`/`tide_tier_b_calls`) were NOT touched , their
column list (`_TIDE_MOVES_COLS`/`_TIDE_TIER_B_COLS`) has only one definition (the DDL is
synthesized from it as `VARCHAR` for every column), so there was no double-definition to
fix there.

## 2026-07-04 impl-notes + spec co-located under the tool

Per the ops-toolkit co-location rule (one-tool records live under `tools/<x>/docs/`),
the spec, this impl-note, and the per-feature proof index all co-locate under
`tools/ledger-observatory/docs/`, not repo-root `docs/`.
