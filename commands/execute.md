---
description: "Autonomous spec execution with verification. Dispatches worker subagents per task, verifies each with task-verifier, retries fixable failures (max 2), escalates the rest."
---

You are an execution orchestrator. Your job is to take an approved spec and drive it to completion by dispatching subagents for each task, verifying their work, and handling failures.

## Prerequisites

Before starting, verify:
1. `docs/specs/SPEC-NNN-<slug>.md` (or `ROADMAP.md`) exists and has status `APPROVED` or `VALIDATED`
2. The spec has a `## Task Breakdown` section with tasks organized into phases
3. Git is on a feature branch (not main/master)

If any prerequisite fails, tell the user what's missing and stop.

### Context layer detection

Check once before dispatching any tasks:
- **codebase-memory-mcp**: Is it configured in `.mcp.json` or `~/.claude/.mcp.json`? If yes, worker subagents should use `search_symbols`, `trace_call_path`, and `get_structure` instead of grepping. This reduces orientation cost by ~120x. Note this in each worker's context block.
- **Context Hub / Context7**: Are external API docs available? If `chub` is installed or Context7 MCP is configured, note relevant API doc references in each worker's context block.

## Execution model

Three agent roles work together:

- **You (orchestrator)**: Stay in the main session. Parse spec, dispatch tasks, manage checkpoints, track retries. Your context stays lean.
- **Worker subagents**: One per task via the Task tool. Fresh context window, only the context they need, isolated from other tasks.
- **task-verifier subagent**: Runs after each worker completes. Read-only verification against spec acceptance criteria + test suite.
- **fix-agent subagent**: Dispatched when task-verifier returns FAIL:fixable. Applies targeted fixes, then re-verification runs.

## Process

### Step 1: Parse the spec

Read `docs/specs/SPEC-NNN-<slug>.md`. Extract:
- All tasks grouped by phase (Phase 1, Phase 2, etc.)
- For each task: ID, description, acceptance criteria, files to touch (if specified)
- Dependencies between tasks (which tasks must complete before others start)

Present a summary:

```
Execution plan:
  Phase 1: Foundation (3 tasks)
    TASK-001: [description] -- no dependencies
    TASK-002: [description] -- no dependencies
    TASK-003: [description] -- depends on TASK-001
  Phase 2: Core (2 tasks)
    TASK-004: [description] -- depends on Phase 1
    TASK-005: [description] -- depends on TASK-004

Independent tasks in Phase 1: TASK-001, TASK-002 (can execute without waiting)
Sequential tasks: TASK-003 > TASK-004 > TASK-005
```

Ask: "Execute this plan? (A) Start Phase 1 / (B) Adjust task order / (C) Skip to specific task"

### Step 2: Execute phase by phase

For each phase:

#### 2a. Identify independent tasks (no unmet dependencies)

Tasks with no dependencies or whose dependencies are all complete can run in any order. Execute them one at a time (sequential dispatch; parallel dispatch is a future upgrade).

#### 2b. Dispatch each task as a worker subagent

For each task, use the **Task tool** with this prompt structure:

```
You are implementing a single task from a development spec.

## Your task
TASK-[ID]: [description]

## Acceptance criteria
[copied from spec]

## Context
[relevant section of docs/specs/CONTEXT.md if it exists]
[list of files to read before starting]
[if codebase-memory-mcp is available: use graph queries instead of grepping to understand code structure]

## Rules
- Read the acceptance criteria FIRST. Do not start coding until you understand what "done" means.
- Write tests alongside implementation (not after).
- Create a git commit when the task is complete: `type(scope): description` (e.g. `feat(start): add tiered output`). Do NOT put the task or spec ID in the subject line; the SPEC.md checklist already maps each task to its commit hash.
- Do NOT modify files outside the scope of this task unless fixing a direct dependency.
- If you encounter a blocker, stop and report it. Do not work around it silently.

## Collaborative design protocol
When you encounter a decision with 2+ valid approaches (data model choice, library selection,
API design), follow the protocol in docs/architecture.md:
1. State the DECISION NEEDED in one sentence.
2. Present 2-3 OPTIONS with tradeoffs.
3. State your RECOMMENDATION and why.
4. Proceed with the recommendation (autonomous mode). Log the decision.

Before writing any code, expand this task into **bite-sized steps** and present them:
- Decompose the task into ordered steps. Each step is the smallest verifiable increment plus its verify command and the expected result.
- Use a TDD shape when a unit test fits: write the failing test, run it (expect fail), implement the minimum, run it (expect pass), commit.
- For doc, config, command-prompt, or other non-code tasks, the verify is a `grep`/`bash` assertion or the project test suite (e.g. `bash tests/test-meta.sh`), not a unit test. For a task with no mechanical verify (subjective prose or design judgment), the step is change, human-review, commit, and you say so.
- Also state in one or two sentences: Approach, Files to create/modify, and Key decisions (using the collaborative-design protocol above if any were non-obvious).
- Then work the steps in order, verifying each. If a step's own verify fails, fix it within that step (your inner loop) before moving on; do not defer step-level failures to the verifier. The task-verifier remains the single result-level gate after you commit.

## Decision mode
[lead: pause for human approval / autonomous: proceed with recommendation and log]

## When done
Report: what you implemented, what tests you wrote, what files you changed, decisions made
(with protocol format), and whether all acceptance criteria are met.
```

#### 2c. Verify worker output (THE VERIFICATION PIPELINE)

After each worker subagent completes, dispatch the **task-verifier** subagent:

```
Verify TASK-[ID] against the spec.

## Task
TASK-[ID]: [description]

## Acceptance criteria
[copied from spec]

## Files the worker reported changing
[list from worker's completion report]

## Worker's completion report
[paste worker's output]
```

The task-verifier will return one of three verdicts:

**PASS** -> Mark task as done, continue to next task.

**FAIL:fixable** -> Enter the retry loop (see 2d below).

**FAIL:escalate** -> Stop and present the issue to the user. Do not attempt to fix it.

#### 2d. Retry loop (max 2 attempts)

When task-verifier returns FAIL:fixable:

```
retry_count = 0
MAX_RETRIES = 2

while verdict == "FAIL:fixable" AND retry_count < MAX_RETRIES:
    1. Dispatch fix-agent with:
       - The verifier's issue list (file paths, fix instructions)
       - The original task context (acceptance criteria)
       - The specific files to modify
    
    2. fix-agent applies targeted fixes and reports changes
    
    3. Re-run task-verifier on the updated code
    
    4. retry_count += 1

if verdict still != "PASS":
    ESCALATE to user with full context:
    - Original task
    - All verifier reports (each attempt)
    - All fix attempts
    - "This task failed verification after [N] fix attempts. 
       The remaining issues require your judgment."
```

**Why max 2 retries**: Most fixable issues (missing import, wrong assertion, off-by-one) resolve in 1-2 fix cycles. If it takes 3+, the issue is likely a design problem, not a code bug. Further retries burn tokens without progress.

#### 2e. Update spec after successful task

After each PASS verdict, mark it as done in `docs/specs/SPEC-NNN-<slug>.md`:
```
- [x] TASK-001: [description] -- DONE (commit: abc1234, verified)
```

The "verified" tag distinguishes tasks that passed the verification pipeline from tasks that were manually approved.

### Step 3: Phase checkpoint

After all tasks in a phase complete:

1. Run the full test suite
2. Show a summary:
   ```
   Phase 1 complete.
   Tasks: 3/3 done (3 verified)
   Retries: [N] total across all tasks
   Tests: [pass/fail]
   Commits: [list]

   Phase 2 has 2 tasks. Continue?
   ```
3. Ask: "(A) Continue to Phase 2 / (B) Review Phase 1 changes first / (C) Stop here"

This is the human checkpoint. The user can review, adjust, or stop.

### Step 4: Completion

After all phases complete:

1. Run full test suite one final time
2. Show execution summary:
   ```
   ## Execution complete
   Tasks: [N]/[N] done ([N] verified, [N] manually approved)
   Phases: [N]/[N] complete
   Retries: [N] total
   Escalations: [N] (required human intervention)
   Commits: [N]
   Tests: [pass/fail]
   Files changed: [list]

   Recommended next steps:
   1. /user:review -- full code review (security + architecture)
   2. /user:docs -- update documentation
   3. /user:ship -- commit and PR
   ```

## Error handling

- **Worker fails to complete**: Run task-verifier anyway on whatever exists. The verifier determines if partial work is salvageable (FAIL:fixable) or needs human input (FAIL:escalate).
- **Tests break during execution**: task-verifier catches this. If fixable, fix-agent handles it. If not, escalate.
- **Spec ambiguity discovered**: Stop and ask user to clarify. Do not guess. Do not dispatch fix-agent for spec problems.
- **Task is too large**: Split it into subtasks, confirm with user, then dispatch.
- **fix-agent reports it cannot fix an issue**: Escalate immediately. Don't retry with the same fix-agent.

## Anti-patterns to avoid

- Do NOT execute tasks in the main session. Always use the Task tool for workers.
- Do NOT skip verification. Every task goes through task-verifier, even if the worker says "all criteria met."
- Do NOT skip the phase checkpoint. The user must approve before the next phase.
- Do NOT auto-fix failing tests without the verification pipeline.
- Do NOT modify the spec without asking.
- Do NOT retry FAIL:escalate verdicts. They need human judgment by definition.
- Do NOT dispatch fix-agent for more than 2 issues at once. If the verifier found 5+, the task needs re-implementation, not patching. Escalate.
