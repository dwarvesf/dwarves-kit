# Sub-goal 05: meta-agent-drafter

**Merge policy:** gate (dwarves-kit shared repo + new agent surface, team review)
**Time budget:** ~1 session
**Proof:** run-table , the drafter produces a valid new subagent .md AND a valid mega-goal sub-goal
file from a one-line description; both pass the kit's frontmatter/structure lint; output is marked
draft-for-review.
**Depends on:** none
**Branch:** `feat/v3-meta-agent`
**PR base:** dwarves-kit `main`

## Outcome
A gated meta-agent ("the agent that builds agents", from claude-code-hooks-mastery) plus a skill
verb drafts a new subagent definition OR a new mega-goal sub-goal file from a natural-language
description. Output is always a DRAFT for human review, fitting the kit's curated+gated philosophy,
not an autonomous agent factory.

## Quality bar
A draft a human would accept with light edits, not boilerplate. It determines minimal tool
requirements and follows the kit's exact frontmatter + structure. It never self-installs or
self-runs; the gate is the point.

## How to close the loop
In the dwarves-kit checkout, author `agents/meta-agent.md` (or the kit's agent location) + a
skill/command verb. Verify:
```
# drive the drafter with a one-line description, twice (agent + sub-goal file)
# lint the outputs against the kit's frontmatter/structure checks
bash tests/test-meta-agent.sh     # or the kit's agent-lint on the generated files
```
Capture a run-table: agent-draft passes frontmatter lint; sub-goal-file draft matches the
plan-for-mega-goal subgoal template; both carry a "DRAFT , review before use" marker.

**Done =** the meta-agent drafts a lint-passing subagent .md and a template-conforming sub-goal file
from a description, both marked draft-for-review, with the run-table recording the lint passes.

## Scope edges
**In:** `agents/meta-agent.md` + a drafting skill/command verb + a test. Phase-1 DRAFTER only.
**Out:** the data-driven auto-routing (SG-06, needs SG-09's data); auto-installing or auto-running
generated agents.
**Not:** a free-running agent factory; generating agents without the review gate; touching the
existing kit agent roster.

## Where to look
claude-code-hooks-mastery meta-agent (`.claude/agents/meta-agent.md`, "the agent that builds
agents", pulls latest CC docs, determines minimal tools). The kit's existing agents (kit:reviewer,
task-verifier, research-*) for the frontmatter + structure to match. `plan-for-mega-goal` subgoal
template (for the sub-goal-file drafting mode). `writing-skills` superpower + `extract-workflow`
(existing meta-tooling, do not duplicate).

## PR body
feat(kit): meta-agent drafter , gated "agent that builds agents" that drafts a subagent or sub-goal
file from a description (from claude-code-hooks-mastery). Draft-for-review only; fits the kit's gated
philosophy. Verification: lint-pass run-table. Gated. token-optim-v3 sub-goal 05.

## Notes
