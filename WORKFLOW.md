# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The only hard stops are the
> safety-gate hook, the push-to-main blocker, the anti-rationalization Stop
> hook, and the verification pipeline.

## Required reading (in order)
1. CLAUDE.md            - project context: stack, structure, rules
2. docs/specs/SPEC-NNN-<slug>.md - the active spec; the shared contract for the cycle
3. docs/architecture.md - how the pieces fit (reference; not required per task)

## Size the work first (risk-tiered intake)
Pick a lane before you start. Smaller work skips ceremony.

| Lane   | When | Path |
|--------|------|------|
| tiny   | typo, copy, comment, one obvious edit | edit, verify, done. No spec. |
| normal | one bounded feature or fix | /spec, /execute, /review, /ship |
| full   | touches auth, authz, hooks, data model, data loss, audit/security, an external provider, an API contract, a migration, or weakens validation | /think, /spec, /spec-validate, /execute, /review-team, /docs, /ship, /retro |

When in doubt between two lanes, take the heavier one. Anything in the full-lane
trigger list uses the full lane unless you explicitly narrow the scope and say why.

## The cycle (phase, exit, enforcer)
| Phase    | Command | Exit when | Enforced by |
|----------|---------|-----------|-------------|
| Think    | /user:think | decision brief written (if BUILD) | advisory |
| Spec     | /user:spec | spec exists, Status: DRAFT | spec-drift-guard hook |
| Validate | /user:spec-validate | Status: VALIDATED | advisory (full lane) |
| Build    | /user:execute or /user:next | tasks checked, verifier PASS | verification pipeline (worker, verifier, fix; max 2) |
| Review   | /user:review or /user:review-team | review verdict recorded | advisory |
| Docs     | /user:docs | README/CHANGELOG match code | advisory |
| Ship     | /user:ship | tagged + PR | ship gate (blocks on DO NOT SHIP), push-to-main blocker |
| Reflect  | /user:retro | docs/retro/v<version>.md written | advisory |

Throughout: safety-gate blocks destructive Bash; anti-rationalization blocks
premature "done"; auto-format runs on edit; session-state-save and
post-compact-reinject protect long sessions.

## Completion contract
A task is done only when its acceptance criteria are met and the verifier has
actually run the tests, not when you claim they pass. If you cannot run the
check, report that plainly; the anti-rationalization hook is the backstop for
premature completion. Self-reported "done" is not proof; the task-verifier is.

## What this contract does NOT do
It does not lock phases. An experienced operator may skip /spec-validate on a
normal-lane change or go straight to /next. The kit detects state
(context-readiness hook) and suggests the next step; it never blocks
progression. Hard stops are reserved for irreversible cost: destructive
commands, push-to-main, premature completion, failed verification.
