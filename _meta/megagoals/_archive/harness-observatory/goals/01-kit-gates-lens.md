# Sub-goal 01: kit-gates-lens (`kit_gates` per-gate table + `gate-yield`)

**Merge policy:** auto
**Time budget:** 2-3 hours of loop work
**Proof:** full reviewable proof: run-table (commands + exit codes + real stdout slices) covering rebuild + gate-yield on the REAL 63+ run ledgers; golden-fixture assertion on a known rid set; the FP negative control; COVERAGE-DELTA row from the over-test pass. Lands in `tools/ledger-observatory/docs/proof-of-done.md` (feature index per SPEC-016).
**Design:** bearing
**Depends on:** none (chain head)
Model: sonnet
**Branch:** `feat/lo-gate-yield`
**PR base:** main (ops-toolkit)
**Over-test: yes** (flagship benchmark query; a wrong benchmark is worse than none)

## Outcome

The kit's per-gate emit finally has a reader: a `kit_gates` table (one row per GATE line: `rid, gate, outcome, caught, reason, start_ts, end_ts`) parsed from the ledger markers (kit #158's `caught=`/START/END; `reason=` tolerated-if-absent, the kit-absorptions mega adds the emitter), plus `ledger gate-yield [--json|--table]`: per gate `ran / override / skipped / caught / override_pct`. The ceremony signal (high-ran + zero-caught) becomes a query instead of a hand probe.

Covers: ID-245 changes 1-2 (`tools/ledger-observatory/docs/benchmark-followup.md`).

## Quality bar

Single-source the schema exactly as `schemas.py` already does (one `(name, type)` spec; DDL + column names derived; `assert_parity` guards). Read-only, delete-and-rematerialize contract untouched. Parser tolerates historical lines (no `caught=`, no `reason=`) without dropping rows.

## How to close the loop

- `uv run ledger rebuild` then `uv run ledger tables` shows `kit_gates` with a plausible row count (>= gates across 63 runs); capture stdout.
- Golden fixture: a committed fixture ledger dir with known rids; test asserts exact `gate-yield` numbers.
- FP NC (load-bearing): a gate with legitimate skips and no caught signal in the FIXTURE is reported with its skip counts, NOT dropped or mislabeled.
- Materialize the 2026-07-04 hand-computed cut as the first real run-table row (grill ~82% skip, ui-design ~100% skip, core gates 2-4% override) and note any drift vs the hand probe.
- Over-test: `/kit:test-plan`-shaped pass over parser edge cases (missing fields, malformed ts, duplicate rids); record the coverage-delta row.
- Kit-adopted repo: run the lane via `bash lib/lane-classify.sh classify`, record each phase via `gate-ledger.sh record` before push (ship-gate enforced).

**Done =** `gate-yield` returns correct numbers on the golden fixture (asserted in tests) AND runs on the real ledgers (captured run-table), with the coverage-delta row committed in the canonical proof.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. Overwrite HOT `HANDOFF.md` (next: 02-defect-correlation; first action + `file:line` pointers incl. the schema spec location). 3. Append invariants to `DECISIONS.md` (e.g. parser tolerance grammar). 4. Report in records, EXIT.

## Scope edges

**In:** `tools/ledger-observatory/src/ledger_observatory/{schemas,adapters,materialize,cli}.py`, tests, docs/proof.
**Out:** anomalies.py (sub-goal 04); git adapter (02); kit-side emitters (kit-absorptions mega).
**Not:** rewriting `kit_runs`; a second schema mechanism; write paths of any kind.

## Where to look

`tools/ledger-observatory/` (shipped module layout); `docs/benchmark-followup.md` changes 1-2; the kit ledger logs under `~/.claude/dwarves-kit/logs/runs/`; original branch specs `docs/megagoal-benchmark:goals/01,02` (intent only, layout predates shipped code).

## PR body

`kit_gates` per-gate table + `gate-yield` ceremony detector over the real gate ledgers. Verification: golden-fixture test + captured real-run table + FP NC + coverage-delta (see proof-of-done). Part of mega-goal harness-observatory (ROADMAP.md). Covers ID-245 (1/3).

## Notes

