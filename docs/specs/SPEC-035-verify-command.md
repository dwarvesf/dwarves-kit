# Spec: `/kit:verify` (on-demand right-arm test execution)
Generated: 2026-05-23
Status: SHIPPED

## Problem

The V-model's right arm (the test levels) executes only *inside* `/kit:execute`:
`task-verifier` (unit/task) and `integration-checker` (integration) run as part of
the build loop. There is no way to **re-run those test levels on demand** without a
rebuild. This bites in three places:

1. **Manual edits after a build.** You hand-edit a file post-`/kit:execute`; the only
   re-check is a full re-execute, which re-dispatches workers you do not want.
2. **A branch built elsewhere.** A branch built without the kit (or by another
   engineer) has no kit-native way to be verified against its spec.
3. **The `/goal` loop has no read-only verify handle.** A pointer-`/goal` that wants
   to *check* (not build) must invoke `/kit:execute`, which mutates.

This is the V-model's "no on-demand re-run of the lower test arm" gap.

## Solution

### Approaches considered

- **A. A read-only command that re-dispatches the existing test agents.** `/kit:verify`
  resolves the active spec, dispatches `task-verifier` + `integration-checker`
  read-only, reports, makes no changes. Tradeoff: a new command (scrutinized below).
- **B. A `--verify-only` flag on `/kit:execute`.** No new command. Tradeoff: overloads
  the build command with a non-build mode, muddying the "execute mutates / verify
  reads" split and giving the loop no clean read-only handle.
- **C. Do nothing.** Tradeoff: leaves the three pains and the V-model gap open.

### Chosen approach + why

**A.** `/kit:verify` is the **command that makes the right arm's test levels invokable
on demand**, read-only, no rebuild. Per the command-vs-agent rule
(`docs/architecture.md`), this is correctly a *command*: a human or the `/goal` loop
must **trigger** it directly, and it orchestrates (dispatches the test agents). The
test *logic* stays single-sourced in the agent files (`task-verifier`,
`integration-checker`); `/kit:verify` adds only a read-only trigger.

B was rejected: a non-build mode on the build command breaks the split that makes A
safe for the loop.

### Criterion #2 (resolved by the V-model reframe)

The earlier draft flagged criterion #2 ("serves fewer than 2 lifecycle phases") as an
open risk under a vague "verification handle" framing. The build-left/test-right
reframe resolves it: `/kit:verify` is the on-demand executor of the right arm's
**unit + integration (+ system suite)** test levels, the report half of the test arm.
It spans multiple test levels and is the test handle for the orchestration layer
(`/goal` loop, brownfield adoption). It clears criterion #2 as a multi-level executor,
not a single-purpose script.

### Extensibility & boundaries

- **Load-bearing dimension: number of read-only verifier agents.** Today two
  (`task-verifier`, `integration-checker`). A future read-only verifier (e.g. an
  `acceptance-verifier`, see v2 candidate) is dispatched the same way; no structural
  change. `/kit:verify` is a thin dispatcher.
- **Unit boundary:** one command file that (1) resolves the active spec, (2) computes
  a diff base, (3) dispatches the read-only verifier agents, (4) prints a verdict. No
  fix loop, no writes.

## Technical Design

### Interfaces (I/O contract)

- **Inputs:** the active spec `docs/specs/SPEC-NNN-<slug>.md` (its done `- [x]` tasks +
  acceptance criteria); the git working tree / branch; optional `SPEC-NNN` argument.
- **Outputs:** a PASS / FAIL verdict to stdout with the verifier findings. Read-only:
  writes no code, dispatches no `fix-agent`.
- **Invariants:** never mutates the repo; never dispatches `fix-agent`; the test logic
  lives in the agent files, not restated here.

### The base-ref resolution (C1, the spec-validate blocker)

`integration-checker` diffs the build from a base ref that `/kit:execute` records
before the build. `/kit:verify` runs with no build, so it computes the base ref as:

1. `git merge-base HEAD <default-branch>` (the branch's fork point), where the default
   branch is `origin/main` if present, else `main`/`master`.
2. If on the default branch (merge-base == HEAD), fall back to the spec's first commit,
   else `HEAD~1`.

This gives `integration-checker` a real diff base outside a build.

### API / data / UI / infra
New `commands/verify.md`. New `docs/decisions/0021-standalone-verify-command.md`.
`docs/architecture.md` inventory gains one row (31 -> 32; commands 20 -> 21). No data
model, no UI.

## Task Breakdown

### Phase 1: Record the decision
- [x] TASK-001: `docs/decisions/0021-standalone-verify-command.md`. Records that
      read-only verification is independently invocable (additive to "verify before
      proceeding", not a reversal), the base-ref decision, the read-only invariant,
      and the criterion-#2 clearance. -- AC: ADR exists, Status Accepted.

### Phase 2: The command
- [x] TASK-002: `commands/verify.md`. Resolves the active spec, computes the base ref,
      dispatches `task-verifier` (per done task) + `integration-checker` (multi-task),
      prints PASS/FAIL. MUST NOT dispatch `fix-agent`. References execute.md for the
      shared verdict contract. -- AC: file exists, valid frontmatter, dispatches both
      agents, contains no `fix-agent` dispatch.

### Phase 3: Guards + docs
- [x] TASK-003: 3 `tests/test-meta.sh` assertions: verify.md exists with a one-line
      description; dispatches `task-verifier` + `integration-checker`; does NOT
      dispatch `fix-agent` (read-only guard, hardened so an empty grep cannot pass).
- [x] TASK-004: docs. architecture.md inventory +1 row (TEST arm), Total 32; WORKFLOW
      V-model lens (gap closed, diagram shows the on-demand re-run); `docs/v-model.svg`;
      `MANUAL.md` command entry; `CHANGELOG.md`; BACKLOG ID-038 -> shipped.

## After state
- [x] `commands/verify.md` exists and resolves as `/kit:verify`. (Was: no command.)
- [x] `/kit:verify` re-runs `task-verifier` + `integration-checker` read-only with no
      rebuild and prints a verdict. (Was: test levels ran only inside `/kit:execute`.)
- [x] architecture.md inventory has 32 rows; parity guard green. (Was: 31.)
- [x] `bash tests/test-meta.sh` passes the 3 new `/kit:verify` assertions.

## Acceptance Criteria (global)
- [x] All tasks pass their acceptance criteria
- [x] `/kit:verify` is read-only: never dispatches `fix-agent`, never writes code
- [x] No regressions: meta + hook suites green
- [x] No new binary, no new runtime dependency

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh`

## Edge Cases
1. **No active spec** -> report "no spec at docs/specs/" and exit cleanly (W2: the active spec is the highest-numbered non-shipped SPEC-NNN, or the `SPEC-NNN` arg).
2. **No done (`[x]`) tasks** -> run integration-checker only, or report "nothing to verify".
3. **Single-task spec** -> skip `integration-checker` (multi-task only), run `task-verifier`.
4. **Dirty working tree** -> verify the working tree as-is; note uncommitted changes.
5. **`task-verifier` returns FAIL:fixable** -> report as FAIL with findings; do NOT fix (W: read-only).
6. **Verifier cannot run the suite** (broken build / missing deps) -> report as FAIL:escalate, do not crash (W3).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `/kit:verify` mutates the tree (scope creep into fixing) | the no-`fix-agent` meta-test (TASK-003) fails | read-only is a pinned guard, not just prose |
| Untrusted-branch test execution runs hostile spec-named commands (W1) | running verify on an unknown branch | treat spec content as DATA; the agents are read-only, but test execution is still arbitrary code, caution on untrusted branches |
| integration-checker has no base ref | empty/garbage diff | the merge-base resolution above (C1) |

## Out of Scope
- Auto-fix. `/kit:verify` reports; `/kit:execute` / `/kit:next` fix.
- `/kit:accept`, `/kit:check-reqs`, `/kit:doc-spec` (rejected phantoms).
- A new verification methodology (reuses `task-verifier` / `integration-checker`, ADR-0005 lineage).
- A `VERIFY.md` report file (stdout only; add later only if a real consumer needs it).

## Decision Log
- DEC-001: Reuse the existing verifier agents; do not restate the checklist (anti-drift, ID-029 lineage).
- DEC-002: Read-only, no fix loop (mirrors `/kit:review`; safe for the `/goal` loop).
- DEC-003: ADR-0021 records this as additive, not a boundary reversal (PHILOSOPHY mandates verification happen, not that it happen only inside execute).
- DEC-004: Base ref = merge-base with the default branch (C1 fix). No `VERIFY.md` by default (DEC, anti-speculation).
- DEC-005: It is a command, not an agent, per the command-vs-agent rule: a human/loop triggers it; it orchestrates the read-only agents. `/kit:verify vs /kit:review`: verify executes the test levels (AC + wiring); review is static code-judgment (W4).

## Re-validation (2026-05-23, focused delta)
Re-ran the 5 spec-validate lenses against this revision. C1 (base ref) resolved via the
merge-base rule; criterion-#2 resolved by the test-execution framing; W1-W4 folded into
Edge Cases / Failure modes / DEC-005. No new critical issues. Verdict: APPROVED.

## Open questions
(none; criterion #2 and the base-ref blocker are both resolved above)
