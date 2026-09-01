# ADR-0016: Doc-verifier agent (independent doc-vs-code fact-check)

## Status: accepted (2026-05-21).

## Context
`/docs` writes documentation and "verifies" it in the same context: it scans for drift, applies fixes, and commits, all main-thread. Nothing independently checks the result. This is the fox-guards-henhouse problem the kit rejects for self-verifying workers (ADR-0005): the context that wrote a doc claim is biased toward believing it. The Build phase has independent verification (`task-verifier` per task, `integration-checker` for cross-task wiring, SPEC-021); the Docs phase had none, so a stale count, a renamed-command reference, a documented flag that does not exist, or a phantom feature survives `/docs` because the only reader was the writer. The 2026-05-21 agent-scene survey ranked this the #2 archetype gap (after the integration-checker); GSD ships `gsd-doc-verifier` as the proven pattern.

## Decision
Adopt `agents/doc-verifier.md`, a read-only adversarial fact-checker dispatched by `/docs` at a new Step 4.5 (after Step 4 applies updates, before Step 5 commits). It reads the uncommitted doc diff (the edits are not committed yet) and verifies each checkable claim against the live code, returning the three-verdict shape. It is the Docs-phase twin of `task-verifier`, sibling to the integration-checker.

Rules that keep it honest:
- **Scoped read-only tools only** (Read/Grep/Glob, `Bash(git diff*)`/`Bash(git log*)`); no `Edit`/`Write`/`MultiEdit`/bare `Bash`, enforced by a meta assertion (same guard as SPEC-021).
- **Target = the uncommitted doc diff.** Step 4.5 runs before the commit, so the changed docs are in the working tree; the agent checks only what changed (no base ref needed, unlike the integration-checker).
- **Checkable claims only.** It verifies counts, names, existence, structure, and cross-references against code; it does not flag uncheckable prose, phrasing differences, or invent required docs (surfacing undocumented features stays `/docs`'s job).
- **The writer fixes, the verifier reports.** `FAIL:fixable` is fixed by `/docs` re-editing the named drift (max 2 rounds), NOT by `fix-agent`: `/docs` is a main-thread command, not the `/execute` worker pipeline. The independence is in the verify step, not the fix step.

## Alternatives considered
- **Extend `/review` to fact-check docs.** Rejected: `/review` is code-focused, human-triggered, and not part of `/docs`; drift would only be caught if a human runs `/review`, not automatically when docs are written.
- **A `/doc-verify` command.** Rejected: the value is automatic dispatch inside `/docs`; this is verification a fresh context does best (an agent), not a human-invoked methodology.
- **Use `fix-agent` for the doc fix.** Rejected: `/docs` is not the `/execute` pipeline; the main-thread re-edit by the writer is the correct fix path (DEC-003 in SPEC-022).

## Consequences
- The kit goes from 10 to 11 agents. `commands/docs.md` gains Step 4.5; the Step 5 commit is gated on the verifier's PASS.
- The kit now has THREE read-only verifiers (task-verifier, integration-checker, doc-verifier), all instances of the one ADR-0005 pattern. This meets the rule-of-three for abstraction; a shared verifier-agent template is recorded as a future option (SPEC-022 DEC-007), deliberately not done yet to avoid coupling three independent agents.
- The value is anticipated, not yet observed (no retro records stale-docs-passing-`/docs`); it concentrates when `/docs`'s self-scan is optimistic. Recorded as the owner-accepted timing call; `/user:retro` should evaluate whether the three verifiers collectively pay off before a fourth (SPEC-022 Known limitation 2).
- Source: SPEC-022; GSD `agents/gsd-doc-verifier.md` (https://github.com/glittercowboy/get-shit-done). Reuses ADR-0005; mirrors `agents/task-verifier.md` and `agents/integration-checker.md` (ADR-0015).
