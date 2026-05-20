# ADR-0005: Separate verifier subagent instead of worker self-verification

## Status: accepted (v1.2)

## Context
After a worker subagent completes a task, the orchestrator needs to know if the work meets the spec. Two options: (A) have the worker self-verify, or (B) dispatch a separate read-only verifier.

## Decision
Separate task-verifier subagent with read-only access. It checks acceptance criteria, runs tests, and checks scope compliance. Returns PASS, FAIL:fixable, or FAIL:escalate.

## Alternatives considered
- Worker self-verification: cheaper (no extra subagent) but biased. The worker's context is saturated with its own implementation. It normalizes its own shortcuts.
- Orchestrator inline verification: keeps it in the main session, but the orchestrator's context should stay lean for coordination, not deep code reading.

## Consequences
- Every task costs one extra subagent dispatch (task-verifier). Roughly 2x the token cost per task.
- Verification is independent: the verifier has no knowledge of the worker's reasoning, only the spec and the code.
- The verifier cannot modify code. If it finds issues, it reports them for the fix-agent.
- Source: Synthesized from the family of architect-verifier-in-Ralph-loop patterns documented across AI-coding-agent projects in 2024-2025, adapted to Claude Code custom subagents. (The "OMC" anchor was removed in v1.6: the repo associated with that name does not match the architect-verifier pattern, and a verifiable single source could not be cited, so the kit owns this pattern as synthesized. See SPEC-002 TASK-4 / DEC-003.)
