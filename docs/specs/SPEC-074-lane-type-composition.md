# SPEC-074: Lane x type combination audit + the composition rule

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery)
Type: eval / behavioral (one regex fix rides the audit)
Board: ID-066

## Problem

The classifiers always emit BOTH a lane and a type (55 possible pairs), but no
surface said how the two compose. The lived consequence: wave-1's doc-type full-lane
run improvised its phase mapping (skips with reasons), and nothing defined who wins
when a pair looks contradictory (bug+incident, tiny+incident).

## Audit method + findings

Full enumeration (docs/research/2026-06-11-lane-type-composition-audit.md):

- 3-surface parity: 11 types present in the loops table, the registry, and the
  classifier; 5 lanes all yield non-empty plans (1/8/13/6/5 phases). PASS.
- Live probes of suspect pairs: bug+incident, tiny+incident, full+migration,
  normal+operate/research/reconcile/eval. One CONTRADICTION class found
  (composition undefined, F1) and one classifier bug (F2).
- F2 (fixed here, failing-first): the backfill anchor missed its OWN documented
  example , `write its AGENTS.md` classified normal because the regex
  `write (agents|claude)\.md` lacked the possessive. Now
  `write (its |the |an? )?(agents|claude)\.md`, 2 pins.
- F3 (verified coherent, pinned): tiny+incident owes no INC record because the
  SPEC-071 proof-class order short-circuits tiny/backfill to inert before the
  registry default.

## Decision

`WORKFLOW.md ### Lane x type composition`: the type names the CONTENT contract
(loop steps, proof dialect, executor); the lane names the EVIDENCE contract (the
depth-matrix gates ship-gate enforces). Loop steps execute inside the canonical
phases; a required phase with no equivalent loop step records
`skipped "<loop-step note>"` (disposed per SPEC-063). Three precedence facts
written and pinned: tiny/backfill inert short-circuit; bug+incident = incident
content in bug-depth gates; degenerate lanes bound ceremony for any type.

Rejected: a 55-cell per-pair table (fossilizes; two axes + three facts cover all
pairs); letting type override lane in ship-gate (weakens enforcement).

## Acceptance criteria

- AC1: WORKFLOW carries the composition section; meta pin.
- AC2: `write its AGENTS.md` (+ trailing-clause variant) -> backfill; failing-first.
- AC3: tiny+incident -> class=inert; pinned as a composition fact.
- AC4: loops-table types == registry types, computed not hardcoded; meta pin.
- AC5: suites green; reverting the regex flips AC2 RED (negative control).

## Verification

- Failing-first: 2 RED (both backfill pins) on the pre-fix tree -> fix -> green.
- Suites post-review: hooks 364/364, meta 439/439, e2e 20/20.
- Negative control: regex reverted -> 2 RED -> restored green (run live at build).

## Review

Date: 2026-06-11. Multi-lens (2 lenses: correctness 6/10, doc-consistency 5/10).
Fixed in-branch:

- Correctness HIGH: the widened backfill anchor could down-lane a compound phrase
  carrying a hard-gate subject ("write its AGENTS.md and disable the safety
  hooks") -> the backfill branch now scans the hard-gate list and up-lanes to full
  on co-occurrence; the pure doc case stays backfill (both pinned). MEDIUMs:
  pronoun coverage (`writes?\b.{0,12}` form), prose precision on skip-disposal.
- Doc-consistency HIGHs: AGENTS.md routing and the WORKFLOW preamble both framed
  lane/type as mutually exclusive, contradicting the new section -> both
  reconciled (lane = evidence contract for EVERY type). MEDIUMs: proof-gate header
  precedence updated 3->4 steps; "6-phase gate depth" precision (3 required
  gates); "other five types" -> ten; SPEC-071 citation narrowed to the step it
  added.
- The preamble fix itself broke the parity pin's awk terminator (caught by the
  suite, reference reworded) , the pin failing loudly on heading drift is by
  design.

Post-fix: hooks 364/364, meta 439/439, e2e 20/20. Verdict: SHIP.
