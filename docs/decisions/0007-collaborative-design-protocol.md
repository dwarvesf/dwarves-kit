# ADR-0007: Collaborative Design Protocol for agent decisions

## Status: accepted (v1.2)

## Context
Worker subagents encounter design decisions during implementation (which library, which data model, which API pattern). Without structure, they either guess silently or block on every decision.

## Decision
Shared protocol with 5 steps: Question > Options > Recommendation > Decision > Record. The protocol definition lives in `docs/architecture.md` (Collaborative Design Protocol section). Agents reference this protocol in their prompts. In autonomous mode (/execute), agents proceed with their recommendation and log it. The task-verifier catches misalignment after the fact.

## Alternatives considered
- Always block on decisions: too slow for autonomous /execute. Every non-trivial task has 2-3 decisions.
- Never structure decisions: agents make silent choices that are hard to review.
- Per-agent decision rules: inconsistent. A shared protocol means all agents speak the same decision language.

## Consequences
- Worker subagents can make decisions autonomously in /execute mode.
- Decisions are logged in .planning/SPEC.md Decision Log for audit.
- task-verifier checks whether decisions align with the spec.
- In manual /next mode, agents pause for human approval on decisions.
- Source: CCGS Collaborative Design Principle, adapted to fit the verification pipeline.
