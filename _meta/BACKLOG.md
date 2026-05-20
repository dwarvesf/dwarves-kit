# Task Backlog

> **`_meta/` charter.** This folder holds live, mutable, maintainer-facing project
> *state*: trackers, queues, and manifests of work. Durable reference and the design
> record live in `docs/` (specs, decisions, handoff, retro, research). Today the only
> artifact meeting that bar is this backlog, and that is expected, not a gap.
>
> **Do not add** to `_meta/`: a `ROADMAP` (the v2-candidates + parking-lot tiers below
> are the roadmap), a `SCHEMAS` file (the backlog schema lives in this file and in
> `docs/architecture.md`; schemas belong next to their artifact), a `LAB_LOG` (use
> `docs/handoff/` + `docs/retro/`), an ADR index (`docs/decisions/` self-indexes by
> number), or `checks/`/`infra/` (that is `tests/` + `.github/`). An `INVENTORY`
> manifest is allowed *only* if it becomes the single source `tests/test-meta.sh` and
> the README derive from, never a hand-maintained fourth copy. Resist the junk drawer.

The kit's single source of truth for "what's left to do." Three tiers, decreasing commitment:

1. **Active queue** - committed work, each with a stable `ID-NNN` id and a status. This is what `/user:start` and `/user:next` read when you ask "what's left?". Shipped items drop off the queue (the CHANGELOG is the canonical "what shipped" record).
2. **v2 candidates** - not committed; become real only after a spec is written and `/spec-validate` passes. Listed for visibility.
3. **Parking lot** - revisit only if a real usage signal arrives.

Completed cycles live in `docs/handoff/v<version>.md` (build notes) and `docs/retro/v<version>.md` (cycle retros). Per-release CHANGELOG entries are the canonical "what shipped" record. Completed work is NOT mirrored back here, to avoid drift.

> Schema note: this active-queue shape is bootstrapped by hand. **ID-006 (SPEC-005)** formalizes its schema, status vocabulary, and the session-start integration. Until then, treat the columns below as the working contract.

## Active queue

Status vocabulary: `queued` (committed, no spec yet) -> `speccing` (spec being drafted) -> `validated` (spec passed `/spec-validate`) -> `executing` (in build) -> `shipped` (drops off, see CHANGELOG). Off-ramp: `parked` (a drafted spec deliberately set aside; the spec holds its own revisit note).

Lane = the WORKFLOW.md risk tier (`tiny` / `normal` / `full`).

| ID | Title | Source | Target artifact | Lane | Status |
|----|-------|--------|-----------------|------|--------|
| ID-001 | Recurring upstream-absorption ritual, maintainer-triggered (generalize SPEC-002's one-shot audit) | item 1 | SPEC-004 | full | validated |
| ID-002 | Absorb skills/hooks developed in ops-toolkit into the kit (internal lane) | item e | SPEC-007 (PARKED; see its Parked note) | full | parked |
| ID-003 | Deep orchestration scan of the copied repos vs our WORKFLOW (report + absorb plan) | item 2 | `docs/research/2026-05-20-orchestration-deep-scan.md` | normal | shipped (report delivered; recs folded into SPEC-006) |
| ID-004 | Resolve `.planning/` vs `docs/specs/` confusion + leakage audit | item a | SPEC-005 | normal | validated |
| ID-005 | Multi-goal state: per-goal files so concurrent goals don't conflict (registry contract in SPEC-005; `/user:goals` command + rendering deferred to SPEC-006) | item b | SPEC-005 + SPEC-006 | full | validated |
| ID-006 | Backlog as the canonical active session-start queue (schema in SPEC-005; `/start`-`/next` rendering in SPEC-006) | item c | SPEC-005 + SPEC-006 | normal | validated |
| ID-007 | Orchestration spine: session-start -> goal-crafter breakdown -> full WORKFLOW per item | item d | SPEC-006 | full | validated |
| ID-008 | Airtight Reflect phase: changes re-checked, every affected doc updated, nothing missed | item f | SPEC-006 | full | validated |
| ID-011 | Unify the spec-location convention onto `docs/specs/SPEC-NNN` (retire downstream `.planning/`; GSD-interop rationale obsolete); make detection + state worktree-safe for worktree-per-spec concurrency; supersede ADR-0002 | maintainer decision + research 2026-05-20 | SPEC-010 | full | Part 1 shipped (see CHANGELOG); Part 2 (worktree-safe detection/state) folded into SPEC-005 dual-detect |
| ID-012 | Goal-loop fidelity (one theme, two parts). P1: stop-criteria in the `/spec` template (pin `## Verification` + `## Open questions` so specs are pointer-`/goal`-ready) -- build now, tiny lane. P2: QA gate around the autonomous loop (verify-into-loops + SPEC-006 completeness clauses + Reviewer 5) -- held until the pointer-`/goal` pattern has real runs | maintainer Q3 2026-05-20 + goal-readiness convergence 2026-05-21 | SPEC-012 | normal (P1) / full (P2) | P1 shipped (see CHANGELOG); P2 held |
Dependency notes:
- ID-012 P1 (spec stop-criteria) shipped (SPEC-012, normal lane; see CHANGELOG); P2 (loop QA gate) is held until the pointer-`/goal` pattern has real runs, since it overlaps the still-unbuilt SPEC-006 completeness clauses and the existing verification pipeline.
- ID-003 (research) gates SPEC-006 design; runs first.
- ID-004/005/006 (state) land before ID-007/008 (the loop that reads that state).
- ID-001/002 (absorption) are independent of the orchestration chain.

## v2 candidates (pending real usage signal)

Items here are NOT committed; they become real only after a spec is written and `/spec-validate` passes. Listed for visibility.

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns). Needs ~30 false-positive logs from `~/.claude/dwarves-kit/logs/anti-rationalization.log` to justify the latency cost.
- `/qa` command with headless browser testing (requires Playwright).
- Agent Teams parallel task dispatch in `/execute`. Currently sequential by design (see `docs/PHILOSOPHY.md`, "Shallow and wide beats deep and narrow").
- `SessionEnd` hook for automatic knowledge capture.
- AutoResearch optimization of the `task-verifier` prompt. Needs 30+ real verification transcripts as eval corpus.
- Multi-harness packaging (Codex / Cursor / Gemini / OpenCode). Defer until real cross-harness demand.

## Parking lot (revisit if a real signal arrives)

- L5 orchestration (Nimbalyst integration). Not needed until 3+ concurrent sessions.
- AutoResearch loop for command prompt optimization. Manual iteration is faster at current volume.
- Agent-type hooks for deep verification. Custom subagents handle this today; revisit only if subagents prove insufficient.

## Source

Backlog format matches `ops-toolkit/_meta/BACKLOG.md`, extended with the Active queue tier (ID-006 / SPEC-005). Completed work is NOT mirrored here, to avoid drift with CHANGELOG.md and `docs/handoff/`.
