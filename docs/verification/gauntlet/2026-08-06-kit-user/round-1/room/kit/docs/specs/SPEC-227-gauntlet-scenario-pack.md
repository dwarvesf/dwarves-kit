# SPEC-227: Gauntlet scenario pack, full-flow scenarios via the test-generation loop

**Status:** DRAFT (matrix first cut committed; cards materialize per row)
Lane: normal
**Unparks:** ID-423's L3 (sandbox-repo E2E scenarios), with the gauntlet as its
executor. **Reuses:** the SPEC-203 test-generation loop as the scenario
GENERATOR. **Relates:** ID-465 (scenario-harness discipline) governs any
scenario needing an external-API mock.

## Problem

The gauntlet's first seed cards test the doorway (adopt + one tiny fix), not the
house. A contributor surface is only proven when a probe survives the FULL
flows: a real lane end to end, a bug through the debug loop, a gate collision, a
mid-flight drift, a dead-session resume. Hand-authoring those scenarios is the
exact test-generation problem ID-423 named and left queued; authoring them ad
hoc per run would rot immediately.

## Decisions

1. **The journey is the spec.** The contributor journey (the features a real dev
   exercises: install, adopt, tiny lane, full lane, debug, gates, drift, review,
   resume, mega) is written down as a feature list with acceptance criteria,
   exactly the shape `/kit:test-plan` consumes. Scenario generation is then the
   SHIPPED SPEC-203 loop run against that journey: test-plan derives the
   coverage matrix, test-plan-review-team critiques it, and the test-write
   analog materializes each row as a seed card + checker assertions. No new
   generator is built.
2. **One matrix, cards per row.** `tests/gauntlet/scenarios.md` holds the
   matrix (committed, reviewed). A card materializes from a row at run time,
   frozen into the run record like any seed card. The matrix is the durable
   artifact; cards are its projections.
3. **Multi-scenario runs are a CAMPAIGN, not a new engine.** The gauntlet
   engine converges the surface against ONE card per run. A scenario-pack run
   is the campaign shape from the loop-engineering skill: a worklist of matrix
   rows, the gauntlet engine invoked per row, progress tracked, stop on
   worklist end or budget. Findings accumulate on the same surface across rows.
4. **Row order = blast radius for docs.** Run doorway rows first (cheap,
   already built), then the full-lane happy path, then failure-injection rows.
   A surface failing the doorway will fail everything; do not pay for a
   full-lane probe round while a doorway finding is open.
5. **This is ID-423's L3.** The L1 (scripted lane replay) and L2 (stage
   benchmarks) layers stay as designed in the bench-plane brief; this spec
   claims only L3 and names the gauntlet as its executor. The board row gets
   that note at review time.

## The journey matrix, first cut (persona A: kit user)

| Row | Journey feature | Scenario (what the probe must survive) | Category | Checker adds |
|---|---|---|---|---|
| J1 | install + adopt | the existing doorway card (seed-card-user.md) | happy | (shipped) |
| J2 | tiny lane | the doorway card's fix ships through the loop | happy | (shipped, same card) |
| J3 | full lane | spec-feature end to end: brief -> spec -> validate -> execute -> review -> ship on a planted feature ask ("add a --repeat N flag with tests") | happy | spec file exists + VALIDATED marker; tests written and green; PR.md; gate-ledger rows for the lane's phases |
| J4 | bug lane / debug loop | fixture ships a planted regression (a failing test the README claims passes); probe must produce a recorded root cause BEFORE the fix | failure-injection | evidence ledger exists; fix commit references the cause; the planted test green |
| J5 | gate collision | the card asks for a behavioral change and the probe must satisfy the ship gate: proof-of-done with a negative control, or the documented override with a reason | failure-injection | docs/verification/ entry with a run table + negative control, or the override recorded |
| J6 | mid-flight drift | the card's ask changes once, mid-run (a planted UPDATE.md appears after the spec hardens: "also cover the empty-string case"); probe must amend, not silently widen | boundary | spec shows the add-only amendment; the new case tested |
| J7 | resume | the probe's session is killed after execute starts (round harness restarts the agent cold); the new session must resume from disk state, not restart the work | recovery | second transcript begins with orientation (/kit:start shape) and does NOT redo completed tasks; final state green |
| J8 | review response | review findings are planted (the fixture's feature has an obvious edge-case hole the probe's own review should catch); probe must fix-then-ship, not verdict-shop | failure-injection | review verdict recorded; the hole's test exists |

Persona B (kit contributor) gets its own matrix after persona A's first campaign;
its rows derive from the kit's own gates (proof, override, spec-drift) rather
than the fixture repo.

## What must be built (delta over the shipped prep)

| # | Task | Acceptance |
|---|---|---|
| P1 | Journey feature list with acceptance criteria (the "spec" the SPEC-203 loop consumes) | committed beside the matrix; review-team critique recorded |
| P2 | Run the SPEC-203 loop over it; reconcile its derived matrix with the first cut above | matrix updated; deltas noted (the loop finding rows a human missed is the point) |
| P3 | Card materializer: `tests/gauntlet/make-card.sh <row>` renders a frozen card + checker fragment from a matrix row | J3 and J4 cards render and their checkers run |
| P4 | Fixture enrichment: the fixture repo gains the planted regression (J4), the feature ask (J3), the drift trigger (J6), the review hole (J8) | each plant verifiable by its row's checker; plants are inert for other rows |
| P5 | Campaign runner note in `tests/gauntlet/README.md`: worklist order (Decision 4), budget, where cross-row findings accumulate | doc present; first campaign run follows it |

## Verification

- P3: `make-card.sh J3` and `make-card.sh J4` produce cards whose checkers
  execute against a hand-built green fixture and fail against the untouched one
  (negative control).
- P2: the SPEC-203 run record (critique verdict included) committed under
  `docs/verification/`.
- The first campaign run's ROUNDS.md records per-row outcomes; that record is
  this spec's acceptance, same rule as SPEC-018's TP10.
