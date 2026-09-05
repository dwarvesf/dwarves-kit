# SPEC: bench

> Written 2026-09-06, after the fact, for the kit contract (SPEC-200 C3): every module carries a SPEC. `bench` entered as a Python harness (runner, events, report, dashboard) with its own README, METRICS and test catalog under `docs/`, and was the one module with no SPEC.md. This is a description of the code as it stands, not a redesign; where it and the README disagree, the code wins.

## Problem

The kit's loops (orchestrate, gate, review) need a repeatable way to measure a change against a suite of fixed scenarios and compare two runs, so a prompt or hook edit is judged on numbers rather than on one anecdote.

## Shape

| Piece | Role |
|---|---|
| `bench.py` | runner: loads a suite from `suites/`, executes each scenario, hashes inputs, scores outputs, writes a run under `runs/` |
| `events.py` | the event stream a run emits (start, scenario, score, end) that the report and dashboard consume |
| `report.py` | summarize one run, diff two runs, render HTML |
| `dashboard.py` | the terminal frontend over the same events: state machine, mid-run frame, roundtrip |
| `docs/METRICS.md` | what each score means and how it is derived |
| `docs/test-catalog.md` | the L1 / L2 / L3 coverage map |

## Acceptance

- A suite runs end to end and leaves a run directory whose summary matches its own events (`tests/test_bench.py`).
- Two runs diff without recomputing scores (`tests/test_report.py`).
- The dashboard renders a mid-run frame and round-trips a finished run (`tests/test_dashboard.py`, `tests/test_tui.py`).
- Repo-root entry: `bash tests/test-bench.sh` runs every module test the same way CI does.

## Out of scope

Scenario authoring guidance and the metric definitions live in `docs/`; this SPEC does not restate them.
