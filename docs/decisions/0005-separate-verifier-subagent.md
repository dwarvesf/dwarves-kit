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
- Source: OMC's architect verification in the Ralph loop, adapted to Claude Code custom subagents. Lineage note: the OMC anchor citation needs review (the `1mancompany/OneManCompany` repo currently associated with the name does not match the architect-verifier pattern; the pattern is genuinely synthesized from the family of architect-verifier-in-Ralph-loop sources).
