# CLAUDE.md

Project instructions for working on **dwarves-kit itself** (the kit's own repo). If you are looking for the template to copy into a NEW project that consumes the kit, see `examples/hello-spec/CLAUDE.md`.

## Project

dwarves-kit is a Claude Code workflow toolkit: 14 hooks + 19 commands + 11 agents + 1 skill. Spec-driven lifecycle (`/user:think` → `/user:spec` → `/user:execute` → `/user:review` → `/user:ship` → `/user:retro`) with a verification pipeline (worker → task-verifier → fix-agent retry, max 2). Distributed as a Claude Code plugin and as a bash installer. Maintainer: Han at Dwarves Foundation.

For component fit and data flow, read `docs/architecture.md`. For operator detail per command, read `MANUAL.md`. For hook misbehavior, read `RUNBOOK.md`. Design rejection rules live in `docs/PHILOSOPHY.md` and are load-bearing.

## Tech stack

| Layer | Choice |
|---|---|
| Hook runtime | bash + jq |
| Distribution | Claude Code plugin (`.claude-plugin/`) + bash installer (`install.sh` + `settings.json`) |
| Tests | bash (`tests/test-hooks.sh` for behavior, `tests/test-meta.sh` for structural integrity) |
| CI | GitHub Actions, macOS + Ubuntu matrix |

The kit deliberately uses no compiled binaries and no Node/Python in hooks (carve-out: statusline may use Node per PHILOSOPHY). Every script must be readable in 30 seconds.

## Commands (for dev on the kit)

```bash
bash tests/test-hooks.sh      # 92 hook behavior tests
bash tests/test-meta.sh       # 212 structural integrity tests
bash install.sh               # install into ~/.claude/ (idempotent)
bash install.sh --uninstall   # clean removal
DWARVES_KIT_DEBUG=1 ...       # verbose hook logging on stderr
```

The kit ships its own slash commands (`/user:start` ... `/user:retro` ... `/user:kit-health`). Working on the kit means dogfooding: write a spec for your change, dispatch the verification pipeline, ship through `/user:ship`. The kit's commands are listed in `MANUAL.md`; do not duplicate the inventory here.

## Repository structure

See README.md "Project structure" section (canonical) and `docs/architecture.md` (component fit). Do not maintain a third copy here.

## Code quality rules

These are the kit's own dev rules. They apply to PRs into dwarves-kit. The same rules ship as the template for downstream projects.

- No speculative features. Add features only when actively needed.
- No premature abstraction. Don't create utilities until the same code appears three times.
- Clarity over cleverness. Explicit, readable code over dense one-liners.
- Justify new dependencies. Each one is attack surface and maintenance burden.
- No phantom features. Don't document or validate features that aren't implemented.
- Replace, don't deprecate. When a new implementation replaces an old one, remove the old one entirely.
- Finish the job. Handle edge cases you can see. Clean up what you touched. Flag adjacent broken things.
- Verify at every level. Linters, type checkers, tests are first-class, not afterthoughts.
- Bias toward action. Decide and move for easily reversed choices. Ask before committing to interfaces, data models, or architecture.

## Spec location

For the kit's own work, specs live at `docs/specs/SPEC-NNN-<slug>.md` from draft to ship. The file's `Status:` header (DRAFT / VALIDATED / SHIPPED) tracks state in place; no migration step. Matches ops-toolkit `tools/tide/docs/specs/` shape.

The kit unified the spec location onto `docs/specs/SPEC-NNN-<slug>.md` for both itself and downstream projects (ADR-0010, supersedes ADR-0002). The hooks keep a bounded `.planning/` deprecation fallback for one minor version, then it is removed. See ADR-0010.

## Workflow

The kit eats its own dog food. The full lifecycle, the risk-tier lanes, and the gate at each phase boundary live in one place: the [`WORKFLOW.md`](WORKFLOW.md) contract. Read it after this file. For kit-on-kit work, spec drafts live in `docs/specs/` (see Spec location above), not `.planning/`.

`/user:kit-health` is the maintainer-only self-assessment against PHILOSOPHY.md. Run it before tagging.

Hooks fire on Claude Code events automatically; do not call them manually. Debug with `DWARVES_KIT_DEBUG=1`.

## Template for downstream projects

If you are scaffolding a new project that will use dwarves-kit, do not copy THIS file. Use `examples/hello-spec/CLAUDE.md` as the template; it shows the full shape (Project, Tech Stack, Commands, Repository Structure, Code Quality Rules, Workflow, Spec Location) with realistic placeholder content.
