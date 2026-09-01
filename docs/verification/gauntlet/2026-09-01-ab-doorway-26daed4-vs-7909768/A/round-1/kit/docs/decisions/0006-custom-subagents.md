# ADR-0006: Custom subagents via .claude/agents/ directory

## Status: accepted (v1.2)

## Context
v1.2 introduces 8 agent roles (task-verifier, fix-agent, reviewer, security-auditor, 4 researchers). These need prompt definitions that commands can reference.

## Decision
Agent definitions live in `.claude/agents/` as markdown files with YAML frontmatter (name, description, tools, model). install.sh copies them to `~/.claude/agents/`. Commands dispatch them via the Task tool.

## Alternatives considered
- Inline prompts in command files: works but duplicates content. Can't tune agent prompts independently.
- MCP server agents: more powerful but requires a running server. Too heavy for this kit.
- Skill files: skills are Claude-triggered, not command-triggered. Agents are dispatched by commands.

## Consequences
- Requires Claude Code v2.0.60+ (custom subagent support).
- Agent prompts can be tuned independently from commands.
- Model selection per agent: research-stack uses haiku (cheap), others use sonnet.
- install.sh handles agent install/uninstall alongside commands and skills.
