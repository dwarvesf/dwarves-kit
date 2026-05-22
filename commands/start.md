---
description: "Detect project state and suggest the right next command. The entry point for any session."
---

You are a project state detector. Read the current project and suggest what the user should do next. Do NOT execute anything. Just detect and recommend.

## Output mode (read `$ARGUMENTS`)

`$ARGUMENTS` selects how much to render. The detection Process below runs identically in every mode; only the output differs.

- `--brief` -- emit exactly ONE line, max 120 characters: the matched state plus the single suggested next command, then the branch/dirty/spec tail in brackets. Nothing else. Example: `Spec VALIDATED, 3/8 tasks -> /kit:execute. [master | 2 dirty | VALIDATED]`
- (no argument) -- DEFAULT. Emit the standard 3-4 line orientation defined in "Output format" below. This default output is unchanged from prior versions; do not alter it.
- `--full` -- emit the default block, then append the "Full report" extras defined near the end of this file.

## Process

**Resolving the active spec (SPEC-005 dual-mode, the same rule the hooks use, reconciled to ADR-0010):** among `docs/specs/SPEC-*.md`, the active spec is the lone non-SHIPPED/PARKED one; if several are live, the one whose slug matches the current git branch; if zero or multiple match the branch, the state is *ambiguous*, report `spec:ambiguous(...)` and ask which spec, never guess. Legacy `.planning/SPEC.md` is a deprecation fallback used only when `docs/specs/` has no live spec. States 3-8 below operate on that resolved active spec.

Check these signals in order and recommend the FIRST matching action:

### 1. No project structure

If there is no `CLAUDE.md` and no `package.json` / `go.mod` / `Cargo.toml` / `pyproject.toml`:

```
This doesn't look like an initialized project.
Suggested: Set up CLAUDE.md with project info, or describe what you want to build.
```

### 2. No spec directory

If no `docs/specs/` directory exists (and no legacy `.planning/`):

```
No spec found.
Suggested: /kit:think to challenge the idea, then /kit:spec to generate a development spec.
```

### 3. Spec is DRAFT

If `docs/specs/SPEC-NNN-<slug>.md` exists and its Status line says `DRAFT`:

```
Spec exists but not yet approved.
Suggested: /kit:spec-validate to run adversarial review (5 reviewers), then approve.
```

### 4. Spec is APPROVED or VALIDATED, tasks remain

If `docs/specs/SPEC-NNN-<slug>.md` status is `APPROVED` or `VALIDATED` and there are unchecked tasks (`- [ ]`):

Count completed vs total tasks. Report progress.

```
Spec approved. [N]/[M] tasks complete.
Suggested: /kit:execute to run the verification pipeline, or /kit:next for manual task-by-task.
```

If some tasks are checked and some aren't, also note which phase is in progress.

### 5. All tasks complete, no review

If all tasks in the spec are checked (`- [x]`) and no `REVIEW.md` exists:

```
All tasks complete. No review on file.
Suggested: /kit:review for paranoid code review (security + architecture).
```

### 6. Review exists with issues

If `REVIEW.md` exists and contains CRITICAL or HIGH items, or verdict is not SHIP:

```
Review found issues: [N] critical, [N] high.
Suggested: Fix the issues, then re-run /kit:review.
```

### 7. Review passed, not shipped

If `REVIEW.md` exists with verdict SHIP and there are uncommitted changes or no PR:

```
Review passed. Ready to ship.
Suggested: /kit:docs to update documentation, then /kit:ship to commit and PR.
```

### 8. Clean state (shipped or nothing to do)

If git is clean, review passed, everything shipped:

```
Project is in a clean state. Nothing pending.
Suggested: /kit:retro if you haven't captured learnings, or describe the next feature to start a new cycle.
```

### Additional context (always show)

Append to every recommendation:
- Current git branch
- Number of uncommitted changes (if any)
- Whether `docs/specs/SPEC-NNN-<slug>.md` exists and its status
- Active goal drafts in `.claude/goals/` (count, and `slug -> status`), if any

## Output format

Keep it to 3-4 lines maximum. The user wants a quick orientation, not a report.

```
[State summary in one sentence]
> Suggested: [command] -- [why]

Branch: [branch] | Dirty: [N] files | Spec: [status or "none"]
```

## Full report (`--full` only)

When `$ARGUMENTS` is `--full`, append these blocks after the standard output:

1. **Backlog queue (what's left?)** -- render the `_meta/BACKLOG.md` Active queue (the Schema there defines the columns) as `ID | Title | Lane | Status`, skipping shipped/parked rows. Read-only. If the queue is malformed, render what parses, note unparseable rows, and never error out of session start.
2. **Goal drafts** -- list `.claude/goals/*.md` as `slug -> target_spec (status)`. If none, print "Goal drafts: none". Read-only; the filesystem is the source of truth (ADR-0011).
3. **SPEC task checklist** -- parse the active spec (resolved per the dual-mode rule above) for `- [ ]` and `- [x]` lines and list each with its state. If no spec exists, print "SPEC: none".
4. **Hook activity (last 7 days)** -- for each hook log file in the kit's log dir modified in the last 7 days, print `<name>: <N> lines`. Counts ONLY; never echo raw log lines (they can contain command fragments or secret-bearing paths). If no logs, print "Hook logs: none".
5. **Recent commits** -- the output of `git log -5 --oneline`.
6. **Command map by phase**:
   - Think: `/kit:think`, `/kit:design`
   - Spec: `/kit:spec`, `/kit:spec-validate`
   - Orchestrate: `/kit:assign` (backlog item -> goal draft -> lane)
   - Build: `/kit:execute`, `/kit:next`
   - Debug: `/kit:debug` (bug lane)
   - Review: `/kit:review`, `/kit:review-team`
   - Ship: `/kit:docs`, `/kit:ship`
   - Reflect: `/kit:retro`
   - Utility: `/kit:start`, `/kit:kit-health`

## Source

Pattern: CCGS /start router (detects project stage and routes to the right agent).
Adapted: reads docs/specs/SPEC-NNN-<slug>.md status field and dwarves-kit command names instead of game-dev-specific state.

Tiered output (`--brief` / default / `--full`): GSD v1.43-rc2 `gsd-help --brief|--full|<topic>` pattern. Adapted to `--brief` + default + `--full` only, no `<topic>` mode (DEC-002: the kit's state space is small enough that section-level help is overkill).
