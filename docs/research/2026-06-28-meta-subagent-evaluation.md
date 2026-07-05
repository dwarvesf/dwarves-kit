---
date: 2026-06-28
slug: meta-subagent-evaluation
type: reference
status: final
verdict: roster-for-core-prototype-for-tail
---

# Meta-subagent (generative agent factory): evaluation + verdict

Decision record. Evaluated whether dwarves-kit should add a "meta-subagent": an
orchestrator that, given a task, dynamically generates a new subagent definition with the
right tools/skills/MCP, instead of picking from a fixed roster. (Research: web + GitHub,
2026-06-28 session.)

## Verdict (refined): curated roster for the core; prototype a meta-agent for the TAIL.

Do NOT replace the roster with a generator. DO prototype a runtime meta-agent for the
unspecified-work tail that currently falls to the generic `general-purpose` agent.

Why not a full generative factory (for the core/known work):
- A generator writes an agent definition every run = recurring token overhead.
- It sacrifices what the kit depends on: determinism, tight tool-scoping, version-control,
  and the proof-of-done / SDD gate. The kit's win cases (reviewer, task-verifier,
  research-*) are valuable precisely because they are fixed, scoped, and reproducible.

Why prototype it for the tail (the refinement, 2026-06-28):
- Unspecified work today runs on `general-purpose` (tools=`*`): no scoping, generic prompt,
  and it loads every tool definition into its context. A runtime-generated, tool-scoped
  ephemeral subagent is plausibly better on BOTH quality (focus) and token (narrow
  allowlist = smaller per-turn footprint). The determinism/reproducibility cost matters far
  less for one-off tail work than for the SDD core.
- The runtime mechanism already exists: the Anthropic Agent SDK `agents` option /
  `AgentDefinition` takes inline `{name, description, prompt, tools, model}` (ephemeral, no
  file). Cheapest prototype: reuse disler's meta-agent prompt (verb -> minimal-tool-allowlist
  logic) to PRODUCE the AgentDefinition, feed it to the SDK `agents` option at runtime, keep
  `general-purpose` as graceful fallback. Tracked as mega-goal SG-05.
- Dynamic flexibility is rarely the bottleneck; a missing specialist is.

## The escape valve (already available)

When a genuine gap appears, use the native Claude Code `/agents` flow to *generate* a new
subagent definition once, review it, and **commit it into the fixed roster**. Generation
at author-time, fixed roster at run-time. No new machinery needed.

## Reference patterns (if ever revisited)

| Name | Pattern | URL |
|---|---|---|
| disler/claude-code-hooks-mastery | The canonical meta-agent: a subagent that emits a new `.claude/agents/*.md` from a description | https://github.com/disler/claude-code-hooks-mastery |
| wshobson/agents | Large curated roster + `agent-organizer` supervisor | https://github.com/wshobson/agents |
| VoltAgent/awesome-claude-code-subagents | Curated index (100+) | https://github.com/VoltAgent/awesome-claude-code-subagents |

Architectures seen: meta-agent/factory (generate definitions), supervisor + fixed roster
(route to specialists), on-the-fly harness (model composes a throwaway multi-agent graph,
e.g. Anthropic dynamic workflows). The kit already uses supervisor + fixed roster; that is
the right fit.

## Relation to the token-hygiene mega-goal

Adjacent, not part of it. The mega-goal (`_meta/megagoals/token-hygiene/`) changes how the
EXISTING fixed subagents return (summarize) and how the loop checkpoints, not whether
subagents are generated. This note records the "no factory" decision so it is not
re-proposed.
