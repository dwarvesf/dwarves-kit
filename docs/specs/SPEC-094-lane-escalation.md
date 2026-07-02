# SPEC-094: Lane mid-flight escalation on emergent scope

Status: VALIDATED
Date: 2026-07-02
Lane: full (new classify trigger + gate-ledger re-plan touching ship-gate enforcement)
Type: feature
Relates-to: ADR-0028 (autonomous-loop hardening, refinement point 4), ADR-0024 (gate-ledger + ship-enforcement, advisory-mid/hard-at-ship), SPEC-053 (lane-classify floor guard / downgrade check), SPEC-061/SPEC-077 (gate-ledger START / START-AMEND routing facts)
Board: kit-hardening mega-goal SG-06 (ops-toolkit `_meta/megagoals/kit-hardening`)

## Problem
The lane is frozen at classify time: every re-classify trigger the kit already has
(`/kit:assign` intake, `/kit:grill` answers, the spec-drift text re-check) keys on the
task's original one-line TEXT, never on scope that only becomes concrete once the SPEC
is written. A `tiny`/`normal` task whose spec introduces auth, a data-model change, or a
migration stays mis-laned for the rest of the run -- the same "untrustable autonomous
run silently under-sizing its lane" failure class ADR-0028 targets. Per ADR-0028
refinement point 4: "Re-run `lane-classify` against the SPEC at the spec->build boundary
(the first point real scope is concrete); a heavier-lane trip escalates + re-plans the
gate-ledger (up-only; the downgrade guard stays; advisory + recorded)."

## Decision
Add a spec->build-boundary re-classification, up-only, advisory, recorded:

1. **`lib/lane-classify.sh escalate <current-lane> <spec-file>`** -- reads the spec
   file's own text, runs it through the existing `classify_core` (the same
   deterministic flag-scoring logic `classify`/`explain`/`check` already use), and
   compares the spec-implied lane's `lane_rank` against `<current-lane>`'s:
   - heavier -> prints `ESCALATE <current> -> <heavier>`
   - same or lighter -> prints `HOLD <current>` (the downgrade guard: reuses
     `lane_rank`, the same function `check` uses, so a lighter re-class is refused
     exactly like an under-sized `check` choice is refused)
   Always exits 0 ("Detect, don't dictate"). It only prints the decision; it does not
   touch the gate-ledger or the spec file.
2. **The caller re-plans up-only at the spec->build boundary.** Wired into
   `commands/execute.md` Prerequisites (right after the spec-status check, before Step
   1 dispatches any task -- the point the spec is VALIDATED/APPROVED and build is about
   to start). On `ESCALATE`:
   - `bash lib/gate-ledger.sh start --amend <rid> <heavier> ...` -- readers take the
     LAST START-AMEND (SPEC-077), so the ledger's effective lane becomes `<heavier>`
     and `required <heavier>`'s extra measure-twice gates are now required.
   - Bump the spec's `Lane:` header UP to `<heavier>` (never down) -- `hooks/ship-gate.sh`
     reads that header (`hooks/ship-gate.sh:140`) to pick the required gate set, so the
     heavier set is enforced at ship.
   - `bash lib/gate-ledger.sh action <rid> "lane escalated ..."` -- one durable line.
   On `HOLD`: no action.

This reuses the kit's existing heavy destination (the `full` lane) and the existing
downgrade-guard mechanism (`lane_rank`); it adds only the missing TRIGGER (a
re-classify at the spec boundary, not classify-time text).

## Acceptance criteria
- AC1: `lib/lane-classify.sh escalate <current-lane> <spec-file>` exists; classifies
  the spec file's own text via `classify_core`; prints `ESCALATE <cur> -> <heavier>` or
  `HOLD <cur>`; exits 0 in both cases.
- AC2 [up-only]: a `tiny` current lane against a spec whose text carries
  auth/data-model/migration scope escalates to `full`.
- AC3 [downgrade guard, negative control]: a `full` current lane against a spec whose
  text is trivial (no hard/soft flags) HOLDS at `full`; it never downgrades.
- AC4 [re-plan]: after `gate-ledger.sh start` at a lighter lane then
  `start --amend` at the heavier lane, `required <heavier>` returns strictly more
  gates than `required <lighter>`, and the ledger's effective lane (last
  START/START-AMEND) is the heavier one.
- AC5 [advisory + recorded]: `escalate` always exits 0 (including on ESCALATE); the
  `commands/execute.md` wiring documents the mechanism as advisory + recorded, never a
  mid-flight hard block (ADR-0024).
- AC6: the classify-time triggers (task text, grill answers, spec-drift re-check) are
  unchanged; the downgrade guard (`lane_check`/`lane_rank`) still blocks a lighter
  re-classification for its existing callers.

## Tasks
- T1: `lib/lane-classify.sh` -- add the `escalate` verb + `main()` dispatch + usage
  string.
- T2: `commands/execute.md` -- wire the spec->build boundary re-check into
  Prerequisites (before Step 1 dispatch).
- T3: `tests/test-lane-escalation.sh` -- positive escalate, gate-ledger re-plan,
  downgrade-guard negative control, advisory-exits-0 assertion.
- T4: `docs/verification/lane-escalation.md` -- table-first proof-of-done.
- T5: `docs/implementation-notes/lane-escalation.md` -- deltas from this spec.

## Verification
```
bash tests/test-lane-escalation.sh   # AC1-AC6
bash tests/test-meta.sh              # stays green (no lib usage-string regressions)
bash tests/test-hooks.sh             # stays green
```

## Out of Scope
- The classify-time triggers (task text at `/kit:assign`, `/kit:grill` answers, the
  spec-drift text re-check) -- unchanged, per ADR-0028 point 4 ("this supplies only
  the missing TRIGGER").
- The downgrade guard itself (`lane_check`/`lane_rank`) -- preserved, reused, not
  modified beyond confirming it still blocks.
- A new lane, or any lane-relaxation/downgrade mechanism of any kind.
- A full re-plan of the run (only the gate-ledger's required-gate set and the spec's
  `Lane:` header move; task breakdown, phases, and dispatch order are untouched).

## Decision Log
- DEC-001: `escalate` re-classifies the SPEC FILE's own text (not the original
  one-line task description) -- the spec is the artifact that carries emergent scope;
  the original task text is exactly what already failed to catch it.
- DEC-002: the caller does the gate-ledger/spec-header mutation, not `escalate`
  itself -- keeps the classifier a pure, side-effect-free advisory function
  (mirrors `check`, which also only prints + logs, never mutates a spec or ledger).
