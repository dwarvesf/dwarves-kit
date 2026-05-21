# Spec: Downstream UI-design loop (`/user:ui-design`: brief -> generate -> critique -> revise)

Generated: 2026-05-21
Status: VALIDATED
Source: `docs/research/2026-05-21-testing-ui-lane-scan.md` (the testing/QA + UI lane scan). The scan's honest finding: the kit critiques visuals (`/user:visual-team`) but never produces them, by deliberate decision (SPEC-016 DEC-005, visual generation needs render machinery and violates bash/no-binaries). But the `frontend-design` skill (third-party, Anthropic) is already installed and IS that generator. The unfilled gap is not a generator; it is the LOOP that connects a structured UI brief to generation to critique to revision. The kit owns 2 of the 3 stations already.
Depends on: `commands/visual-team.md` (the 5-lens visual critique this loops on, SPEC-016), `commands/design.md` + `docs/specs/DECISION-BRIEF.md` (the brief this extends with a UI section, SPEC-011), and the **external** `frontend-design` skill (the generator this delegates to; not vendored). Adapts the UI brief shape from `hoangnb24/harness-experimental` `docs/templates/high-risk-story/design.md` (its UI/Platform Impact section).
Relates to: SPEC-016 Part C (the visual-team downstream carve-out this lane extends to a second command), SPEC-006 (the doc-impact map for a new `commands/*`).
Lane: normal, downstream-facing. No hook is touched. Bounded surface: one new command (`ui-design`), a PHILOSOPHY carve-out extension, a kit-health allow-note, WORKFLOW.md placement, meta-test additions, inventory + count + CHANGELOG.

## Problem

The kit's UI surface is half a loop:

| Station | Owner today | Status |
|---|---|---|
| 1. Structured UI brief | (none; `/user:design` shapes a general `## Solution`, not a UI surface) | **missing** |
| 2. Generate the UI | `frontend-design` (external skill, installed) | exists, **not wired** |
| 3. Critique the UI | `/user:visual-team` (5 lenses, report-only) | exists |
| 4. Revise (loop 2->3) | (none) | **missing** |

So a downstream developer with a UI must hand-carry the work between stations: write an ad-hoc prompt, invoke frontend-design by hand, eyeball the result, maybe remember `/user:visual-team` exists, read the critique, and manually re-prompt. Three specific holes:

1. **No structured UI brief.** `/user:visual-team` critiques against generic lenses, and `frontend-design` generates against whatever prose it is handed. Neither has a concrete UI spec (layout, component states, responsive behavior, accessibility targets, design-system tokens) to work from, so the generation is unanchored and the critique has no stated intent to measure against.
2. **No wiring to the generator.** The kit explicitly defers generation to "a downstream image or frontend skill" (visual-team's own body) but never names `frontend-design` or routes to it. The dependency exists; the connection does not.
3. **No revise loop.** A `REVISE` verdict from `/user:visual-team` is a dead end: nothing feeds the findings back into generation. The developer closes the loop by hand, every iteration.

The temptation is to read "we want a UI-design skill" as "build a generator inside the kit." That is a hard reject and already decided (SPEC-016 DEC-005). The correct move is to build the **loop** around the generator the kit already depends on.

## Solution

### Approaches considered
1. **A downstream-facing `/user:ui-design` command that orchestrates the loop (CHOSEN).** It writes a structured `## UI design` brief section (borrowing the harness UI/Platform-Impact shape), hands generation to the external `frontend-design` skill, routes the output through `/user:visual-team`, and loops on `REVISE` with a bounded iteration cap. The kit ships no renderer; it ships the orchestration and the brief shape.
2. **Build a generator in the kit.** Rejected, already decided: render/browser machinery violates bash/no-binaries (SPEC-016 DEC-005).
3. **A standalone skill instead of a command.** Defensible (the kit has skills; `frontend-design` is itself a skill; the user said "flow/skill"). Rejected for consistency: the kit's downstream-facing visual lane is a command (`/user:visual-team`) with a recorded carve-out, shares the `SOLID/REVISE/RECONSIDER` verdict vocabulary, and sits in the WORKFLOW cycle; `/user:ui-design` belongs in the same family and the same slot. The skill option is recorded (DEC-002) in case a downstream wants to invoke it outside the `/user:` workflow.
4. **Fold the UI track into `/user:design`.** Rejected: `/user:design` shapes a general solution conversationally (one question at a time); the UI brief is a structured, sectioned artifact and the loop mutates external generation output. Mixing them bloats `/user:design` and crosses the generate/critique split the kit keeps elsewhere (SPEC-016 DEC-002).

### Chosen approach + why
Approach 1. The kit's correct posture toward generation is "external tools are dependencies, not features." `frontend-design` is the dependency; the kit's value-add is the loop and the brief that anchors both generation and critique. This reuses two stations the kit already owns and connects them through a dependency it already has, adding only the brief shape and the bounded revise loop. It is the smallest thing that closes the half-loop without building a renderer.

### Extensibility & boundaries
- **Load-bearing dimension:** the **`## UI design` brief is the shared contract** between the generator (frontend-design reads it) and the critic (visual-team measures against it). If the brief is thin, both stations degrade. The brief shape is fixed and sectioned so it stays a real spec, not prose.
- **Unit boundaries:** `/user:ui-design` owns the brief, the loop, and the terminal verdict. Generation is delegated to `frontend-design` (not reimplemented); critique is delegated to `/user:visual-team` (not reimplemented). The command knows neither station's internals beyond "hand it the brief / read its verdict."
- **Graceful degradation:** if `frontend-design` is not installed, the command still writes the brief and runs `/user:visual-team` on whatever the developer supplies (a screenshot/link), and tells the developer which generation skill to install. It never hard-fails on the missing optional dependency.
- **What changes when the dimension grows:** a different generator (Figma plugin, another frontend skill) slots into station 2 by changing one delegation point; the brief and the critique are generator-agnostic.

### Architecture
```
/user:design  -> shapes the general ## Solution (SPEC-011)
            -> /user:ui-design   (opt-in, downstream-facing, for UI-bearing work)
                 |
                 v
            [brief]   write/replace `## UI design` into the ACTIVE SPEC if one exists,
                      ELSE the pre-spec DECISION-BRIEF.md  (spec-bound = multi-spec safe;
                      mirrors SPEC-016 DEC-011 + SPEC-018)  (DEC-008)
                      (layout, component states, responsive, a11y, design tokens, copy)
                 |
                 v
            [generate]  ask Claude to invoke the frontend-design skill (external);
                      prompt-driven, not a programmatic call (DEC-009)
                      (if absent/errors: skip, ask the developer to supply a visual + name the skill)
                 |
                 v
            [critique]  invoke /user:visual-team on the generated/supplied visual
                      -> verdict SOLID | REVISE | RECONSIDER (+ findings),
                         written to the same active-spec-else-brief location
                 |
                 v
            [report]   v1 is ONE report-only pass (DEC-010): present the verdict + findings;
                       on REVISE the developer re-runs /user:ui-design with the findings
                       (manual revise, like /user:visual-team's report-only posture);
                       on RECONSIDER, surface that the direction is wrong, do not regenerate.
                       (An optional bounded auto-revise loop is Phase 2, TASK-2.)
```

## Technical Design

### Interfaces (I/O contract)
- **Where the `## UI design` + `## Visual critique` sections land (DEC-008, the multi-spec fix):** the **active spec** (`docs/specs/SPEC-NNN-<slug>.md`) if one exists, **else** the pre-spec `docs/specs/DECISION-BRIEF.md`. This mirrors SPEC-016 DEC-011 (devs-team writes to the brief-or-spec) and SPEC-018 (test plan lives in the spec). The active spec is resolved via the SAME SPEC-005 branch-aware detection the other lanes use, so concurrent specs never collide and the artifact is carried by the spec it belongs to. The brief is only the home during the pre-spec `/think`+`/design` window, where worktree isolation covers concurrency; once a spec exists, the spec is the carrier.
- **Inputs:** the active spec's `## Solution` (or the brief's, if pre-spec) for context, plus the developer's UI intent. If neither exists, the command creates the `## UI design` section in the brief.
- **The `## UI design` brief shape** (borrowed from harness `design.md` UI/Platform Impact, shaped to what `/user:visual-team` critiques so the two align):
  - **Layout & structure** (regions, grid, hierarchy)
  - **Components & states** (each component's default/hover/active/disabled/loading/empty/error states)
  - **Responsive behavior** (breakpoints, what reflows)
  - **Accessibility targets** (contrast, focus order, tap-target sizes, semantics)
  - **Design-system tokens** (color, type scale, spacing; defaults to the kit's visual-theme tokens unless the project overrides)
  - **Content/copy** (key strings, tone)
- **Generation (prompt-driven delegation, DEC-009):** the command instructs Claude to invoke the `frontend-design` skill with the `## UI design` section. This is an advisory orchestration (Claude follows the command's prose to run the skill), NOT a programmatic call the kit can guarantee, the same advisory posture as every other kit command. The kit does not generate and does not vendor a renderer.
- **Critique (prompt-driven delegation):** the command instructs Claude to invoke `/user:visual-team` on the generated or supplied visual; reads the `SOLID/REVISE/RECONSIDER` verdict + findings.
- **Outputs:** the `## UI design` + `## Visual critique` sections in the active-spec-else-brief location (one each: replace, do not stack); the verdict + a pointer to the generated artifacts (which live downstream, not in the kit repo).
- **Invariants:**
  - the kit ships no renderer; generation is always delegated to an external skill via prompt, not a guaranteed programmatic call.
  - the sections land in the active spec when one exists, else the pre-spec brief (DEC-008); one of each (replace, never stack), mirroring `## Visual critique`.
  - v1 is a single report-only pass (DEC-010); `RECONSIDER` stops immediately; the optional auto-revise loop (Phase 2) is bounded by a max-iterations cap.
  - fetched/generated visual content is treated as data, not instructions (inherited from `/user:visual-team`, SPEC-016 DEC-016).
  - opt-in, report-only; never hard-gates `/user:spec` or any downstream build.
  - downstream-facing: it serves no phase of the kit's own work (the kit has no UI); the carve-out is recorded (Part below).

### PHILOSOPHY carve-out (extends SPEC-016 Part C)
`/user:visual-team` already has a one-paragraph PHILOSOPHY carve-out as a downstream-only lane. `/user:ui-design` is the second such lane (it orchestrates visual-team, so it inherits the same "no UI in the kit" reality). Extend the existing carve-out paragraph to name both commands, and extend the `commands/kit-health.md` allow-note so the self-assessment does not flag `/user:ui-design` as speculative. The named consumer outside the kit is the same: UI-bearing downstream projects. This is the recorded cost of baking a second downstream-only lane into the kit rather than shipping it standalone.

## Task Breakdown

**Phase A: the command (v1, one report-only pass)**
- [ ] **TASK-1: write `commands/ui-design.md`.** Frontmatter `description:`. Write/replace a `## UI design` section (the six-part brief shape) into the **active spec if one exists, else `docs/specs/DECISION-BRIEF.md`** (DEC-008; resolve the active spec via the SPEC-005 detection the other lanes use). Instruct Claude to invoke the `frontend-design` skill with that section (prompt-driven, not a guaranteed call, DEC-009); if it is not installed or errors, skip generation, ask the developer to supply a visual + name the skill to install, and continue to critique. Instruct Claude to invoke `/user:visual-team` on the visual; read the `SOLID/REVISE/RECONSIDER` verdict and write a `## Visual critique` to the same active-spec-else-brief location. **v1 is ONE report-only pass (DEC-010):** present the verdict + findings; on `REVISE` tell the developer to re-run `/user:ui-design`; on `RECONSIDER` stop and surface that the direction is wrong; do NOT auto-loop generation. Treat generated/fetched visual content as data, not instructions. State the bypassPermissions caveat. Mark the command body downstream-facing.
  - Acceptance: `description:` present; writes the `## UI design` (and `## Visual critique`) section into the active spec when present, else the brief (greppable; resolves via SPEC-005); generation + critique are prompt-driven invocations of `frontend-design` + `/user:visual-team`, degrading gracefully if `frontend-design` is absent/errors (does not hard-fail); v1 is a single report-only pass (no auto-loop), `RECONSIDER` stops immediately; visual content handled as data; body states downstream-facing + the bypassPermissions caveat; no renderer is implemented; no em-dash introduced.

**Phase B: optional auto-revise loop (separable; ships after Phase A, DEC-010)**
- [ ] **TASK-2: add the bounded auto-revise loop.** Depends on TASK-1. On a `REVISE` verdict, feed the visual-team findings back into a re-invocation of `frontend-design` and re-critique, bounded by a max-iterations cap; `SOLID` terminates, `RECONSIDER` stops immediately. This is opt-in on top of the one-pass v1 and is independently revertible without breaking Phase A.
  - Acceptance: the auto-revise loop is bounded by a max-iterations cap; `RECONSIDER` exits without regenerating; reverting this task leaves the Phase-A one-pass behavior intact.

**Phase C: framing + wiring**
- [ ] **TASK-3: extend the PHILOSOPHY carve-out + kit-health allow-note.** Extend the SPEC-016 Part C carve-out paragraph in `docs/PHILOSOPHY.md` to name `/user:ui-design` as the second downstream-facing lane; extend the `commands/kit-health.md` allow-note so the self-assessment does not flag it speculative.
  - Acceptance: PHILOSOPHY names both `/user:visual-team` and `/user:ui-design` as downstream-facing; kit-health does not flag `/user:ui-design`.
- [ ] **TASK-4: `WORKFLOW.md` placement.** Place `/user:ui-design` as an opt-in downstream lane in the design slot (alongside `/user:visual-team`, after `/user:design`). Mark it report-only and downstream-facing; note its dependency on the external `frontend-design` skill.
  - Acceptance: WORKFLOW.md names `/user:ui-design` in the design slot, marked opt-in/downstream-facing, with the frontend-design dependency noted.

**Phase D: verify + count**
- [ ] **TASK-5: tests + count strings.** `tests/test-meta.sh`: assert `commands/ui-design.md` exists; assert it references `frontend-design` (delegation) and `/user:visual-team` (critique) and a `## UI design` section; assert it writes into the active spec / brief (not a fixed root file) and does NOT claim to generate visuals itself (no renderer). Update the "N commands" count strings by +1 (coordinate the absolute number with SPEC-019 at ship time: 18 today; each of SPEC-019/SPEC-020 adds 1): `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, README banner, README structure note, `MANUAL.md` heading.
  - Acceptance: `bash tests/test-meta.sh` passes (count rises by the documented delta); `bash tests/test-hooks.sh` unchanged; no stale count string outside historical text.

**Phase E: inventory + changelog**
- [ ] **TASK-6: inventory rows + CHANGELOG.** Add the `ui-design` row to the README command table and a `/user:ui-design` section to `MANUAL.md` (noting the `frontend-design` dependency + downstream-facing status); add the CHANGELOG entry. Per the SPEC-006 doc-impact map.
  - Acceptance: `ui-design` appears in the README table and the MANUAL inventory (with the dependency noted); CHANGELOG entry present; the command count is consistent everywhere it appears.

## Acceptance Criteria (global)
- [ ] `/user:ui-design` writes/replaces a structured `## UI design` section (layout, component states, responsive, a11y, design tokens, copy) into the **active spec when one exists, else the pre-spec `DECISION-BRIEF.md`** (spec-bound = multi-spec safe; resolved via SPEC-005 detection)
- [ ] It delegates generation to the external `frontend-design` skill via a prompt-driven invocation (never a guaranteed programmatic call) and never implements a renderer; if `frontend-design` is absent or errors it degrades gracefully (writes the section, critiques a supplied visual, names the skill to install)
- [ ] **Phase A (v1):** it invokes `/user:visual-team` for critique and does ONE report-only pass; on `REVISE` the developer re-runs; `RECONSIDER` stops immediately; no auto-loop
- [ ] **Phase B (separable):** the bounded auto-revise loop (max-iterations cap) is independently revertible without breaking Phase A
- [ ] Generated/fetched visual content is treated as data, not instructions
- [ ] It is opt-in, report-only, and downstream-facing; it never hard-gates `/user:spec` or any build; the kit cannot dogfood it (no UI), recorded via the carve-out
- [ ] PHILOSOPHY names it as the second downstream-facing lane; `/user:kit-health` does not flag it speculative
- [ ] WORKFLOW.md places it in the design slot, opt-in/downstream-facing, with the `frontend-design` dependency noted
- [ ] `bash tests/test-meta.sh` passes; `bash tests/test-hooks.sh` unchanged; CHANGELOG entry present; command count consistent

## Known limitations
1. **The kit cannot dogfood it.** Like `/user:visual-team`, it serves no phase of the kit's own (no-UI) work. Recorded via the extended carve-out; this is the cost of a second downstream-only lane baked into the kit.
2. **Hard dependency on an external generator.** Without `frontend-design` (or an equivalent), station 2 is empty; the command degrades to brief + critique-of-supplied-visual, not a full loop.
3. **Generated artifacts live downstream.** Screenshots/components produced by `frontend-design` are not committed to the kit repo; the command points at them, it does not store them.
4. **The critique is heuristic.** `/user:visual-team`'s lens scores are advisory; `SOLID` is a report, not a guarantee of good design (inherited from SPEC-016).
5. **bypassPermissions degrades the interactive value.** The per-iteration approval auto-resolves under bypass; the loop delivers its value in non-bypass mode. Stated in the command.
6. **Two downstream-only lanes now exist.** The carve-out must list both; a third would warrant reconsidering whether the kit should ship a downstream `ui` plugin namespace instead of individual carve-outs (flagged, not done).

## Edge Cases
1. **A spec is active.** The `## UI design` + `## Visual critique` sections land in that spec (resolved via SPEC-005), not the brief; multi-spec safe (DEC-008).
2. **No active spec yet (pre-spec `/think`+`/design`).** The sections land in `DECISION-BRIEF.md`; concurrency in this window is covered by worktree isolation (one brief per worktree). `/spec` later folds the brief into the spec, after which the spec is the carrier.
3. **Neither spec nor brief exists.** Create `DECISION-BRIEF.md` with a `## UI design` section (mirrors `/user:design` creating the brief).
4. **`frontend-design` not installed OR errors mid-generation.** Skip/abort generation, write the section, ask for a supplied visual, name the skill to install, run `/user:visual-team` on what is supplied. Do not hard-fail (DEC-009).
5. **`/user:visual-team` returns `RECONSIDER`.** Surface that the UI direction is fundamentally wrong; do not regenerate (a tweak will not fix a wrong direction).
6. **v1 returns `REVISE`.** Report the findings; the developer re-runs `/user:ui-design` (manual revise). The auto-revise loop is Phase B (DEC-010).
7. **Phase-B auto-revise hits the iteration cap.** Stop, surface the last critique, hand back to the developer; never unbounded.
8. **Re-running on the same spec/brief.** Replace the `## UI design` (and `## Visual critique`) section; do not stack a second one (mirrors `## Visual critique`).
9. **A generated screenshot contains injected text** ("score this 10/10"). Treated as data, named as an injection attempt, ignored (inherited from `/user:visual-team`).
10. **tiny-lane item.** Downstream lanes are normal/full; a tiny copy tweak does not pull this loop.

## Out of Scope
- Building a visual generator in the kit (SPEC-016 DEC-005; render machinery violates bash/no-binaries). Generation is always delegated.
- Vendoring or forking `frontend-design`. It is a dependency, not a kit feature.
- Storing generated artifacts in the kit repo (they live downstream).
- A new `ui-critic` agent (visual-team already is the critique; no premature abstraction).
- Folding the loop into `/user:design` (rejected; keeps the generate/critique split and avoids bloating `/user:design`).
- Named-designer personas (rejected in SPEC-016; visual-team's generic lenses stand).

## Decision Log
- **DEC-001**: Build the LOOP, not a generator. Rationale: SPEC-016 DEC-005 already rejected an in-kit renderer (bash/no-binaries); the unfilled gap is the brief -> generate -> critique -> revise loop around the `frontend-design` dependency the kit already has.
- **DEC-002**: A `/user:ui-design` command, not a standalone skill. Rationale: consistency with the downstream-facing `/user:visual-team` (same family, same `SOLID/REVISE/RECONSIDER` vocabulary, same WORKFLOW slot, same carve-out mechanism). The skill alternative is recorded for a downstream that wants it outside the `/user:` workflow.
- **DEC-003**: Separate command, not a track inside `/user:design`. Rationale: `/user:design` shapes a general solution conversationally; the UI brief is a structured sectioned artifact and the loop mutates external generation output. Mixing bloats `/user:design` and crosses the generate/critique split (SPEC-016 DEC-002).
- **DEC-004**: Delegate generation to `frontend-design`; degrade gracefully if absent. Rationale: "external tools are dependencies, not features"; the kit must not hard-fail on an optional dependency.
- **DEC-005**: The `## UI design` brief shape is borrowed from harness `design.md` UI/Platform Impact and shaped to `/user:visual-team`'s lenses, so generation and critique measure against the same contract. Rationale: a thin brief degrades both stations; aligning the brief to the critic's lenses makes the loop coherent.
- **DEC-006**: Second downstream-facing carve-out (extends SPEC-016 Part C), not a new mechanism. Rationale: it inherits visual-team's no-UI reality; reuse the existing carve-out + kit-health allow-note. A third downstream-only lane would trigger reconsidering a downstream plugin namespace (flagged in Known limitations 6).
- **DEC-007**: Bounded revise loop; `RECONSIDER` stops immediately. Rationale: a wrong direction is not fixable by regeneration; unbounded revision burns generation cost without convergence (the same bound logic as fix-agent's max-2).
- **DEC-008 (validation)**: The `## UI design` + `## Visual critique` sections land in the **active spec when one exists, else the pre-spec brief** (resolved via SPEC-005), not unconditionally in the fixed-name `DECISION-BRIEF.md`. Rationale: the failure-mode lens + the maintainer's multi-spec flag flagged that writing to the single pre-spec root brief collides when concurrent specs run; binding to the spec (as SPEC-016 DEC-011 + SPEC-018 already do) makes it per-spec and multi-spec safe. The brief remains the home only in the pre-spec window, where worktree isolation covers concurrency. (CRITICAL.)
- **DEC-009 (validation)**: Generation + critique are **prompt-driven** invocations of `frontend-design` + `/user:visual-team` (Claude follows the command's prose to run them), NOT a programmatic pipeline the kit can guarantee; `frontend-design` erroring mid-generation degrades like absent. Rationale: the assumption-destroyer + solution-design lenses flagged the original "hands the brief to the skill" framing as implying a hard call the kit cannot make; commands orchestrate by instructing Claude, an advisory posture that must be stated honestly. (HIGH.)
- **DEC-010 (validation)**: v1 is a **single report-only pass**; the bounded auto-revise loop is a separable Phase B. Rationale: the scope lens flagged the auto-revise loop as more aggressive than the kit's report-only posture (`/user:visual-team` reports, the human decides) and as gold-plating for v1. One pass + manual re-run ships the value; the auto-loop is opt-in and independently revertible. (Scope, HIGH.)

## Source citations
- The critique station reused: `commands/visual-team.md` + SPEC-016 (Part B lenses, Part C carve-out, DEC-016 data-not-instructions).
- The brief station extended: `commands/design.md` + `docs/specs/DECISION-BRIEF.md` (SPEC-011).
- The generation station (external dependency): the `frontend-design` skill (third-party, Anthropic; not vendored).
- The UI brief shape adapted: `hoangnb24/harness-experimental` `docs/templates/high-risk-story/design.md` (UI/Platform Impact), via `docs/research/2026-05-21-testing-ui-lane-scan.md`.
- The scan that surfaced this: `docs/research/2026-05-21-testing-ui-lane-scan.md`.
- The doc-impact map this exercises: `WORKFLOW.md` (SPEC-006) for new `commands/*`.

## Validation
`/user:spec-validate` dogfooded 2026-05-21 (5 lenses run inline). Pre-fix verdict: **NEEDS REVISION** (1 critical + 2 warnings). All resolved inline; Status set to VALIDATED.

- **Critical (Failure-Mode + the maintainer's multi-spec flag):** the command wrote `## UI design` + `## Visual critique` into the single pre-spec root `DECISION-BRIEF.md`, which collides when concurrent specs run. Fixed: write into the active spec when one exists, else the brief (DEC-008), per the SPEC-016 DEC-011 + SPEC-018 precedent.
- **Warning (Assumption + Solution-Design):** the "hands the brief to frontend-design" framing implied a programmatic call the kit cannot make. Fixed: stated as prompt-driven advisory orchestration; mid-generation errors degrade like absent (DEC-009).
- **Warning (Scope):** the auto-revise loop is more aggressive than the kit's report-only posture and gold-plated for v1. Fixed: v1 is one report-only pass; the bounded auto-revise loop is a separable Phase B (DEC-010).
- **Concurrency check (per the multi-spec flag):** with DEC-008 the design artifacts are spec-bound (per-spec, multi-spec safe); the pre-spec brief window relies on worktree isolation, consistent with the kit's SPEC-010 model and the maintainer's "per spec if possible" steer. REVIEW/TODOS are untouched (transient per-diff, out of scope here).
- **Passed:** no in-kit renderer (delegates to frontend-design); downstream carve-out reused, not reinvented; generic lenses (no named designers); opt-in/report-only; visual content as data.
