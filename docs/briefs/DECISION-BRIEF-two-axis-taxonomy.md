# Decision Brief: two-axis taxonomy cleanup (lanes = pure evidence, a ~6-type public view)

Date: 2026-07-25 · Source: the 2026-07-24 workflow assessment's taxonomy corrections, HAN-GATED
(risk-classification surface per AGENTS.md zone 4). Status: DRAFT, awaiting Han's go on the two
decisions below. Consuming row: ID-391. Record: ops-toolkit
`research/2026-07-24-workflow-pattern-and-assessment.md` §2.2.

## The defect (verified against docs/WORKFLOW.md)

The kit's own composition rule says lane = EVIDENCE contract, type = CONTENT contract, and every
(lane, type) pair is legal. The lane table then lists `bug` and `backfill` as lanes, but both are
content types wearing lane clothes: `bug` names a work kind (defect) whose loop mandates
root-cause-first; `backfill` names a doc-output work kind. The first question every new reader asks
("why is bug a lane?") is the tell. Separately, 11 type loops is too many to teach a team; three
of them (migration / reconcile / operate) share one skeleton (inventory -> act -> verify ->
record).

## The design (two decisions for Han)

**D1, lanes become strictly evidence tiers**: tiny / normal / full. `bug` migrates to the type
registry (its loop = the incident/debug root-cause-first discipline; its evidence tier still
auto-escalates per the existing triggers). `backfill` becomes the doc type's
existing-codebase entry path. Classifier + depth-matrix rows migrate; the ship-gate's lane header
contract is unchanged in shape (a spec still declares one of three lanes).

**D2, a ~6-type public taxonomy over the internal 11/12**: build, research, review, eval,
maintain (= migration + reconcile + operate), incident, presented in WORKFLOW.md and the
onboarding docs; doc/learning/planning stay as internal extensions in the registry. The registry
keeps all internal types; the public view is a presentation layer, not a schema change.

## Why HAN-GATED

D1 changes the risk-classification surface (AGENTS.md zone 4 pause item: never reclassify risk
without the human). D2 is presentation-only but pairs with D1 in the same docs pass, so both go
together.

## Sequencing constraint

Decide BEFORE dfoundation DF-152 (the onboarding 2-pager) is written, or the 2-pager teaches
vocabulary that is about to change. Churn estimate is the open question flagged in the row
(classifier + depth matrix + suites).

## North-star conformance (§6)

Serves N7 (pickup cost; the taxonomy is the first thing a teammate must hold). Honors the
plain-words meta-principle. Does not touch N5/N6 machinery.

## Exit criteria

1. `lane-classify.sh` emits only tiny/normal/full; bug/backfill inputs route to types with
   unchanged effective ceremony (regression-controlled against the current matrix).
2. WORKFLOW.md presents 6 public types; the registry still resolves all internal types.
3. Every existing suite green; no spec's lane header needed manual migration beyond bug/backfill.
