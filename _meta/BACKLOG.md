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
| ID-015 | AGENTS.md operating layer: tool-agnostic entrypoint + brownfield backfill lane + six-section goal projection + observable After-state spec section (ships ADR-0013) | ADR-0013 (hoangnb24/harness-experimental study, 2026-05-21) | SPEC-024 | full | shipped (CHANGELOG [Unreleased], no version bump; PR #7) |
| ID-016 | Promote the "new SPEC -> BACKLOG status row" doc-impact check to a guard (a hook or a kit-health line); it was missed across multiple cycles | SPEC-025 retro 2026-05-21 (recurrence clears the PHILOSOPHY section 5 bar) | TBD | normal | queued |
| ID-017 | Reconcile retro-file naming across the `retro` skill body + description, CLAUDE.md, and WORKFLOW.md to the repo's actual `RETRO-YYYY-MM-DD-<slug>.md` convention | SPEC-025 retro 2026-05-21 | TBD | tiny | queued |
| ID-018 | install.sh prints blind `cp` tips for AGENTS.md and CLAUDE.md; harden both to copy-if-absent at the command level (`cp -n` or a guard) so the printed command matches its "if absent" prose, or record why prose-only suffices | SPEC-024 review 2026-05-21 (security lens) | TBD | tiny | queued |
| ID-019 | Demo `examples/hello-spec/docs/specs/SPEC-001-version-flag.md` lacks a `## After state` section; add one so the demo is a complete exemplar of the post-SPEC-024 spec template | SPEC-024 review 2026-05-21 (test-coverage lens) | TBD | tiny | queued |
| ID-020 | Verification-pipeline absence-checks: teach task-verifier + integration-checker to assert that removed/replaced content is GONE for "replace, don't duplicate" / "remove X" tasks, not just that the new artifact exists. A replace-task left both copies and passed BOTH verifiers this cycle; only the independent review caught it | SPEC-024 retro 2026-05-21 (pipeline blind spot) | TBD | normal | queued |
| ID-021 | Reduce execute-worker shell/hook friction: pre-warn the recurring gotchas in `commands/execute.md`'s worker template (fish `noclobber` -> `>|`; no heredoc commit `-m` -> `git commit -F`; no `rm` -> `mv`), and investigate the commit-format/commit-msg heredoc mis-parse (it read a multi-line `-m` body as a 459-char subject) | SPEC-024 retro 2026-05-21 (worker friction) | TBD | normal | queued |
| ID-022 | Freeform front door: extend `/user:assign` to accept freeform intent (not only `ID-NNN`), auto-allocating an ID + BACKLOG row so "apply SDD to X" / a vague brief is a native one-shot intake (unparks the SPEC-024-deferred griller entry; preserves ID-first traceability) | PLAYBOOK.md scenarios 2026-05-22 | SPEC-026 | normal | speccing |
Dependency notes:
- ID-012 P1 (spec stop-criteria) shipped (SPEC-012, normal lane; see CHANGELOG); P2 (loop QA gate) is held until the pointer-`/goal` pattern has real runs; it will build on the now-shipped SPEC-006 completeness clauses + the existing verification pipeline.
- ID-002 (internal absorption lane, SPEC-007) is parked; independent of the orchestration chain.
- ID-016 / ID-017 came out of the SPEC-025 retro; both are kit-internal hygiene, independent of the SPEC-024 chain.
- ID-018 / ID-019 came out of the SPEC-024 /review-team pass (deferred LOW findings); both are tiny-lane polish, independent of the SPEC-024 ship.
- ID-020 / ID-021 came out of the SPEC-024 retro; ID-020 (verifier absence-checks) relates to ID-016 (both are guard/verifier hardening) and is the highest-signal kit finding of the cycle.
- ID-022 came out of writing `docs/PLAYBOOK.md` (scenarios S2/S5): the freeform-intent gap. It unparks the SPEC-024-deferred griller entry; SPEC-026 drafts it. Independent of the other chains.

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
