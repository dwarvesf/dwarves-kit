---
name: loop-engineering
description: Use when the user wants to design or add a new bounded loop to the kit's own SDLC orchestration ("let's build a loop", "design a new loop for the orchestrator", "loop engineering", "make this a bounded loop", "is this worth a loop"). Walks the gate (should this even be a loop) then the anatomy (artifact / scanner / reviser / stop condition) reusing the kit's own generic bounded-revise engine. NOT for a one-off in-session Stop-hook goal (use goal-craft), NOT for the debug loop (already exists, use /kit:debug), NOT for building the loop's actual code once the shape is agreed (just build it).
disable-model-invocation: false
---

# Loop engineering

## Overview

The kit runs 3 first-party bounded loops: Goal, Debug, Execute. It also runs a bounded-revise
side-flow, `test-plan-review-team` (SPEC-203/204). This skill extracts the reusable shape from
that fourth loop. Use it to design a new loop against a known pattern, instead of starting from
scratch.

## How to use this skill

You do not need to design the stop condition or the output shape before you start. Describe the
artifact and the itch. This skill runs the rest.

**Step 1 needs**: the artifact, and why now. Example: "the README's feature list keeps drifting
from the code." This skill checks it against the four gate criteria below and reports pass or
fail.

**Step 2 needs**: what good and bad look like, in plain words. You do not need to sort checks
into Tier 1 or Tier 2 yourself. Describe what wrong looks like, for each check you want. This
skill sorts them and shows you the split, so you can correct it.

**Step 3 needs**: what the artifact should look like when done. Say whether it is a
written-back section, a standalone report, or an applied edit. Say what verdict shape you want.
If you do not say, this skill defaults to the kit's own shape: a written-back section, a
three-way verdict (SOLID / REVISE / RECONSIDER), and an honest halt on non-convergence.

**How it fires**: name it directly ("use the loop-engineering skill"), or describe the problem
close to the trigger phrases in this file's frontmatter. No slash command is required.

**A caveat on reuse across sessions**: a plugin skill fires in other sessions only after its
change merges to `master`, and the installed plugin copy refreshes (`claude plugin marketplace
update`). Until then, it runs only in a session that reads this file directly off its branch.

## Step 1: Gate, before designing anything

`docs/PHILOSOPHY.md`'s "Loop boundaries" and "Feature rejection criteria" set the bar. This
skill invents no new one:

- **Bounded-in-session only.** The loop keeps working inside the current session, under a
  verifiable stop condition. An unbounded outer loop (an external `while` that re-spawns
  sessions) belongs to autonomous-runtime tools like GSD v2, not this kit.
- **Serves 2+ lifecycle phases.** Or names a real external consumer, like `visual-team` /
  `ui-design` does, as a downstream-facing exception. "Might be useful someday" does not count.
- **Explainable in one sentence.** If the README-table line for it runs long, the scope is too
  complex.
- **Has a source citation.** Trace it to a proven implementation, or to an existing kit pattern
  (per "synthesize, do not originate"). Do not invent a mechanic from nothing.

If any of these fail, the idea is not a loop. It may still work as a one-shot side-flow, like
`kit-health` or `absorb`. A side-flow is simpler and does not need this skill.

## Step 2: Pick the shape, engine, or campaign?

Two shapes already exist. Do not conflate them:

- **Bounded-revise engine.** Use this when the loop converges on one artifact. Dispatch N
  scanners against the artifact. Merge findings by severity. Revise the artifact. Re-check.
  Repeat until clean, or until the round cap hits. This generalizes `test-plan-review-team.md`
  Step 2-4:

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

  Parameterize three things: the artifact, who scans it (N lenses), and who revises it. The
  reviser must be distinct from every scanner. The convergence rule tracks severity, not raw
  count. A flat K still counts as progress if the worst severity dropped. See
  `test-plan-review-team.md` Step 4.3 for the exact wording.

  **The scan step runs in two tiers. It does not dispatch all N lenses every round.**
  `docs/WORKFLOW.md` already states a cheap-first verification-cost-routing principle. This
  section applies that principle inside the engine's own scan step.

  Tier 1 runs a deterministic check: grep or bash, zero model cost. Use it for any criterion
  that reduces to a mechanical yes-or-no, like a row that exists, a command that is present, or
  a field that is set. Tier 1 runs every round and decides on its own.

  Tier 2 runs the N-lens model critique. Dispatch it only for the criteria Tier 1 cannot reduce
  to a script, like oracle quality, ambiguity, or determinism risk. Skip any lens whose whole
  finding-space Tier 1 already cleared.

  The stop condition becomes: Tier 1 is all clean, and Tier 2 hits K=0, or its severity drops,
  or the round cap hits.

  This fixes the engine's real cost problem. N parallel model dispatches every round cost too
  much when most findings are mechanical. See `docs/research/2026-07-30-loop-engine-prior-art.md`
  for the worked cost comparison.

- **Campaign / worklist iteration.** Use this when you drive an existing loop across many
  items. It is not a new engine. It wraps an existing one.

  Shape: build a worklist of untreated items. Run the existing loop or command on each item in
  turn. Track progress. Stop when the worklist runs out, or a budget or blocker hits.

  This reuses the Goal loop's own shape: "keep working one objective until a verifiable stop
  holds." Here it points at a list instead of one objective. Do not build a second convergence
  mechanic. Reuse the Goal loop.

## Step 3: Where it lands once shaped

- A new bounded-revise engine becomes a new `/kit:<name>` side-flow. Register it in
  `docs/WORKFLOW.md`'s "Opt-in side-flows" table, and in `docs/workflow-map.md`'s mirror.
  Update both in the same commit, per that section's own companion-drift note.
- A new campaign wrapper usually becomes a `/kit:<name>` command. That command invokes the Goal
  loop machinery. It does not become a new engine.
- An idea with no commitment yet goes into `_meta/BACKLOG.md`'s "v2 candidates" tier. The
  entries already logged there, feature-list reconciliation, doc-drift, agent-effectiveness,
  dependency patch, and the test-plan backfill campaign, show what Step 1 and Step 2 output
  looks like.

## Lineage (satisfies Step 1's source-citation gate)

The engine's coarse shape is not original. It comes from Anthropic's own **Evaluator-Optimizer
/ Reflection-loop** workflow (["Building Effective Agents"](https://www.anthropic.com/research/building-effective-agents)).
Self-Refine (Madaan et al. 2023), Reflexion (Shinn et al. 2023), and CRITIC (Gou et al. 2023)
share the same lineage. A 2026-07-30 web sweep found no framework, paper, or Claude Code skill
that packages the specific bundle used here:

- **Artifact-agnostic parameterization.** This matches Evaluator-Optimizer's own framing. The
  kit did not invent it.
- **Severity-aware convergence.** A flat finding-count still counts as progress if the worst
  severity dropped. No surveyed literature or tool does this. The kit added it.
- **Distinct reviser, never a scorer.** Practice shows this incidentally, one model reviews, a
  different model fixes, but no source states it as an enforced rule. The kit added it.
- **Hard cap with an honest-halt reporting path.** The loop reports "not converging" as a real
  outcome, not a silent stop. Pieces of this exist, max-round caps, keep-best fallbacks, but no
  source packages them as an explicit contract. The kit added it.

Cite Evaluator-Optimizer for the shape. Do not claim the shape itself is new. The three deltas
above are the real contribution. Defend those three if this pattern gets challenged later.

## Reference

`commands/test-plan-review-team.md` is the worked engine instantiation. `_meta/BACKLOG.md`'s v2
candidates sketch four more engine instantiations and one campaign. None are built yet.
