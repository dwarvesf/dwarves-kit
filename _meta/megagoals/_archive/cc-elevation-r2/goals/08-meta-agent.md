# Sub-goal 08: Meta-agent (generate a subagent from a description)

**Time budget:** ~2-3h
**Depends on:** none
**Branch:** feat/cc-elev-r2-08-meta-agent
**PR base:** main

## Outcome

A meta-agent: given a natural-language description ("a read-only agent that audits Terraform for drift"), it emits a valid subagent spec file (correct frontmatter: name, description-as-when-to-use, scoped tools, focused system prompt) into the right directory, so I can mint a focused subagent without hand-writing the spec. "Build the thing that builds the thing." Ships as a skill or a small generator tool.

## Quality bar

The generated spec is valid (loads/registers, frontmatter correct, tools scoped to the task, description follows the when-to-use discipline). It generates, it does not auto-install over an existing agent without confirm.

## How to close the loop

- Implement the generator (skill or tool); run it on a sample description; confirm the emitted file is a valid subagent spec (frontmatter parses, tools scoped, description is trigger-shaped) and that it registers/validates.
- Negative control: a vague/empty description yields a request for detail, not a malformed spec.
- Lane via lane-classify; the new tool/skill owes proof-of-done (or a skill test) with the generated sample.

**Done =** the meta-agent turns a description into a valid, scoped subagent spec file that loads, proven on a sample (and refuses a vague description rather than emitting garbage); proof-of-done; on PR #NN.

## Scope edges

**In:** the generator skill/tool + a sample generated agent + proof.
**Out:** a library of pre-built agents (commodity); the saved-workflows (05).
**Not:** auto-overwriting existing agents.

## Where to look

disler's meta-agent (https://github.com/disler/claude-code-hooks-mastery), the subagent spec/frontmatter format + the agent-type registry, the writing-skills description discipline (description = when-to-use, not workflow), existing agents under the kit.

## PR body

Outcome: a meta-agent that generates a valid, scoped subagent spec from a description.
Verify: sample description -> valid registering spec; vague description -> asks for detail (no garbage).
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 08).

## Notes
