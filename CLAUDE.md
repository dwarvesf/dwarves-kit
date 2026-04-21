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

- `/user:start` - Detect project state, suggest next command (entry point)
- `/user:think` - Challenge an idea before writing spec
- `/user:spec` - Generate development spec from intent
- `/user:spec-validate` - Adversarial spec review (4 reviewers)
- `/user:execute` - Autonomous execution with verification pipeline (worker > verifier > fix-agent retry loop)
- `/user:next` - Pick next task from spec, load context, manual execution
- `/user:review` - Paranoid code review (single-pass, all lenses)
- `/user:review-team` - Parallel 3-lens review (security + architecture + test-coverage)
- `/user:docs` - Update all docs to match current code
- `/user:ship` - Review gate, test, version bump, changelog, commit, docs, PR
- `/user:retro` - Retrospective: what worked, what hurt, action items
- `/user:kit-health` - Self-assessment: checks kit against its own philosophy

Subagents (dispatched automatically by commands):
- `task-verifier` - Read-only verification of each task against spec acceptance criteria + tests
- `fix-agent` - Targeted fixes when task-verifier returns FAIL:fixable (max 2 retries)
- `security-auditor` - Deep security review, dispatched by /review-team
- `reviewer` - Focused code reviewer with configurable lens (security/architecture/test-coverage)
- `responding-to-review` - Responds to review findings with verify-before-implement, no performative agreement, YAGNI check
- `research-stack` - Maps technology stack for brownfield /spec
- `research-features` - Maps existing features related to target area
- `research-architecture` - Maps architecture patterns and conventions
- `research-pitfalls` - Finds landmines before implementation begins

Hooks run automatically:
- SessionStart: context readiness check + command suggestion
- PreToolUse(Bash): blocks rm-rf, push to main, force push
- PreToolUse(Write): spec drift warning for unplanned files
- PostToolUse(Write|Edit): auto-format (local formatters only, no network)
- PostToolUse(compact): re-inject critical rules after compaction
- PreCompact: backup session state before compaction
- Stop: anti-rationalization guard (5 unambiguous patterns)
- Stop: slop-cleaner (flags bloated code, nudge only)
- Stop: session-state-save (persists progress to .claude/session-state/)
- SubagentStop: session-state-save (catches worker/verifier completion)
- Notification: desktop alert when Claude needs input
- PermissionRequest: auto-approve read-only operations (pipe-safe)
- StatusLine: model, branch, context %, cost, thinking mode

Debug mode: set DWARVES_KIT_DEBUG=1 for verbose hook logging.

## Spec Location

Development specs live in `.planning/`. Read `SPEC.md` before implementing any feature.
