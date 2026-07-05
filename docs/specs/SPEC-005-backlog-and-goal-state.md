# Spec: The kit's state model (backlog, goals, spec-location detection)

Generated: 2026-05-20
Status: SHIPPED
Source: maintainer braindump 2026-05-20 (items a + b + c). Backlog: ID-004, ID-005, ID-006.
Prior spec: docs/specs/SPEC-004-absorption-cadence.md
Validation: 4 reviewers run 2026-05-20 (scope-critic, assumption-destroyer, failure-mode, philosophy-fidelity). Pre-fix verdict NEEDS REVISION (8 critical + multiple warnings); all resolved inline. See Decision Log DEC-008..DEC-017 and the Validation section.
Reconciled: 2026-05-21, after SPEC-010/ADR-0010 shipped (superseding ADR-0002) and ID-013 landed. Part 1's detection ORDER is inverted to docs/specs-first (ADR-0010 unified the convention; `.planning/` is now a bounded deprecation fallback, not downstream-precedence); the branch-match SELECTION rule within `docs/specs/` is retained as the still-valid core; TASK-1a's two abort fixes are marked done (ID-013). See DEC-019.
Reconciled: 2026-05-23 (SPEC-037/ADR-0023). Part 2's `INDEX.md` derived cache was never built and is dropped: the filesystem (`ls .claude/goals/*.md`) is the sole source of truth, and drafts gain an archive-on-ship lifecycle (`lib/goal/goal-drafts.sh archive` moves a shipped draft to `.claude/goals/done/`). The `INDEX.md` mentions in Part 2 and DEC-016 below are retained as the historical record; ADR-0023 is the live decision.

## Problem

The kit has three kinds of working state, and all three are under-specified. The braindump hit each one.

**1. Spec-location detection is single-mode, so kit-on-kit work is invisible to the hooks (ID-004 / item a).**
The braindump asked "why is `.planning/SPEC.md` still referenced; shouldn't new specs go in `docs/specs/`?" The answer is half reassuring, half a real bug:
- **By design (ADR-0002):** downstream projects use `.planning/SPEC.md`; the kit ITSELF uses `docs/specs/SPEC-NNN-*.md`. The `.planning/` references in hooks and commands are the downstream convention, not stale leftovers.
- **The real bug:** the spec-reading machinery is hardcoded to `.planning/` only. `hooks/context-readiness.sh` (line 26) gates its entire spec-state detection on `[ -d ".planning" ]`. `hooks/spec-drift-guard.sh` (lines 28-31) only sets `PLAN_DIR` to `.planning` or `.gsd`. `commands/next.md` reads `.planning/SPEC.md`. **When you work on the kit, none of them see `docs/specs/`.** Kit-on-kit work silently loses the "next:" suggestion, the spec-status readout, and drift-guarding. The convention split was documented but never wired into the readers.

**2. Goal state is a single file, so concurrent brainstorming clobbers (ID-005 / item b).**
The Claude Code built-in `/goal` writes `.claude/last-goal.md` and installs a Stop hook from it. It is single-slot by design. Brainstorming a second goal overwrites the first. There is no draft store, no way to hold several candidate goals. (Note: `last-goal.md` is written by the built-in, not by the kit; the user-level `goal-craft` skill crafts the text but explicitly does not shadow `/goal`. So the kit cannot change the built-in's single-slot behavior, and it does not own `last-goal.md`; it can only provide a draft store beside it.)

**3. The backlog has no schema, so "what's left?" has no canonical source (ID-006 / item c).**
`_meta/BACKLOG.md` existed as a maintainer-facing "v2 candidates" list, explicitly not an active tracker. The 2026-05-20 restructure bootstrapped an Active-queue tier by hand (ID-001..ID-008), but its schema, status vocabulary, and the session-start read are not specified. Without that, the orchestration spine (ID-007/SPEC-006) has nothing well-defined to read when the user asks "what's left to do?".

These are one problem in three parts: **the kit's state model**. What is committed vs ephemeral, where each store lives, and how the readers detect them.

```
_meta/BACKLOG.md          committed queue        "what's left"     (ID-006)
   | pick an item
.claude/goals/<slug>.md   ephemeral drafts       "what's active"   (ID-005)
   | the user runs the built-in /goal with the draft text
.claude/last-goal.md      the built-in's single active slot  (kit does NOT write this)
docs/specs/SPEC-NNN-*.md  committed designs      "the contract"    (ID-004 detection)
```

## Decision: chosen version

**Specify the three-store state model and wire the readers to it: (1) dual-mode spec detection so the hooks and commands see whichever convention the repo uses, with a no-silent-wrong-pick selection rule; (2) a `.claude/goals/` draft-store CONTRACT beside the built-in `/goal`'s single active slot (the command + the /start-/next rendering are deferred to SPEC-006); (3) a formalized `_meta/BACKLOG.md` Active-queue schema. Plus a leakage audit that fixes only the genuinely-wrong kit-on-kit `.planning/` references, leaving the downstream convention intact.**

### Part 1: Dual-mode spec detection (ID-004)

One detection order, used by every spec-reader (`context-readiness.sh`, `spec-drift-guard.sh`, `commands/next.md`, `commands/start.md`):

```
1. If docs/specs/SPEC-*.md exists -> primary mode (kit + downstream, ADR-0010):
     candidates = specs whose `Status:` line exists AND does NOT start with
                  "SHIPPED" or "PARKED" (prefix test, so `Status: SHIPPED (v1.6.0)`
                  is excluded; a file with no parseable Status line is skipped,
                  not treated as live)
     - exactly 1 candidate  -> use it.
     - more than 1 candidate -> prefer the candidate whose slug matches the current
                                git branch name (slug tokens appear in the branch).
                                If zero or multiple still match, emit
                                `spec:ambiguous(SPEC-00X,00Y,...)` and suggest the
                                maintainer disambiguate. NEVER silently pick one.
     - 0 candidates (all SHIPPED/PARKED) -> fall through to step 2.
2. Else if .planning/SPEC.md exists -> legacy deprecation fallback (removed next
     minor, ADR-0010); use it AND emit a deprecation warning. (downstream mid-migration)
3. Else                             -> no spec; suggest /user:think then /user:spec.
```

This is "Detect, don't dictate" applied to spec selection: among the unified `docs/specs/` specs the reader picks by branch and refuses to guess when intent is genuinely ambiguous. `docs/specs/` is primary for both the kit and downstream (ADR-0010); `.planning/SPEC.md` remains only as a bounded deprecation fallback (step 2, removed next minor). The interim "highest-NNN" selector SPEC-010 shipped is replaced here by branch-match-else-ambiguous.

**`spec-drift-guard` greps the UNION of all non-SHIPPED/PARKED specs in `docs/specs/`**, not a single chosen one. A file referenced in ANY active design is "known" (matching the legacy dir-wide `grep -rq "$PLAN_DIR/"` semantics). Scoping to non-SHIPPED/PARKED specs avoids both the false-positive storm of single-spec narrowing (a file for SPEC-004 flagged while you work SPEC-005) and the "grep everything, nothing drifts" failure of including SHIPPED specs.

**Why edit hooks when SPEC-003 cut a hook edit.** SPEC-003 DEC-002 cut a hook edit because it was a cosmetic delivery channel for a doc and carried abort risk. This edit is different: it fixes a real correctness bug (the interim "highest-NNN" selector mis-routes when more than one spec is live). The two latent `set -euo pipefail` abort bugs SPEC-005 originally bundled here were **already fixed by ID-013** (the `|| true` guards on the count + find pipelines); TASK-1a no longer touches them, only preserves them. `spec-drift-guard.sh` has NO `set -e`; it must NOT be blanket-retrofitted with one (that would turn previously-harmless non-zero greps into aborts); its only change is the union-grep scoping above. The edit is justified by the selector bug, implemented per-hook, not blanket.

### Part 2: `.claude/goals/` draft-store contract (ID-005)

`.claude/` is already fully gitignored (`.gitignore:10`), so goal drafts are per-machine and never pollute version control (correct: half-baked goals are not shared artifacts). Layout:

```
.claude/goals/
  <slug>.md           one goal draft (frontmatter: slug, target_spec/id, status, created;
                      body = the goal text to run through the built-in /goal)
  INDEX.md            a DERIVED cache (one row per draft), rebuilt from the *.md files;
                      the filesystem (ls .claude/goals/*.md) is the source of truth
.claude/last-goal.md  the built-in /goal's single active slot. The kit NEVER writes,
                      parses, or rewrites this file. It is shown for context only.
```

- **The kit owns the draft store, not activation.** The kit writes `.claude/goals/<slug>.md` files and the derived `INDEX.md`. It does NOT write `last-goal.md`. "Activating" a draft means the maintainer runs a goal-loop activator with that draft's body (the built-in `/goal` if present, else the `ralph-loop` plugin or the `goal-craft` skill); the activator writes `last-goal.md` + installs the Stop hook. This honors the no-shadow rule and keeps the kit on the integration side of "External tools are dependencies, not features."
- **A goal-loop activator is a precondition with graceful degradation.** The activator may be the built-in `/goal` (if installed), the `ralph-loop` plugin, or the `goal-craft` skill; the kit detects what is available and feeds the draft to it. If none is present, the drafts still work as plain reusable files (the maintainer pastes the body wherever); the kit loses only the one-step activation, not the draft store. The kit treats `last-goal.md`'s path/format as an external contract it cannot version (Known limitation 2).
- **Brainstorm many, one active.** Drafts accumulate in `.claude/goals/`; the built-in's single active slot is respected, not fought. Each draft carries a `target_spec`/`id`, the seam SPEC-006 will use.
- **Deferred to SPEC-006:** the `/user:goals` command (list/new/switch) and the wiring that makes `/user:start`/`/user:next` render the queue + drafts. Those have their real consumer (the orchestration spine) in SPEC-006; building them here would be a phantom feature (DEC-010). SPEC-005 ships the CONTRACT only.

### Part 3: `_meta/BACKLOG.md` Active-queue schema (ID-006)

Formalize the bootstrapped shape:
- **Columns:** `ID | Title | Source | Target artifact | Lane | Status`.
- **IDs:** `ID-NNN`, stable, never reused.
- **Status lifecycle:** `queued -> speccing -> validated -> executing -> shipped`. SHIPPED items drop off (CHANGELOG is the canonical shipped record).
- **Lane:** the WORKFLOW.md risk tier (`tiny / normal / full`).
- **Intended consumer:** `/user:start`/`/user:next` will surface the queue when the user asks "what's left?". That rendering is **wired in SPEC-006**, not here (DEC-011); SPEC-005 only pins the schema the spine reads.

**Three stores, not confused with each other:**

| Store | Committed? | Lifetime | Role |
|---|---|---|---|
| `_meta/BACKLOG.md` | yes (git) | durable | the queue of committed work (what's left) |
| `.claude/goals/<slug>.md` | no (gitignored) | ephemeral | candidate goal drafts (what's active) |
| `docs/specs/SPEC-NNN` | yes (git) | durable | the design contract per cycle |
| `TODOS.md`, `REVIEW.md` | no (gitignored) | transient | per-diff `/review` output; NOT the backlog |

`TODOS.md` already exists as a gitignored per-diff review artifact (`.gitignore:16`). It is not the backlog and must not be conflated; the schema doc states this.

### Tradeoff table (key forks)

| Fork | CHOSEN | Rejected alt |
|---|---|---|
| Spec location | docs/specs primary (ADR-0010) + `.planning` deprecation fallback | (A) `.planning`-first precedence: reverts ADR-0010's unification. (B) env var `DWARVES_KIT_SPEC_DIR`: speculative config. (C) docs-only, no wiring: leaves the selector bug unfixed. |
| Multi-spec selection | branch-match, else emit ambiguous (never guess) | (A) highest-SPEC-NNN-wins: picks the wrong spec whenever >1 DRAFT exists (the current state). (B) tie to goal pointer: over-couples SPEC-005 to SPEC-006. |
| Goal piece scope | ship the draft-store CONTRACT only; command + rendering -> SPEC-006 | (A) ship `/user:goals` now: phantom feature (consumer unbuilt), fails 2-phase gate. (B) reimplement `/goal`: shadows the built-in. |
| Backlog home | promote `_meta/BACKLOG.md` to active queue | (A) a second root queue file: two stores to sync. (B) derive from git+spec status only: no durable queue for unspecced items. |

### NO-list check
One-sentence descriptions (gate 4):
- *"Spec-readers select among `docs/specs/` specs by branch (ADR-0010 unified location), fall back to legacy `.planning/`, and refuse to guess when ambiguous."*
- *"`.claude/goals/` holds multiple goal drafts beside the built-in's single active `last-goal.md`, which the kit never writes."*
- *"`_meta/BACKLOG.md`'s Active queue is the canonical list of what's left, with stable ids and a status lifecycle."*

| Gate | Compliance |
|---|---|
| Bash over binaries | ✓ hook edits stay bash+jq; context-readiness `set -e` aborts already fixed (ID-013); spec-drift-guard not retrofitted; under 500ms |
| Serves 2+ phases | ✓ detection serves Spec/Build/Review; backlog serves Reflect/Think. (The goal piece is a CONTRACT/convention, not a command; the command's phase-justification is deferred to SPEC-006 where it has a consumer.) |
| Detect, don't dictate | ✓ detection suggests, never blocks; refuses to guess rather than mis-route |
| Synthesize, don't originate | **✓-with-caveat.** Dual-detect extends the CCGS `/start` single-file state pattern, but the multi-file newest/branch selection and the goal-draft-store directory are net-new, single-source, and have NOT met the §5 "1 week on a real project" bar. Recorded in Known limitations, not hidden (matching SPEC-003 DEC-003's honesty). |
| One sentence describable | ✓ (above) |
| No speculative config | ✓ no env var, no flag (env-var alt rejected); no command shipped ahead of its consumer |

## Solution

| Task | Files | Type | Depends on |
|---|---|---|---|
| TASK-1a | `hooks/context-readiness.sh`, `hooks/spec-drift-guard.sh` (+ the shared detection rule) | Hook detection + bug fix | - |
| TASK-1b | `commands/next.md`, `commands/start.md` | Command detection prose | TASK-1a (the rule it cites) |
| TASK-2 | Leakage audit: kit-on-kit prose in `CLAUDE.md`, `WORKFLOW.md`, `docs/architecture.md`, `docs/decisions/0002-*` | Doc clarity (scoped) | TASK-1a |
| TASK-3 | `.claude/goals/` contract in `WORKFLOW.md` + a new `docs/decisions/00NN-goal-registry.md` (number pinned at execute) | Goal-store contract | - |
| TASK-4 | `_meta/BACKLOG.md` schema section + state-model section in `docs/architecture.md` | Backlog schema + state model | TASK-1a, TASK-3 (state-model references both) |
| TASK-5 | `tests/test-hooks.sh` + `tests/test-meta.sh` + `README`/`MANUAL`/`CHANGELOG` | Tests + hygiene | TASK-1..4 |

### Task Breakdown

**Phase 1: Detection (the bug fix)**
- [x] **TASK-1a: Branch-match selection + union drift-grep in the two hooks (reconciled with ADR-0010).** Replace the interim "highest non-SHIPPED/PARKED NNN" selector SPEC-010 shipped with the Part 1 rule (collect all non-SHIPPED/PARKED `docs/specs/` candidates; 1 -> use it; >1 -> branch-match; ambiguous -> emit `spec:ambiguous(...)`, pick none) in `context-readiness.sh`, and the union-grep (a file in ANY non-SHIPPED/PARKED spec is "known") in `spec-drift-guard.sh`. Keep the ADR-0010 order: `docs/specs/` primary, `.planning/` deprecation fallback. The two `set -euo pipefail` abort bugs this task originally bundled are ALREADY FIXED by ID-013 (`|| true` guards on the count + find pipelines); do not re-do them, just preserve them.
  Acceptance (one checkbox each):
  - [x] `.planning/SPEC.md` fallback still resolves WITH a deprecation warning when no `docs/specs/` candidate exists
  - [x] `Status: SHIPPED (v1.6.0)` is correctly excluded (prefix match), verified by fixture
  - [x] with 3 non-SHIPPED specs and no branch match, emits `spec:ambiguous(...)`, picks none
  - [x] with a branch whose name contains a spec slug, selects that spec
  - [x] `spec-drift-guard` greps the union of non-SHIPPED specs; a file in any of them is "known"
  - [x] `context-readiness.sh` emits valid JSON and exits 0 on every fixture: empty `docs/specs/`, all-SHIPPED, zero-task spec, zero source files, both dirs present (exactly one `spec:` token)
  - [x] both hooks under 500ms at the current spec count; dir-size assumption stated
- [x] **TASK-1b: Dual-mode detection in the two command dispatchers.** Update `commands/next.md` and `commands/start.md` prose to cite the same detection rule (read `.planning/SPEC.md` first, else the branch-selected non-SHIPPED `docs/specs/` spec, else none).
  - Acceptance: both commands describe the dual-mode order; neither hardcodes `.planning/` as the only path; ambiguous-case behavior described.

**Phase 2: Leakage audit (the clarity fix)**
- [x] **TASK-2: Fix only the wrong kit-on-kit references.** Acceptance is grep-checkable: `grep -rn '\.planning/'` over the kit-on-kit doc set (NOT `examples/hello-spec/`, NOT the hooks' downstream branch) returns only references on a documented downstream-facing allowlist; every other hit is corrected to `docs/specs/`. Add one sentence to ADR-0002 + `WORKFLOW.md` that detection is dual-mode.
  - Acceptance: the grep audit passes against the stated allowlist; ADR-0002 + WORKFLOW.md state dual-mode; `examples/hello-spec/` untouched.

**Phase 3: Goal-store contract**
- [x] **TASK-3: `.claude/goals/` contract + ADR.** Document the layout, per-draft frontmatter, INDEX-as-derived-cache (filesystem authoritative), the "kit never writes `last-goal.md`" rule, the built-in-`/goal` precondition + graceful degradation, in `WORKFLOW.md` (goal-state subsection) and a new ADR (`docs/decisions/00NN-goal-registry.md`, number pinned at execute time to avoid a clash with SPEC-006's ADR). Confirm `.claude/goals/` is covered by the existing `.claude/` gitignore (`git check-ignore` returns `.gitignore:10`).
  - Acceptance: contract documented; ADR records "draft store beside the built-in, not a shadow, kit never writes last-goal.md" + the external-dependency limitation; gitignore coverage confirmed by command output; NO command and NO /start-/next wiring in this spec (deferred to SPEC-006).

**Phase 4: Backlog schema + state model**
- [x] **TASK-4: Formalize the queue + the state model.** Add a "Schema" subsection to `_meta/BACKLOG.md` pinning columns, the `ID-NNN` rule, the status lifecycle, the lane mapping. Add a "State model" section to `docs/architecture.md` with the three-store table and the `TODOS.md`-is-not-the-backlog clarification. State that `/user:start`/`/user:next` rendering of the queue is wired in SPEC-006.
  - Acceptance: BACKLOG schema pinned; architecture state-model section present; the BACKLOG/TODOS.md/goals distinction stated; the "rendering wired in SPEC-006" note present.

**Phase 5: Verify + hygiene**
- [x] **TASK-5: Tests + cross-refs.** `tests/test-hooks.sh`: fixtures for kit-on-kit detection (only `docs/specs/SPEC-001-x.md`, asserts `spec:` + `next:`), the `SHIPPED (vX)` exclusion, the ambiguous-multi-spec case, and the abort-path fixtures (empty dir, all-SHIPPED, zero-task, zero-source) asserting exit 0 + valid JSON. Use `mktemp -d`, trap cleanup, no fixture in the repo. `tests/test-meta.sh`: assert `_meta/BACKLOG.md` has Active-queue + Schema sections, `docs/architecture.md` has the state-model section, the goal-registry ADR exists. README/MANUAL note the dual-mode detection. CHANGELOG entry.
  - Acceptance: `bash tests/test-hooks.sh` passes incl. the new detection + abort-path tests (count rises from 42); `bash tests/test-meta.sh` passes (count rises by the documented delta); CHANGELOG entry.

## Acceptance Criteria (global)
- [x] All four spec-readers detect both conventions; downstream path unchanged; kit-on-kit path works
- [x] Selection excludes `SHIPPED*`, prefers branch match, emits ambiguous rather than guessing; drift-guard greps the union of non-SHIPPED specs
- [x] `context-readiness.sh` exits 0 + valid JSON on all abort-path fixtures (its two latent bugs fixed)
- [x] No kit-on-kit prose misroutes to `.planning/`; downstream references intact (grep audit passes)
- [x] `.claude/goals/` draft-store contract + ADR documented; kit never writes `last-goal.md`; built-in-`/goal` precondition + degradation stated; gitignored via existing rule
- [x] NO `/user:goals` command and NO /start-/next rendering in this spec (deferred to SPEC-006)
- [x] `_meta/BACKLOG.md` schema pinned; `docs/architecture.md` state-model section present; TODOS.md distinction stated
- [x] `bash tests/test-hooks.sh` passes incl. new tests; hooks under 500ms; `bash tests/test-meta.sh` passes (new count documented)
- [x] No new dependency, env var, or settings.json field; no new gitignore line
- [x] CHANGELOG entry

## Known limitations
1. **The multi-spec selection rule and the goal-draft-store directory are net-new, single-source, and have not met the PHILOSOPHY §5 "1 week on a real project" bar.** They extend cited patterns (CCGS `/start` single-file detection; a draft store beside an external single-slot tool) but the specific multi-file/branch selection and the directory format are originated here. Accepted under the indirect-lineage carve-out and labeled, not hidden (mirrors SPEC-003 DEC-003).
2. **The goal store depends on the built-in `/goal`'s `last-goal.md` path/format/Stop-hook contract, which the kit cannot version.** If Claude Code changes that contract, activation degrades to manual (the drafts still work as files). The kit mitigates by never reading/writing `last-goal.md` itself.
3. **`switch` semantics (deferred to SPEC-006) are unsafe mid-loop.** Re-running the built-in `/goal` while a Stop-hook goal is actively iterating re-points the active slot; the prior goal's progress is not migrated, only its draft is preserved. SPEC-006 must warn on this.

## Edge Cases
1. **Both `docs/specs/` and `.planning/SPEC.md` exist.** Step 1 wins (`docs/specs/` is primary, ADR-0010); the `.planning/` fallback is in the `else` only, so exactly one `spec:` token is emitted (asserted in TASK-5).
2. **`docs/specs/` has only SHIPPED specs.** 0 candidates; detection falls through to step 3 ("no spec, consider /user:think"). Correct for a fully-shipped repo. (This is the current near-future state; tested.)
3. **More than one non-SHIPPED spec** (the state today: SPEC-004/005/006). Branch-match selects if the branch names a slug; otherwise `spec:ambiguous(...)` is emitted and nothing is auto-picked. drift-guard greps the union, so no false positives across the open set.
4. **A spec with no parseable `Status:` line.** Skipped (not treated as a live candidate); the schema (TASK-4) requires a Status line and TASK-5 can assert it.
5. **`spec-drift-guard` greps a multi-task spec** that legitimately omits a new helper file. Same known grep limitation as today (documented in the hook header); warns, never blocks.
6. **Goal slug collision** in `.claude/goals/`. The filesystem is the source of truth; a new draft refuses to overwrite an existing `<slug>.md`. INDEX.md is rebuilt from the files, so a hand-deleted INDEX self-heals on the next `list` (in SPEC-006).
7. **`.claude/goals/` on a fresh machine.** Absent until first use; no hook depends on it existing.

## Out of Scope
- The `/user:goals` command and the `/user:start`/`/user:next` queue+draft rendering: deferred to SPEC-006 (their consumer, the orchestration spine, lives there).
- The orchestration loop that consumes this state (pick item -> craft goal -> activate -> run WORKFLOW): SPEC-006.
- Reimplementing or shadowing the built-in `/goal`.
- Committing goal drafts to git (intentionally ephemeral/per-machine).
- Re-introducing `.planning/`-first precedence or migrating away from the unified `docs/specs/` (ADR-0010 stands; ADR-0002 superseded).
- A `DWARVES_KIT_SPEC_DIR` env var (speculative config).
- Multi-session concurrent active goals (the kit is one-session).

## Decision Log
- **DEC-001**: Dual-detect with `.planning/` precedence, not a migration. Fixes the kit-on-kit blindness bug while keeping ADR-0002 and downstream unchanged.
- **DEC-002**: Hooks ARE edited here (unlike SPEC-003 DEC-002). This is a correctness bug fix, not a cosmetic delivery channel; implemented per-hook (see DEC-013).
- **DEC-003**: Goal state is a draft store BESIDE the built-in, not a replacement. The built-in owns activation via `last-goal.md`; the kit never writes it.
- **DEC-004 (revised)**: The kit does NOT write/parse/rewrite `last-goal.md`. Activation = the maintainer runs the built-in `/goal` with a draft body. Resolves the "kit treats an undocumented internal as a public API" finding (assumption-destroyer C4).
- **DEC-005**: `.claude/goals/` gitignored via the existing `.claude/` rule (`.gitignore:10`), confirmed by `git check-ignore`; no new gitignore line.
- **DEC-006**: `_meta/BACKLOG.md` promoted to the active queue (one store, avoids translation drift).
- **DEC-007**: `TODOS.md` is explicitly NOT the backlog (gitignored per-diff `/review` output).
- **DEC-008 (validation)**: SHIPPED test is a **prefix match** (`SHIPPED*`), not exact equality. Rationale: shipped specs write `Status: SHIPPED (v1.6.0)`; exact match misclassified them as live (assumption-destroyer + failure-mode + philosophy C1).
- **DEC-009 (validation)**: Multi-spec selection is **branch-match, else emit ambiguous, never silently pick highest-NNN**. Rationale: three DRAFTs are live now; highest-NNN picks SPEC-006 while the maintainer works SPEC-005, mis-routing the drift-guard (assumption-destroyer + failure-mode C2; maintainer decision 2026-05-20).
- **DEC-010 (validation)**: `spec-drift-guard` greps the **union of non-SHIPPED specs** in kit-on-kit mode. Rationale: single-spec narrowing causes a false-positive storm across simultaneously-open specs; including SHIPPED specs would defeat the guard (failure-mode C3).
- **DEC-011 (validation)**: The `/user:goals` command and the `/start`-`/next` queue rendering are **cut from SPEC-005 and deferred to SPEC-006**. Rationale: their consumer (the spine) is unbuilt, so shipping them here is a phantom feature that also fails the 2-phase gate (scope-critic + philosophy C7; maintainer decision 2026-05-20). SPEC-005 ships the draft-store CONTRACT only.
- **DEC-012 (validation)**: TASK-1 **split** into TASK-1a (hooks + inherited-bug fixes) and TASK-1b (command prose); per-task checkbox ACs. Rationale: four readers with four edit models + a selector + a run-on AC violated the atomicity heuristic (scope-critic C5).
- **DEC-013 (validation)**: `set -e` discipline is **per-hook**: `context-readiness.sh` has `set -euo pipefail` AND two latent abort bugs that TASK-1a must fix; `spec-drift-guard.sh` has no `set -e` and must NOT be retrofitted (its fix is the union-grep scope). Rationale: the blanket "same `set -e` discipline" misdescribed spec-drift-guard (failure-mode C6 + philosophy W1).
- **DEC-014 (validation)**: Synthesize-row downgraded to **✓-with-caveat** + a Known-limitations section added. Rationale: the registry + multi-file selection are net-new/single-source; SPEC-003 set the precedent of labeling, not hiding, this gap (philosophy C8).
- **DEC-015 (validation)**: The "Read by `/user:start`+`/user:next`" claim **downgraded to "intended consumer, wired in SPEC-006"**. Rationale: no SPEC-005 task built that rendering (assumption-destroyer W3).
- **DEC-016 (validation)**: INDEX.md is a **derived cache**; the filesystem (`ls .claude/goals/*.md`) is authoritative. Rationale: a slash command is not transactional; INDEX can diverge and must self-heal (failure-mode W2).
- **DEC-017 (validation)**: The goal-registry ADR **number is pinned at execute time**, not draft time. Rationale: SPEC-005 and SPEC-006 are drafted concurrently and could both claim 0010 (philosophy W3).
- **DEC-018 (cross-spec, from SPEC-006 validation)**: The activation handoff names a goal-loop *activator* (built-in `/goal` / `ralph-loop` / `goal-craft`), detected at runtime, not a guaranteed built-in `/goal`. Rationale: `/goal` is not confirmed present in the environment (SPEC-006 assumption-destroyer finding); the kit must not assume a specific activator.
- **DEC-019 (reconciliation, 2026-05-21)**: SPEC-010/ADR-0010 shipped after SPEC-005 was validated, superseding ADR-0002 and unifying the spec location onto `docs/specs/`. Part 1's detection ORDER is therefore inverted from the original `.planning`-first to **docs/specs-first, `.planning` as a bounded deprecation fallback**; the branch-match SELECTION rule within `docs/specs/` (DEC-009) is retained as the still-valid core (it replaces the interim "highest-NNN" selector SPEC-010 shipped). The two `context-readiness.sh` abort bugs (DEC-013) were already fixed by ID-013, so TASK-1a no longer touches them. Edits: Part 1 order, the "why edit hooks" note, the tradeoff / NO-list / out-of-scope ADR refs, Edge case 1, and TASK-1a scope. No reviewer re-run: the change narrows scope and aligns to already-shipped behavior; the design's risk surface did not grow.

## Source citations
- Convention split: `docs/decisions/0002-planning-dir-convention.md` + `docs/specs/README.md`.
- State-detection pattern extended to dual-mode: `commands/start.md` / CCGS `/start` router (PHILOSOPHY §1).
- Goal draft store beside an external single-slot tool: the built-in `/goal` + the user-level `goal-craft` skill it wraps.
- Backlog schema shape: `ops-toolkit/_meta/BACKLOG.md` + ADR-style stable ids.
- Hooks/commands current behavior + the two latent abort bugs: `hooks/context-readiness.sh`, `hooks/spec-drift-guard.sh`, `commands/next.md` (read + reproduced 2026-05-20).

## Validation
4 reviewers run 2026-05-20 (scope-critic, assumption-destroyer, failure-mode, philosophy-fidelity). Aggregate pre-fix verdict: NEEDS REVISION.

Critical concerns, all resolved inline:
- `SHIPPED (vX)` defeats exact-match filter -> prefix match (DEC-008).
- highest-NNN picks the wrong live spec -> branch-match-else-ambiguous (DEC-009).
- single-spec drift-grep -> union of non-SHIPPED specs (DEC-010).
- built-in `/goal` treated as owned/stable API -> kit never writes `last-goal.md`, precondition + degradation (DEC-004, Known limitation 2).
- TASK-1 non-atomic -> split + checkbox ACs (DEC-012).
- latent `set -e` aborts in `context-readiness.sh` -> fixed in TASK-1a with abort-path fixtures (DEC-013, C6).
- `/user:goals` phantom/scope-creep -> command + rendering deferred to SPEC-006 (DEC-011).
- unqualified "✓ Synthesize" -> ✓-with-caveat + Known limitations (DEC-014).

Warnings addressed: per-hook `set -e` language (DEC-013); "read by /start-/next" downgraded (DEC-015); INDEX derived cache (DEC-016); ADR number pinned (DEC-017); dependency declarations added to the Solution table; switch-mid-loop recorded as Known limitation 3.

Status flipped to VALIDATED after inline resolution. Re-run `/user:spec-validate` if the design changes materially before execute.

**Post-validation reconciliation (2026-05-21):** the design was realigned to ADR-0010 (see DEC-019). This narrows scope (drops the `.planning`-precedence order + the already-done abort fixes) and aligns to shipped behavior; it does not expand the risk surface, so a full reviewer re-run was not triggered. Status remains VALIDATED.
