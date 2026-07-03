# Context for implementation , SPEC-106 DAG-wavefront scheduling

## Stack
- Pure bash (POSIX-leaning), jq for JSON. **CI is macOS `macos-latest` = bash 3.2** (`.github/workflows/test.yml`). No bash-4 features.
- Tests are bash scripts under `tests/` (e.g. `tests/test-orchestrate.sh`). Run with `bash tests/<file>.sh`.

## Conventions (match these)
- `set -uo pipefail` at the top of `lib/orchestrate.sh` (L33). Empty arrays MUST use the guard `${arr[@]+"${arr[@]}"}` , precedent `lib/mega-merge.sh:224`, `lib/stack-merge.sh:127`.
- Background+wait is `{ cmd; } &` / `spid=$!` / `kill -0 "$spid"` poll / `wait` (see `_run_session_watchdog` L312-333). NOT `wait -n` (bash 4.3+).
- No `flock` anywhere (absent on macOS). Locking = `mkdir <lockdir>` atomic + stale-timeout (new helper; none exists yet).
- Helper functions are small + named `_verb`; the event log is append-only and replay-derived (never mutated in place).
- Grounded completion: never trust session stdout; re-read the ROADMAP box (L448-455).
- Specs: `Status:` header tracks DRAFT/VALIDATED/SHIPPED in place (ADR-0010). Replace, don't deprecate.

## Key files
- `lib/orchestrate.sh` (500L) , the driver. `_subgoals` L86, `_next` L101 (serial pick, being generalized), `_sg_deps_blocked` L133 (ready-set primitive), event log L108-121, `_build_prompt`/HANDOFF L267-282, `_run_session_watchdog` L312, `cmd_run` main loop L376-489 (grounded check L448-455).
- `lib/dispatch-gate.sh` (211L) , prove-or-serialize disjointness over `## Touches` globs. `gate_disjoint` L84, `gate_plan` L115 (already a greedy wavefront-shaped admission loop). Reuse for wave pairs; verify it parses goal files, not only specs.
- `tests/test-orchestrate.sh` , the regression baseline; asserts on plain `HANDOFF.md` at L42,80,93,157,179,408-485. Keep the no-deps/linear path byte-compatible.
- `lib/mega-merge.sh:224`, `lib/stack-merge.sh:127` , copy the empty-array guard from here.

## External dependencies
- None new. Reuses `dispatch-gate.sh`, the `depends` parser, the watchdog, worktree discipline (`.claude/worktrees/<id>`).

## Decision anchors
- ADR-0030 (Accepted) authorizes the scope; DECISION-BRIEF-dag-wavefront pins the design + 5 exit criteria.
- ADR-0030 supersedes-in-part `docs/research/2026-05-22-concurrent-goal-dispatch.md` §5 (see its Reconciliation section).
- Research: `docs/research/pitfalls.md`, `docs/research/architecture-orchestrator-wavefront.md`.
