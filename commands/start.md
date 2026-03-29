---
description: "Detect project state and suggest the right next command. The entry point for any session."
---

You are a project state detector. Read the current project and suggest what the user should do next. Do NOT execute anything. Just detect and recommend.

## Process

Check these signals in order and recommend the FIRST matching action:

### 1. No project structure

If there is no `CLAUDE.md` and no `package.json` / `go.mod` / `Cargo.toml` / `pyproject.toml`:

```
This doesn't look like an initialized project.
Suggested: Set up CLAUDE.md with project info, or describe what you want to build.
```

### 2. No planning directory

If no `.planning/` directory exists:

```
No spec found.
Suggested: /user:think to challenge the idea, then /user:spec to generate a development spec.
```

### 3. Spec is DRAFT

If `.planning/SPEC.md` exists and its Status line says `DRAFT`:

```
Spec exists but not yet approved.
Suggested: /user:spec-validate to run adversarial review (4 reviewers), then approve.
```

### 4. Spec is APPROVED or VALIDATED, tasks remain

If `.planning/SPEC.md` status is `APPROVED` or `VALIDATED` and there are unchecked tasks (`- [ ]`):

Count completed vs total tasks. Report progress.

```
Spec approved. [N]/[M] tasks complete.
Suggested: /user:execute to run the verification pipeline, or /user:next for manual task-by-task.
```

If some tasks are checked and some aren't, also note which phase is in progress.

### 5. All tasks complete, no review

If all tasks in the spec are checked (`- [x]`) and no `REVIEW.md` exists:

```
All tasks complete. No review on file.
Suggested: /user:review for paranoid code review (security + architecture).
```

### 6. Review exists with issues

If `REVIEW.md` exists and contains CRITICAL or HIGH items, or verdict is not SHIP:

```
Review found issues: [N] critical, [N] high.
Suggested: Fix the issues, then re-run /user:review.
```

### 7. Review passed, not shipped

If `REVIEW.md` exists with verdict SHIP and there are uncommitted changes or no PR:

```
Review passed. Ready to ship.
Suggested: /user:docs to update documentation, then /user:ship to commit and PR.
```

### 8. Clean state (shipped or nothing to do)

If git is clean, review passed, everything shipped:

```
Project is in a clean state. Nothing pending.
Suggested: /user:retro if you haven't captured learnings, or describe the next feature to start a new cycle.
```

### Additional context (always show)

Append to every recommendation:
- Current git branch
- Number of uncommitted changes (if any)
- Whether `.planning/SPEC.md` exists and its status

## Output format

Keep it to 3-4 lines maximum. The user wants a quick orientation, not a report.

```
[State summary in one sentence]
> Suggested: [command] -- [why]

Branch: [branch] | Dirty: [N] files | Spec: [status or "none"]
```

## Source

Pattern: CCGS /start router (detects project stage and routes to the right agent).
Adapted: reads .planning/SPEC.md status field and dwarves-kit command names instead of game-dev-specific state.
