# SPEC-099: lane-telemetry render (routing diagram + run counts)

Status: VALIDATED
Date: 2026-07-02
Lane: full (adds a subcommand to lib/lane-telemetry.sh, a covered enforcement/telemetry lib)
Type: feature
Relates-to: SPEC-061 (lane-telemetry record+aggregate), SPEC-097 (durable corpus), SPEC-098 (lane-telemetry is now hard-gated)
Board: ops-toolkit ID-150 (narrowed remainder); kit-telemetry mega-goal SG-04

## Problem
The record+aggregate half of lane telemetry exists (`report`/`misfires`, SPEC-061), but
lane usage is not VISUALIZED: there is no task-type -> lane -> gate routing view with run
counts. ID-150 (narrowed) asks for the render/dashboard over the existing data, now that
SG-01 made the corpus durable.

## Decision
Add a `render` subcommand to `lib/lane-telemetry.sh` that draws, from the durable ledgers
(reusing `_rows()`, no second parser, no new dependency):
1. a `task-type -> lane` table with run counts + gates(ran/skip/override) + ships,
2. an ASCII routing flow grouping task-types by the lane they routed into,
3. per-phase gate coverage (how many runs recorded each gate ran),
4. an optional positional filter `render [<lane-or-type-substring>]` that narrows to matching
   runs (table, flow, and gate-coverage all respect it).
ASCII + markdown only, TTY-gated bold reused from the file (pipe-safe). A dated markdown
snapshot lands at `docs/research/2026-07-02-lane-usage-snapshot.md`.

## Acceptance criteria
- AC1: `render` prints the routing header, a type->lane table, the ASCII flow, and gate coverage.
- AC2: run counts are correct (a 3-run seeded corpus reports 3 runs; the type->lane rows sum to 3).
- AC3 [filter]: `render <lane>` narrows to matching runs only (a `full` filter excludes normal-lane runs), and the gate-coverage respects the filter.
- AC4 [filter no-match]: `render <nomatch>` prints an honest "no runs match", not a crash.
- AC5 [graceful-empty, NEGATIVE CONTROL]: an empty/fresh LOG_DIR renders "no runs recorded yet", never a crash or fake zeros.
- AC6 [no regression]: `test-meta.sh`, `test-hooks.sh` stay green; `report`/`misfires`/`trace` unchanged.

## Tasks
- T1: `lib/lane-telemetry.sh` -- `render()` + dispatch `render) render "$@"` + usage/header.
- T2: `tests/test-lane-telemetry.sh` (new) -- AC1-AC5 over a seeded corpus + the empty NC.
- T3: `docs/research/2026-07-02-lane-usage-snapshot.md` -- dated capture (full + filtered).
- T4: `docs/verification/lane-dashboard.md` -- table-first proof (2-3 captures).
- T5: `.github/workflows/test.yml` -- wire the new suite into CI.

## Verification
```
bash tests/test-lane-telemetry.sh   # AC1-AC5, 13 pins
bash lib/lane-telemetry.sh render          # real-corpus capture
bash lib/lane-telemetry.sh render full     # filtered capture
bash tests/test-meta.sh ; bash tests/test-hooks.sh   # stay green
```

## Out of Scope
- A web UI, charts/images, a new binary, per-repo dashboards (contract's Not-list).
- Collecting/aggregating (exists, SPEC-061); storage (SG-01); rule changes (SG-03).
- Fixing the untracked-run dominance (ID-085) -- render surfaces it honestly, does not fix it.

## Decision Log
- DEC-001: reuse `_rows()` rather than a new parser -- one aggregation source, and render
  automatically inherits START-AMEND / first-wins semantics.
- DEC-002: the filter is a LITERAL substring match (awk `index()`, not `~`) on lane OR type
  -- one arg covers "show me the full-lane runs" and "show me the eval runs" without a flag
  grammar, and a filter that is a regex metacharacter (`.`, `[`) is a plain string, never an
  awk regex that over-matches or crashes (review robustness fix). The match is lane OR type,
  so `render full` intentionally also includes a `normal`-lane run whose TYPE contains "full"
  (e.g. `full-stack`); this is by design (one filter for "the full lane" and "full-stack
  work") and is pinned in the test so the substring boundary can't silently regress.
- DEC-004 (review): gate-coverage counts DISTINCT runs per phase (dedupe on rid+phase), not
  raw ledger lines, so a phase re-recorded within one run (a retry) never inflates the count
  past the header's run total.
- DEC-003: graceful-empty returns exit 0 with an honest message (not an error) -- a fresh
  install running `render` is a normal state, not a failure.
