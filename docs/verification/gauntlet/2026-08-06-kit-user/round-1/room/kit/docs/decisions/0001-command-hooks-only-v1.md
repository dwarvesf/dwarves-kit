# ADR-0001: Command hooks only for v1

## Status: accepted

## Context
Claude Code supports 4 hook handler types: command, http, prompt, agent. Prompt hooks delegate decisions to an LLM (Haiku). Agent hooks spawn subagents with tool access. Both add latency and cost per hook invocation.

## Decision
v1 uses command hooks exclusively. All 5 hooks are bash scripts that read JSON from stdin, pattern-match, and return exit codes.

## Alternatives considered
- Prompt hooks for anti-rationalization: better accuracy but adds ~2-5s latency per Stop event and costs tokens. Deferred to v2.
- Agent hooks for spec-drift-guard: could verify file intent with codebase analysis. Overkill for a grep-based check.
- HTTP hooks for team-wide enforcement: useful but requires a shared server. Not needed for solo/small team.

## Consequences
- Anti-rationalization hook uses grep patterns, which will have some false positives on legitimate "out of scope" mentions.
- All hooks run in under 500ms, keeping sessions fast.
- No external API calls or LLM costs from hooks.
