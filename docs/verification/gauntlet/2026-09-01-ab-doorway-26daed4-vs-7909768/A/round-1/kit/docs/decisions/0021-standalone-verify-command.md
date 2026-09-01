# 0021. Standalone read-only verification: `/kit:verify`

Date: 2026-05-23
Status: Accepted
Relates-to: SPEC-035 (verify command), ID-038, the build-left/test-right V-model (ADR-0018 correction)

## Decision (one line)

Read-only verification is **independently invocable** as `/kit:verify`: it re-dispatches the existing `task-verifier` + `integration-checker` agents against the active spec/branch with **no rebuild and no fix**. This is **additive** to "verify before proceeding", not a reversal of it.

## Context

The V-model's right arm (the test levels) executed only inside `/kit:execute`. There was no way to re-run the unit + integration levels on demand: after a manual edit, on a branch built elsewhere, or for a read-only `/goal` loop check. The V-model coverage map named this the one genuinely missing command.

An earlier framing called this a "boundary reversal" needing a superseding ADR (parallel to ID-035). On closer reading of PHILOSOPHY that was an overstatement: "verify before proceeding" / "verify, then trust" mandate that verification *happen* and that it run in a *fresh read-only context*, not that it run *only* inside `/kit:execute`. So a standalone read-only verify command is additive, not a reversal.

## Decision

1. **`/kit:verify` is a command, not an agent.** Per the command-vs-agent rule (`docs/architecture.md`): a human or the `/goal` loop must trigger it directly, and it orchestrates (dispatches the read-only test agents). The test logic stays single-sourced in `task-verifier` / `integration-checker`; the command adds only a trigger.

2. **Read-only, no fix.** `/kit:verify` reports PASS/FAIL and never dispatches `fix-agent`. This mirrors `/kit:review` and keeps it safe for the `/goal` loop to call (no surprise mutations). To fix, the operator runs `/kit:next` or `/kit:execute`.

3. **Base ref by merge-base.** `integration-checker` needs a diff base that `/kit:execute` normally records before a build. With no build, `/kit:verify` computes `git merge-base HEAD <default-branch>` (`origin/main` if present, else `main`/`master`); on the default branch it falls back to the spec's first commit or `HEAD~1`.

4. **Criterion #2 cleared.** `/kit:verify` executes the unit + integration (+ system suite) test levels: a multi-level executor and the test handle for the orchestration layer, not a single-purpose script.

## Alternatives considered

- **A `--verify-only` flag on `/kit:execute`.** Rejected: overloads the build command with a non-build mode and breaks the "execute mutates / verify reads" split that makes `/kit:verify` safe for the loop.
- **A verify *agent* instead of a command.** Rejected by the command-vs-agent rule: the user/loop triggers verification directly, so it is a command. The actors it dispatches (`task-verifier`, `integration-checker`) are the agents.
- **Verify-and-fix.** Rejected: that is a second `/kit:execute`. Read-only keeps the surfaces distinct.
- **A `VERIFY.md` report file.** Deferred (anti-speculation): stdout only until a real consumer needs a file.

## Consequences

- New `commands/verify.md`; `docs/architecture.md` inventory gains one TEST-arm row (31 -> 32; commands 20 -> 21); the parity guard tracks it.
- The WORKFLOW V-model lens closes its "no on-demand re-run" gap; the diagram shows `/kit:verify` re-running the lower test arm.
- 3 `tests/test-meta.sh` assertions pin it: file + one-line description, dispatches both agents, no `fix-agent` (read-only, hardened against a vacuous pass).
- The three rejected "symmetry" commands (`/kit:accept`, `/kit:check-reqs`, `/kit:doc-spec`) stay rejected as phantom duplications of the ship gate + retro + spec-validate.
- Source: SPEC-035 / ID-038. Reuses the `task-verifier` / `integration-checker` agents (ADR-0005 verify-then-trust lineage); no net-new methodology.
