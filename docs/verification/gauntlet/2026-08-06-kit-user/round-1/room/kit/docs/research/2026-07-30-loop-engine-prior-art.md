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
loop counts as legitimate (per "synthesize, do not originate," `docs/PHILOSOPHY.md`). Before we
trusted that gate on our own generalized "bounded-revise engine" pattern, extracted 2026-07-30
from `test-plan-review-team.md`, we checked whether it already existed elsewhere under a
different name. Short answer: the coarse shape exists. The specific four-property bundle does
not.

## What we built (recap)

Dispatch N scanner subagents against an artifact, in parallel. Merge their findings and tag
each with a severity. If findings exist, dispatch a **distinct** reviser, never one of the
scanners. Re-check. Repeat until clean, or until a hard cap of 3 rounds hits. The stop
condition tracks severity: a flat raw finding-count still counts as progress if the worst
severity present dropped round over round. Non-convergence gets reported as an explicit verdict
(`RECONSIDER`), not a silent halt.

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

1. **Severity-aware convergence.** No surveyed source has this. It prevents two failure modes
   at once. A false stall: a genuinely-improving round reads as stuck, because raw count did
   not drop. Our own SPEC-204 hit this. A false victory: the loop clears five LOW findings while
   a CRITICAL from round 1 ages out unaddressed.
2. **Distinct reviser, never a scorer, as an enforced rule.** Practice shows this incidentally.
   One model reviews, a different model fixes. No source states it as a design contract. It
   matters because Self-Refine's own limitations section names the risk: the mechanism only
   helps when the model's error-*detection* ability exceeds its error-*avoidance* ability. If
   the same weights wrote the flaw, they will likely miss it on re-read too.
3. **Honest-halt as a reported verdict**, not a silent stop or a best-effort return. Every
   surveyed framework either loops until success or quietly returns its best attempt.
   `RECONSIDER` makes non-convergence a first-class, human-visible outcome, not a hidden failure
   inside an unattended run.

## When to use which shape (decision framework)

Ours is not always the better choice. The kit already runs both shapes in production, matched
to what the artifact actually needs:

| Signal | Use the fuller engine (severity-aware, distinct reviser, honest-halt) | Use the simpler shape (binary stop, cap + escalate) |
|---|---|---|
| Artifact's quality bar | Graded, multiple independent findings with a real severity gradient (test plan, spec, code review) | Binary correctness (compiles, test passes, matches an AC) |
| Lenses that apply | 2+ independent quality angles worth checking in parallel | One check, one verifier |
| Cost of silent non-convergence | High, unattended run, no human watching each round | Low, already nested inside a pipeline with its own escalation |
| Token/latency budget | Can afford N parallel scanners + a distinct reviser per round | Needs to stay cheap and fast (tight retry loop) |
| Existing kit precedent | `test-plan-review-team` (this shape) | `/kit:execute`'s worker -> task-verifier -> fix-agent (max 2) -> ESCALATE (already this shape, already kit-native, already has a distinct reviser and a cap, just no severity tiering because task ACs are binary by nature) |

Reach for an **external framework** instead, and skip building either kit-native shape, when
the loop does not operate on a kit-authored artifact (spec, test-plan, or code inside
dwarves-kit's own SDLC). `docs/PHILOSOPHY.md`'s own "When to recommend an external tool
instead" names this case: a downstream consumer's own app-domain critique-revise loop fails the
"serves 2+ kit lifecycle phases" gate. It does not belong as a kit feature at all.

## Worked example (illustrative traces, not verbatim reproductions of the papers)

One shared task, a leap-year check, lets all four patterns run on the same starting bug. This
makes the mechanical differences visible instead of abstract. The task has a well-known subtle
defect: the century exception. 1900 is not a leap year. 2000 is.

Draft v0, what any of them start from:

```python
def is_leap_year(year):
    return year % 4 == 0
```

**Self-Refine** (same model critiques and revises):

```
Round 1: model writes draft v0
Model self-critiques: "year % 4 == 0 for 2024 -> True. Looks correct."
No century exception considered. The model's own blind spot in GENERATING
the function is the same blind spot it uses to GRADE it.
Reports PASS. Loop stops. Bug ships.
```

Documented failure mode: this only helps when error-*detection* exceeds error-*avoidance*. Same
context, same blind spot, both times.

**Reflexion** (external evaluator, e.g. real test execution, actor reflects and retries):

```
Round 1: draft v0
Evaluator runs: assert is_leap_year(1900) == False -> FAILS (returns True)
Actor reflects: "Returned True for 1900, expected False. Need century rule."
Actor revises: year % 4 == 0 and year % 100 != 0

Round 2: Evaluator runs: assert is_leap_year(2000) == True -> FAILS (returns False)
Actor reflects: "2000 is div by 100 but IS a leap year (div by 400 too)."
Actor revises: year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

Round 3: all tests pass -> STOP
```

This is a real improvement: the external test, not the actor's own judgment, catches the bug.
But the stop signal stays binary per round. FAIL just means "try again." It carries no sense of
"closer" versus "just as wrong."

**CRITIC** (tool-verified critique, not self-judgment):

```
Round 1: draft v0
CRITIC dispatches a tool call (code execution against known cases, or a
lookup of the actual leap-year rule) instead of asking the model to judge
itself: "Rule requires century exception; year=1900 check fails."
Actor revises based on the TOOL's verified finding, not a guess.
Repeat until tool-verification passes or a round cap.
```

This is the same shape as Reflexion, grounded in an external tool instead of the actor's own
reflection text. It is harder to fool, but still binary pass or fail per round.

**Evaluator-Optimizer** (Anthropic's generic workflow, our closest ancestor):

```
Generator produces draft v0.
A SEPARATE Evaluator call checks named criteria ("handles century
exception," "handles div-by-400") -> PASS/FAIL + feedback text.
Optimizer revises on FAIL. Repeat until PASS.
Anthropic's own writeup names no prescribed cap and no prescribed behavior
on repeated failure. It leaves both to whoever implements it.
```

This is structurally closest to ours. It encourages a distinct evaluator role, but still has no
severity gradient and no contract for what happens if the loop never converges.

**Ours, on the actual delta: severity-aware convergence.** None of the patterns above can
express this state, so here it is on a kit-native artifact, a `## Test plan` covering this same
function, engineered to hit the exact case that matters:

```
Round 1: 6 lenses scan the test plan
  -> lens 1 (coverage):    CRITICAL  "no test for century-boundary years (1900, 2000)"
  -> lens 2 (oracle):      HIGH      "expected output for year=2000 not a concrete assertion"
  -> lens 4 (test-ladder): LOW       "no test for year=0 or negative years"
  K = 3. Distinct reviser (not one of the 6 lenses) revises the plan:
  it adds century-boundary rows and makes assertions concrete, but
  introduces a duplicate row and leaves the year=0 case still vague.

Round 2: re-scan
  -> CRITICAL and HIGH from round 1: gone
  -> 2 NEW findings appear: MEDIUM "duplicate test row", MEDIUM "year=0 still vague",
     plus an unrelated LOW nit
  K = 3 again. Same raw count as round 1.

  Under a plain Evaluator-Optimizer or raw-count rule: K stays flat (3 == 3),
  so the loop halts, reporting "not converging." This is the exact false
  stall SPEC-204 actually hit.

  Under our rule: the worst severity dropped from CRITICAL to MEDIUM even
  though K did not. The loop continues.

Round 3: reviser clears the two MEDIUMs and the LOW. K = 0. Verdict: SOLID.
```

The concrete payoff: none of Self-Refine, Reflexion, CRITIC, or Evaluator-Optimizer has a state
that distinguishes "3 findings, one of them CRITICAL" from "3 findings, all MEDIUM." Each treats
it as PASS or FAIL, full stop. A naive raw-count bounded loop, what we ourselves ran before the
fix, would have halted at round 2 here, wrongly, and reported a working test plan as "stuck."
That is not hypothetical. It is what SPEC-204 actually did.

## Cost problem, and the hybrid fix (2026-07-30, same-day follow-up)

The engine's real cost weakness: it dispatches N model-judged lenses every round, regardless of
whether a given finding was ever mechanical. A binary stop condition (Reflexion or CRITIC style)
is cheaper, and just as correct, whenever a criterion genuinely reduces to a measurable yes or
no. The severity-graded machinery earns its cost only for the residual judgment calls a script
cannot make. The fix is not a new idea. It is `docs/WORKFLOW.md`'s own cheap-first
verification-cost-routing principle (line 210), applied inside the engine's own scan step,
instead of only across whole verifier tiers:

```
TWO-TIER STOP CONDITION (best of both)

  round N: scan <ARTIFACT>
       │
       ▼
  ┌───────────────────────────────┐
  │ TIER 1: deterministic checks   │  grep/bash, zero model cost,
  │ (only criteria reducible to a  │  runs EVERY round, decisive
  │  mechanical yes/no: row exists,│
  │  command present, field set)   │
  └───────────────┬─────────────────┘
                  │
         any FAIL? ──yes──▶ finding, CRITICAL by default, cheap to detect
                  │ no (all Tier-1 pass)
                  ▼
  ┌───────────────────────────────┐
  │ TIER 2: N-lens model critique  │  only dispatched for the RESIDUAL
  │ (only genuinely non-mechanical │  judgment surface Tier 1 can't
  │  judgment: oracle quality,     │  reduce to a script; skip any lens
  │  ambiguity, determinism risk)  │  whose whole finding-space Tier 1
  └───────────────┬─────────────────┘  already cleared
                  │
       merge findings, severity-graded (same convergence rule as before)
                  │
                  ▼
   STOP = Tier-1 all clean AND (Tier-2 K=0 OR severity fell OR cap hit)
```

Reworking the leap-year test-plan example (round 1) under this rule:

| Round 1 finding | Tier | Why |
|---|---|---|
| No test row for year=1900/2000 | Tier 1 | `grep` the test plan for the literal boundary years. The row exists or it does not. |
| Expected output for year=2000 not a concrete assertion | Tier 1 | Mechanical presence check: does the row contain a runnable assertion string, or a placeholder. |
| No test for year=0/negative years | Tier 2 | Genuine judgment call: is this edge case in scope for the spec. A script cannot decide that. |

Two of the three round-1 findings never needed a model dispatch at all. Round 2 only re-runs
the Tier-2 lens whose finding-space Tier 1 could not clear, not all 6, since Tier 1 already
confirmed the century rows exist. Cost drops from "6 parallel model calls across 3 rounds"
toward "2 grep checks plus 1 model call across fewer rounds." The severity-aware convergence
rule still protects the genuinely judgment-heavy residual from the false-stall problem. This is
now folded into `skills/loop-engineering/SKILL.md` Step 2 as the engine's default scan shape,
not an optional optimization.

## Recommendation carried into `skills/loop-engineering/SKILL.md`

Do not rename the pattern. No single literature term covers the full bundle. Cite
Evaluator-Optimizer as the lineage, which satisfies the skill's own source-citation gate. Name
the three deltas above as the actual contribution. Pick the shape, the fuller engine or the
Execute-pipeline style, per the decision table, not by default.
