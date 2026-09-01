# SG-05: cheap-planner / expensive-executor split (experiment)

> REFRAME (Han 2026-06-29, out-of-loop, approved): the "planner" here is a LOCATOR (find code:
> file/symbol/interface), NOT a designer. Locating is search, not reasoning, so the right tool is a
> deterministic INDEX (zero model cost), not a cheap LLM. The cheap-LLM-planner is demoted to a
> falsification arm. The separate axis "smart-DESIGN + cheap-EXECUTE" (where to put intelligence
> when the goal's DESIGN is ambiguous) is a different question, logged to NOTES `## Proposed
> additions`, measured separately.

Merge policy: gate (stacked; reviewed at end of wave with the rest, per Han 2026-06-29)
Time budget: ~1-2 sessions
Depends on: (none hard; uses token-forensic --loops from token-hygiene SG-01, merged)
Stacking: first in the ops-toolkit stack; branch off ops-toolkit main. SG-09 stacks on this branch.
Model: opus
Effort: high

## Directional outcome
Test the hypothesis that doing DISCOVERY on a cheap model (the "find out" tax Han flagged) and
handing precise answers to Opus for the actual edit is cheaper at equal quality. Prototype +
measure; do not wire into the kit yet.

## Done =
`experiments/planner-split/` with: (1) the mechanism under test , an index-based LOCATOR
(codebase-memory MCP, or the kit codebase-index; zero model cost) that returns precise
file:symbol pointers for a task, feeding a narrow-read Opus executor; (2) a 3-arm head-to-head on
2-3 representative tasks , **A** Opus-does-everything (baseline); **B** index-locator -> Opus
narrow-read+execute (the real candidate); **C** cheap-LLM-planner -> Opus-executor (run on 1 task
only, to falsify the original framing); (3) a token comparison + a coherence note
(turns-to-green / rework, not tokens alone); (4) a verdict (adopt index-first discovery into
/kit:execute, or not) with the numbers. Keep a lever only if tokens DOWN **and** coherence not
worse. PR opened.

## Close the loop (verification)
```
ls experiments/planner-split/README.md          # comparison table (tokens + quality) + verdict
python3 experiments/planner-split/*selfcheck* 2>/dev/null || true   # if any helper code, its check
```

## Scope edges
Experiment only, in `experiments/planner-split/`. Do NOT wire into `/kit:execute` in this
sub-goal (that is a follow-up if the verdict is yes). Same task/model-tier apples-to-apples.

## Where to look
The token-hygiene SG-05 meta-agent experiment as a shape; the kit `codebase-index` hook;
`research/2026-06-28-*` cost notes; the 2026-06-29 planner-split discussion.

## Proof expectation
README with the comparison table (tokens + quality) + a verdict; a runnable selfcheck if there
is any helper code. Full reviewable proof (it is an experiment with a measured claim).

## PR body
feat(experiment): cheap-planner / expensive-executor split + token/quality comparison vs
Opus-does-all. Gate (experimental; informs a kit /kit:execute change).

## From the token-efficient note (2026-06-29)
Caveat to measure honestly: subagents can cost ~7x, so the cheap-planner split only wins when
the planner's narrow-context discovery genuinely offloads work the executor would otherwise do
in the expensive context. If the split adds round-trips without removing executor discovery, the
ablation will show it losing , report and drop it. See `research/2026-06-28-token-efficient-design.md`.
