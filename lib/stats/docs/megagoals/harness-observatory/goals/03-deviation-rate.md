# Sub-goal 03: deviation-rate (`impl_notes` adapter + the upstream-unknowns bridge)

**Merge policy:** auto
**Time budget:** 1.5-2 hours of loop work
**Proof:** full reviewable proof: run-table on the real implementation-notes corpus; golden fixtures for all three classes; the honest-zero NC; coverage-delta row.
**Design:** bearing
**Depends on:** 02
Model: sonnet
**Branch:** `feat/lo-deviation-rate`
**PR base:** `feat/lo-defect-corr`
**Over-test: yes** (the honest-zero NC is load-bearing: flagging honest zeros teaches people to stop writing the marker)

## Outcome

The bridge between upstream unknowns and downstream escapes: an `impl_notes` adapter over the hook-enforced `docs/implementation-notes/<slug>.md` files (`repo, slug, file, n_deviations, zero_marker, first_ts, last_ts`), a `ledger deviation-rate` query JOINing `git_fixes` with three classes (UNDER-SPECCED >= 3 deviations; CLEAN 0 + no later fixes; SUSPECT zero_marker + later fix() on the same files), and an `unknown-density` anomaly proposing "condition grill ON for this repo/domain" (propose-not-autofile).

Covers: ID-248.

## Quality bar

Same single-source schema mechanism; parser matches the hook-enforced entry shape (`## YYYY-MM-DD HH:MM <title>`) and the exact zero-marker line, tolerant of prose drift around them. Class thresholds are named tunables.

## How to close the loop

- Golden fixtures: one file per class; tests assert UNDER-SPECCED / CLEAN / SUSPECT exactly.
- Honest-zero NC (load-bearing): zero_marker + NO later fixes = CLEAN, never SUSPECT, asserted.
- Real run: `uv run ledger deviation-rate --table` over ops-toolkit + dwarves-kit notes; captured run-table.
- Anomaly: fixture pushing rolling median over threshold stages ONE proposal into the cc-backlog staging buffer (never a board write), asserted; below threshold stages nothing.
- Over-test parser edges (multiple entries same day, missing marker, both marker AND entries = malformed -> counted as entries + logged); coverage-delta row.
- Kit lane + gate-ledger records before push.

**Done =** all three class fixtures + the honest-zero NC asserted green AND the real-corpus run captured, coverage-delta committed.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 04-anomalies-advisor; name where gate-yield + fix-correlation live for its conditioning. 3. `DECISIONS.md`: thresholds chosen + malformed-file policy. 4. EXIT.

## Scope edges

**In:** impl_notes adapter, deviation-rate command, unknown-density anomaly, tests, proof docs; `tools/ledger-observatory/` only.
**Out:** ceremony/token-runaway/advisor (04); any change to the impl-notes hook or format.
**Not:** true runtime recall instrumentation; auto-filing board rows.

## Where to look

`docs/benchmark-followup.md` change 5; `research/2026-07-04-fable-unknowns-absorption.md` Design 2; the global CLAUDE.md implementation-notes contract (entry shape + zero-marker line); `anomalies.py` for the propose contract.

## PR body

`impl_notes` adapter + `deviation-rate` (UNDER-SPECCED/CLEAN/SUSPECT) + `unknown-density` anomaly: the upstream half of the benchmark. Stacked on defect-correlation; review after it. Verification per proof-of-done. Covers ID-248.

## Notes

