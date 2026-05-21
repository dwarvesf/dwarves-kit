# Spec: AGENTS.md operating layer + brownfield backfill lane
Generated: 2026-05-21
Status: SHIPPED

> Implements ADR-0013 (accepted 2026-05-21) and its After-state addendum. Backlog: ID-015 (full lane).
> Validated 2026-05-21 via /user:spec-validate (5 lenses); revisions recorded in the Decision Log (DEC-004 corrected, DEC-005..DEC-008 added).
> Research note: the standard brownfield 4-agent research pass was skipped because the relevant
> surfaces were already mapped in the session that produced ADR-0013 (WORKFLOW.md, CLAUDE.md,
> commands/assign.md, commands/spec.md, install.sh, the WORKFLOW doc-impact map). No CONTEXT.md was
> regenerated; this spec + ADR-0013 are the implementation context. Regenerate CONTEXT.md at
> /user:execute time only if a worker needs more than the files named per task.

## Problem
The kit out-enforces `hoangnb24/harness-experimental` (real hooks, verifier, push-blocker vs their advisory markdown) but under-ships the *legible in-repo operating layer a `/goal` can point at*:

- The entrypoint is `CLAUDE.md` (+ `WORKFLOW.md`), which is Claude-Code-specific. There is no tool-agnostic front door.
- "Pause if / ask a human" is enforced by safety hooks but never *stated* as a directive a goal can mirror.
- There is no brownfield "review the codebase and backfill docs" entry; the cycle is greenfield-feature oriented (`/think -> /spec`).

Consequence: operators hand-write the rich six-section `/goal` structure every time, with no in-repo referent, so they never reach the altitude shown in the trigger screenshot. The harness-experimental operator does not write that structure into the prompt; they reference structure the repo already carries (its `AGENTS.md` read-order, done-definition, and "ask before" list). We lack that carrier.

## Solution

### Approaches considered
- **A: `AGENTS.md` canonical operating layer; `CLAUDE.md` becomes a thin CC-specific pointer (chosen).** Tradeoff: some operate-contract prose moves out of CLAUDE.md; one-time churn.
- **B: Keep `CLAUDE.md` canonical, add `AGENTS.md` as a pointer to it.** Rejected: a Codex/Gemini agent reading `AGENTS.md` gets redirected to a CC-specific file; defeats portability.
- **C: Ship the full harness-experimental scaffold (empty `product/`, `stories/`, `TEST_MATRIX.md`).** Rejected: violates PHILOSOPHY "every file must justify its existence" + "no phantom features". Their product *is* the scaffold; ours is not.

### Chosen approach + why
Adopt `AGENTS.md` as the tool-agnostic front door carrying the portable operate-contract (ordered read list, task loop, done-definition, explicit "Pause if" list). `CLAUDE.md` shrinks to the CC-only layer (hooks, slash commands, plugin) and points at `AGENTS.md` for the operate-contract. Add a `backfill` brownfield lane to `WORKFLOW.md`. Make the goal-crafter (`commands/assign.md`) emit the six-section operating directive, each section projecting an `AGENTS.md` artifact. Add an observable `## After state` section to the spec template and project it into the goal's `Done-when`. (ADR-0013 decisions 1, 2, 4, 5 + addendum. Decisions 3 and 6 are honored as Out-of-Scope guards below.)

### Extensibility & boundaries
- **Load-bearing dimension: number of agent runtimes.** `AGENTS.md` is plain markdown any runtime reads. Enforcement stays Claude-Code-only (the hooks). Adding a runtime means it *reads* `AGENTS.md`; it does NOT inherit the guardrails until the v3.x agent-hook work lands. The spec must not over-claim portability of enforcement.
- **Units (each independently testable):** `AGENTS.md` (entrypoint), `CLAUDE.md` (CC layer), `WORKFLOW.md` (lanes), `commands/assign.md` (projection), `commands/spec.md` (after-state template). Each describable in <=3 sentences.

### Architecture
```
AGENTS.md  (tool-agnostic front door)
  | sections: ordered read list, task loop, done-definition, "Pause if"
  |
  +-- CLAUDE.md  (CC-specific: hooks/commands/plugin) --points to--> AGENTS.md (no restating)
  +-- WORKFLOW.md  (lanes incl. new `backfill`) <-- AGENTS.md points here for lane selection
  +-- commands/assign.md  (goal-crafter)
  |        projects --> six-section /goal:
  |          Context-to-read  <- AGENTS.md read list
  |          Constraints      <- AGENTS.md/CLAUDE.md rules
  |          Operating rules  <- AGENTS.md task loop
  |          Validation loop  <- spec ## Verification
  |          Done-when        <- AGENTS.md done-definition + spec ## After state
  |          Pause-if         <- AGENTS.md "Pause if" list
  +-- commands/spec.md template  (new ## After state, feeds ## Acceptance Criteria)
```

## Technical Design

### Interfaces (I/O contract)
- **`AGENTS.md`** consumes: nothing (it is the root). Produces: **four portable operate-contract zones** (ordered read list, task loop, done-definition, "Pause if" list). The goal-crafter *composes* the six-section `/goal` from these four zones plus the active spec's `## Verification` and `## After state` (and the CLAUDE.md rules), per the Architecture diagram above; the mapping is a composition, not 1:1. Invariant: the four zone names are stable; renaming one without updating `assign.md` breaks the projection.
- **`commands/assign.md`** consumes: the resolved `AGENTS.md` sections + the `_meta/BACKLOG.md` row for `ID-NNN`. Produces: a six-section operating directive in `.claude/goals/<slug>.md`. Invariant: BACKLOG-ID-first entry (no freeform-intent path in this spec).
- **`commands/spec.md`** template: gains a `## After state` block between `## Solution` and `## Acceptance Criteria`. Invariant: every After-state bullet is observable (checkable by a human or a command), never narrated prose.

### Data model changes
- New file `AGENTS.md` at kit root and `examples/hello-spec/AGENTS.md`.
- `commands/spec.md` template gains a `## After state` section.

### API changes (the goal-crafter contract)
- `commands/assign.md` output shape changes from a tight contract goal (outcome/verify/scope/blocker) to the six-section operating directive, each section pointing at `AGENTS.md`. `Done-when` includes the spec's observable After-state.

### UI changes
None. The kit ships no UI.

### Infrastructure changes
- `WORKFLOW.md`: add the `backfill` lane to the lane table + the cycle. Add an `AGENTS.md` companion-doc row to the doc-impact map. The existing bolded self-maintaining rule is scoped to a new top-level *dir*; `AGENTS.md` is a top-level *file*, so TASK-007 also adds a "new top-level file" trigger row so the map self-maintains for files too.
- `install.sh`: add the `AGENTS.md` copy tip alongside the existing `CLAUDE.md` tip. (Separately, this cycle's install dogfood exercised the settings merge/clean against a `settings.json` that already carried third-party hooks, the previously-untested path; TASK-009 owns it as a regression test and applies any jq fix the test surfaces. See DEC-004.)
- `tests/test-meta.sh`: assert `AGENTS.md` carries the four portable zones, and that `assign.md` carries the six-section projection.

## Task Breakdown
Each task is atomic: implementable in one session, fits in ~50% of a context window.

### Phase 1: Operating layer
- [x] TASK-001 (DONE 7c5015c, verified): Write `AGENTS.md` at kit root: ordered read list, task loop, done-definition (which MUST include "review recorded + report written, and the final response says what changed and what was not attempted"), and an explicit "Pause if / ask a human" list (architecture direction, source-of-truth hierarchy, validation removal, risk-classification change, privacy/security). State plainly that enforcement is Claude-Code-only; under other runtimes `AGENTS.md` is advisory. - AC: file exists; `grep -q 'Pause if' AGENTS.md`; the four portable zones (read list, task loop, done-definition, Pause-if) are present and named so `assign.md` can project them into the six-section goal.
- [x] TASK-002 (DONE c343d92, verified): Make the CC-layer docs point at `AGENTS.md` for the operate-contract (replace, don't duplicate). Two files: (a) kit-root `CLAUDE.md` (NOT `examples/hello-spec/CLAUDE.md`, which TASK-003 handles) gets/keeps a one-line pointer to `AGENTS.md`; (b) `WORKFLOW.md` is the file that actually carries the operate-contract prose today (`## Required reading` ordered list + `## Completion contract` done-definition), so reconcile it to point at `AGENTS.md` as the read-order/done source rather than restating it. Pick one direction (`AGENTS.md` canonical, `WORKFLOW.md` points) and apply it to both. - AC: neither `CLAUDE.md` nor `WORKFLOW.md` restates the ordered read-order + done-definition that now live in `AGENTS.md`; both reference `AGENTS.md`; `WORKFLOW.md`'s required-reading list names `AGENTS.md` first.
- [x] TASK-003 (DONE 5e4bfc1, verified): Add `examples/hello-spec/AGENTS.md` as the downstream template (realistic placeholder content, same shape). - AC: file exists; the hello-spec README/template note references it.

### Phase 2: Lanes + projection
- [x] TASK-004 (DONE f9c04cf, verified): Add a `backfill` brownfield lane to `WORKFLOW.md` (lane table + cycle): review an existing codebase and write the operating-layer docs without changing application behavior; spec-optional, doc-output, no app-code edits. - AC: `grep -q backfill WORKFLOW.md`; lane row + a one-line description present.
- [x] TASK-005 (DONE b7bb3ee, verified): Make `commands/assign.md` emit the six-section operating directive, each section projecting an `AGENTS.md` artifact, with `Done-when` including the spec's observable After-state. - AC: `assign.md` documents the six-section projection and the After-state in `Done-when`; the contract-goal-only shape is replaced, not left alongside.
- [x] TASK-006 (DONE 86e3aa0, verified): Add `## After state` to the `commands/spec.md` template (between `## Solution` and `## Acceptance Criteria`), with the observable-not-narrated rule inline. - AC: `grep -q '## After state' commands/spec.md`; the rule text is present.

### Phase 3: Sync (the doc-impact map)
- [x] TASK-007 (DONE 9fc3e25, verified): Update the `WORKFLOW.md` doc-impact map: add a "new top-level file" trigger row (the current bolded self-maintaining rule covers only a new top-level *dir*, so a top-level *file* like `AGENTS.md` slips through), add the `AGENTS.md` companion-doc row, and a `backfill`-lane reference. - AC: the map names `AGENTS.md` and carries a top-level-file trigger row.
- [x] TASK-008 (DONE f51537e, verified): Update `README.md` "Project structure" and `docs/architecture.md` cross-refs to include `AGENTS.md` and the `backfill` lane. - AC: both name `AGENTS.md`.
- [x] TASK-009 (DONE 6ec7880, verified; merge test passes on current install.sh -> no jq fix needed, DEC-004 resolved as no-bug): Update `tests/test-meta.sh` to assert `AGENTS.md` exists and carries the four portable zones, and that `assign.md` carries the six-section projection. Add a regression test that runs `install.sh` into a throwaway HOME whose `settings.json` already contains a third-party hook (the dogfood case), and asserts the user's hook survives the merge and the result is valid JSON. If that test fails on the current `install.sh`, apply the minimal jq fix to the merge/clean within this task. - AC: `bash tests/test-meta.sh` exercises the four-zone + projection checks AND the merge-with-existing-hooks case, and passes.
- [x] TASK-010 (DONE 43fa85d; version bump REVERTED post-ship per DEC-009): `CHANGELOG.md` entry and the `install.sh` `AGENTS.md` tip. - AC: CHANGELOG records the feature + the install-merge regression test as coverage (not a fix; DEC-004 resolved as no-bug, see TASK-009). The version bump originally done here was reverted to 1.6.0; the kit accumulates under CHANGELOG `[Unreleased]` and does not cut a version per spec (DEC-009).

## Acceptance Criteria (global)
- [x] All tasks pass their individual acceptance criteria.
- [x] `AGENTS.md` is the front door (root + examples) carrying the four portable zones; `CLAUDE.md` and `WORKFLOW.md` point at it (no restating); `backfill` lane present; `assign.md` projects the six sections; `spec.md` template has `## After state`.
- [x] No regressions: `bash tests/test-meta.sh && bash tests/test-hooks.sh` both exit 0.

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh` exit 0 AND `grep -q 'Pause if' AGENTS.md` AND `grep -q backfill WORKFLOW.md` AND `grep -q '## After state' commands/spec.md`

## After state
Observable; each bullet was false before this cycle and is a real check now (all verified at review).
- [x] `AGENTS.md` exists at the kit root and `grep -q 'Pause if' AGENTS.md` passes. (Was: no `AGENTS.md` anywhere in the kit.)
- [x] `CLAUDE.md` points at `AGENTS.md` and no longer restates the read-order / done-definition / pause list. (`WORKFLOW.md` likewise points; the no-restate invariant is now pinned by test-meta.)
- [x] `WORKFLOW.md` lists a `backfill` lane. (Was: only `tiny` / `normal` / `full` / `bug`.)
- [x] `commands/assign.md` produces a six-section directive (Context-to-read / Constraints / Operating rules / Validation loop / Done-when / Pause-if), not a one-line contract goal.
- [x] `commands/spec.md` template contains a `## After state` section, and a newly generated spec carries observable after-state bullets.
- [x] `examples/hello-spec/AGENTS.md` exists so a downstream repo inherits the front door.

## Edge Cases
1. A non-CC runtime (Codex/Gemini) reads `AGENTS.md` but gets no hook enforcement: `AGENTS.md` must state enforcement is CC-only so no operator assumes the guardrails are portable.
2. A downstream repo already has its own `AGENTS.md`: `install.sh` does not copy `AGENTS.md` at all. Like `CLAUDE.md`, it only prints a copy *tip* (`install.sh:299`), so there is no clobber path to guard. The real requirement is that the printed tip read as copy-if-absent, not a blind overwrite (it must not imply the installer will replace an existing `AGENTS.md`). (Commands are symlinked and rules are copy-with-skip; `AGENTS.md` follows the tip model, not either of those.)
3. An After-state bullet that cannot be made checkable: `/spec-validate` and `/review` must flag it and require cutting or rewriting it (the observable-not-narrated rule is enforced at the gate, not just stated).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `AGENTS.md` ↔ `CLAUDE.md` / `WORKFLOW.md` drift (a CC-layer doc restates the contract) | doc-verifier or `/review` finds duplicated read-order/done/pause in `CLAUDE.md` or `WORKFLOW.md` | `AGENTS.md` is the single source; both `CLAUDE.md` and `WORKFLOW.md` point only (replace, don't duplicate) |
| Over-claiming portable enforcement | a reviewer reads "works with Codex" as "enforced under Codex" | `AGENTS.md` states advisory-only under non-CC runtimes; PHILOSOPHY honesty rule |
| After-state rots into aspirational fluff | bullets are not checkable on re-read | observable-not-narrated rule + the spec-validate/review gate cut non-checkable bullets |
| `backfill` lane silently edits app code | a backfill run changes behavior, not just docs | lane definition forbids app-behavior change; pause-if covers it |

## Out of Scope
- **Freeform "griller" entry** (a casual intent with no BACKLOG ID): BACKLOG-ID-first stays canonical (the 2026-05-21 scope call). Why: preserves the detector/mutator + traceability discipline.
- **Portable enforcement / agent-hooks for Codex/Gemini** (ADR-0013 decision 6): deferred to the v3.x multi-runtime work. We add portable *guidance*, not portable *guardrails*.
- **Empty `product/` / `stories/` / `TEST_MATRIX.md` scaffolds** (ADR-0013 decision 3): created only when real content exists.

## Decision Log
- DEC-001: `AGENTS.md` canonical, `CLAUDE.md` a thin pointer. Rationale: tool-agnostic front door + no duplication. Alternatives B (CLAUDE.md canonical) and C (full empty scaffold) rejected. Who: ADR-0013 (human-accepted).
- DEC-002: `backfill` is a new lane, not a reuse of `normal`. Rationale: brownfield doc-backfill has different inputs (existing code) and a no-app-change constraint. Who: ADR-0013 decision 4.
- DEC-003: After-state is a spec section + a `Done-when` projection target, governed by observable-not-narrated. Rationale: a checkable picture both human and agent verify; fluff is rejected by PHILOSOPHY. Who: ADR-0013 addendum (human-requested).
- DEC-004: The install dogfood for this cycle exercised the settings merge/clean against a `settings.json` that already carried third-party hooks, the previously-untested path. TASK-009 owns this end to end: it adds the regression test and applies any minimal jq fix the test surfaces. (Earlier framing claimed the bugs "were already fixed"; `install.sh` is unchanged on this branch, so the work is owned by TASK-009, not pre-done.) Rationale: a merge that drops or crashes on a real user's existing hooks blocks install. Who: auto (raised in dogfood), corrected in spec-validate.
- DEC-005: `AGENTS.md` carries **four** portable zones (read list, task loop, done-definition, Pause-if); the six-section `/goal` is a *composition* of those four plus the spec's `## Verification` and `## After state`, not a 1:1 mapping. Rationale: the Architecture diagram already shows two goal sections sourced from the spec, so the earlier "six contract zones in `AGENTS.md` / 1:1" framing (Interfaces, TASK-001 AC, TASK-009) was internally contradictory and unsatisfiable. Who: spec-validate Reviewer 5/4.
- DEC-006: The operate-contract prose (ordered read-order + done-definition) lives in `WORKFLOW.md` today, not kit-root `CLAUDE.md`. TASK-002 therefore reconciles `WORKFLOW.md` (point at `AGENTS.md`), not just `CLAUDE.md`, and a failure-mode row now covers `AGENTS.md`↔`WORKFLOW.md` drift. Rationale: without this the dedup is a no-op on the named file and the real three-way overlap ships. Who: spec-validate Reviewer 3/5.
- DEC-007: Edge Case 2 reframed to the tip model: `install.sh` never copies `AGENTS.md` (tip-only, like `CLAUDE.md`), so the "must not clobber" guard described a mechanism that does not exist. Rationale: accuracy; the real requirement is the tip wording. Who: spec-validate Reviewer 2.
- DEC-009: No version bump for this spec. TASK-010 had bumped 1.6.0 -> 1.7.0, but the kit's convention is to accumulate changes under CHANGELOG `[Unreleased]` and cut a version separately (1.7.0 had also clobbered the prior `## [1.6.0]` heading). Reverted all three version surfaces to 1.6.0 and moved the SPEC-024 notes into `[Unreleased]`. Rationale: per-spec version bumps were not the established pattern; the bump also corrupted the changelog history. Who: maintainer call (2026-05-21).
- DEC-008: TASK-007 adds a "new top-level file" trigger row to the doc-impact map. Rationale: the bolded self-maintaining rule is scoped to a new top-level *dir*; a top-level *file* like `AGENTS.md` was not actually covered, so line-71's "already requires" claim was false. Who: spec-validate Reviewer 4.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
