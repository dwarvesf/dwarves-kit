# SPEC-076: V-model descent contract (review-gated steps on every lane)

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery)
Type: spec-feature / behavioral
Board: ID-068

## Problem

The operator's intake decision (2026-06-10, item 4): every left-arm step must pass
a review lens + feedback loop BEFORE the work descends to the next step, on EVERY
lane, including tiny ("scale the lens weight to the lane, never waive the gate").
Today: (a) the tiny lane has NO review obligation at all (matrix cell `skip`), so
the obligation IS waived on one lane; (b) nothing checks descent ORDER , a run can
record spec before think disposed, build before test-plan disposed, and only the
ID-050 display marker hints at it after the fact.

## Decision

1. **Obligation everywhere**: the matrix's tiny x Review cell flips `skip` ->
   `run-lite`. Tiny's review weight = a recorded self-review note (one line on the
   ledger); the OBLIGATION now exists on all 5 lanes (tiny build+review, backfill
   review lite, bug/normal/full unchanged). The matrix stays the single source;
   `gate-ledger.sh plan tiny` derives the new 2-phase plan with no code change.
2. **Descent detector**: new verb `gate-ledger.sh descent <rid> <lane>`. The
   lane's PLAN ORDER (already lane-scaled by the matrix) IS the descent order , no
   second pair table to drift. The verb replays the ledger timeline: a phase
   recorded while an EARLIER plan phase is still undisposed at that timestamp is a
   DESCENT violation (`<phase> recorded before <earlier> disposed`). Exit 0
   always; output `descent clean` or the violation lines.
3. **Ship-time accounting, never a mid-flight block** (ADR-0024 preserved):
   hooks/ship-gate.sh prints one advisory line with the violation count when
   `descent` reports any; never blocks. Promotion to a hard gate is a retro
   decision AFTER telemetry shows violations correlate with escapes (SPEC-073
   metric framework).
4. **The right arm stays as built**: verify-twins (validate/critique/review/
   doc-verifier/proof-of-done) already exist per phase; this spec wires the ORDER
   discipline and the missing tiny obligation, not new review machinery.

## Acceptance criteria

- AC1: `plan tiny` lists build AND review; `required tiny` still lists only
  build (run-lite is an obligation, not a measure-twice gate) , the matrix edit
  changes the plan, not the enforcement set.
- AC2: a fixture ledger recording build before grill disposed -> `descent` names
  the violation; an in-order ledger -> `descent clean`; exit 0 both ways.
- AC3: ship-gate prints the descent advisory on a violating run; silent on a
  clean one; never blocks (exit unchanged).
- AC4: skipped-with-reason disposes for descent exactly as for progress
  (SPEC-063 agreement); a bare skip does NOT dispose.
- AC5: suites green; NC: disabling the descent case arm flips its pins RED.

## Test plan

| # | Case | Proof | Expected |
|---|------|-------|----------|
| 1 | AC1 plan | `plan tiny` | 2 lines: build, review |
| 2 | AC1 required | `required tiny` | build only |
| 3 | AC2 violation | fixture: build recorded, grill undisposed | violation line names both phases |
| 4 | AC2 clean | in-order fixture | `descent clean` |
| 5 | AC3 advisory | ship-gate fixture w/ violating ledger | advisory on stderr, exit 0 |
| 6 | AC3 silent | clean ledger | no descent advisory |
| 7 | AC4 disposal parity | fixture with skipped-with-reason then next phase | clean |
| 8 | AC4 bare skip | bare `skipped` then next phase | violation |

Failing-first where behavior exists (rows 1 is RED pre-matrix-edit; rows 3-8 RED
pre-verb). NC: comment the `descent)` case arm -> verb rows RED; restore.

## Verification

- Failing-first: 8 RED on the pre-fix tree -> implementation -> green; review
  fixes reworked the disposal semantics (lite-only implicit) -> 386/386.
- Suites: hooks 386/386, meta 442/442, e2e 20/20.
- NC: descent case arm disabled -> 6 RED -> restored green.
- Live dogfood: this run's own ledger reports `descent clean` under the full
  lane, before AND after the review rework.

## Review

Date: 2026-06-11. Multi-lens (correctness 5/10, contract-consistency 7/10).
Fixed in-branch:

- Correctness HIGH: unrecorded run-lite phases produced false violations on
  every natural run -> run-lite plan phases are implicit checkpoints; grill
  (intake, the universal done-first) and required phases stay REAL checkpoints
  (the first implicit rule over-included grill; the suite caught it, semantics
  narrowed to lite-only). MEDIUM: violations dedup to one line per (phase, gap)
  pair; natural-skip + off-plan + dedup fixtures added.
- Contract HIGH: the composition section still said "tiny (1 phase)" -> updated.
  MEDIUM: RLANE derivation decoupled from the ID-062 build-ran gate (a run can
  violate order without ever recording build). LOW: AGENTS.md descent one-liner
  added.

Post-fix: hooks 386/386, meta 442/442, e2e 20/20. Verdict: SHIP.
