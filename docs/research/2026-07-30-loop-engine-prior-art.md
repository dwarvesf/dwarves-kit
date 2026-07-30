---
title: Bounded-revise loop engine vs prior art (Evaluator-Optimizer, Self-Refine, Reflexion, CRITIC)
date: 2026-07-30
source: web research (WebSearch/WebFetch) dispatched to a general-purpose agent, cross-checked against commands/test-plan-review-team.md and docs/PHILOSOPHY.md "Loop boundaries"
feeds: skills/loop-engineering/SKILL.md Lineage section; any future bounded-revise engine instantiation (see _meta/BACKLOG.md v2 candidates)
benchmarked_against: commands/test-plan-review-team.md Step 2-4 (SPEC-203/204), docs/PHILOSOPHY.md "Loop boundaries (bounded in-session, not unbounded outer)" + "Feature rejection criteria"
status: active
---

# Bounded-revise loop engine vs prior art

## Why this note exists

`skills/loop-engineering/SKILL.md`'s own Step 1 gate requires a source citation before a new
loop counts as legitimate ("synthesize, don't originate," `docs/PHILOSOPHY.md`). Before trusting
that gate on our own generalized "bounded-revise engine" pattern (extracted 2026-07-30 from
`test-plan-review-team.md`), we checked whether it already exists elsewhere under a different
name. Short answer: the coarse shape does; the specific four-property bundle does not.

## What we built (recap)

Dispatch N scanner subagents against an artifact in parallel -> merge findings, tag severity ->
if findings exist, dispatch a **distinct** reviser (never one of the scanners) -> re-check ->
repeat until clean or a hard cap of 3 rounds. The stop condition is severity-aware: a flat raw
finding-count still counts as progress if the worst severity present dropped round over round.
Non-convergence is reported as an explicit verdict (`RECONSIDER`), not a silent halt.

## Prior-art survey

| Name | Source | Generalizes across artifacts? | Severity-aware convergence? | Critic ≠ reviser enforced? | Hard cap + honest-halt? |
|---|---|---|---|---|---|
| Evaluator-Optimizer workflow | [Anthropic, "Building Effective Agents"](https://www.anthropic.com/research/building-effective-agents) | Yes, by design | No, binary "meets criteria" only | Not enforced (often blended role) | Not specified |
| Reflection Loop / Reflection Agent | [LangGraph docs](https://www.langchain.com/blog/reflection-agents) | Yes (graph-generic) | No | Usually no (self-critique) | No |
| Self-Refine | [Madaan et al. 2023](https://arxiv.org/abs/2303.17651) | Yes, tested on 7 task types | No | No, same LLM critiques and revises | No |
| Reflexion | [Shinn et al. 2023](https://openreview.net/pdf?id=vAElhFcKW6) | Yes, pluggable Evaluator | No | Evaluator ≠ Actor, but no distinct reviser role | No |
| CRITIC | [Gou et al. 2023](https://arxiv.org/abs/2305.11738) | Yes (tool-interactive) | No | No | No |
| Constitutional AI critique-revise | [Bai et al. 2022](https://arxiv.org/pdf/2212.08073) | Yes, extended to other domains | No | No, same model does both steps | No |
| VRR-Stop (2026) | [arXiv 2607.17641](https://arxiv.org/html/2607.17641) | No, scoped to verify-repair | Closest match: marginal-gain stopping, K_max=5 + keep-best fallback | Not its axis | Partial (reactive fallback, not pre-announced) |
| Claude Code marketplace skills | Auto Review, Review Loop, adversarial-loop, looper (searched 2026-07-30) | No, all code-review-shaped | No, verdict/count-based | Incidental (Codex fixes, Claude reviews) not a stated rule | Capped 3-5 rounds, no honest-halt path found |

## The three deltas that are actually ours

1. **Severity-aware convergence.** Not found anywhere surveyed. Prevents two failure modes at
   once: a false stall (a genuinely-improving round misread as stuck because raw count didn't
   drop, our own SPEC-204 experience) and a false victory (clearing five LOW findings while a
   CRITICAL from round 1 ages out unaddressed).
2. **Distinct reviser, never a scorer, as an enforced rule.** Seen incidentally in practice
   (e.g. one model reviews, a different one fixes) but never stated as a design contract.
   Matters because Self-Refine's own limitations note the mechanism only helps when the model's
   error-*detection* ability exceeds its error-*avoidance* ability; if the same weights wrote the
   flaw, they're likely to miss it on re-read too.
3. **Honest-halt as a reported verdict**, not a silent stop or best-effort return. Every
   framework surveyed either loops until success or quietly returns its best attempt.
   `RECONSIDER` makes non-convergence a first-class, human-visible outcome instead of a hidden
   failure in an unattended run.

## When to use which shape (decision framework)

Not "ours is always better." The kit already runs BOTH shapes in production, matched to what
the artifact actually needs:

| Signal | Use the fuller engine (severity-aware, distinct reviser, honest-halt) | Use the simpler shape (binary stop, cap + escalate) |
|---|---|---|
| Artifact's quality bar | Graded, multiple independent findings with a real severity gradient (test plan, spec, code review) | Binary correctness (compiles, test passes, matches an AC) |
| Lenses that apply | 2+ independent quality angles worth checking in parallel | One check, one verifier |
| Cost of silent non-convergence | High, unattended run, no human watching each round | Low, already nested inside a pipeline with its own escalation |
| Token/latency budget | Can afford N parallel scanners + a distinct reviser per round | Needs to be cheap and fast (tight retry loop) |
| Existing kit precedent | `test-plan-review-team` (this shape) | `/kit:execute`'s worker -> task-verifier -> fix-agent (max 2) -> ESCALATE (already this shape, already kit-native, already has a distinct reviser and a cap, just no severity tiering because task ACs are binary by nature) |

Reach for an **external framework** instead of building either kit-native shape when the loop
isn't operating on a kit-authored artifact (spec/test-plan/code inside dwarves-kit's own SDLC),
per `docs/PHILOSOPHY.md`'s own "When to recommend an external tool instead": a downstream
consumer's own app-domain critique-revise loop fails the "serves 2+ kit lifecycle phases" gate
and doesn't belong as a kit feature at all.

## Recommendation carried into `skills/loop-engineering/SKILL.md`

Don't rename the pattern, no single literature term covers the full bundle. Cite
Evaluator-Optimizer as the lineage (satisfies the skill's own source-citation gate), name the
three deltas above as the actual contribution, and pick the shape (fuller engine vs
Execute-pipeline-style) per the decision table, not by default.
