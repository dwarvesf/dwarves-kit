# CLAUDE.md

Project instructions for working on **dwarves-kit itself** (the kit's own repo). If you are onboarding a NEW project onto the kit, run `/kit:adopt` there (see "Template for downstream projects" below).

## Project

dwarves-kit is a Claude Code workflow toolkit: hooks, slash commands, subagents, and skills. Spec-driven lifecycle (`/kit:think` → `/kit:spec` → `/kit:execute` → `/kit:review` → `/kit:ship` → `/kit:retro`) with a verification pipeline (one builder → end verifiers → fix-agent retry, max 2). Distributed as a Claude Code plugin and as a bash installer. Maintainer: Han at Dwarves Foundation.

For component fit and data flow, read `docs/reference/architecture.md`. For operator detail per command, how to drive the kit from natural language, and how to recover from hook misbehavior, read `docs/MANUAL.md`. Design rejection rules live in `docs/reference/PHILOSOPHY.md` and are load-bearing.

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
bash tests/run-all.sh         # the dev loop: diff-scoped suites + the always-on lints (about 1-2 min)
bash tests/test-hooks.sh      # hook behavior tests
bash tests/test-meta.sh       # structural integrity tests
bash install.sh               # install into ~/.claude/ (idempotent)
bash install.sh --uninstall   # clean removal
DWARVES_KIT_DEBUG=1 ...       # verbose hook logging on stderr
```

The kit ships its own slash commands (`/kit:start` ... `/kit:retro` ... `/kit:kit-health`). Working on the kit means dogfooding: write a spec for your change, dispatch the verification pipeline, ship through `/kit:ship`. The kit's commands are listed in `docs/MANUAL.md`; do not duplicate the inventory here.

## Repository structure

See `docs/MANUAL.md` "Project structure" section (canonical) and `docs/reference/architecture.md` (component fit). Do not maintain a third copy here.

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

The kit unified the spec location onto `docs/specs/SPEC-NNN-<slug>.md` for both itself and downstream projects (ADR-0010, supersedes ADR-0002). `docs/specs/` is now the sole location; the legacy planning-dir fallback has been removed. See ADR-0010.

## Workflow

The operate-contract (read-order, task loop, done-definition, the "Pause if" list) is canonical in [`AGENTS.md`](AGENTS.md), the tool-agnostic front door. Read it first; this file is the Claude-Code layer on top of it. Do not restate the operate-contract here; point at `AGENTS.md`.

The kit eats its own dog food. The full lifecycle, the risk-tier lanes, and the gate at each phase boundary live in one place: the [`docs/WORKFLOW.md`](docs/WORKFLOW.md) contract. Read it after `AGENTS.md` and this file. For kit-on-kit work, spec drafts live in `docs/specs/` (see Spec location above).

`/kit:kit-health` is the maintainer-only self-assessment against PHILOSOPHY.md. Run it before tagging.

Hooks fire on Claude Code events automatically; do not call them manually. Debug with `DWARVES_KIT_DEBUG=1`.

## Template for downstream projects

To onboard a new project onto the kit, do not copy THIS file. Run `/kit:adopt` in the target repo (or `/kit:onboard` for the guided first run): it writes a small `AGENTS.md` pointer, a `CLAUDE.md` loader, a WORKFLOW pointer, and the proof marker, never over a file the repo already has. `examples/hello-spec/` is an illustration of what an adopted repo looks like, not the onboarding path.
