# Spec: Mid-flight spec amend (BUILDING -> SPECIFYING -> BUILDING)
Generated: 2026-05-22
Status: VALIDATED

Source: `docs/operating-layer-vision.md` Scenario 7 + the Section 5 gap-analysis row "Mid-flight spec amend"; ID-023. Goal draft: `.claude/goals/mid-flight-spec-amend.md`.

## Problem

You are mid-`/user:execute` on a `VALIDATED` spec (state `BUILDING`). Partway through, the work reveals scope that must be added now: "also do Y." Today there is **no declared path** for this:

- `commands/execute.md` says outright *"Do NOT modify the spec without asking"* and *"Spec ambiguity discovered: Stop and ask user to clarify."* It tells you to stop, not how to add scope and continue.
- The only ways forward are both bad: silently mutate the spec mid-build (the SPEC-024 retro flagged exactly this, editing a TASK's acceptance criterion mid-execute, as a *"process smell"*, recorded only after the fact), or restart the lane (`/spec` -> `/spec-validate` from scratch), which throws away the completed-task state.
- `docs/operating-layer-vision.md` §3.3 has no `BUILDING -> SPECIFYING` row for an amend; Scenario 7 is listed as a **gap** and is not rendered in `docs/PLAYBOOK.md` or `docs/ORCHESTRATION.md`.

The state machine is therefore not legible at this point: an operator mid-build cannot answer "where can I go from here, what does it cost, how do I trigger it" for the add-scope case.

## Solution

### Approaches considered
- **A (chosen): convention + a recorded checkpoint.** Declare the `BUILDING -> SPECIFYING -> BUILDING` micro-loop across the model + rules + operator docs; reword `execute.md`'s "don't modify the spec" anti-pattern into "amend at a checkpoint via the declared path, never silently"; add an **optional, on-demand `## Amendments`** provenance section to the spec template; pin the convention with a `tests/test-meta.sh` assertion. No new command, no new hook. Tradeoff: discoverability rests on the docs + Claude's interpret layer, not a one-word command; mitigated because the amend is rare (~2 occurrences) and the trigger phrase ("also do Y") is natural.
- **B: a new `/user:amend` command.** One-step, discoverable, repeatable. Rejected for v1: a new command costs `MANUAL.md` + README command table + `.claude-plugin/plugin.json` + `marketplace.json` + `test-meta` frontmatter checks, and PHILOSOPHY rejects unearned commands ("no speculative features"; "earn the abstraction"). A twice-used path does not yet clear that bar. Revisit if amends become frequent.
- **C: a hook-enforced amend ritual.** A `PreToolUse` hook that blocks edits to a `VALIDATED` spec mid-build unless an `## Amendments` entry exists. Rejected: PHILOSOPHY explicitly reserves hard blocks for the safety subset and rejects hard-gating *process* completeness (the completeness clauses warn+log, never block). An amend is a process step, not a safety boundary.

### Chosen approach + why
Approach A. It closes the gap with the kit's own grain: a **declared, recorded** path instead of a silent mutation, enforced by convention + one structural test rather than a new command or a hard gate. It composes with what exists: amend-the-spec-first means the new scope's source files become "known" to `spec-drift-guard` (which already greps the union of active specs and skips `.md`), and `/user:next` already resumes by picking the next undone (`- [ ]`) task and skipping `- [x]` done rows, so a resumed build runs only the amended tasks. (`/user:execute` re-parses and re-presents the *whole* plan, so resume after an amend leads with `/user:next`, not a fresh `/user:execute`; see DEC-006.) B and C add weight the evidence does not yet justify.

### The amend micro-loop (the declared transition)

```
  BUILDING (mid /user:execute, spec is VALIDATED)
     │  trigger: operator says "also do Y" / "amend the spec to add Y"
     ▼
  [GUARD] at a task checkpoint only:
     - the in-flight task is verified + committed (or no task is in flight)
     - completed - [x] tasks are FROZEN (never re-opened by an amend)
     ▼
  SPECIFYING (amend, not restart)
     1. append new TASK-NNN rows (new phase or appended) to ## Task Breakdown
     2. update ## After state / ## Acceptance Criteria / ## Verification for the DELTA only
     3. record an ## Amendments entry (date | what | why | at which checkpoint | new task ids)
     4. re-validate the DELTA only (full lane: /spec-validate on the new tasks; normal lane: advisory)
     ▼  Status STAYS VALIDATED (no drop to DRAFT -> that would be a lane restart)
  BUILDING (resume)
     - /user:next picks the next undone - [ ] task (skips - [x] done rows) -> runs only the amended tasks
       (/user:execute re-lists the FULL plan; resume after an amend leads with /user:next. See DEC-006.)
```

Key invariants:
- **No lane restart.** `Status:` never drops back to `DRAFT`. The amend is an in-place delta on a `VALIDATED` spec; only the delta is (re-)validated. This is the literal "without restarting the lane" requirement of ID-023.
- **Completed work is frozen.** An amend may only *add* scope (tasks / AC / after-state bullets). It must not silently rewrite a checked-off task's acceptance criterion; changing an already-DONE contract is a separate, heavier decision (re-open / re-spec), not an amend.
- **Recorded at a checkpoint, not mid-worker.** The `## Amendments` entry is the provenance the SPEC-024 retro asked for, captured *at the moment of the change* and *between tasks*, not reconstructed afterward.

### `## Amendments` section shape (optional, on-demand)

Added only when an amend happens (like `## Failure modes` / `## Open questions`, never an empty scaffold):

```markdown
## Amendments
- AMEND-001: 2026-05-22 | added <one-line scope> | why: <reason> | at TASK-007 checkpoint | new tasks: TASK-009..TASK-010 | re-validated: delta-only (advisory, normal lane)
```

### Source-of-truth placement (avoid duplicating the procedure)
- **`WORKFLOW.md`** (the rules contract) is the **canonical** home of the amend rule (when you may amend, the checkpoint guard, the recorded entry, resume).
- `docs/operating-layer-vision.md` §3.3 gains the `BUILDING -> SPECIFYING` transition **row** (the model) and §5 marks the gap **closed** (-> SPEC-027), mirroring how ID-022 -> SPEC-026 was recorded.
- `docs/PLAYBOOK.md` renders Scenario 7 as an operator card (what you say -> what happens); `docs/ORCHESTRATION.md` renders the loop view. Both **point at** WORKFLOW.md, they do not restate the rule.
- `commands/execute.md` rewords the anti-pattern + the ambiguity branch to point at the declared path.
- `commands/spec.md` documents the optional on-demand `## Amendments` section.

## Technical Design

### Interfaces (I/O contract)
- **Consumes:** an active `docs/specs/SPEC-NNN-<slug>.md` with `Status: VALIDATED` and a `## Task Breakdown` containing both `- [x]` (done) and `- [ ]` (pending) rows; the existing branch-aware active-spec detection (SPEC-005) that `/user:execute` and `/user:next` already use.
- **Produces:** the same spec file, amended in place: new `- [ ]` TASK rows, an `## Amendments` log entry, delta updates to `## After state` / `## Acceptance Criteria` / `## Verification`. No new files, no schema migration.
- **Invariants:** `Status:` stays `VALIDATED` across an amend; `- [x]` rows are byte-for-byte unchanged by an amend; an amend only appends scope.

### Data model changes
None. The spec template gains one **optional** documented section (`## Amendments`); no required field, no parser change. `spec-drift-guard.sh` is unchanged (it already skips `.md` and greps the active-spec union).

### API / UI / Infrastructure changes
None. This is a convention + doc + one meta-test change. No hook code, no new command, no `settings.json`/`hooks.json` wiring.

## Task Breakdown

### Phase 1: Declare the transition (model + rules)
- [x] TASK-001 (DONE: 17e411a, verified): Add the `BUILDING -> SPECIFYING` amend row to `docs/operating-layer-vision.md` §3.3 transition table (trigger "also do Y" / "amend"; guard "at a task checkpoint, completed tasks frozen, Status stays VALIDATED"; To `SPECIFYING`), and add the return `SPECIFYING -> BUILDING (resume)` semantics note. Mark §5 gap-analysis row "Mid-flight spec amend" as closed (-> SPEC-027), matching the ID-022 -> SPEC-026 style., AC: `rg "BUILDING -> SPECIFYING" docs/operating-layer-vision.md` matches in §3.3; §5 row references SPEC-027; no other §5 row altered.
- [x] TASK-002 (DONE: 704092b, verified): Add the canonical mid-flight amend rule to `WORKFLOW.md` (the micro-loop, the checkpoint guard, the frozen-completed-tasks + add-only invariants, Status-stays-VALIDATED, resume via `/next` picking the next undone row, the `## Amendments` record)., AC: `WORKFLOW.md` contains a "mid-flight" / "amend" subsection naming all four invariants; `bash tests/test-meta.sh` still green.

### Phase 2: Wire the operator-facing surfaces (projections)
- [x] TASK-003 (DONE: 7c6eaae, verified): Reword `commands/execute.md` so the anti-pattern "Do NOT modify the spec without asking" and the "Spec ambiguity discovered" / "Task is too large" branches point at the declared amend path (amend at a checkpoint, record in `## Amendments`, resume), instead of only "stop and ask". The no-silent-mutation rule is preserved (amend != silent edit)., AC: `commands/execute.md` references "amend" + "checkpoint"; it no longer instructs a flat "do NOT modify the spec" with no escape hatch; existing tests green.
- [x] TASK-004 (DONE: c11b7af, verified): Document the optional on-demand `## Amendments` section in `commands/spec.md`'s template prose (alongside the other optional sections), with the `AMEND-NNN: date | what | why | at checkpoint | new tasks | re-validated` shape., AC: `commands/spec.md` mentions `## Amendments` and the AMEND entry shape; the section is described as optional/on-demand (no empty scaffold).
- [x] TASK-005 (DONE: 2db948f, verified): Render Scenario 7 in `docs/PLAYBOOK.md` (operator card: "also do Y" mid-build -> the amend micro-loop) and add the loop view to `docs/ORCHESTRATION.md`; both point at WORKFLOW.md as canonical, not restating the rule., AC: `rg -i "also do|mid-flight|amend" docs/PLAYBOOK.md docs/ORCHESTRATION.md` matches in both; both link/point to WORKFLOW.md.

### Phase 3: Pin the convention
- [x] TASK-006 (DONE: e2a9b5c, verified): Add a `tests/test-meta.sh` section "Mid-flight amend convention" asserting (a) `commands/execute.md` references the amend path (`amend` + `checkpoint`), (b) `WORKFLOW.md` documents the mid-flight amend rule, (c) `commands/spec.md` documents the `## Amendments` section, (d) `docs/operating-layer-vision.md` has the `BUILDING -> SPECIFYING` transition row., AC: the four new assertions PASS; `bash tests/test-meta.sh` exits 0 with an increased total.

## After state
The definition-of-done picture. Each is false now, true after, and checkable.
- [ ] An operator mid-build can find a declared "add scope without restarting" path. (Today: `commands/execute.md` says only "do NOT modify the spec" / "stop and ask".) Checkable: `rg -i "amend" commands/execute.md WORKFLOW.md` returns the declared path.
- [ ] `docs/operating-layer-vision.md` §3.3 has a `BUILDING -> SPECIFYING` row and §5 marks the mid-flight gap closed. (Today: no row; §5 says "**ID-023** (new)".) Checkable: `rg "BUILDING -> SPECIFYING" docs/operating-layer-vision.md`.
- [ ] The spec template documents an optional `## Amendments` provenance section. (Today: no amend convention exists.) Checkable: `rg "## Amendments" commands/spec.md`.
- [ ] Scenario 7 is rendered for operators in both PLAYBOOK and ORCHESTRATION. (Today: absent from both.) Checkable: `rg -i "also do|mid-flight|amend" docs/PLAYBOOK.md docs/ORCHESTRATION.md` matches in both.
- [ ] The convention is regression-pinned. (Today: nothing tests it.) Checkable: `bash tests/test-meta.sh` includes and PASSes the "Mid-flight amend convention" assertions.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `bash tests/test-meta.sh && bash tests/test-hooks.sh` green (no regressions)
- [ ] The amend rule is canonical in exactly one place (WORKFLOW.md); other docs point at it, not restate it (no source-of-truth duplication)

## Verification
```bash
bash tests/test-meta.sh && bash tests/test-hooks.sh
```
Plus the After-state greps above (each is a real command).

## Edge Cases
1. **Amend requested mid-worker (a task is in flight).** The guard defers: finish + verify + commit the in-flight task to reach a checkpoint, then amend. The amend never interrupts a running worker.
2. **Amend that rewrites an already-DONE task's AC** (not just adds). Out of scope for an amend; that is a re-open/re-spec decision. The convention says amends are add-only; a contract change to completed work pauses for a human (Pause-if: risk-classification / architecture).
3. **Amend on a `DRAFT` (not yet validated) spec.** No amend needed: just edit the DRAFT directly before `/spec-validate`. The amend path is specifically for `VALIDATED`/building specs.
4. **Amend on a single-task spec.** Allowed; the new tasks make it multi-task, so the Step-4 integration-checker now applies on resume. The operator should expect the integration check.
5. **Concurrent specs (multi-spec worktrees).** The amend targets the branch-aware active spec (SPEC-005 detection), so an amend cannot land in the wrong spec.
6. **Amend done without recording the `## Amendments` entry.** Not detected in v1: Approach A is convention, not enforcement (B/C were rejected deliberately). This is a known limitation, mirroring `spec-drift-guard`'s documented grep limitation (the kit's honesty rule: never over-claim enforcement). The completeness clauses already reviewed at `/user:ship` + `/user:retro` are where an un-recorded amend would surface informally; wiring it into the completeness log is a future option, not v1. See DEC-007.

## Out of Scope
- A `/user:amend` slash command (Approach B), revisit only if amends become frequent.
- Any hook enforcement of the amend ritual (Approach C), PHILOSOPHY rejects hard-gating process.
- Re-opening / re-spec of a `SHIPPED` spec, that is ID-025 (SHIPPED -> TRIAGING), a separate item.
- Context-switch across specs / the ABANDONED terminal, that is ID-024, a separate item.
- Rewriting completed (`- [x]`) tasks' contracts, a heavier decision than an add-only amend.

## Decision Log
- DEC-001: Convention + recorded checkpoint (Approach A), not a new command (B) or a hook (C). Rationale: matches PHILOSOPHY (earn the abstraction; warn-not-block; no speculative features); the amend has ~2 real uses. Alternatives B/C rejected as unearned weight / a hard gate on process. (Confirmed with the maintainer at the design checkpoint.)
- DEC-002: `Status:` stays `VALIDATED` across an amend; only the delta is (re-)validated. Rationale: dropping to `DRAFT` *is* a lane restart, the exact thing ID-023 removes. Alternative (reset to DRAFT) rejected.
- DEC-003: Amends are **add-only**; completed `- [x]` tasks are frozen. Rationale: rewriting a done contract mid-build is the "process smell" the SPEC-024 retro flagged; keep that on the heavier re-open path. Alternative (allow arbitrary mid-build edits) rejected.
- DEC-004: `## Amendments` is an **optional, on-demand** section, not added to every spec. Rationale: PHILOSOPHY "no empty scaffolds"; mirrors `## Failure modes` / `## Open questions`. Alternative (always-present section) rejected.
- DEC-005: The amend rule is canonical in `WORKFLOW.md`; the vision doc carries the model row, PLAYBOOK/ORCHESTRATION/execute point at it. Rationale: source-of-truth hierarchy; avoid the four-copies drift the kit repeatedly fights. (Build:) the meta-test asserts the rule is present, not duplicated.
- DEC-006 (validation): Resume after an amend leads with `/user:next`, not a fresh `/user:execute`. Rationale: spec-validate verified that `/user:next` skips `- [x]` done rows and picks the next undone task, while `/user:execute` re-parses and re-presents the *whole* plan; only `/user:next` makes the "completed work frozen, only new tasks run" promise hold. Found by Reviewer 2/3; the original draft over-claimed `/user:execute`.
- DEC-007 (validation): An amend done without an `## Amendments` entry is undetected in v1 (documented as a known limitation, Edge case 6), not enforced. Rationale: honesty rule (never over-claim portable enforcement); B/C were rejected, so v1 has no guard. Wiring it into the completeness log is a future option. Found by Reviewer 2.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
