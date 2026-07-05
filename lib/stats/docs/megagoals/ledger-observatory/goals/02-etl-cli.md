# Sub-goal 02: the `ledger` tool (DuckDB lens + agent-callable CLI)

**Merge policy:** auto
**Time budget:** 4-6 hours (the widest build , ETL + CLI + over-test).
**Proof:** run-table with COVERAGE DELTA: `ledger rebuild` materializes the DuckDB db from the files · `ledger show <name>` returns a store's rows (--table + --json) · `ledger query "<sql>"` runs a cross-ledger JOIN (e.g. kit gate events × tide moves) · the DELETE-AND-REMATERIALIZE property: delete the db, re-run, identical output (files are canonical) · cross-format read correctness across pipe-log + markdown + sqlite + json · negative control: a query does NOT mutate any source ledger (read-only-by-contract). A COVERAGE-DELTA row names what was covered + what was left uncovered.
**Depends on:** 01.
Model: opus
Effort: high
**Branch:** feat/lo-02-etl-cli
**PR base:** feat/lo-01-schema

## Outcome

`tools/ledger-observatory/` , the `ledger` tool: DuckDB views over the ledgers IN PLACE. One pipe-log reader drains the ~10 schema-uniform kit stores (REUSING `lane-telemetry` for the kit-side read, NOT rebuilding it) + the 3 adapters (DuckDB reads sqlite + json natively; a small markdown adapter for learned-ledger.md). An agent-callable CLI: `ledger show <name>` (a named store's rows), `ledger query "<sql>"` (arbitrary read-only SQL incl. cross-ledger JOINs), `ledger rebuild` (re-materialize the db from the files), each returning STRUCTURED output (`--json` | `--table`). The db is a derivable, disposable LENS: delete it, rebuild, identical , the files stay canonical. Harness = Python + uv (DuckDB SQL for the transform; a thin `uv run` CLI). READ-ONLY by contract (the icy-ops/asus-mesh/growatt-pull shape): it never writes back to a ledger.

## Quality bar

DuckDB is the LENS, never a second source of truth , the delete-and-rematerialize property is a NAMED proof, not a hope. REUSE lane-telemetry (do not re-implement the pipe-log parse). Cross-format read correctness is over-tested (pipe-log + markdown + sqlite + json all read right). The CLI returns machine-parseable structured output (the agent consumes it) and NEVER mutates a source , a read-only-by-contract negative control.

## How to close the loop

`/spec` + `/spec-validate` first (this is design-bearing , write a `## Design` block; pin the view set + the CLI contract; resolve open-fork 1 harness-language and 2 refresh-trigger). Then `/kit:test-plan` + `bash tests/test-ledger-cli.sh`: rebuild-materializes, show/query structured output, the cross-ledger JOIN, the delete-and-rematerialize property, cross-format correctness across all 4 source shapes, and the read-only NC (a query leaves every source byte-identical). Capture the COVERAGE-DELTA row. Assumptions: ROADMAP 02 + open-forks 1/2.

**Done =** `ledger show/query/rebuild` return structured output over all 4 source formats via DuckDB views reusing lane-telemetry, the delete-and-rematerialize property holds, a cross-ledger JOIN works, no source is mutated (read-only NC), the COVERAGE-DELTA row is recorded, tests green.

## Scope edges

**In:** the `tools/ledger-observatory/` package (uv), the DuckDB views + adapters, the `ledger` CLI (show/query/rebuild, `--json`/`--table`), the lane-telemetry reuse, tests + the coverage-delta.
**Out:** the render skill (03); the feedback/anomaly loop (04); the README/proof docs (05); the schema doc (01, this consumes it).
**Not:** a second source of truth / a synced db (lens only, delete-and-rematerialize); a write path to any ledger (read-only by contract); a daemon (on-demand refresh per open-fork 2); re-implementing lane-telemetry.

## Where to look

`tools/icy-ops/` + `tools/growatt-pull/` (the read-only agent-callable CLI shape + the DuckDB-archive query pattern), `lib/lane-telemetry.sh` (REUSE for the kit read), SG-01's schema doc + adapter contracts, DuckDB's native sqlite + json readers, the research Addendum (ETL = a handful of views + a refresh, NOT a custom engine).

## PR body

`ledger` tool (the DuckDB lens): read-only DuckDB views over the ledgers in place (one pipe-log reader over the kit corpus reusing lane-telemetry + native sqlite/json + a markdown adapter) with an agent-callable `ledger show/query/rebuild` CLI returning json/table. Files stay canonical (delete-and-rematerialize). Stacked on #<01's PR>; review after it. Verify: `bash tests/test-ledger-cli.sh` (structured-output + cross-ledger-JOIN + delete-and-rematerialize + cross-format + read-only NC) + coverage-delta. Roadmap: ops-toolkit `_meta/megagoals/ledger-observatory/ROADMAP.md`.

## Notes

<empty>
