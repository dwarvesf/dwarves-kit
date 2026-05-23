# Context for implementation (SPEC-031, ID-034)

## Stack
Bash + jq hooks; markdown docs; tests in bash (`tests/test-meta.sh` structural,
`tests/test-hooks.sh` behavior). No Node/Python in hooks. Every script readable in
30 seconds. This spec is contract + docs + tests only: no runtime code.

## Conventions
- Specs: `docs/specs/SPEC-NNN-<slug>.md`, `Status:` header tracks DRAFT/VALIDATED/SHIPPED in place (ADR-0010).
- ADRs: `docs/decisions/NNNN-<slug>.md`, format Context / Decision / Consequences (see 0001-0016).
- Replace, don't deprecate. No phantom features. Every file justifies its existence.
- "Detect, don't dictate": completeness is warn+log to `~/.claude/dwarves-kit/logs/completeness.log`, never a hard block. Hard stops reserved for the safety subset.
- The phase list has ONE source (WORKFLOW.md cycle table); other docs reference it, never restate it.

## Key files
- `WORKFLOW.md`, the cycle table (lines 30-50), lane table (16-28), doc-impact map (123-148), version-surfaces note (148), "Artifact placement and concurrency" (169-200). This spec ADDS sections here; it cites the doc-impact map, does not restate it.
- `docs/PHILOSOPHY.md:51` and `:170`, the two "8 phases" sites (C2 reword targets).
- `commands/kit-health.md:152`, the third "8 phases" site + reject-list.
- `docs/architecture.md`, gets the command/agent → V-phase inventory table.
- `agents/integration-checker.md` (+ SPEC-021, ADR-0015), cross-task wiring verifier. Convergence must NOT duplicate it.
- `commands/ship.md`, Steps 1b/4a/7 already do the shared-surface write. Convergence must NOT duplicate it.
- `agents/{task-verifier,fix-agent,doc-verifier}.md`, the existing verify arm; reference, do not change.

## External dependencies
None. No APIs, no services, no new libraries. git + grep + bash are the only tools the verification command needs.

## The non-duplication boundary (read before writing convergence)
- `task-verifier` answers "is THIS task correct?" (per-task gate, max-2 fix retry).
- `integration-checker` answers "do the tasks CONNECT?" (cross-task wiring, once at /execute Step 4).
- `/kit:ship` WRITES the shared surfaces (CHANGELOG, VERSION, plugin.json, tool.toml).
- `convergence` (this spec) answers neither and writes nothing: it only enumerates the hands-off list and collates per-worktree branch-ready/blocker signals, then hands the write to `/kit:ship`.
