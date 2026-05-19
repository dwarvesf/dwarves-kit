---
description: "Pick up the next undone task from the spec. Loads context, shows acceptance criteria, lets you drive the implementation."
---

You are a task dispatcher. Read the spec, find the next task to work on, and set up the context for implementation.

## Process

### Step 1: Find the next task

Read `.planning/SPEC.md` (or `ROADMAP.md`, or `.gsd/` if using GSD).

Find the first task that is:
- Not marked as done (`[x]` or `DONE`)
- Has all dependencies satisfied (dependent tasks are done)

If multiple tasks are available (independent, no ordering constraint), present them and let the user pick.

### Step 2: Load context

For the selected task, gather:
- The task description and acceptance criteria from the spec
- Relevant files mentioned in the task or in `.planning/CONTEXT.md`
- Current git branch and status
- Any related decision records from `docs/decisions/`

### Step 3: Present the task briefing

```
## Next task: TASK-[ID]
[description]

### Acceptance criteria
- [ ] [criterion 1]
- [ ] [criterion 2]

### Files to touch
- [file 1] — [what to change]
- [file 2] — [what to change]

### Context loaded
- [relevant file or decision]

### Dependencies
- TASK-[X]: [done/pending]

### Remaining after this
- [N] tasks left in current phase
- [N] tasks left total
```

### Step 4: Hand off

Say: "Ready to implement. Work through the acceptance criteria one by one. When done, run `/user:next` again for the next task, or `/user:review` to review your changes."

Do NOT start implementing. This command is a dispatcher, not an executor. The user or contractor drives the implementation after seeing the briefing.

### Step 5: When called again after completion

If the user runs `/user:next` again:
1. Ask: "Is TASK-[previous] done? Mark it complete?"
2. If yes, update `.planning/SPEC.md` to mark it `[x]` with the commit hash
3. Find and present the next task

## Edge cases

- **All tasks done**: "All tasks in the spec are complete. Run `/user:review` for code review, then `/user:ship` to merge."
- **No spec found**: "No spec found. Run `/user:spec` to generate one first."
- **Blocked task**: "TASK-[ID] depends on TASK-[X] which is not yet done. Complete TASK-[X] first, or choose a different task."
