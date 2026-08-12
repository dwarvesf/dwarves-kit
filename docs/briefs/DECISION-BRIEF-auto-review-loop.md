# Decision Brief: auto review-fix loop as a default spine phase

The design was discussed with the operator across prior conversation turns; this
brief records the accepted shape. The operator raised the pain directly and
approved the recommendation before this brief was written.

## Verdict: BUILD

## Core thesis

The operator keeps invoking a multi-lens review by hand after a build ("anything
to improve, run the review lenses"), and it keeps finding real defects, including
critical ones that a prior fix batch introduced. The machinery already exists in
the kit (`review-team`, `advisor`, `brief-reviewer`, `devs-team`); the gap is
that every review phase is advisory-optional, so it only runs when someone
remembers to ask. This promotes the review from an operator question to a
default phase, adds the loop that catches fix-batch regressions, and gates the
cost by lane.

## Q1: real user pain

The review step is manual. High-value work (it found four critical money-path
bugs in one session) depends on the operator remembering to ask for it. A step
that valuable should not be opt-in.

## Q2: 10x version

Every full-lane change is reviewed by default, its findings ranked by lens
convergence, and the review re-runs on each fix batch until the convergent
findings clear. The operator never has to ask "should we review this," and a fix
batch cannot quietly reintroduce the bug it fixed.

## Q3: simplest version that proves the thesis

Wire the existing agents into default phases for the full lane only, add
convergence-ranking and a two-round cap to `review-team`, and add a design-time
pass at the spec stage. No new agents. The pattern is precedented by the
existing V-model and cost-routing philosophy.

## Q4: what gets cut

- No auto-BLOCK. The verdict stays advisory, consistent with the spine.
- No loop on normal or tiny lanes. The scaling gate keeps cost where the blast
  radius earns it.
- No new lens agents. The change is policy plus a merge-step edit.

## Q5: what breaks

- Cost blowup if the loop runs unbounded or on every lane: mitigated by the
  two-round cap and the lane gate.
- Signal dilution if single-lens taste findings rank equally: mitigated by
  convergence-ranking.
- Context exhaustion if lenses run inline: mitigated by dispatching every lens as
  a subagent (already the `review-team` shape).

## Survival scenarios

| Scenario | Guarantee |
|---|---|
| Loop never converges | Two-round cap; unresolved-at-cap reported, not silently passed |
| Every finding is single-lens taste | Convergent set is empty, loop stops after one pass |
| A fix batch introduces a new convergent finding | The re-run over the fix diff catches it before ship |
| Operator on a tiny-lane change | No review loop fires; the gate exempts it |
