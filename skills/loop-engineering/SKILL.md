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

## Reference

Worked instantiation: `commands/test-plan-review-team.md` (the engine) +
`_meta/BACKLOG.md` v2 candidates (four more engine instantiations sketched, one campaign
sketched, none built yet).
