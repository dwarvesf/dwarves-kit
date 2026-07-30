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

## Worked example (illustrative traces, not verbatim reproductions of the papers)

One shared task, checking leap years, lets all four patterns run on the same starting bug so
the mechanical differences are visible instead of abstract. It has a well-known subtle defect:
the century exception (1900 is NOT a leap year, 2000 IS).

Draft v0, what any of them start from:

```python
def is_leap_year(year):
    return year % 4 == 0
```

**Self-Refine** (same model critiques + revises):

```
Round 1: model writes draft v0
Model self-critiques: "year % 4 == 0 for 2024 -> True. Looks correct."
No century exception considered , the model's own blind spot in GENERATING
the function is the same blind spot it uses to GRADE it.
Reports PASS. Loop stops. Bug ships.
```

Documented failure mode: only helps when error-*detection* exceeds error-*avoidance*. Same
context, same blind spot, both times.

**Reflexion** (external evaluator, e.g. real test execution; actor reflects and retries):

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

Real improvement (external test != the actor's own judgment, so it actually catches the bug),
but the stop signal is still binary per round: FAIL just means "try again," no sense of
"closer" vs "just as wrong."

**CRITIC** (tool-verified critique, not self-judgment):

```
Round 1: draft v0
CRITIC dispatches a tool call (code execution against known cases, or a
lookup of the actual leap-year rule) instead of asking the model to judge
itself: "Rule requires century exception; year=1900 check fails."
Actor revises based on the TOOL's verified finding, not a guess.
Repeat until tool-verification passes or a round cap.
```

Same shape as Reflexion, grounded in an external tool rather than the actor's own reflection
text, harder to fool, still binary pass/fail per round.

**Evaluator-Optimizer** (Anthropic's generic workflow, our closest ancestor):

```
Generator produces draft v0.
A SEPARATE Evaluator call checks named criteria ("handles century
exception," "handles div-by-400") -> PASS/FAIL + feedback text.
Optimizer revises on FAIL. Repeat until PASS.
Anthropic's own writeup: no prescribed cap, no prescribed behavior on
repeated failure , left to whoever implements it.
```

Structurally closest to ours (a distinct evaluator role is *encouraged*), but still no severity
gradient and no contract for what happens if it never converges.

**Ours, on the actual delta: severity-aware convergence.** None of the above can express this
state, so here it is on a kit-native artifact (a `## Test plan` covering this same function),
engineered to hit the exact case that matters:

```
Round 1: 6 lenses scan the test plan
  -> lens 1 (coverage):    CRITICAL  "no test for century-boundary years (1900, 2000)"
  -> lens 2 (oracle):      HIGH      "expected output for year=2000 not a concrete assertion"
  -> lens 4 (test-ladder): LOW       "no test for year=0 or negative years"
  K = 3.  Distinct reviser (not one of the 6 lenses) revises the plan:
  adds century-boundary rows, makes assertions concrete , but introduces
  a duplicate row and leaves the year=0 case still vague.

Round 2: re-scan
  -> CRITICAL and HIGH from round 1: gone
  -> 2 NEW findings appear: MEDIUM "duplicate test row", MEDIUM "year=0 still vague",
     plus an unrelated LOW nit
  K = 3 again. SAME raw count as round 1.

  Under a plain Evaluator-Optimizer / raw-count rule: K flat (3 == 3) -> HALT,
  "not converging." This is the exact false stall SPEC-204 actually hit.

  Under our rule: worst severity dropped CRITICAL -> MEDIUM even though K
  didn't. Continue.

Round 3: reviser clears the two MEDIUMs and the LOW. K = 0. Verdict: SOLID.
```

The concrete payoff: none of Self-Refine, Reflexion, CRITIC, or Evaluator-Optimizer has a state
that distinguishes "3 findings, one of them CRITICAL" from "3 findings, all MEDIUM", it's PASS
or FAIL, full stop. A naive raw-count bounded loop (what we ourselves ran before the fix) would
have halted at round 2 here, wrongly, and reported a working test plan as "stuck." That is not
hypothetical, it is what SPEC-204 actually did.

## Cost problem, and the hybrid fix (2026-07-30, same-day follow-up)

The engine's real cost weakness: it dispatches N model-judged lenses every round regardless of
whether a given finding was ever mechanical. A binary stop condition (Reflexion/CRITIC-style) is
cheaper and just as correct whenever a criterion genuinely reduces to a measurable yes/no, the
severity-graded machinery only earns its cost for the residual judgment calls a script can't
make. The fix is not a new idea, it is `docs/WORKFLOW.md`'s own cheap-first
verification-cost-routing principle (line 210), applied *inside* the engine's own scan step
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
| No test row for year=1900/2000 | Tier 1 | `grep` the test plan for the literal boundary years, either the row exists or it doesn't |
| Expected output for year=2000 not a concrete assertion | Tier 1 | mechanical presence check: does the row contain a runnable assertion string, or a placeholder |
| No test for year=0/negative years | Tier 2 | genuine judgment call, is this edge case in scope for the spec, a script can't decide that |

Two of the three round-1 findings never needed a model dispatch at all. Round 2 only re-runs
the Tier-2 lens whose finding-space Tier 1 couldn't clear, not all 6, since Tier 1 already
confirmed the century rows exist. Cost drops from "6 parallel model calls x 3 rounds" toward
"2 grep checks + 1 model call x fewer rounds," while the severity-aware convergence rule still
protects the genuinely judgment-heavy residual from the false-stall problem. This is folded
into `skills/loop-engineering/SKILL.md` Step 2 as the engine's default scan shape, not an
optional optimization.

## Recommendation carried into `skills/loop-engineering/SKILL.md`

Don't rename the pattern, no single literature term covers the full bundle. Cite
Evaluator-Optimizer as the lineage (satisfies the skill's own source-citation gate), name the
three deltas above as the actual contribution, and pick the shape (fuller engine vs
Execute-pipeline-style) per the decision table, not by default.
