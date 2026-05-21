# docs/absorption/

Dated, proposal-only absorption reports written by `/user:absorb` (SPEC-004). Each file is a point-in-time audit of the kit's upstream sources against the kit, scored by the adoption rubric in `docs/ABSORPTION.md`. Nothing here is absorbed automatically; an approved proposal flows through the WORKFLOW.

## Naming + collisions

`YYYY-MM-external.md`. Same-month re-runs append a numeric suffix (`YYYY-MM-external-2.md`); **never overwrite** (overwriting destroys the point-in-time audit).

## What each run records

- The ranked candidate table (top <=15) plus an **overflow appendix** (gate-passers below the display cap, listed not dropped).
- A **recommend-external** section for binary/runtime-needing candidates (PHILOSOPHY section 3).
- A **no-drift / no-candidates** body when a run finds nothing, so the directory is the **last-run ledger** (staleness is visible on the next run).
- A machine-readable **baseline footer** of lane-B seed-repo HEAD SHAs (the since-last-run baseline; WebFetch has no diff, so the SHA ledger is how "changed" is computed).

## Handoff

Approved ADOPT/ADAPT -> a `_meta/BACKLOG.md` item -> a SPEC -> the full WORKFLOW + a README Credits citation + a PHILOSOPHY section 5 soak. Only approved outcomes leave this directory; the full scan (including rejects + rationale) stays here as the audit record.

This directory is NOT the backlog and NOT `TODOS.md`; it is the absorption run-history. See the state model in `docs/architecture.md`.
