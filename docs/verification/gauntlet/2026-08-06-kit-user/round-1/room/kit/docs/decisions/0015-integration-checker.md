# ADR-0015: Integration-checker agent (cross-task wiring verification)

## Status: accepted (2026-05-21).

## Context
The 2026-05-21 agent-scene survey (the deep dig across GSD, wshobson/agents, SuperClaude, claudekit, ouroboros, BMAD, superpowers) found the kit's 9-agent set close to complete for a one-session lifecycle, with exactly one genuine archetype gap: nothing verifies that the tasks of a build actually wire together. `task-verifier` is per-task by design; the full test suite runs once per phase and at completion, and it silently passes when integration tests do not exist (the common case). The result is a build where every task is verified, the suite is green, and a new component is never registered, a handler is never mounted, or a data chain is broken at a seam no single task owned. Everything else the mature toolkits add was persona theater, swarm orchestration, or a command the kit already owns.

## Decision
Adopt one agent: `agents/integration-checker.md`, a read-only adversarial cross-task verifier dispatched ONCE at `/execute` Step 4 for specs with more than one task. It reuses the kit's own already-blessed mechanism (a read-only verifier in a fresh window, plus the write-scoped fix-agent for fixable gaps, ADR-0005), applied to the seam between per-task PASS and the once-at-end suite.

Four rules keep it honest rather than noisy:
- **Scoped read-only tools only** (Read/Grep/Glob, `Bash(git diff*)`/`Bash(git log*)`, the test runners). No `Edit`/`Write`/`MultiEdit`, no bare `Bash`. A "read-only" verifier that can write is the exact foot-gun ADR-0005 separates verifier from fix-agent to prevent; a meta assertion enforces it.
- **Verify activation, not invented links.** It checks that each new component reaches its activation point (a hook registered, a handler mounted, an export imported AND called) plus the spec's STATED end-to-end chains. It does NOT invent links between independent tasks (many specs ship unrelated components in one build). A defined-but-unactivated component is a finding; an imagined cross-link is not.
- **Diff the whole build.** `/execute` passes the pre-build base ref so the agent diffs `<base>..HEAD`, not just the last commit.
- **Gated and bounded.** Single-task specs skip it (nothing to wire). It runs once (not per task), so token cost is bounded. `FAIL:fixable` reuses fix-agent + the max-2 retry; design-level gaps escalate.

## Alternatives considered
- **Extend `task-verifier`.** Rejected: it is per-task and runs N times; the cross-task check is only fully present at the end. Folding it in either runs the global check N times or muddies a single-purpose agent.
- **A `/integration-check` command.** Rejected: the value is automatic dispatch inside the build, and this is verification work a fresh context does best (an agent), not a human-invoked methodology; a command would also duplicate the agent.
- **Adopt more survey agents now (doc-verifier, simplify).** Deferred. The survey found the 9-agent set otherwise complete; `doc-verifier` (independent verification for `/docs`) is the next candidate if this pattern proves out; `simplify` waits until slop is measured.

## Consequences
- The kit goes from 9 to 10 agents. `commands/execute.md` Step 4 gains the dispatch + routing; `task-verifier`/`fix-agent` are unchanged.
- A new boundary: `task-verifier` answers "is this task correct?", `integration-checker` answers "do the tasks connect?".
- The value is anticipated, not yet observed (no retro records broken-wiring-passing-CI in kit usage) and concentrates in under-tested/greenfield code; a well-tested project's suite already catches wiring. Recorded as the owner-accepted timing call, to confirm at `/user:retro` (SPEC-021 Known limitation 4).
- Source: SPEC-021; GSD `agents/gsd-integration-checker.md` (https://github.com/glittercowboy/get-shit-done). Reuses ADR-0005 (verification pipeline); mirrors `agents/task-verifier.md`.
