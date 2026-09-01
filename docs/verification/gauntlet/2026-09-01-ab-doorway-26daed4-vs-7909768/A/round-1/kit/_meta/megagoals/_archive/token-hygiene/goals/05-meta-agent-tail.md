# SG-05: meta-agent tail-specialization prototype

Merge policy: gate
Time budget: ~1-2 sessions
Depends on: SG-01 (needs `token-forensic --loops` to measure)

## Directional outcome
Test Han's hypothesis: for unspecified "tail" work that today falls to the generic
`general-purpose` subagent, a runtime-generated **ephemeral, tool-scoped** subagent is
better, on quality AND token cost (narrow tool allowlist = smaller per-turn footprint than
general-purpose loading every tool). Prototype + measure; do NOT touch the fixed roster.

## Done =
An experiment at `experiments/meta-agent-tail/` containing: (1) a meta-agent mechanism that
turns a task description into an ephemeral subagent definition with a NARROW tool allowlist
(model the disler meta-agent + native `/agents`); (2) a head-to-head on 2-3 representative
tail tasks, meta-agent-generated vs general-purpose; (3) a `token-forensic --loops`
comparison (tokens) plus a quality note; (4) a verdict: adopt as a kit "tail" lane, or not,
with the numbers. PR opened (gate: experimental pattern, wants review before any kit
adoption).

## Close the loop (verification)
```
ls experiments/meta-agent-tail/README.md
# README shows the comparison table (meta-agent vs general-purpose: tokens + quality) + verdict
tools/token-forensic/bin/token-forensic --loops --days 1   # numbers behind the comparison
```

## Scope edges
Prototype only , lives in `experiments/`, never edits the kit core roster in this sub-goal.
The generated agent MUST be tool-scoped (narrow allowlist); a wide allowlist defeats the
token premise. Compare apples-to-apples (same task, same model tier).

## Where to look
`research/2026-06-28-meta-subagent-evaluation.md` (the do-not-build-blanket / do-prototype-
tail refinement), disler/claude-code-hooks-mastery (generation mechanism), Anthropic native
`/agents` + dynamic workflows. The deep-read brief from the 2026-06-28 session.

## PR body
feat(experiment): meta-agent tail-specialization prototype + token/quality comparison vs
general-purpose. Gate (experimental; informs whether the kit gets a tail lane).
