# Implementation notes , data-driven routing (SG-06)

Delta from `ops-toolkit/_meta/megagoals/token-optim-v3/goals/06-data-driven-routing.md`.

## 2026-07-01 , SG-09 data is lever-ablation + by-model spend, NOT a per-task model sweep

The goal assumed SG-09 produced a "measured-cheapest model/effort per sub-goal" mapping. It did not.
SG-09's committed output is the 12-col ablation ledger (`task arm pass total_tokens ... models ...`),
per-ARM (baseline/orchestrator/distilled/routing/handoff) x task, and the COMMITTED run is haiku-only
n=1 (the Opus matrix is gated on Han). Consequence: "cheapest-at-parity per sub-goal" is undecidable
on the real data, so the router's correct behavior is ABSTAIN, which is what the quality bar demanded
anyway. The router still fires a real suggestion when >=2 models passed a task (proven on a synthetic
rich fixture), so it is correct the moment richer data lands, without code change.

## 2026-07-01 , effort is unmeasured -> always abstain on effort

SG-09's schema has no effort column. Suggesting effort would be fabricating a measurement. The router
abstains on effort in every branch and says so; only model is data-driven.

## 2026-07-01 , failing arm = infinite cost (negative control baked into the fixture)

The rich fixture's cheapest arm (sonnet, 90k tok) FAILS. The router must exclude it and pick haiku
(cheapest PASS). This encodes SG-09's anti-cherry-pick rule (a failed run counts as infinite cost) and
is asserted as a negative control, not just a happy-path agreement check.

## 2026-07-01 , stacked on SG-05 (same repo), base feat/v3-meta-agent

SG-06 "extends SG-05's meta-agent": it adds a `## Data-driven routing` section to `agents/meta-agent.md`
(from SG-05's branch) plus `lib/route-suggest.sh` + test + fixtures. Same-repo dependency, so the branch
stacks on `feat/v3-meta-agent` (not master). Han merges bottom-up at end-review; no retarget dance.
Goal file said PR base `main`; actual default is `master` (and here the base is the parent branch).

## 2026-07-01 , thin fixture is the REAL committed ledger, not invented

`tests/fixtures/routing/thin-ledger.tsv` is a verbatim copy of SG-09's committed
`results/sample/sg09-ablation-proof.tsv`, so the abstention case is proven against the actual data
state, not a contrived one. The rich fixture is explicitly synthetic (labeled in the proof) to exercise
the decidable branch the real data can't yet reach.
