# Spec: Docs-wiring for kit-run-integrity (01-05) + a no-orphan wiring check

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (docs-only edits plus one new read-only verification script; no app-behavior
change, no new subsystem, no correctness-critical concurrency).

## Problem

Sub-goals 01-05 of the `kit-run-integrity` mega-goal (gate-outcome emit, wavefront
spec-reservation, advisory coverage-delta, advisory mutation-smoke, generated proof-table,
plus the SPEC-133 reconcile and SPEC-134 security hardening) are merged to master, but none
of them are reflected in the kit's governing surfaces: `AGENTS.md` and `WORKFLOW.md` carry
zero mentions of `OUTCOME`, `coverage-delta`, `mutation-smoke`, `spec-next reserve`, or
`proof-table-gen` (verified by grep against the merged tree at `a9a2e55`). `docs/verification/README.md`
already documents 05 (SPEC-132) reasonably, but not from the ship/proof-of-done moment an
agent would actually be standing at. An agent or operator reading the front-door docs today
has no way to discover that these five surfaces exist, and (per the TIER-4 finding recorded
in ops-toolkit `_meta/megagoals/kit-run-integrity/NOTES.md`) 03/04 are PROSE-INVOKED-ONLY
(an agent can skip the command inside `commands/review-team.md` / `commands/verify.md` with
zero trace; `check()`/`descent()`/`plan()`/`progress()` never notice), which a doc claiming
they are "wired" on the weakest reading would misstate.

## Solution

Surgical doc edits reflecting the FINAL merged state of 01-05, each honestly labeled by its
actual enforcement level (hook-enforced / prose-invoked-optional / operator-invocable), plus
one new read-only no-orphan check that proves each surface has a live call site (reusing the
`tests/test-docs-wiring.sh` no-orphan-sweep pattern already established for ADR-0032).

- **AGENTS.md** -- a short paragraph after the existing "Record your gates (ADR-0024)" line:
  the OUTCOME marker (01, hook-enforced at ship only today), the wavefront SPEC-reservation
  (02, orchestrate.sh's own dispatch path), and a proof-table-gen cross-link (05).
- **WORKFLOW.md** -- three edits: (a) a `SPEC-128` reservation bullet in "Mega-goal delegate
  execution" (02); (b) an OUTCOME-marker bullet + a proof-table-gen cross-link bullet in
  "Gate ledger and ship enforcement" (01, 05); (c) a new "Advisory measurement gates" section
  (03, 04) that states the enforcement asymmetry plainly: hook-enforced (01) vs
  prose-invoked-optional (03/04, invisible to the ledger's status surfaces) vs
  operator-invocable (05), names coverage-delta a diff-line heuristic, and names the
  advisory-to-block promotion as Han's call (not taken here).
- **docs/decisions/0024-gate-ledger-and-ship-enforcement.md** -- a short dated addendum
  naming `OUTCOME` (01) and `MUTATION` (04) as new additive marker types under the same
  convention the ADR already owns (beside `GATE`/`DEBT`/`TOKENS`), no new convention invented.
- **docs/verification/README.md** -- one honesty parenthetical: the CAUGHT/DURATION column
  05 surfaces from 01's marker reflects the Ship phase only today (01's sole live emitter),
  not a per-phase measurement (TIER-4 finding C2).
- **tests/test-kri-wiring.sh** (new) -- a no-orphan sweep, same shape as
  `tests/test-docs-wiring.sh`: one fixed-string grep per surface against its live call site
  (01: `hooks/ship-gate.sh`; 02: `lib/orchestrate.sh` + `lib/spec-next.sh`; 03:
  `commands/review-team.md`; 04: `commands/verify.md`; 133: `lib/proof-table-gen.py`'s real
  marker parse; 134: the path-confinement guard), plus doc-presence assertions that
  AGENTS.md/WORKFLOW.md actually carry the enforcement-level vocabulary, plus a load-bearing
  negative control (a planted "03/04 are hook-enforced" over-claim must be CAUGHT by the same
  sweep function).

**Not changed:** no application behavior in 01-05 themselves; no promotion of 03/04 to a
block (named as Han's call only); no new marker convention; no README.md "Project structure"
edit (that list is already a curated subset, not exhaustive, and none of 01-05 land a file
that list would be expected to carry per a fresh read of its existing entries).

## Design

`obvious: not design-bearing`. No new component, no schema change, no external integration,
no irreversible choice: this is markdown edits reflecting already-merged, already-designed
behavior, plus one verification script that reuses an established pattern
(`tests/test-docs-wiring.sh`) verbatim in shape. A diagram would restate the file list above
without adding information.

## Acceptance criteria

1. `AGENTS.md` and `WORKFLOW.md` each mention all of: the OUTCOME marker (01), the wavefront
   SPEC-reservation (02), coverage-delta (03), mutation-smoke (04), and proof-table-gen (05).
2. WORKFLOW.md's new section states plainly which of 01/03/04/05 are hook-enforced vs
   prose-invoked-optional vs operator-invocable, and names coverage-delta a heuristic.
3. `docs/decisions/0024-*.md` names OUTCOME and MUTATION as additive marker types.
4. `docs/verification/README.md` states the OUTCOME column is ship-boundary-only today.
5. `bash tests/test-kri-wiring.sh` passes: every one of 01/02/03/04/133/134's live call
   sites is found by a fixed-string grep against the real source file, AND the negative
   control (a planted over-claim that 03/04 are hook-enforced) is caught by the same sweep
   function.
6. No regression: `bash tests/test-meta.sh` and `bash tests/test-docs-wiring.sh` stay green.

## Verification

```
bash tests/test-kri-wiring.sh
bash tests/test-docs-wiring.sh
bash tests/test-meta.sh
```
All green; see `docs/verification/kri-06-docs-wiring.md` for the full run-table.
