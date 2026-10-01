# Spec: make `lane-telemetry.sh misfires` fast

Generated: 2026-10-01
Status: DRAFT
Lane: normal
Depth: standard
References: `lib/telemetry/lane-telemetry.sh`, `tests/test-lane-telemetry.sh`, `lib/gate/gate-ledger.sh` (`check`)
Source: operator approved in session 2026-10-01; measured about 93 s over 197 run ledgers

## Problem

`/kit:retro` and `/kit:wrap` call `lane-telemetry.sh misfires` every time. Over 197 ledgers it takes about 93 s: `_rows` runs twice (about 10 s each, one awk per ledger), and `_shipped_incomplete` spawns `gate-ledger.sh check` 22 times (about 60 s).

## Rules

| # | Rule |
|---|---|
| R1 | `misfires` computes `_rows` once and feeds both awk filters from it. |
| R2 | `_rows` runs one awk over every ledger in glob order. Per-file state resets at `FNR==1`. An empty ledger still yields its row. Output stays byte-identical. |
| R3 | `_shipped_incomplete` caches each `check` verdict in `$LOG_DIR/.shipped-incomplete.cache`, keyed on rid, file size and mtime, under a header that hashes the lane data (root, operator and project kit.toml, plus the gate scripts). A header mismatch drops every entry. A missing or corrupt cache falls back to the live check. The write is a temp file plus `mv`. |
| R4 | Output lines and order do not change. `_boardless` is untouched. |

## Tasks

- [ ] TASK-1 Compute `_rows` once in `misfires` and rewrite `_rows` as a single awk, with an identity test against the old per-file loop.
- [ ] TASK-2 Add the verdict cache to `_shipped_incomplete`, with tests for hit, touch, corrupt line and lane-data change.
- [ ] TASK-3 Proof table with cold and warm timings, CHANGELOG entry.

## Verification

```bash
bash tests/test-lane-telemetry.sh
bash tests/test-meta.sh
bin/test-affected --base origin/master
```

Negative control: revert the `FNR==1` reset, the cache lookup, and the header check one at a time; the matching assert goes red, then restore.
