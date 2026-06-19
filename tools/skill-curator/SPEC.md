# cc-self-improve , spec index

The skill half of the Hermes self-improvement loop for Claude Code. This file is the navigator; the
behaviour contract lives in `docs/specs/`, the why in `docs/decisions/`.

## Documents

| Doc | Purpose |
|---|---|
| [README.md](./README.md) | What it is + install + quick reference |
| [MANUAL.md](./MANUAL.md) | Daily-use guide (CLI surfaces, config knobs, operator flow) |
| [RUNBOOK.md](./RUNBOOK.md) | Incident triage (cost, runaway, stuck lock, settings.json, promote refusals, curator) |
| [docs/architecture.md](./docs/architecture.md) | Topology, trust boundary, data flow, component + state map |
| [docs/specs/SPEC-103-cc-self-improve.md](./docs/specs/SPEC-103-cc-self-improve.md) | The umbrella behaviour contract (Phases A/B/C, DEC-001..008) |
| [docs/specs/CONTEXT.md](./docs/specs/CONTEXT.md) | Implementation context (stack, conventions, key files) |
| [docs/hermes-prompt-patterns.md](./docs/hermes-prompt-patterns.md) | The Hermes prompts the reviewer/curator prompts were built from |
| [docs/proof-of-done.md](./docs/proof-of-done.md) | The proof-of-done index (Features A/B/C, run-tables + negative controls) |
| [docs/decisions/](./docs/decisions/) | ADRs 0001-0009 (why the load-bearing choices were made) |
| [docs/implementation-notes/](./docs/implementation-notes/) | Per-sub-goal deltas from the spec during the build |

## Features (the three phases, all shipped)

| Phase | Feature | Trigger | Contract |
|---|---|---|---|
| A | skill-draft reviewer (no-write `claude -p` + trusted staging + cost ledger) | PreCompact / SessionEnd hook (async, detached) | SPEC-103 TASK-001..005 |
| B | promote gate (`/skill-review`) + SessionStart surfacing + idempotent install | on demand + SessionStart | SPEC-103 TASK-006..010 |
| C | skill-library curator (`cc-improve curate`, git-mv archive, never delete) | on demand + weekly propose-only launchd | SPEC-103 TASK-011..014 |

A single umbrella spec (SPEC-103) covers all three; the phases are indexed in `docs/proof-of-done.md`
per feature rather than split into SPEC-001/002/003, because they share one design and one I/O
contract.

## Canonical invariants (stated once, here)

- Hooks return in well under 200ms; the reviewer runs detached and never blocks a turn.
- **The `claude -p` reviewer/curator have no filesystem write** (`--allowedTools ""`); only the
  trusted bash wrappers write, to fixed paths. Staging-by-path is the structural gate.
- The reviewer never writes `~/.claude/skills/`; only `/skill-review` promote (human) and the
  default-off `auto_promote` references-add path do.
- The curator never deletes: `git mv` to `_archive/` is the maximum action; `restore` reverses it.
- A reviewer never triggers a reviewer (`CLAUDE_REVIEWING` sentinel + `--bare`); single-flight via an
  atomic mkdir lock (the host has no `flock(1)`).
- Every path is exit-0 on failure: a self-improvement run must never break a session.

## Host placement

Personal, single-host (Han's Air/Mini). Hooks run in-session; the optional weekly curator is a
`mini.*` LaunchAgent (propose-only). No server, no daemon beyond that one cron.
