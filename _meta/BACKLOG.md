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

> Schema note: the column + status-vocabulary contract is formalized in the **[Schema](#schema)** section below (SPEC-005 / ID-006). The session-start rendering of this queue is wired in SPEC-006.

## Active queue

Status vocabulary: `queued` (committed, no spec yet) -> `speccing` (spec being drafted) -> `validated` (spec passed `/spec-validate`) -> `executing` (in build) -> `shipped` (drops off, see CHANGELOG). Off-ramp: `parked` (a drafted spec deliberately set aside; the spec holds its own revisit note).

Lane = the WORKFLOW.md risk tier (`tiny` / `normal` / `full`).

| ID | Title | Source | Target artifact | Lane | Status |
|----|-------|--------|-----------------|------|--------|
| ID-002 | Absorb skills/hooks developed in ops-toolkit into the kit (internal lane) | item e | SPEC-007 (PARKED; see its Parked note) | full | parked |
| ID-003 | Deep orchestration scan of the copied repos vs our WORKFLOW (report + absorb plan) | item 2 | `docs/research/2026-05-20-orchestration-deep-scan.md` | normal | shipped (report delivered; recs folded into SPEC-006) |
| ID-012 | Goal-loop fidelity (one theme, two parts). P1: stop-criteria in the `/spec` template (pin `## Verification` + `## Open questions` so specs are pointer-`/goal`-ready) -- build now, tiny lane. P2: QA gate around the autonomous loop (verify-into-loops + SPEC-006 completeness clauses + Reviewer 5) -- held until the pointer-`/goal` pattern has real runs | maintainer Q3 2026-05-20 + goal-readiness convergence 2026-05-21 | SPEC-012 | normal (P1) / full (P2) | P1 shipped (see CHANGELOG); P2 held |
| ID-013 | Count-consistency meta-test: assert the "N hooks / N commands / N agents" strings across `plugin.json`, `marketplace.json`, README, MANUAL, and `CLAUDE.md` all equal the live file counts, so the count drift cannot recur | dogfooding signal (count drift recurred 15 -> 18 -> 19 -> 20 this session; parallel `REVIEW.md` issue 4) | (tiny, no spec) | tiny | queued |
Dependency notes:
- ID-012 P1 (spec stop-criteria) shipped (SPEC-012, normal lane; see CHANGELOG); P2 (loop QA gate) is held until the pointer-`/goal` pattern has real runs; it will build on the now-shipped SPEC-006 completeness clauses + the existing verification pipeline.
- ID-002 (internal absorption lane, SPEC-007) is parked; independent of the orchestration chain.

## Schema

The Active-queue contract (formalized per SPEC-005 / ID-006; the charter keeps the schema in this file, not a separate SCHEMAS file).

| Column | Meaning |
|---|---|
| `ID` | `ID-NNN`, zero-padded, stable, assigned on entry, NEVER reused. |
| `Title` | one-line description of the work. |
| `Source` | where the item came from (a braindump item, a research finding, a dogfooding signal). |
| `Target artifact` | the spec or doc this becomes (`SPEC-NNN`, or `(tiny, no spec)`). |
| `Lane` | the WORKFLOW.md risk tier: `tiny` / `normal` / `full`. |
| `Status` | the lifecycle state below. |

**Status lifecycle:** `queued` (committed, no spec) -> `speccing` (spec drafting) -> `validated` (spec passed `/spec-validate`) -> `executing` (in build) -> `shipped`. Off-ramp: `parked` (a drafted spec deliberately set aside; the spec holds its own revisit note). SHIPPED items drop off the queue: the CHANGELOG is the canonical shipped record and completed work is not mirrored back here.

**Consumer:** `/user:start` and `/user:next` render this queue when you ask "what's left?". That rendering is wired in SPEC-006, not here; SPEC-005 pins only the schema the spine reads.

This is **not** `TODOS.md`: that file is gitignored, transient, per-diff `/review` output, not the backlog. See the state model in `docs/architecture.md`.

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
