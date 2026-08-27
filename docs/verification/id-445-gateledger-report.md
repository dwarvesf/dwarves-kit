# ID-445: periodic-report verb over gate-ledger

## Claim

`gate-ledger.sh report --period week|month [--lane L]` prints a cross-cutting
markdown table (rid, lane, repo, gates ran/skipped) for every run whose START
falls in the window, plus totals. The smallest useful absorb: `mega.sh
cmd_report` stays per-mega-goal telemetry and does not satisfy this; `report`
is the sibling verb next to `history` in gate-ledger.sh, the ledger corpus
both would otherwise re-derive separately.

## Run table

Command: `bash tests/test-gate-ledger-report.sh`
Exit: 0
Verdict: PASS (8/8 passed)

| # | Action | Result |
|---|---|---|
| 1 | `bash tests/test-gate-ledger-report.sh` | 8/8 passed |
| 2 | `bash tests/test-gate-ledger-history.sh` (regression: sibling verb unchanged) | 9/9 passed |
| 3 | manual: `gate-ledger.sh report --period week` against a fixture run | markdown table + `**Totals:** 1 runs, 2 gates ran, 1 gates skipped` |
| 4 | `gate-ledger.sh report --period month` against an empty runs dir | header + `No runs recorded.`, honest-empty |
| 5 | `gate-ledger.sh report --period year` (negative control: unknown period) | rc 64 |

## NEGATIVE CONTROL

C3 in the test backdates a run's START line 40 days and asserts a 30-day
(`month`) window excludes it (`No runs in this window.`). Proves the period
filter actually filters by time, not just by presence of `--period`. Ran the
suite again with C3's backdating step commented out: C3 flips RED (the old
run stays IN the window and the assertion fails), confirming the check is
live, then restored.

Command: `bash tests/test-gate-ledger-report.sh` (C3 backdate step removed)
Exit: 1
Verdict: FAIL as expected (RED), restored immediately after

## Review

Reuses the existing `history()` scan loop's per-file field extraction and the
portable ISO8601 cutoff idiom already shipped in
`lib/learn/weekend-batch.sh`'s `_cutoff_iso` (copied locally rather than
factored into a shared lib module: six lines, one other caller, no other
coupling). No new I/O beyond what `history()` already does.
