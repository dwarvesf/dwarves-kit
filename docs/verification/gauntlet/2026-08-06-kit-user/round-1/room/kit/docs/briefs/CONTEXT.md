# Context for implementation: backlog-reconcile

Hand-assembled from direct reads (topology-drift/memory-tidy are the two closest precedents;
both were read in full before this spec), not the 4-agent research fan-out: the target area is
small (one new skill file + one pattern-doc registration + a mechanical registry regen) and
already precisely known from prior in-session reads, so a generic stack/architecture/pitfall
sweep would restate what's already verified.

## Stack

Bash (skills are markdown + bash tool invocations), Python only in `lib/registry/` generator
tooling. No new dependency needed; every tool this skill uses already exists in the kit.

## Conventions

- Skill file: `skills/<name>/SKILL.md`, frontmatter `name` + `description` + `disable-model-invocation: false`.
- Audit-loop instances document their "four slots" as a table right after the Overview
  (topology-drift lines 20-27), then a numbered `## Process`, then `## Cadence`, then `## Red flags`.
- Mechanical (Tier 1) checks are inline bash in the SKILL.md body, not a separate script, unless
  reused elsewhere (`backlog.sh` itself is the one reusable piece here, already exists).
- Tier 2 always dispatches the SAME shared agent, `agents/audit-scanner.md`; instances never
  fork their own scanner.
- Verdict grammar is fixed kit-wide: OK / FIX / REMOVE / UNSURE / DANGER (`docs/patterns/audit-loop.md`).
- Every instance branches first (isolated worktree), ships via PR, never edits its target on
  the current branch.

## Key files

| File | Role |
|---|---|
| `skills/topology-drift/SKILL.md` | Direct template: same shape, same Tier1/Tier2 split, same refusal-guard pattern (stale FEATURES.md) this spec adapts for a missing/unadopted board. |
| `skills/memory-tidy/SKILL.md` | Second precedent; simpler (no Tier 1/Tier 2 split, single fan-out pass) but shows the worktree-branch-PR mechanics generically. |
| `lib/board/backlog.sh` | The mechanical substrate: `board` (enumerate), `set <ID> <state> [note]` (mechanical status flip), `next`, `states`. `BACKLOG_FILE` env override already exists (tests point it at a fixture; this spec's own test can reuse that). |
| `agents/audit-scanner.md` | Shared Tier-2 scanner, already generic (`doc-drift`, `topology-drift`), read-only tools roster is the write-path enforcement. Reused as-is, zero changes needed. |
| `docs/patterns/audit-loop.md` | The pattern doc. "Known instances" section (lines 61-71) needs a new paragraph; "SDLC instances" table row 55 ("Backlog reconcile") is what this spec fulfills. |
| `docs/FEATURES.md` / `docs/workflow-paths.md` | Generated registry + hand-maintained path index; `lib/registry/feature-registry.sh generate` regenerates the former; the latter needs one new line so `topology-drift`'s own freshness check (which this new skill sits alongside) stays green. |
| `tests/test-hooks.sh` | Where `backlog.sh`'s own 10 fixture tests live (SPEC-055); this spec's tests can follow the same fixture-copy pattern (`BACKLOG_FILE` override). |

## External dependencies

`gh` CLI (already a hard dependency elsewhere in the kit, e.g. board sync) for PR-pointer state
checks. No new credential, no new API, no new package.
