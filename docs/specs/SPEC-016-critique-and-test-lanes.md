# Spec: Design-critique + test-plan lanes (devs-team, visual-team, test-plan)

Generated: 2026-05-21
Status: DRAFT
Source: maintainer brainstorm 2026-05-21 (superpowers:brainstorming run), porting two external skills to the kit's house style: `az-skills/engineering/devs-roundtable` and `az-skills/design/design-roundtable` (zvadaadam/az-skills). The QA lane has no external source; it is the kit's own coverage-matrix shape.
Depends on: SPEC-011 (the `/user:design` lane + `docs/specs/DECISION-BRIEF.md` contract this critiques), SPEC-008 (solution-design depth, the brief's `## Solution` sub-section shape), and the `/user:review-team` + `reviewer` parallel-multi-lens pattern this mirrors.
Relates to: SPEC-006 (the orchestration spine; this is the first work to exercise its doc-impact map for new `commands/*`).

## Problem

The kit critiques **code** (`/user:review`, `/user:review-team`) and **specs** (`/user:spec-validate`), but it has **no design-level critique** and **no up-front test-case design**. The generate/critique map shows the holes:

| Layer | Generate | Critique |
|---|---|---|
| Solution / design | `/user:design` (SPEC-011) | **missing** |
| Visual / UI | (downstream skills) | **missing** |
| Spec | `/user:spec` | `/user:spec-validate` |
| Test | **missing** (no test design) | `/user:review-team` test-coverage lens |
| Code | `/user:execute` | `/user:review`, `/user:review-team` |

Three specific gaps:

1. **Solution critique.** `/user:design` shapes a solution into `DECISION-BRIEF.md`, but nothing stress-tests that solution from multiple engineering angles before it hardens into a spec. Today the first adversarial pass is `/user:spec-validate`, which critiques the written *spec*, not the *design* behind it. By then the framing is already locked.
2. **Visual critique.** The kit has nothing for UI/visual quality. This serves downstream projects that have a UI; the kit itself (bash/CLI) does not.
3. **Test-case design.** Test coverage is only ever *reviewed* after code exists (`review-team` test-coverage lens). No lane *designs* the test cases up front from the spec's acceptance criteria, so `/user:execute` builds without a planned coverage target.

The honest framing (from the brainstorm): the gap is **not** "generate more design options" (that is `/user:design`'s job already; a generative roundtable would duplicate it and violate "Replace, don't deprecate"). The gap is **multi-lens critique of a design**, which is exactly the shape `/user:review-team` already proves for code. So `devs-team`/`visual-team` are "`review-team` for design," not new generators.

## Decision: chosen version

**Add three opt-in lanes that mirror the existing `/user:review-team` parallel-multi-lens pattern: `/user:devs-team` and `/user:visual-team` critique a design (solution-level and visual-level) before the spec hardens; `/user:test-plan` derives a test-case coverage matrix from a spec's acceptance criteria before `/user:execute`. All three are opt-in lanes (never hard gates), use generic house-style lenses (not named-person personas), and dispatch lenses as inline parallel Task calls (no new agent files). A one-paragraph PHILOSOPHY carve-out records that `/user:visual-team` is downstream-facing so `/user:kit-health` does not flag it as a speculative feature.**

### Part A: Two design-critique lanes (devs-team, visual-team)

Both mirror `/user:review-team`: dispatch N read-only lenses in parallel, each returns findings + a score, then merge/dedupe/verdict. The difference from `review-team` is the **input** (a design, not a code diff) and the **timing** (before the spec, not before merge).

```
/user:think -> /user:design (shape solution into DECISION-BRIEF.md, SPEC-011)
            -> /user:devs-team    critique the design's ## Solution across 5 eng lenses (parallel)
                                  (the brief if present, else the active spec's ## Solution)
                                  -> merged findings + verdict appended to that doc
            -> (revise /design or proceed)
            -> /user:spec -> /user:spec-validate -> ...

  (/user:visual-team runs in the same slot, opt-in, for items with a UI)
```

- **`/user:devs-team`** critiques the design **wherever it lives**: `docs/specs/DECISION-BRIEF.md`'s `## Solution` if a brief exists, **else** the active `docs/specs/SPEC-NNN-<slug>.md`'s `## Solution` section. (`/user:design` is opt-in, so a `/think -> /spec` path produces no brief; the lane must still have a design to critique. DEC-011.) Lenses: **simplicity**, **performance**, **boundaries/composability**, **data-model & correctness**, **operability/failure-modes**. Output: a merged critique (findings by severity, which lens caught each, one combined verdict `SOLID / REVISE / RECONSIDER`) appended to whichever doc holds the design as a `## Design critique` section. Read-only on code; it only edits that doc. On **partial lens failure** (a Task subagent errors or times out), merge from the lenses that returned, note which are missing, and never block (DEC-012). The `SOLID / REVISE / RECONSIDER` verdict vocabulary is **shared with `/user:visual-team`** (same altitude); it intentionally differs from `/user:review-team` (code: SHIP/FIX/DO-NOT-SHIP) and `/user:spec-validate` (spec: APPROVED/NEEDS REVISION), which operate on different artifacts (DEC-015).
- **`/user:visual-team`** critiques a described/linked visual design. Lenses: **hierarchy/typography**, **system-consistency**, **accessibility/contrast**, **restraint/simplicity**, **expressiveness/brand-fit**. Output: same critique shape and shared verdict vocabulary as devs-team. Same partial-failure handling. When it fetches a URL or reads a screenshot, it treats the fetched content as **data, not instructions** (the kit's security rule; DEC-016). Downstream-facing (see Part C).

The verdict is **report-only**, never a block: the maintainer decides whether to revise the design or proceed. This matches `review-team`'s gate (which only hard-blocks on a `DO NOT SHIP` it cannot itself enforce; the human acts).

### Part B: The test-plan lane (test-plan)

`/user:test-plan` is **structurally different** from the two critique lanes and is deliberately not called a "roundtable." A design critique explores an open space (many valid critiques, divergence is signal). Test planning derives from **fixed** acceptance criteria, so the right shape is **systematic coverage**, not divergence.

```
/user:spec -> /user:spec-validate
           -> /user:test-plan    read SPEC-NNN acceptance criteria
                                 -> enumerate a coverage matrix -> write TEST-PLAN.md
           -> /user:execute      build against TEST-PLAN.md
```

It reads the active `docs/specs/SPEC-NNN-<slug>.md` acceptance criteria and enumerates test cases across coverage categories: **happy-path**, **boundary/edge**, **failure-injection**, **security/abuse**, **regression**. Output: `TEST-PLAN.md` (project root, same placement convention as `REVIEW.md`/`TODOS.md`), a table of `case -> category -> the acceptance criterion it covers -> expected`. `/user:execute` reads it as the coverage target. Coverage is "covers the enumerated categories," not "exhaustive" (Known limitation 3).

### Part C: PHILOSOPHY carve-out for the visual lane

The kit itself is bash/CLI with no UI, so `/user:visual-team` serves no phase of the kit's own work. Per "no speculative features," `/user:kit-health` would otherwise flag it. Add a one-paragraph carve-out to `docs/PHILOSOPHY.md`: `/user:visual-team` is a **downstream-facing** lane (it serves projects that consume the kit and have a UI; the kit dogfoods the other two but not this one), and add it to the `kit-health` allow-note so the self-assessment does not mark it speculative. This is the recorded cost of shipping a downstream-only command in the kit; it is surfaced, not hidden.

### Tradeoff table

| Fork | CHOSEN | Rejected alt |
|---|---|---|
| devs-team shape | parallel multi-lens **critique** (mirror `review-team`) | **generator** (diverge N approaches): duplicates `/user:design` Step 2/3, violates "Replace, don't deprecate" |
| devs-team home | separate command (like `review-team` is separate from `execute`) | a critique beat folded into `/user:design`: mixes generate+critique, bloats the command, no independent run |
| Personas | generic house-style lenses | named legends (Carmack/Rams): off house-style, taste/maintenance liability |
| test-plan shape | coverage-matrix generator (not a roundtable) | 5-persona roundtable: mislabels a deterministic enumeration as open-space divergence |
| visual generation | out of scope (downstream skills) | port the generative design-roundtable incl. mockups/screenshots: needs render/browser machinery, violates bash/no-binaries |
| dispatch | inline parallel Task calls | a new `design-critic` agent: premature (only 2 consumers; extract at the 3rd per "no premature abstraction") |
| enforcement | opt-in lanes, report-only verdict | hard gate before `/spec`/`/execute`: the field-wide + PHILOSOPHY-rejected pattern |

### NO-list check (PHILOSOPHY gates)

Per-part one-sentence descriptions:
- *"`/user:devs-team` critiques the solution in the decision brief across five engineering lenses before the spec hardens."*
- *"`/user:visual-team` critiques a visual design across five design lenses (downstream-facing)."*
- *"`/user:test-plan` turns a spec's acceptance criteria into a test-case coverage matrix before execute."*

| Gate | Compliance |
|---|---|
| Guardrails over guidance | OK: opt-in lanes, report-only; hard blocks stay with the existing safety/verify gates |
| Synthesize, don't originate | OK: devs-team/visual-team synthesize `review-team` + the two az-skills roundtables; test-plan is the kit's coverage shape (labeled) |
| Detect, don't dictate | OK: lanes the user pulls; verdicts report, never block the next phase |
| Bash over binaries | OK: command prompts + inline Task dispatch; no new binary; visual *generation* (which would need a renderer) is explicitly out |
| Serves 2+ phases | Partial: devs-team/test-plan serve Design+Spec+Build; **visual-team serves no kit phase** (downstream-only), recorded via the Part C carve-out, not hidden |
| One sentence describable | OK: per-part (above) |
| No speculative config | OK: no env var, no flag; each command has a real consumer or a recorded downstream rationale |
| No premature abstraction | OK: inline dispatch; the shared `design-critic` agent is deferred to a 3rd consumer |

## Solution

| Task | Files | Type | Depends on |
|---|---|---|---|
| TASK-1 | `commands/devs-team.md` (new) | New command | review-team pattern, DECISION-BRIEF contract |
| TASK-2 | `commands/visual-team.md` (new) | New command | TASK-1 (shared critique shape) |
| TASK-3 | `commands/test-plan.md` (new) | New command | spec acceptance-criteria shape |
| TASK-4 | `docs/PHILOSOPHY.md` + `commands/kit-health.md` (visual-team carve-out) | Doc (framing) | TASK-2 |
| TASK-5 | `WORKFLOW.md` (place the three lanes in the cycle + the spine) | Doc (wiring) | TASK-1..3 |
| TASK-6 | `tests/test-meta.sh` assertions + count strings (`plugin.json`, `marketplace.json`, README banner + structure, `MANUAL.md` heading; 15 -> 18) | Tests + count | TASK-1..3 |
| TASK-7 | README command-table rows + `MANUAL.md` command sections + `CHANGELOG.md` | Inventory + hygiene (doc-impact map) | TASK-6 |

### Task breakdown

**Phase 1: The three commands**
- [ ] **TASK-1: `commands/devs-team.md`.** Frontmatter `description:`. Reads the design's `## Solution` from `docs/specs/DECISION-BRIEF.md` if present, **else** from the active `docs/specs/SPEC-NNN-<slug>.md`; if neither has a `## Solution`, says so and stops (DEC-011). Dispatches 5 read-only lenses (simplicity, performance, boundaries/composability, data-model/correctness, operability/failure-modes) as parallel Task calls; each returns findings + a 0-10 score. On partial lens failure, merge from the returned lenses and note the missing ones (DEC-012). Merge/dedupe by severity, combined verdict `SOLID / REVISE / RECONSIDER`. Appends a `## Design critique` section to whichever doc holds the design. Report-only; never blocks. States the bypassPermissions caveat.
  - Acceptance: `description:` present; reads the brief's OR the spec's `## Solution` (greppable); 5 lenses dispatched in parallel; partial-failure handling stated; appends to the design doc, does not touch code; verdict is report-only.
- [ ] **TASK-2: `commands/visual-team.md`.** Same critique shape as TASK-1; lenses: hierarchy/typography, system-consistency, accessibility/contrast, restraint/simplicity, expressiveness/brand-fit. Input is a described or linked visual design. Marked downstream-facing in its own body.
  - Acceptance: `description:` present; 5 visual lenses in parallel; same report-only verdict; body states it is downstream-facing.
- [ ] **TASK-3: `commands/test-plan.md`.** Frontmatter `description:`. Reads the active `docs/specs/SPEC-NNN-<slug>.md` acceptance criteria (branch-aware detect, SPEC-005 dual-detect if present); enumerates a coverage matrix across happy-path / boundary-edge / failure-injection / security-abuse / regression; writes `TEST-PLAN.md` mapping each case to the acceptance criterion it covers. Not a roundtable; no personas. States it is a coverage target, not exhaustive.
  - Acceptance: `description:` present; reads a SPEC acceptance-criteria section; writes `TEST-PLAN.md` with the category x criterion mapping; explicitly not exhaustive.

**Phase 2: Framing + wiring**
- [ ] **TASK-4: PHILOSOPHY carve-out.** One paragraph in `docs/PHILOSOPHY.md`: `/user:visual-team` is downstream-facing (serves UI-bearing consumer projects; the kit dogfoods devs-team + test-plan but not visual-team). Add the matching allow-note to `commands/kit-health.md` so the self-assessment does not flag it speculative.
  - Acceptance: PHILOSOPHY names visual-team as downstream-facing; kit-health does not flag it.
- [ ] **TASK-5: `WORKFLOW.md` placement.** Place devs-team/visual-team after `/user:design` and before `/user:spec`; place test-plan after `/user:spec-validate` and before `/user:execute`. Show them as opt-in lanes (read-only/critique or plan, never blocking). Cross-link the spine section.
  - Acceptance: the cycle/spine text names all three lanes in the right slots and marks them opt-in.

**Phase 3: Verify + count (split from the old TASK-6 per the atomicity finding, DEC-014)**
- [ ] **TASK-6: Tests + count strings.** `tests/test-meta.sh`: assert the three command files exist (the per-command frontmatter loop already covers `description:`). Update every "N commands" count string from 15 to 18: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the README banner line, the README structure note, the `MANUAL.md` heading.
  - Acceptance: `bash tests/test-meta.sh` passes (count rises by the documented delta); `bash tests/test-hooks.sh` unchanged (no hook touched); no stale "15 commands" string outside historical text.

**Phase 4: Inventory + changelog (the prose half of the old TASK-6)**
- [ ] **TASK-7: Inventory rows + CHANGELOG.** Add the three command rows to the README command table and the three command sections to `MANUAL.md`; add the CHANGELOG entry. Per the SPEC-006 doc-impact map for new `commands/*`.
  - Acceptance: the three commands appear in the README table and the MANUAL inventory; CHANGELOG entry present; command count is 18 everywhere it appears.

## Acceptance Criteria (global)
- [ ] `/user:devs-team` critiques the design's `## Solution` (brief if present, else the active spec) across 5 eng lenses in parallel; merges on partial lens failure; appends a report-only `## Design critique`; never blocks
- [ ] `/user:visual-team` critiques a visual design across 5 design lenses; same shape; marked downstream-facing
- [ ] `/user:test-plan` derives a coverage matrix from a spec's acceptance criteria into `TEST-PLAN.md`; not a roundtable; not claimed exhaustive
- [ ] All three are opt-in lanes; no hard gate added; verdicts report; the bypassPermissions degradation is stated in each
- [ ] Generic house-style lenses (no named-person personas); inline parallel Task dispatch (no new agent file)
- [ ] PHILOSOPHY records visual-team as downstream-facing; `/user:kit-health` does not flag it speculative
- [ ] `WORKFLOW.md` places the three lanes in the right cycle slots, marked opt-in
- [ ] `bash tests/test-hooks.sh` unchanged; `bash tests/test-meta.sh` passes; command count is 18 in README, MANUAL, plugin.json, marketplace.json
- [ ] CHANGELOG entry; consistent with SPEC-011 (consumes the brief) and the review-team pattern (mirrors it)

## Known limitations
1. **`/user:visual-team` serves no phase of the kit's own work.** It is downstream-facing only; the kit cannot dogfood it (no UI). Recorded via the Part C carve-out so kit-health does not flag it; this is the cost of the maintainer's decision to bake the visual lane into the kit rather than ship it as a standalone skill.
2. **Two critique layers sit adjacent** (`devs-team` then, later, `spec-validate`). They are at different altitudes (solution vs written-contract) so they are not redundant, but a user who runs both pays double the critique tokens for closely-spaced passes. Opt-in mitigates this.
3. **The test-plan coverage matrix is not exhaustive.** It covers the enumerated categories against the stated acceptance criteria; a missing acceptance criterion or an unenumerated category is a gap, surfaced as a plan with holes, not a guarantee.
4. **bypassPermissions degrades the interactive value.** Like `/user:design`, the per-section `AskUserQuestion` approval auto-resolves under bypass; these lanes deliver their value in non-bypass mode. Stated in each command.
5. **The two design-critique lanes are read-only on code but write to the brief.** They are not verified by a behavior harness (the kit has none for command behavior); TASK-6 asserts only structural presence, like SPEC-006 TASK-7.

## Edge Cases
1. **`/user:devs-team` with no design to critique.** If a `DECISION-BRIEF.md` exists, use its `## Solution`. If not, fall back to the active spec's `## Solution`. Only if **neither** has a `## Solution` (or the brief exists but has no `## Solution`): say so, suggest `/user:design` or `/user:spec` first, stop. Do not invent a design to critique. (DEC-011, DEC-013.)
2. **`/user:visual-team` on a kit-internal (no-UI) item.** It still runs if pulled, but the body notes it is meant for UI-bearing downstream work; the maintainer decides.
3. **`/user:test-plan` before a spec exists.** No acceptance criteria to read; say so and point to `/user:spec`.
4. **A design critique returns RECONSIDER.** Report-only: the maintainer revises `/user:design` or proceeds; the lane never blocks `/user:spec`.
5. **Re-running a critique lane.** Re-appends or replaces the `## Design critique` section (one critique section per brief; replace, do not stack duplicates).
6. **tiny-lane item.** These lanes are normal/full only; a tiny item skips them (consistent with the lane model and SPEC-006's tiny-lane suppression).

## Out of Scope
- Visual *generation* (mockups, screenshots, `.pen` files): needs render/browser machinery, violates bash/no-binaries; downstream image/frontend skills own it.
- Named-person personas (Carmack/Rams/etc.): off house-style.
- A hard gate before `/spec` or `/execute` on any critique/plan verdict (the rejected pattern).
- A shared `design-critic` agent / roundtable engine: deferred to a 3rd consumer (no premature abstraction); three thin commands for now.
- Folding any lane into an existing command (the user chose three separate commands).
- Turning `/user:test-plan` into a generative roundtable.

## Decision Log
- **DEC-001**: The gap is design *critique*, not design *generation*. A generative roundtable would duplicate `/user:design` (Step 2/3) and violate "Replace, don't deprecate". devs-team/visual-team are "`review-team` for design."
- **DEC-002**: devs-team is a separate command, not a beat inside `/user:design`. Kit precedent: code generation (`/execute`) and code critique (`/review`, `/review-team`) are separate; design follows the same split.
- **DEC-003**: Generic house-style lenses, not named-person personas. Consistent with `/spec-validate` (5 reviewers) and `/review-team` (3 lenses).
- **DEC-004**: `/user:test-plan` is a coverage-matrix generator, not a roundtable. Test planning derives from fixed acceptance criteria (systematic coverage), unlike open-space design critique (divergence). Calling it a roundtable would mislabel it.
- **DEC-005**: `/user:visual-team` is critique, not generation. Consistency with the critique reframe, and visual generation needs render machinery that violates bash/no-binaries.
- **DEC-006**: visual-team is downstream-facing; recorded via a PHILOSOPHY carve-out + a kit-health allow-note so the self-assessment does not flag it speculative. This is the recorded cost of the maintainer's bake-into-kit choice (over a standalone skill).
- **DEC-007**: Inline parallel Task dispatch, no new agent file. A shared `design-critic` agent is deferred to a 3rd consumer (no premature abstraction); keeps file count down (tests count files).
- **DEC-008**: All three are opt-in lanes with report-only verdicts; no hard gate (PHILOSOPHY "Detect, don't dictate"). Hard blocks stay with the safety/verify gates.
- **DEC-009**: Command names keep the `-team` suffix for the two critique lanes (`devs-team`, `visual-team`, paralleling `review-team`); `test-plan` is named for what it is, not forced into the `-team` family.
- **DEC-010**: One spec, three parts (two critique lanes + one test lane), like SPEC-003/005/006 multi-part specs; they share opt-in-lane shape and fill the pre-execute assurance gaps.
- **DEC-011 (validation)**: devs-team critiques the design's `## Solution` from the brief if present, **else** the active spec's `## Solution`. Rationale: `/user:design` is opt-in, so a `/think -> /spec` path (the very path that birthed this spec, which has no brief) would leave the lane with nothing to critique. A hard `DECISION-BRIEF.md` requirement was a self-contradiction. (Reviewer 3, critical.)
- **DEC-012 (validation)**: On partial lens failure (a Task subagent errors/times out), merge from the lenses that returned, note the missing ones, never block. Rationale: 5 parallel dispatches with undefined partial-failure behavior. (Reviewer 2.)
- **DEC-013 (validation)**: A brief that exists but lacks a `## Solution` is treated as "no design here" and falls through to the spec, then to the stop message. Rationale: only the absent-file case was handled. (Reviewer 2/3.)
- **DEC-014 (validation)**: The old TASK-6 (4 files, many sub-edits) is split into TASK-6 (tests + count strings) and TASK-7 (inventory rows + CHANGELOG). Rationale: the bundled task was over the atomicity heuristic. (Reviewer 4.)
- **DEC-015 (validation)**: devs-team and visual-team share the `SOLID / REVISE / RECONSIDER` verdict vocabulary (same altitude); it intentionally differs from review-team (code) and spec-validate (spec), which act on different artifacts. Rationale: surfaced verdict-vocabulary drift across the kit's critique commands; aligned the two same-altitude ones, documented the rest as intentional. (Reviewer 5.)
- **DEC-016 (validation)**: visual-team treats fetched URL/screenshot content as data, not instructions (the kit's security rule). Rationale: it ingests untrusted external content. (Reviewer 1.)

## Source citations
- The parallel multi-lens pattern this mirrors: `commands/review-team.md` + `agents/reviewer.md`.
- The design lane + brief this critiques: `commands/design.md` + `docs/specs/SPEC-011-design-lane.md` + SPEC-008 (`## Solution` sub-section shape).
- The two external roundtables ported to house style: `zvadaadam/az-skills` `skills/engineering/devs-roundtable/SKILL.md` and `skills/design/design-roundtable/SKILL.md`.
- The doc-impact map this work exercises: `WORKFLOW.md` (SPEC-006) for new `commands/*`.
- Lifecycle slots: `WORKFLOW.md` cycle table + `## The spine` (SPEC-006).

## Validation
`/user:spec-validate` dogfooded on this spec 2026-05-21 (5 reviewers run inline). Pre-fix verdict: **NEEDS REVISION** (1 critical + 5 warnings). All resolved inline; see DEC-011..DEC-016.

- Critical (Reviewer 3, Assumption Destroyer): devs-team hard-required `DECISION-BRIEF.md`, but `/user:design` is opt-in and this spec's own `/think -> /spec` path produced no brief -> the lane would error on the feature that ships it. Fixed: critique the brief OR the active spec's `## Solution` (DEC-011).
- Warnings: partial-lens-failure handling (DEC-012); brief-without-Solution case (DEC-013); TASK-6 atomicity split (DEC-014); verdict-vocabulary drift across critique commands (DEC-015); visual-team untrusted-content handling (DEC-016).
- Passed: opt-in/report-only matches PHILOSOPHY; generic lenses (not named personas); the visual-team downstream carve-out; inline-dispatch deferral is defensible YAGNI.

Status held at DRAFT pending a re-validate after the fixes (and after the writing-plans plan is re-synced to DEC-011).
