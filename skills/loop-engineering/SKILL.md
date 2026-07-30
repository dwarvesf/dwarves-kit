---
name: loop-engineering
description: Use when the user wants to design or add a new bounded loop to the kit's own SDLC orchestration ("let's build a loop", "design a new loop for the orchestrator", "loop engineering", "make this a bounded loop", "is this worth a loop"). Walks the gate (should this even be a loop) then the anatomy (artifact / scanner / reviser / stop condition) reusing the kit's own generic bounded-revise engine. NOT for a one-off in-session Stop-hook goal (use goal-craft), NOT for the debug loop (already exists, use /kit:debug), NOT for building the loop's actual code once the shape is agreed (just build it).
disable-model-invocation: false
---

# Loop engineering

## Overview

The kit already runs 3 first-party bounded loops (Goal, Debug, Execute) plus a bounded-revise
side-flow (`test-plan-review-team`, SPEC-203/204). This skill is the reusable *shape* extracted
from that fourth one, so a new loop idea gets designed against a known pattern instead of
re-derived from scratch each time.

## Step 1: Gate, before designing anything

`docs/PHILOSOPHY.md` "Loop boundaries" + "Feature rejection criteria" are the kit's own bar, not
a new one invented here:

- **Bounded-in-session only.** A continuation that keeps working *inside* the current session
  under a verifiable stop condition. An unbounded outer loop (external `while` re-spawning
  sessions) is explicitly declined territory (GSD v2 / autonomous-runtime, not this kit).
- **Serves 2+ lifecycle phases**, or is a named downstream-facing exception (like
  `visual-team`/`ui-design`) with a real external consumer, not "might be useful someday."
- **Explainable in one sentence.** If the README-table line for it would run long, it's too
  complex as scoped.
- **Has a source citation.** Trace it to a proven implementation or an existing kit pattern
  (per "synthesize, don't originate"), not an invented mechanic.

Any of these failing kills the idea as a *loop*; it may still be worth a one-shot side-flow
(like `kit-health` / `absorb`), which is simpler and doesn't need this skill.

## Step 2: Pick the shape, engine, or campaign?

Two different existing shapes, don't conflate them:

- **Bounded-revise engine** (converging on one artifact): dispatch N scanners against an
  artifact -> merge findings by severity -> revise the artifact -> re-check -> repeat until
  clean or capped. This is `test-plan-review-team.md` Step 2-4, generalized:

  ```
  dispatch N scanners against <ARTIFACT>
                │
                ▼
     count findings (K), by severity
                │
   ┌────────────┼────────────┐
  K = 0    severity fell    neither
 (clean)  (even if K flat)   fell
     │           │              │
     │     revise <ARTIFACT>  halt honestly
     │     round += 1 (cap 3)  (report as-is)
     │           │
     └───────────┴──── or round cap hit
                │
                ▼
      verdict: SOLID / REVISE / RECONSIDER
  ```

  Parameterize: what's the artifact, who scans it (N lenses), who revises it (a distinct
  reviser, never one of the scanners). Convergence rule is severity-aware, not raw-count
  (a flat K with lower max severity still counts as progress; see `test-plan-review-team.md`
  Step 4.3 for the exact wording).

  **Scan step is two-tier, not "always dispatch all N lenses."** Per `docs/WORKFLOW.md`'s own
  cheap-first verification-cost-routing principle, applied here: Tier 1 is a deterministic
  check (grep/bash, zero model cost) for any criterion reducible to a mechanical yes/no (a row
  exists, a command is present, a field is populated) , run every round, decisive on its own.
  Tier 2 is the N-lens model critique, dispatched ONLY for the residual criteria Tier 1 can't
  reduce to a script (oracle quality, ambiguity, determinism risk); skip any lens whose entire
  finding-space Tier 1 already cleared. Stop condition becomes: Tier 1 all clean AND (Tier 2
  K=0 OR severity fell OR cap hit). This is the fix for the engine's real cost problem, N
  parallel model dispatches every round is expensive when most findings are actually mechanical;
  see `docs/research/2026-07-30-loop-engine-prior-art.md` for the worked cost comparison.

- **Campaign / worklist iteration** (driving an existing loop across many items): not a new
  engine, an outer wrapper. Shape: a worklist of untreated items -> run the existing
  loop/command on each in turn -> track progress -> stop when the worklist is exhausted or a
  budget/blocker hits. This is the Goal loop's own "keep working one objective until a
  verifiable stop holds" shape, pointed at a list instead of a single objective. Don't build a
  second convergence mechanic for this; reuse the Goal loop.

## Step 3: Where it lands once shaped

- New bounded-revise engine instantiation -> a new `/kit:<name>` side-flow, registered in
  `docs/WORKFLOW.md`'s "Opt-in side-flows" table + `docs/workflow-map.md`'s mirror (both, same
  commit, per that section's own companion-drift note).
- New campaign wrapper -> likely a `/kit:<name>` command that itself invokes the Goal loop
  machinery, not a new engine.
- Not yet committed, just an idea -> `_meta/BACKLOG.md` "v2 candidates" tier (see the entries
  logged there for feature-list reconciliation, doc-drift, agent-effectiveness, dependency
  patch, and the test-plan backfill campaign, they're worked examples of Step 1+2 output).

## Lineage (satisfies Step 1's source-citation gate)

The engine's coarse shape is not original: it's Anthropic's own **Evaluator-Optimizer /
Reflection-loop** workflow (["Building Effective Agents"](https://www.anthropic.com/research/building-effective-agents)),
the same lineage as Self-Refine (Madaan et al. 2023), Reflexion (Shinn et al. 2023), and CRITIC
(Gou et al. 2023). What none of those, nor any Claude Code skill/plugin found on a 2026-07-30
web sweep, package together is the specific bundle used here:

- **Artifact-agnostic parameterization**, matches Evaluator-Optimizer's own framing; not a
  kit invention.
- **Severity-aware convergence** (a flat finding-count still counts as progress if the worst
  severity dropped), not found in any literature or tool surveyed; this IS the kit's addition.
- **Distinct reviser, never a scorer**, seen incidentally in practice (e.g. one model reviews,
  a different one fixes) but never stated as an enforced rule; this IS the kit's addition.
- **Hard cap with an honest-halt reporting path** (report "not converging" as a real outcome,
  not a silent stop), pieces exist (max-round caps, keep-best fallbacks) but never packaged as
  an explicit contract; this IS the kit's addition.

So: cite Evaluator-Optimizer for the shape, don't claim the shape is novel. The three deltas
above are what's actually new, and are the parts worth defending if this pattern gets
challenged later.

## Reference

Worked instantiation: `commands/test-plan-review-team.md` (the engine) +
`_meta/BACKLOG.md` v2 candidates (four more engine instantiations sketched, one campaign
sketched, none built yet).
