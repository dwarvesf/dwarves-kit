# Spec: Bite-sized step expansion in /user:execute (the kit's plan-artifact answer)

Generated: 2026-05-21
Status: DRAFT
Source: dogfood comparison 2026-05-21 (kit pipeline vs superpowers brainstorming + writing-plans on SPEC-016). The comparison found superpowers' writing-plans produces a more execution-ready, bite-sized plan than the kit's coarser spec task-breakdown, and the kit's target persona ("solo lead handing off to contractors with questionable taste", README) is exactly who that granularity serves. Maintainer decision 2026-05-21: fold the granularity into `/user:execute` rather than add a `/user:plan` command.
Depends on: `commands/execute.md` (the worker-dispatch loop this enhances) + `agents/task-verifier.md` (the runtime gate, unchanged).
Relates to: SPEC-016 (the spec whose dogfood surfaced this gap). Refines the kit's "coarse plan + strong runtime" bet by adding plan-time discipline at the worker, not a second artifact.

## Problem

The kit bets on **runtime enforcement** (worker -> task-verifier -> fix-agent, max 2) over **plan-time detail**: `/user:spec` produces a task-level breakdown with acceptance criteria, and `/user:execute`'s worker gets a 3-bullet "implementation plan" sub-step (Approach, Files, Key decisions) before it codes. Superpowers' `writing-plans` bets the other way: a separate plan file decomposes every task into bite-sized steps (write failing test -> run it -> implement -> run -> commit) with exact content.

The 2026-05-21 dogfood ran both on SPEC-016 and the honest finding was: the writing-plans output was materially more execution-ready, and the gap matters most for the kit's stated persona, a contractor who decomposes coarse tasks themselves and is exactly where taste failures happen. The verifier catches a bad result *after* the fact; bite-sized steps prevent it *before*.

But a standalone `/user:plan` command (the literal superpowers shape) would be the wrong fix for the kit: it duplicates writing-plans, runs a second belt alongside the verifier, adds a 19th command, and would write a separate plan artifact the kit's ephemeral worker does not need. The kit-consonant fix is to **upgrade the worker's existing plan sub-step** to bite-sized rigor and have the worker work the steps in order, so the granularity lives where the work happens and the orchestrator stays lean.

One adaptation is load-bearing: `writing-plans` assumes code + a unit-test runner (pytest). The kit's own tasks are mostly **markdown, bash, JSON, and command-prompt edits** (see SPEC-016: command files, doc edits, count strings). A pytest-shaped "write the failing test" step does not fit a doc task. So the step shape must generalize to **smallest verifiable increment -> verify -> commit**, where "verify" is a test for code, a `grep`/`bash test` for a doc/config/command change, and the kit's existing test suites where they apply.

## Decision: chosen version

**Upgrade the `/user:execute` worker-dispatch prompt (Step 2b) so each worker, before coding, expands its task into bite-sized steps following "smallest verifiable increment -> verify -> commit" (TDD when a unit test fits; grep/bash-verify for doc/config/command tasks), then works the steps in order. The expansion happens worker-side (the orchestrator stays lean), produces no new persistent artifact (the worker presents the step plan in its output; lead-mode pauses for approval, autonomous logs and proceeds), adds no new command and no new agent, and leaves the task-verifier -> fix-agent runtime gate unchanged. This is plan-time discipline added before the existing runtime gate, not a replacement for it.**

### What changes (and what does not)

```
BEFORE:  worker gets task + AC
         -> "present implementation plan: Approach, Files, Key decisions" (3 bullets)
         -> codes -> commits -> task-verifier (runtime gate)

AFTER:   worker gets task + AC
         -> expand into bite-sized steps: each step = smallest verifiable increment,
            its verify command, expected result; TDD shape for code, grep/bash for docs
         -> [lead: pause for approval | autonomous: log + proceed]
         -> work the steps in order, verifying each
         -> commit -> task-verifier (runtime gate, UNCHANGED)
```

- **Worker-side, not orchestrator-side.** The orchestrator's Step 1 summary stays task-level (coarse); the bite-sized granularity lives in the worker. Rationale: the kit's execution model keeps the orchestrator context lean (execute.md "Your context stays lean"); expanding all tasks upfront in the orchestrator would bloat it.
- **No new artifact.** The worker presents its step plan in its completion-protocol output, the same place it already presents Approach/Files/Decisions. No per-task plan file. Rationale: the worker is an ephemeral Task subagent; a persistent plan file is overhead the verifier already substitutes for at the result level.
- **Generalized step shape.** "Smallest verifiable increment -> verify -> commit." Verify = a unit test (code), a `grep`/`bash` assertion (doc/config/command), or the project's test suite (`bash tests/test-meta.sh` etc.) where it applies. Rationale: the kit's own tasks are mostly non-pytest; a code-only TDD shape would not fit them (the literal writing-plans assumption).
- **Runtime gate unchanged.** task-verifier and the max-2 fix loop are untouched. Step expansion is added discipline *before* the gate, not a second gate.
- **No new command, no new agent.** It is a prompt enhancement to `commands/execute.md` Step 2b. Rationale: "Synthesize, don't originate" (writing-plans is the source) + "no premature abstraction".

### Tradeoff table

| Fork | CHOSEN | Rejected alt |
|---|---|---|
| Where | fold into `/user:execute` worker prompt | a `/user:plan` command (superpowers shape): +1 command, duplicates writing-plans, second belt vs the verifier |
| Who expands | worker-side (per task, before coding) | orchestrator-side (expand all upfront): bloats the lean orchestrator |
| Artifact | none (in the worker's output) | a per-task plan file: overhead for an ephemeral worker the verifier already backstops |
| Step shape | generalized "increment -> verify -> commit" | literal pytest-TDD: does not fit the kit's markdown/bash/JSON tasks |
| Runtime gate | unchanged | weaken the verifier now that there is a plan: loses the kit's moat |

### NO-list check (PHILOSOPHY gates)

One-sentence description: *"Each `/user:execute` worker expands its task into bite-sized verify-each-step increments before coding, so contractors get writing-plans-grade granularity without a second command or artifact."*

| Gate | Compliance |
|---|---|
| Guardrails over guidance | OK: no new hard gate; the existing verifier stays the gate; this is worker guidance |
| Synthesize, don't originate | OK: the bite-sized step rigor is `superpowers:writing-plans`; the generalization to non-code verify is the kit's adaptation (labeled) |
| Detect, don't dictate | OK: lead-mode pauses, autonomous proceeds; no mid-loop block added |
| Bash over binaries | OK: a prompt edit; "verify" steps are tests/grep/bash, no new binary |
| Serves 2+ phases | OK: serves the Spec->Build seam (reads the spec's tasks/AC, drives Build) |
| One sentence describable | OK (above) |
| No speculative config | OK: no env var/flag; enhances an existing command with a real, dogfood-evidenced need |
| No premature abstraction | OK: no new command/agent; a prompt sub-step upgrade |

## Solution

| Task | Files | Type | Depends on |
|---|---|---|---|
| TASK-1 | `commands/execute.md` (Step 2b worker prompt: bite-sized step expansion + generalized verify shape + lead/autonomous handling) | Command enhancement | - |
| TASK-2 | `tests/test-meta.sh` (assert execute.md carries the step-expansion marker) | Test | TASK-1 |
| TASK-3 | `MANUAL.md` (`/user:execute` note) + `CHANGELOG.md` | Doc + hygiene | TASK-1 |

### Task breakdown

**Phase 1: The enhancement**
- [ ] **TASK-1: `commands/execute.md` Step 2b.** Replace the worker prompt's "Before writing any code, also present your implementation plan: Approach / Files / Key decisions" block with a bite-sized step-expansion block: the worker decomposes the task into ordered steps, each step = the smallest verifiable increment + its verify command + expected result; TDD shape (write failing test -> run -> implement -> run -> commit) when a unit test fits, grep/bash-assertion or the project test suite for doc/config/command tasks; then works the steps in order, verifying each. Keep the existing collaborative-design protocol and decision-mode (lead pauses on the step plan; autonomous logs + proceeds). Do not touch the task-verifier / fix-agent sections.
  - Acceptance: Step 2b requires an ordered bite-sized step plan before coding; the step shape is "increment -> verify -> commit" and explicitly generalizes beyond unit tests to grep/bash/test-suite verification; lead vs autonomous handling preserved; the verification pipeline sections (2c-2d) are unchanged.

**Phase 2: Verify + hygiene**
- [ ] **TASK-2: `tests/test-meta.sh` assertion.** Assert `commands/execute.md` contains the step-expansion marker (a pinned heading or phrase, e.g. `bite-sized steps`), so the discipline cannot silently regress. Assert presence of the marker, not exact prose (avoid brittle coupling).
  - Acceptance: a new test-meta assertion passes; `bash tests/test-meta.sh` green; `bash tests/test-hooks.sh` unchanged (no hook touched).
- [ ] **TASK-3: MANUAL note + CHANGELOG.** Add a sentence to the `MANUAL.md` `/user:execute` section noting that workers expand each task into bite-sized verify-each-step increments before coding. CHANGELOG entry. No command count change (this adds no command).
  - Acceptance: MANUAL `/user:execute` mentions step expansion; CHANGELOG entry; command count unchanged.

## Acceptance Criteria (global)
- [ ] `/user:execute` Step 2b requires each worker to expand its task into ordered bite-sized steps before coding
- [ ] The step shape is "smallest verifiable increment -> verify -> commit" and generalizes beyond pytest-TDD to grep/bash/test-suite verification for the kit's non-code tasks
- [ ] Expansion is worker-side; the orchestrator's plan summary stays task-level; no new persistent plan artifact
- [ ] lead-mode pauses on the step plan, autonomous logs + proceeds; no new hard gate
- [ ] task-verifier + fix-agent (max 2) runtime gate is unchanged
- [ ] No new command, no new agent; `commands/execute.md` modified in place
- [ ] `tests/test-meta.sh` asserts the step-expansion marker and passes; `tests/test-hooks.sh` unchanged
- [ ] MANUAL note + CHANGELOG entry; command count unchanged
- [ ] Consistent with writing-plans (the source) and the kit's lean-orchestrator execution model

## Known limitations
1. **The bite-sized rigor is worker-self-discipline, not a hard gate.** A worker can under-decompose; the task-verifier still backstops the *result*, but the *step quality* is not separately enforced (consistent with the kit's "guardrails for safety only" stance). Promotion to a checked artifact is deferred behind a PHILOSOPHY §5 drift signal.
2. **The generalized verify shape is the kit's adaptation, not the literal writing-plans pattern** (which assumes code + pytest). Labeled here, not hidden.
3. **No measurement yet that step expansion reduces escalations.** The dogfood is one comparison; whether the added plan-time discipline lowers verifier retries on a real contractor handoff is unproven (the §5 bar for any further promotion).

## Edge Cases
1. **A doc-only or config-only task** (most kit tasks): the worker uses grep/bash/test-suite verify steps, not "write a failing test". The generalized shape covers this.
2. **A task too small to decompose** (a one-line change): the step plan is one or two steps (change -> verify -> commit); do not pad it. Bite-sized does not mean artificially many.
3. **A task too large** (already handled by execute.md "Task is too large -> split"): step expansion makes oversize tasks obvious earlier; the worker reports the task needs splitting rather than producing a 20-step plan.
4. **Autonomous mode**: the worker logs the step plan and proceeds without pausing; the plan still appears in its output for the phase-checkpoint review.
5. **Lead mode**: the worker pauses after presenting the step plan for human approval before coding, reusing the existing decision-mode mechanism.

## Out of Scope
- A `/user:plan` command or any separate plan file (rejected: duplicates writing-plans, second belt vs the verifier).
- Changing the task-verifier / fix-agent / retry-cap behavior.
- Orchestrator-side upfront expansion of all tasks (rejected: bloats the lean orchestrator).
- Enforcing step quality with a new gate or agent (deferred behind a §5 drift signal).
- Parallel worker dispatch (still a separate future upgrade per execute.md).

## Decision Log
- **DEC-001**: Fold into `/user:execute`, do not add `/user:plan`. The kit-consonant fix upgrades the worker's existing plan sub-step; a standalone command duplicates writing-plans and runs a second belt alongside the verifier. (Maintainer decision 2026-05-21.)
- **DEC-002**: Worker-side expansion, not orchestrator-side. Keeps the orchestrator context lean (execute.md execution model).
- **DEC-003**: No new persistent plan artifact. The worker presents the step plan in its completion output; the verifier backstops the result. The ephemeral worker does not need a plan file.
- **DEC-004**: Generalized step shape "increment -> verify -> commit", not literal pytest-TDD. The kit's own tasks are mostly markdown/bash/JSON; a code-only shape would not fit. This is the kit's adaptation of the writing-plans pattern.
- **DEC-005**: The task-verifier runtime gate is unchanged. Step expansion is plan-time discipline added before the gate, not a replacement; the verifier stays the kit's moat.
- **DEC-006**: No new command, no new agent (prompt enhancement only). "Synthesize, don't originate" + "no premature abstraction".

## Source citations
- Bite-sized step granularity + no-placeholders rigor: `superpowers:writing-plans` (the dogfood comparison source).
- The worker-dispatch loop + lean-orchestrator model this enhances: `commands/execute.md` (Step 2b, the execution model).
- The runtime gate left unchanged: `agents/task-verifier.md` + `agents/fix-agent.md`.
- The dogfood that surfaced the gap: this session's kit-vs-superpowers comparison on `docs/specs/SPEC-016-critique-and-test-lanes.md`.
- The persona this serves: README ("a solo technical lead handing off implementation to contractors").
