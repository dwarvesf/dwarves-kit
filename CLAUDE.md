# CLAUDE.md — dwarves-kit template

Copy this to your project root and fill in the [placeholders].

---

## Project

[One paragraph: what it is, who it is for, what problem it solves.]

## Tech Stack

| Layer | Choice | Version |
|-------|--------|---------|
| Runtime | [e.g. Node.js] | [e.g. 22 LTS] |
| Framework | [e.g. Next.js] | [e.g. 15] |
| Database | [e.g. PostgreSQL] | [e.g. 16] |
| ORM | [e.g. Drizzle] | [e.g. latest] |

## Commands

```bash
[install command]    # install dependencies
[dev command]        # start dev server
[test command]       # run tests
[lint command]       # run linter
[build command]      # production build
```

## Repository Structure

```
[fill after scaffolding]
```

## Code Quality Rules

Adapted from Trail of Bits + Dwarves conventions:

- No speculative features. Don't add features, flags, or configuration unless actively needed.
- No premature abstraction. Don't create utilities until you've written the same code three times.
- Clarity over cleverness. Prefer explicit, readable code over dense one-liners.
- Justify new dependencies. Each dependency is attack surface and maintenance burden.
- No phantom features. Don't document or validate features that aren't implemented.
- Replace, don't deprecate. When a new implementation replaces an old one, remove the old one entirely.
- Finish the job. Handle edge cases you can see. Clean up what you touched. Flag adjacent broken things.
- Verify at every level. Set up linters, type checkers, and tests as the first step, not an afterthought.
- Bias toward action. Decide and move for easily reversed choices. Ask before committing to interfaces, data models, or architecture.

## Workflow

This project uses dwarves-kit. Available commands:

- `/user:think` - Challenge an idea before writing spec
- `/user:spec` - Generate development spec from intent
- `/user:spec-validate` - Adversarial spec review (4 reviewers)
- `/user:execute` - Autonomous execution (subagent per task, phase checkpoints)
- `/user:next` - Pick next task from spec, load context, manual execution
- `/user:review` - Paranoid code review
- `/user:docs` - Update all docs to match current code
- `/user:ship` - Test, commit, docs, PR
- `/user:retro` - Retrospective: what worked, what hurt, action items

Hooks run automatically:
- SessionStart: context readiness check
- PreToolUse(Bash): blocks rm-rf, push to main, force push
- PreToolUse(Write): spec drift warning for unplanned files
- PostToolUse(Write|Edit): auto-format
- PostToolUse(compact): re-inject critical rules after compaction
- PreCompact: backup session state before compaction
- Stop: anti-rationalization guard
- Notification: desktop alert when Claude needs input
- PermissionRequest: auto-approve read-only operations

## Spec Location

Development specs live in `.planning/`. Read `SPEC.md` before implementing any feature.
