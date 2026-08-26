# ID-444: generic gate-ledger history export

## Claim

`gate-ledger.sh history [--lane L] [--json]` exports one row per run over all
gate ledgers: rid, lane, repo, first/last timestamp, and the GATE ran/skipped
counts, optionally filtered to a lane. Ported generically from
learning-kit/bin/study-history so the dev kit and every vertical share the verb.

## Run table

| # | Action | Result |
|---|---|---|
| 1 | `bash tests/test-gate-ledger-history.sh` | 9/9 passed |
| 2 | `bash tests/test-gate-outcome.sh` (regression: existing gate reader unchanged) | 22/22 passed |
| 3 | manual: `gate-ledger.sh history` against a fixture run | header + `r1,full,dwarves-kit,…,1,1`, rc 0 |
| 4 | `gate-ledger.sh history --lane study` | excludes the `full` run (lane filter) |
| 5 | `gate-ledger.sh history --json` | JSON array with rid/lane/repo/gates_ran/gates_skipped |
| 6 | empty runs dir | header-only (`[]` for --json), honest-empty |
| 7 | `gate-ledger.sh history --bogus` | rc 64 (unknown flag) |

## Debt note

grep -c exits 1 on zero matches; under the file's `set -euo pipefail` that would
abort a run with zero `ran` or zero `skipped` lines mid-loop. The counts are
therefore guarded with `|| true` (the printed count is kept; only the exit code
is neutralized). This was caught by C1 in the test (a run with one `ran`, zero
`skipped`).

## Review

Reviewed through the kit lenses before merge (inline; subagent dispatch was
down). Architecture: pure read-side addition at the same layer as the other run
ledger verbs, no I/O other than the ledger read. Test coverage: invariants
(header, per-lane counts, lane filter both ways, JSON fields, honest-empty)
asserted; regression suite kept green. No blockers.
