# Spec: Unify the spec-location convention onto docs/specs/, worktree-ready

Generated: 2026-05-20
Status: VALIDATED
Source: maintainer decision 2026-05-20 (unify, dogfood here) + the mid-2026 SDD-convention research (this session). Decision brief folded in below in lieu of a separate `/user:think` (the research + the Q1/Q2/Q3 decision exchange covered think's stress-test). Backlog: ID-011.
Supersedes: ADR-0002 (the `.planning/` vs `docs/specs/` split). A new ADR-0010 records the supersession.
Depends on: SPEC-005 (dual-detect: active spec = current branch), which is VALIDATED but NOT yet shipped. Part 2's active-spec-by-branch selection rides on SPEC-005 execution (see Known limitations 1); Part 1 + state-namespacing do not. Conceptual lineage for the concurrency stance: gsd-2 (git-worktree isolation per active spec).
Lane: full (changes the spec-location contract every command + hook + downstream project depends on; supersedes an ADR). Blast radius: 12 commands, 5 hooks, 3 example files, the demo, test-meta assertions, 1 ADR.

## Decision brief (folded-in /think)
- **Real pain:** two conventions confuse users (kit-on-kit uses `docs/specs/`, downstream uses `.planning/SPEC.md`), and the reason for the split is obsolete.
- **Why now:** research shows the precedent ADR-0002 cited is gone. Current GSD no longer uses `.planning/SPEC.md` (it uses `.planning/phases/`), so the "GSD interop, both check `.planning/`" rationale no longer holds. The field has moved unanimously to multi-spec directory layouts; the kit's own `docs/specs/SPEC-NNN` already is one.
- **Cut list (out of scope):** in-kit parallel orchestration; the OpenSpec two-tree storage model; the heavier goal-loop QA (its own later spec, maintainer decision Q3).
- **Exit criteria:** no command or hook reads/writes `.planning/` except a single bounded-deprecation fallback; the demo + downstream template use `docs/specs/`; dual-detect + kit state are worktree-safe; ADR-0010 supersedes 0002; tests green.

## Problem

ADR-0002 (2026-05-20) split the spec location: downstream projects write `.planning/SPEC.md` (GSD lineage), the kit itself writes `docs/specs/SPEC-NNN-<slug>.md` (ops-toolkit tide shape). The stated reason to keep `.planning/` downstream was GSD interop ("Compatible with GSD if user also installs GSD, both check `.planning/`").

Two findings from this session's research weaken that rationale, in order of robustness:
1. **The kit already uses `docs/specs/SPEC-NNN` for itself, and the field standard is now multi-spec directories** (Spec Kit, OpenSpec, Agent OS, gsd-2 all use per-feature/per-change dirs). Unifying means moving downstream onto the kit's existing modern convention, not inventing anything. This reason stands on its own.
2. **The cited GSD precedent appears gone** (current GSD uses `.planning/phases/`, not a single `.planning/SPEC.md`), so the interop argument is moot. Caveat: the exact GSD version is unconfirmed (web-fetch, post-cutoff). The decision does NOT hinge on this finding; it only reinforces finding 1.

Maintainer goal (this session): one convention everywhere, dogfooded here, AND positioned so that "multiple active specs executed concurrently" is reachable via the worktree-per-spec model (Q2), with the kit providing per-worktree detection and an external runtime doing the orchestration.

## Solution

### Approaches considered
1. **Unify onto `docs/specs/SPEC-NNN` + bounded `.planning/` deprecation fallback + worktree-safe detection/state.** Tradeoff: one migration touching 12 commands + 5 hooks + 3 examples, but the convention is already proven kit-side and the fallback protects the installed base.
2. **Hard cut (remove `.planning/` immediately, no fallback).** Tradeoff: cleanest ("replace, don't deprecate"), but breaks every existing downstream project on upgrade with no grace.
3. **Adopt OpenSpec two-tree (changes/ + canonical specs/).** Tradeoff: solves the latent fragmentation problem, but it is a different storage model (revises the Q1 choice) and a heavier rewrite. Rejected here; revisit separately if fragmentation bites.

### Chosen approach + why
Approach 1. It delivers the unification the maintainer chose (Q1) and the worktree-ready posture (Q2) while honoring the installed base with a bounded deprecation window (one minor version of `.planning/` fallback with a warning, then removed). Approach 2 was rejected for breaking downstream projects on upgrade; Approach 3 was rejected as out of scope (it revises Q1 and is a separate, larger decision).

### Extensibility & boundaries
- Load-bearing dimension: number of `.planning/` references. The risk is missing one of the 12 commands / 5 hooks. Mitigation: a test-meta guard asserting no command/hook references `.planning/` except the documented fallback (so a missed reference fails CI).
- Concurrency dimension: "multiple active specs" scales by running N git worktrees, each one-active via dual-detect. The kit's boundary stops at per-worktree detection + per-worktree state isolation; spawning/scheduling/merging the N worktrees is external (gsd-2 / Agent Teams / Conductor). This boundary keeps the one-session PHILOSOPHY intact.
- Unit boundaries: Part 1 (convention swap) and Part 2 (worktree-safety) are separable; Part 1 alone is shippable, Part 2 makes the concurrency path real.

### Architecture (diagram if it helps)
```
BEFORE                                  AFTER
downstream -> .planning/SPEC.md         everyone -> docs/specs/SPEC-NNN-<slug>.md
kit        -> docs/specs/SPEC-NNN       (kit unchanged; downstream + demo migrate)

hooks/commands read .planning/    ->    read docs/specs/ (primary)
                                        + .planning/ fallback w/ deprecation warning (1 minor, then removed)

concurrency:  N git worktrees, each on its own branch
              each worktree -> dual-detect picks that branch's active spec (one-active per session)
              kit state (logs, session-state) namespaced per branch/worktree
              fan-out + merge of the N worktrees = EXTERNAL runtime (out of scope)
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** ADR-0002 (superseded); the 12 commands + 5 hooks (`context-readiness`, `spec-drift-guard`, `pre-compact-backup`, `session-state-save`, `post-compact-reinject`) + 3 example files referencing `.planning/`; SPEC-005 dual-detect (active = current branch); git worktrees as the isolation primitive.
- **Outputs / produces:** one convention (`docs/specs/SPEC-NNN-<slug>.md`) for kit and downstream; hooks/commands reading `docs/specs/` with a bounded `.planning/` fallback; per-worktree-safe detection + namespaced kit state; ADR-0010; a documented worktree-per-spec concurrency pattern in WORKFLOW.md; updated demo + downstream template.
- **Invariants (must stay true):** the kit's own existing specs in `docs/specs/` are untouched; existing downstream `.planning/` projects keep working for exactly one deprecation window; the verification pipeline, the lanes, and the 5-reviewer set are unchanged; orchestration stays external (the kit only detects, never spawns/merges parallel sessions).

### Data model changes
None (file/dir convention only).

### API / UI / Infrastructure changes
Hook + command path references; example/demo paths; a deprecation-warning code path in the spec-locating hooks.

## Task Breakdown

**Phase 1: Convention swap (Part 1)**
- [x] **TASK-1: hooks read `docs/specs/` with a bounded `.planning/` fallback.** DONE (5 hooks updated; resolver smoke-tested on the docs/specs/ primary path; test-hooks 42/42, test-meta 129/129). Update the 5 spec-aware hooks to resolve specs from `docs/specs/` first; if absent, fall back to `.planning/SPEC.md` and emit a one-time deprecation warning (to the existing hook log, not stderr spam). Keep `.gsd/` handling per ADR-0002 if present.
  - Acceptance: each of the 5 hooks resolves `docs/specs/` first; the fallback fires only when `docs/specs/` is empty and emits a single deprecation notice; `bash tests/test-hooks.sh` still 42/42 (update fixtures as needed).
- [x] **TASK-2: commands reference `docs/specs/`.** DONE (sd sweep + DEC-014 mapping; 1 intentional legacy note in start.md). Update all 12 commands that mention `.planning/` to use `docs/specs/SPEC-NNN-<slug>.md`. Where a command writes a new spec, it writes to `docs/specs/`. This applies the DEC-014 satellite mapping (research->docs/research/, retro->docs/retro/, CONTEXT->docs/specs/CONTEXT.md, decision-brief folded). A mechanical multi-mapping sweep across 12 files; it exceeds the >5-file atomicity heuristic only by file count, not complexity.
  - Acceptance: no command references `.planning/` except an explicit "legacy projects" note; the spec-authoring path is `docs/specs/`; the post-sweep diff is reviewed in one pass.
- [x] **TASK-3: migrate the demo + downstream template + their tests.** DONE (git mv to docs/specs/SPEC-001-version-flag.md; 3 demo docs swept; 3 test assertions flipped). Move `examples/hello-spec/.planning/SPEC.md` to `examples/hello-spec/docs/specs/SPEC-001-<slug>.md`; update `examples/hello-spec/{WORKFLOW.md,CLAUDE.md}`. Flip the `test-meta.sh` assertions that currently require `examples/hello-spec/.planning/SPEC.md` and that the demo WORKFLOW "uses .planning/SPEC.md" over to `docs/specs/`.
  - Acceptance: the demo uses `docs/specs/`; the two flipped test-meta assertions pass against the new path; the demo still has all required spec sections.
- [x] **TASK-4: ADR-0010 supersedes ADR-0002.** DONE (ADR-0010 written; ADR-0002 marked superseded). Write `docs/decisions/0010-unify-spec-convention.md` (decision: one `docs/specs/` convention; the GSD-interop rationale is obsolete; bounded `.planning/` deprecation). Mark ADR-0002 superseded with a pointer (do not rewrite its history).
  - Acceptance: ADR-0010 exists and cites the research finding; ADR-0002 status line points to ADR-0010.

**Phase 2: Worktree-safety (Part 2; active-selection piece deferred to SPEC-005)**
- [ ] **TASK-5: make kit state worktree-safe (buildable now).** Audit the 5 hooks for writes to a shared location outside the working tree (`~/.claude/dwarves-kit/logs/`, session-state, completeness log) and namespace those writes by a SANITIZED worktree id so two concurrent worktrees do not clobber each other. The id must be derived safely (a hash of the worktree path, or `git rev-parse --git-dir`), NOT the raw branch name: a branch like `feat/x` or `../y` would path-traverse when used as a directory component. The dual-detect active-spec-by-branch verification rides on SPEC-005 execution and is deferred there (Known limitation 1); working-tree-native isolation already gives each worktree its own `docs/specs/` today.
  - Acceptance: shared-path writes are namespaced by a sanitized worktree id (no raw branch name in a path); a two-worktree manual check shows no state collision (documented; the kit has no concurrency harness); the SPEC-005 dependency for active-selection is stated, not silently assumed.
- [ ] **TASK-6: document the worktree-per-spec concurrency pattern.** In WORKFLOW.md, add a short note: many specs coexist in `docs/specs/`; one is active per branch (dual-detect); concurrency = N git worktrees each one-active; the fan-out/merge orchestration is external (gsd-2 / Agent Teams), not the kit's job.
  - Acceptance: WORKFLOW.md states the per-worktree one-active model and that orchestration is external; no claim that the kit runs parallel specs itself.

**Phase 3: Verify + hygiene**
- [x] **TASK-7: guard + cross-refs + CHANGELOG.** DONE (no-stray-.planning guard; README/MANUAL/architecture/CLAUDE/CHANGELOG updated). test-meta 130/130. Add a test-meta guard: no file in `commands/` or `hooks/` references `.planning/` except the documented fallback line(s). Update README "Project structure", MANUAL, `docs/architecture.md`, CHANGELOG. Update the kit's own `CLAUDE.md` "Spec location" + the `.planning` references to reflect the unified convention.
  - Acceptance: the no-`.planning/` guard passes (fallback lines explicitly allowlisted); `bash tests/test-meta.sh` + `bash tests/test-hooks.sh` green; README/MANUAL/architecture/CHANGELOG/CLAUDE.md updated.

## Acceptance Criteria (global)
- [ ] `docs/specs/SPEC-NNN-<slug>.md` is the single spec convention for both the kit and downstream; the demo + downstream template use it
- [ ] The 5 spec-aware hooks resolve `docs/specs/` first with a single bounded `.planning/` deprecation fallback (removed next minor); the 12 commands reference `docs/specs/`
- [ ] Detection (dual-detect) + kit state are worktree-safe; the worktree-per-spec concurrency pattern is documented; orchestration stays external (no in-kit parallel engine)
- [ ] ADR-0010 supersedes ADR-0002; ADR-0002 marked superseded
- [ ] A test-meta guard fails if any command/hook references `.planning/` outside the allowlisted fallback
- [ ] `bash tests/test-hooks.sh` 42/42; `bash tests/test-meta.sh` passes (new count documented)
- [ ] README / MANUAL / architecture / CHANGELOG / kit `CLAUDE.md` updated; no in-kit orchestration, no OpenSpec two-tree, no heavier-QA work bundled

## Known limitations
1. **Part 2's active-spec-by-branch selection depends on SPEC-005 (dual-detect), which is VALIDATED but not shipped.** SPEC-010 ships now the unify (Part 1), kit-state namespacing, and working-tree-native per-worktree `docs/specs/` isolation, none of which need dual-detect. The "which spec is ACTIVE per worktree" refinement lands when SPEC-005 executes. Recommended sequencing: execute SPEC-005/006 before relying on per-worktree active-selection.
2. **Worktree-safety is manually verified.** The kit has no concurrency test harness; TASK-5's no-collision check is a documented two-worktree manual run, not an automated test.
3. **The `.planning/` deprecation fallback is temporary by design** and must be removed next minor; if missed it lingers (failure-modes row + a ship/retro check guard against this).
4. **The interim selector is not branch-aware.** It picks the highest-numbered non-SHIPPED/PARKED spec ("the latest in-flight spec"). In a repo with several in-flight specs on one branch (like this one right now), it picks the highest number, which may not be the spec you are actively working. SPEC-005 dual-detect (active = current branch) is the real fix; until then this is a deterministic best-guess.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Existing downstream project breaks when hooks stop seeing `.planning/` | user reports "kit no longer finds my spec" after upgrade | one-minor-version `.planning/` fallback + deprecation warning + a migration note (`mv .planning/SPEC.md docs/specs/SPEC-001-<slug>.md`) in README/install |
| Two concurrent worktrees clobber shared kit state (logs, session-state, completeness log) | interleaved/garbled logs or lost state across parallel sessions | TASK-5 namespaces shared-path writes by branch/worktree id |
| A `.planning/` reference is missed in one of 12 commands / 5 hooks | a command/hook still uses `.planning/` post-unify | TASK-7 test-meta guard asserts no `.planning/` outside the allowlisted fallback (fails CI) |
| Demo + test assertions left pointing at `.planning/` | `test-meta.sh` fails, or the demo misleads new users | TASK-3 migrates the demo and flips the two coupled assertions |
| Users believe the kit now orchestrates parallel specs | scope-creep requests, support questions | WORKFLOW + ADR-0010 state plainly: kit detects per-worktree; fan-out/merge is external |
| ADR-0002 left "accepted" while contradicted | doc drift, contradictory ADRs | TASK-4 marks ADR-0002 superseded with a pointer to ADR-0010 |
| Deprecation fallback never removed (becomes permanent) | the `.planning/` path lingers releases later | the fallback carries a removal-version note; a retro/ship check flags it for removal next minor |
| A worktree id derived from a raw branch name path-traverses when building a state path | a branch like `feat/x` or `../y` writes outside the intended log dir | TASK-5 derives the id from a hash of the worktree path / git-dir, never the raw branch name |
| Part 2 assumes dual-detect exists, but SPEC-005 is not yet shipped | "dual-detect" referenced with no implementation to make worktree-safe | the active-selection piece is deferred to SPEC-005 (Known limitation 1); SPEC-010 ships the unify + state-namespacing + working-tree-native isolation, which do not need dual-detect |

## Edge Cases
1. **A downstream project with BOTH `.planning/SPEC.md` and `docs/specs/`.** Hooks prefer `docs/specs/`; the `.planning/` file is ignored (no warning, since `docs/specs/` exists). The user is mid-migration; no breakage.
2. **The kit itself.** No migration: its specs are already in `docs/specs/`. Only the downstream-facing references and the demo change.
3. **A worktree with no spec on its branch.** Dual-detect returns "no active spec" for that worktree (consistent with today); the worktree is idle, not broken.
4. **Tiny-lane work.** No spec written; the convention change is a no-op for tiny work.
5. **`.gsd/` present (user also runs current GSD).** Untouched; GSD uses `.planning/phases/` now, which the kit does not read. No collision with the kit's `docs/specs/`.

## Out of Scope
- In-kit parallel orchestration (spawning/scheduling/merging N worktrees). Delegated to gsd-2 / Agent Teams / Conductor (PHILOSOPHY one-session).
- The OpenSpec two-tree storage model (changes/ + canonical specs/). Separate decision if fragmentation bites.
- The heavier goal-loop test/review process (Q3: its own later spec, SPEC-011, after this unify).
- Auto-migrating downstream users' files (we provide the `mv` note + fallback, not a migration script, this cycle).
- Removing the `.planning/` fallback now (scheduled for next minor, not this spec).
- Fixing the pre-existing `context-readiness.sh` `SRC_COUNT` `set -e` trap in zero-source-file dirs (found during execution; backlogged as ID-013, tiny lane; independent of the unify).

## Decision Log
- **DEC-001**: Unify onto `docs/specs/SPEC-NNN` for both kit and downstream (maintainer Q1). The kit already uses it; the GSD-interop reason for `.planning/` is obsolete (research).
- **DEC-002**: Bounded deprecation, not a hard cut. One minor version of `.planning/` fallback + warning, then removed. Rationale: protect the installed base while still converging ("replace, don't deprecate" honored within a window).
- **DEC-003**: Concurrency = worktree-per-spec, orchestration external (maintainer Q2). The kit provides per-worktree detection + state isolation only; it does not become a parallel engine (PHILOSOPHY one-session).
- **DEC-004**: ADR-0010 supersedes ADR-0002 (not edited in place), per the do-not-rewrite-decided-records rule.
- **DEC-005**: A test-meta guard enforces the convention (no stray `.planning/`), mirroring the SPEC-008 drift-guard discipline.
- **DEC-006**: The heavier goal-loop QA is a separate spec (maintainer Q3), not bundled here (scope discipline).
- **DEC-007**: OpenSpec two-tree rejected for this cycle. Rationale: it revises Q1's storage choice and is a heavier, separate decision aimed at fragmentation, not the unify+concurrency goal.
- **DEC-008 (validation)**: Part 2 scoped to buildable-now (state namespacing + working-tree-native isolation + doc); the dual-detect active-selection piece is deferred to SPEC-005 execution. Rationale: SPEC-005 is validated-not-shipped, so "make dual-detect worktree-safe" had nothing to make safe yet (assumption + scope reviewers).
- **DEC-009 (validation)**: worktree state ids are sanitized (hash of worktree path / git-dir), never the raw branch name. Rationale: a branch like `feat/x` or `../y` used as a path component path-traverses (security reviewer H1).
- **DEC-010 (validation)**: the supersession justification leads with "kit already uses docs/specs/ + field standard" and treats the GSD-obsolete finding as supporting, not load-bearing. Rationale: the exact GSD version is unconfirmed (post-cutoff); the decision must not hinge on it (assumption reviewer W1).
- **DEC-011 (validation)**: TASK-2 (12 commands) is labeled a mechanical single-pattern sweep reviewed in one diff pass. Rationale: it exceeds the >5-file atomicity heuristic only by file count, not complexity (scope reviewer W2).
- **DEC-012 (execution)**: interim active-spec selector = highest-numbered `SPEC-NNN` in `docs/specs/` whose Status is not SHIPPED/PARKED (deterministic; zero-padded NNN sorts correctly with `sort -r`, no `-V` needed for macOS+Ubuntu). Maintainer decision this session. SPEC-005 dual-detect (branch-based) replaces it.
- **DEC-013 (execution)**: the ~6-line resolver is inlined in each of the 5 hooks, not a sourced helper. Rationale: keeps each hook standalone and readable in 30s ("Bash over binaries"); the duplication is small and a sourced lib would add structural coupling + settings paths. Revisit if a 6th consumer appears.
- **DEC-014 (execution)**: satellite-artifact mapping (maintainer decision; the `.planning/` working set is more than `SPEC.md`): `SPEC.md`->`docs/specs/SPEC-NNN-<slug>.md`; `research/`->`docs/research/`; `RETRO.md`->`docs/retro/`; `CONTEXT.md`->`docs/specs/CONTEXT.md`; `DECISION-BRIEF.md` folded into the spec's Decision-brief section (transient handoff at `docs/specs/DECISION-BRIEF.md`). Flat + shared, matching the kit's own conventions + the flat Q1 choice. Surfaced during execution (SPEC-010 was under-specified here).

## Source citations
- The split being superseded: `docs/decisions/0002-planning-dir-convention.md`.
- The research that obsoletes the interop rationale (GSD now `.planning/phases/`; field is multi-spec; concurrency needs isolation; OpenSpec/gsd-2 the only true-parallel models): this session's framework survey + `~/workspace/tieubao/ops-toolkit/research/2026-05-20-agent-workflow-enforcement-patterns.md`.
- Active-spec-by-branch primitive this builds on: `docs/specs/SPEC-005-backlog-and-goal-state.md` (dual-detect).
- Worktree-isolation concurrency lineage: gsd-2 (`git.isolation = worktree`, `/gsd parallel start`).
- The spec format this dogfoods: SPEC-008 (Solution depth) + SPEC-009 (I/O contract + Failure modes).

## Validation
5 reviewers run 2026-05-20 (security, failure-mode, assumption-destroyer, scope-critic, solution-design & extensibility). Pre-fix verdict: NEEDS REVISION (1 critical dependency, 1 high security, 2 warnings).
Critical / high, resolved inline:
- Part 2 assumed dual-detect (SPEC-005) is implemented, but SPEC-005 is validated-not-shipped -> Part 2 scoped to buildable-now; active-selection deferred to SPEC-005 (DEC-008, Known limitation 1).
- Branch-name-derived state paths could path-traverse -> sanitized worktree id (DEC-009, failure-modes row, TASK-5).
Warnings, resolved:
- Supersession over-leaned on the unconfirmed GSD-version claim -> justification broadened, GSD finding demoted to supporting (DEC-010).
- TASK-2 (12 commands) exceeded the atomicity heuristic -> labeled a mechanical sweep reviewed in one pass (DEC-011).
Security: the `.planning/` fallback adds no new injection surface; the only security item was the path-traversal (fixed).
Status flipped to VALIDATED after inline resolution. Note: EXECUTION of Part 2's active-selection is gated on SPEC-005/006 shipping (Known limitation 1).
