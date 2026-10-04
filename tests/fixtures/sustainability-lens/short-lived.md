# SPEC-901: rename the --verbose flag to --debug

**Status:** DRAFT
Lane: tiny
Type: spec-feature

## Problem

`bin/report --verbose` prints debug traces, not more report detail. Users expect more rows.

## Contract

- `bin/report --debug` prints the debug traces `--verbose` prints today.
- `--verbose` stays as an alias for one release and prints `--verbose is renamed --debug` on stderr.
- `--help` lists `--debug` only.

## Design

obvious: a flag rename with a one-release alias.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: rename | `bin/report`, `tests/test-report.sh` | both flags print traces; `--verbose` also prints the rename notice |

## Verification

`bash tests/test-report.sh` exits 0.

## After state

`--debug` is the documented flag.
