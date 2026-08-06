# Decision Brief: kit-hardening (autonomous-loop closure)

Date: 2026-06-29 · Source: `/kit:think` stress-test of ADR-0028

## Verdict: BUILD (with two scope refinements the think pass surfaced)

## Core thesis
Closing three narrow gaps , agent-definition **effectiveness** validation, **conditional deployable-done**, and a **mega-lane reconcile** , makes unattended kit runs TRUSTABLE, on top of the V-model machinery the kit has already shipped (SPEC-076, ADR-0024/0025, the validator family).

## Strongest argument for
Most of the autonomous loop is already shipped; these three are the last mile to "I trust the autonomous result without re-checking it."

## Strongest argument against
None of the three pains is acute TODAY: gap A's payoff needs the meta-agent (ops-toolkit SG-05, not yet shipped), gap B bites only on deployable work (rare in current kit use, v2/v3 are non-deployable), gap C is low-grade confusion, not a blocker. Real risk of building ahead of need.

## Forcing-question findings (the refinements)
- **Q1 pain:** real but not acute. Gap A is anticipatory , its value lands when a meta-agent generates agents, so COUPLE it to v3 SG-05. Gap B is real only for deployable work. Gap C is divergence-confusion, low urgency.
- **Q4 cut:** DROP kit-side merge-autonomy on shared repos. It fights the kit's deliberate human-ship identity (ADR-0024) and adds the least value where it is riskiest. Keep only the skill's front-load checkpoint + deploy/UAT terminus. Auto-merge stays a SKILL feature on operator-owned repos, where the operator owns the ship-gate.
- **Q5 scale:** the bottleneck is VERIFICATION TOKEN COST (ironic for a token-optim-adjacent effort). Keep agent-effectiveness diff-keyed (new/changed agents only), read-only, bounded. UAT is a HUMAN bottleneck , script acceptance wherever possible, reserve human UAT for genuine judgment.
- **Q6 exit:** validator catches a planted-bad agent AND passes the good roster with no false positives; a deployable item cannot be marked done without a deploy-proof + UAT (negative control: blocked / logged-override); `/kit:mega` ≡ the skill on the same input (front-load present, deploy/UAT terminus). Trust metric: % of autonomous "done" claims that survive a fresh-context re-audit with zero rework , pre-register a threshold.

## If BUILD: recommended v1 scope
- **SG-A** agent-effectiveness validator (SPEC-088): scoped to the existing roster now; expand to meta-agent output when v3 SG-05 lands. Read-only / advisory / fail-safe / diff-keyed.
- **SG-B** conditional deployable-done (AGENTS.md zone 3 + ship-gate): script acceptance where possible.
- **SG-C** mega-lane reconcile MINUS kit-side merge-autonomy , front-load checkpoint + deploy/UAT terminus only.
- Team-review ADR-0028 FIRST (it changes the done-definition every kit user inherits).

## Sequencing
ADR-0028 team-blessed before any SPEC ships. Gap A couples to v3 SG-05; gap B and C are independent. The two refinements above are deltas from ADR-0028 as written (gap C narrows; gap A sequences) , fold them into the ADR + the mega-goal.
