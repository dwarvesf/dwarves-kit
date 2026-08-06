# Decision Brief: review-economics telemetry (the slop metric) + gate red-teaming

Date: 2026-07-25 · Source: the 2026-07-24 workflow assessment (gates are the whole slop strategy
and nothing measures them) + the kit-planning session's feedback-loop principles. Status: DRAFT
(feeds ID-392's spec; ID-393 depends on it). Consuming rows: ID-392, ID-393. Records:
ops-toolkit `research/2026-07-24-workflow-pattern-and-assessment.md` §2.3 + Part 4,
`research/2026-07-18-framework-test-design-methodology.md` §7.

## Verified current state

- Loop-3 telemetry exists for GATES: gate-ledger (append-only), lane-telemetry, `caught=bool` +
  override-rate (SPEC-129), delivery-ratio (ADR-0033), stats as recomputed projections.
- NOTHING measures review OUTCOMES: no first-pass acceptance rate, no rework-loop count, no
  reviewer-minutes, no defect-escape rate. The team expansion decision (dfoundation DF-45 phase 5)
  currently has no number to read.

## The design

**ID-392, the metric set** (per card/PR): first-pass acceptance (merged without a rework round),
rework round-trips, time-to-merge, human reviewer minutes (coarse, self-reported or
timestamp-derived), escape count (defects found after merge, back-linked to the PR). BUILD
CONSTRAINT (kit-planning §7 principles 1-2): emit to the EXISTING append-only ledger substrate;
stats projections recompute on query; no new metrics store. First measurement bed: the Multica
pilot cards. The number that gates team expansion: first-pass acceptance ~70% held for a month.

**ID-393, the negative control on the review chain**: canary cards with planted defects (a logic
bug that passes tests, a subtle spec deviation) injected occasionally; catch/miss lands in the
ID-392 metric set. This is mutation-smoke's principle (a suite that never reddens is dead) lifted
from the test suite to the review chain. Only meaningful once ID-392 emits.

## North-star conformance (§6)

N6 verbatim (a measurable signal feeding the Learn stage, itself measured); serves N7 (review
capacity is the team bottleneck; these numbers are how it gets budgeted). Propose-never-dispose
holds: metrics propose gate tuning; a human changes gates.

## Exit criteria

1. A month of Multica-pilot cards renders a first-pass-acceptance number from ledger data alone.
2. A planted canary's catch/miss appears in the same projection.
3. Zero new state stores (the ledger diff is the whole storage change).
