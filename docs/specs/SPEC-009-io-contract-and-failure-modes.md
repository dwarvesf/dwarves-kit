# Spec: Port the I/O contract + failure-modes table into /spec (from ops-toolkit SDD)

Generated: 2026-05-20
Status: VALIDATED
Source: cross-repo study 2026-05-20 of ops-toolkit's SDD template (`tools/agency-lead-radar/docs/SPEC.md`, `tools/tide/docs/specs/`). Two sections there have no equivalent in dwarves-kit's spec format and are worth porting: the Input/Output contract and the Failure-modes table. Complements SPEC-008 (the Solution-depth lane). Backlog: ID-010.
Depends on: SPEC-008 shipped the enriched `## Solution` template + Reviewer 5 (this spec extends the same `commands/spec.md` template and reuses Reviewers 2 + 5). Conceptual lineage: ops-toolkit `agency-lead-radar` / `tide` SDD shape.
Lane: normal (touches `commands/spec.md`, `commands/spec-validate.md`, tests, README/MANUAL, CHANGELOG; no auth/data/hook/migration risk). `/user:spec-validate` recommended (it changes the spec-authoring contract).

## Problem

dwarves-kit's spec template (`commands/spec.md`, post-SPEC-008) covers Problem, Solution (with depth), Technical Design, Task Breakdown, Acceptance Criteria, Edge Cases, Out of Scope, Decision Log. Two structures that ops-toolkit's SDD treats as first-class are missing:

1. **No Input/Output contract.** The kit's specs describe a solution but never declare, as a contract, what a change *consumes* (existing data/files/APIs/state it depends on) and what it *produces* (the shape downstream code can rely on). ops-toolkit makes this first-class (`Input contract` / `Output contract`), which is what lets its specs be reviewed by interface, not just prose. SPEC-008 added a prose "Extensibility & boundaries" prompt; an I/O contract is that boundary made concrete.
2. **Edge Cases is looser than a failure-modes table.** The kit's `## Edge Cases` lists specific input scenarios. ops-toolkit adds a `Failure modes` table: named systemic failure *classes* (external service down, partition, rate-limit, auth rotation) each with a detection signal and a mitigation. That is the artifact Reviewer 2 (Failure Mode Analyst) currently has to invent from scratch every time.

The downstream cost: specs hand off interfaces implicitly (the next change guesses what it may break), and failure handling is reasoned ad hoc at review time instead of being declared and checked.

This is a deliberately small port. The risk is the opposite of the SPEC-008 problem: ops-toolkit's SDD is *heavy* (its `SPEC-A` is ~400 lines with a 200-line source registry), and importing it wholesale would push the Spec phase into the "deep and narrow" trap PHILOSOPHY rejects. So both sections ship as **optional, lane-scoped prompts**, not mandatory ceremony.

## Solution

### Approaches considered
1. **Two optional template sections, reviewed by the existing reviewers.** Add `### Interfaces (I/O contract)` under Technical Design and an optional `## Failure modes` table after Edge Cases; point Reviewers 2 and 5 at them. Tradeoff: template-grade (followed ~70%), but zero new mechanism and stays shallow.
2. **Replace Edge Cases with a Failure-modes table.** Tradeoff: cleaner single concept, but a breaking change to the template + `test-meta.sh` (which asserts `## Edge Cases` on the demo spec) and it loses the specific-scenario granularity Edge Cases gives.
3. **Full ops-toolkit-grade SDD template** (typed dataclass contracts, source registry, phasing matrix). Tradeoff: maximally rigorous, but it is the deep-and-narrow trap and a different product than a "readable in 30 seconds" kit.

### Chosen approach + why
Approach 1. It adds the two highest-value ops-toolkit ideas as optional sections, reuses the reviewers SPEC-008 already established (no new reviewer, the kit stays at 5), and respects "shallow and wide". Approach 2 was rejected because Edge Cases and Failure modes are complementary, not substitutes (specific scenario vs systemic class), and replacing breaks the demo + tests. Approach 3 was rejected as the explicit anti-pattern: it trades the kit's readability thesis for rigor the verifier already provides more cheaply.

### Extensibility & boundaries
- Load-bearing dimension: number of spec sections. Each added section must justify itself (PHILOSOPHY) and stay optional, or the template bloats. This spec adds exactly two and scopes both; a third would need its own justification.
- Unit boundaries: the change is confined to `commands/spec.md` (template prose) + two one-line pointers in `commands/spec-validate.md` + test assertions. No hook, no settings, no new command. Internals (the exact prompt wording) can change without breaking consumers, because the test asserts heading presence only.

### Architecture (diagram if it helps)
```
commands/spec.md template (after SPEC-009)
  ## Technical Design
    ### Interfaces (I/O contract)   <- NEW (optional)
    ### Data model changes
    ### API / UI / Infrastructure changes
  ...
  ## Edge Cases                      (specific input scenarios; unchanged)
  ## Failure modes                   <- NEW (optional; full-lane / external-dependency)
  ## Out of Scope

commands/spec-validate.md
  Reviewer 2 (Failure Mode Analyst)  <- +1 line: check the Failure modes table if present
  Reviewer 5 (Design & Extensibility)<- +1 line: check the I/O contract if present
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** the post-SPEC-008 `commands/spec.md` template; `commands/spec-validate.md` Reviewers 2 and 5; `tests/test-meta.sh` (the SPEC-008 "Spec-authoring depth contract" section, which this extends).
- **Outputs / produces:** an enriched `commands/spec.md` template with two new optional sections; +2 grep-presence assertions in `test-meta.sh`; the documented contract that downstream specs *may* include `### Interfaces (I/O contract)` and `## Failure modes`.
- **Invariants (must stay true):** every existing template section (Problem, Solution, Technical Design, Task Breakdown, Acceptance Criteria, Edge Cases, Out of Scope, Decision Log) is preserved unchanged; both new sections are OPTIONAL (a spec without them is still valid); the kit stays at 5 reviewers; `test-meta.sh` asserts template-presence, never per-spec usage.

### Data model changes
None. This is prose template + test assertions only.

### API / UI / Infrastructure changes
None.

## Task Breakdown

**Phase 1: Template + review (the substance)**
- [x] **TASK-1: add the two sections to `commands/spec.md`.** Add `### Interfaces (I/O contract)` as the first sub-section of `## Technical Design` (inputs/consumes, outputs/produces, invariants), and a `## Failure modes` table section after `## Edge Cases`. Mark both optional and lane-scoped (Failure modes: "full-lane / external-dependency specs"; I/O contract: "strongest when this spec exposes or consumes an interface"). Add a one-line note distinguishing the I/O contract (the concrete declared interface: inputs/outputs/invariants) from Solution's "Extensibility & boundaries" (the qualitative design lens: does each unit have one purpose). Add a one-line lineage comment crediting ops-toolkit SDD.
  - Acceptance: `commands/spec.md` contains `### Interfaces (I/O contract)` under Technical Design and `## Failure modes` after Edge Cases; both are marked optional/lane-scoped (prose, not mandatory); the template distinguishes the I/O contract from Extensibility & boundaries; Edge Cases retained; lineage credited.
- [x] **TASK-2: point the existing reviewers at the new artifacts.** In `commands/spec-validate.md`, add one bullet to Reviewer 2 (if a Failure modes table is present, check classes are real + each has detection + mitigation) and one bullet to Reviewer 5 (if an I/O contract is present, check inputs/outputs/invariants are concrete). No new reviewer; the kit stays at 5.
  - Acceptance: Reviewer 2 and Reviewer 5 each gain exactly one pointer bullet; the `## The 5 reviewers` count is unchanged; the drift guard (`no stale '4 reviewer'`) still passes.

**Phase 2: Verify + hygiene**
- [x] **TASK-3: tests.** `tests/test-meta.sh`: assert `commands/spec.md` contains `### Interfaces (I/O contract)` and `## Failure modes` (grep -F on stable anchors; presence only, not prose).
  - Acceptance: `bash tests/test-meta.sh` passes with the documented count delta (+2); `bash tests/test-hooks.sh` 42/42 (no hook touched).
- [x] **TASK-4: cross-refs + CHANGELOG.** README/MANUAL note the I/O contract + Failure modes sections; CHANGELOG `[Unreleased]` entry.
  - Acceptance: README/MANUAL updated; CHANGELOG entry present.

## Acceptance Criteria (global)
- [x] `commands/spec.md` has `### Interfaces (I/O contract)` (inputs/outputs/invariants) under Technical Design and an optional `## Failure modes` table after Edge Cases; both optional + lane-scoped; Edge Cases retained
- [x] `commands/spec-validate.md` Reviewers 2 and 5 each gain one pointer bullet; no new reviewer; the 5-reviewer count + drift guard unchanged
- [x] Lineage to ops-toolkit SDD (`agency-lead-radar` / `tide`) cited; no new dependency, command, env var, or settings.json field
- [x] `bash tests/test-hooks.sh` 42/42; `bash tests/test-meta.sh` passes (127 -> 129)
- [x] README/MANUAL/CHANGELOG updated (MANUAL /user:spec note + CHANGELOG; the README spec-line update rides with SPEC-010's path sweep)

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Authors treat the new sections as mandatory and bloat every small/normal spec | retro signal: normal-lane specs grow an empty I/O-contract + failure-modes boilerplate | both sections marked optional + lane-scoped in the template; Reviewer 5 calibration (SPEC-008) already exempts "extensibility nobody asked for" |
| Failure modes table duplicates Edge Cases | review notes the two sections repeat | template note distinguishes them (Edge Cases = specific input scenarios; Failure modes = systemic failure classes); Failure modes is optional, used when systemic classes exist |
| `test-meta.sh` over-couples to exact heading prose | a future reword of the template fails the suite | assert via `grep -F` on stable anchors (`### Interfaces (I/O contract)`, `## Failure modes`) only; never assert body prose |
| I/O contract section present but filled shallowly (the ~70% template problem) | specs declare an interface with vague inputs/outputs | advisory: Reviewer 5 flags a non-concrete contract; not hard-gated (PHILOSOPHY "Detect, don't dictate") |
| The two new sections collide with the SPEC-008 demo-spec gap | demo `examples/hello-spec` now lags the template by even more | out of scope here too; logged as the same demo-refresh follow-up SPEC-008 noted |

## Edge Cases
1. **A tiny-lane change.** No spec is written, so neither section applies.
2. **A normal-lane internal refactor with no external interface.** The I/O contract section is a no-op (author writes "none / internal only"); Failure modes is omitted (not full-lane). No bloat.
3. **A full-lane spec touching an external provider.** Failure modes is expected; Reviewer 2 checks each class has detection + mitigation. The I/O contract declares the provider's request/response shape as an input.
4. **A spec that omits both sections entirely.** Still valid; both are optional. Reviewer 5/2 do not storm (consistent with SPEC-008's legacy-grace posture).

## Out of Scope
- A typed/dataclass contract format or a source registry (ops-toolkit's heavyweight shape; rejected as deep-and-narrow).
- A phasing matrix with deterministic ship gates (the kit keeps gates advisory per "Detect, don't dictate").
- Replacing Edge Cases (kept; complementary).
- A new reviewer (Reviewers 2 + 5 absorb the checks).
- Refreshing the `examples/hello-spec` demo spec to model the new sections (same deferred demo-refresh follow-up as SPEC-008).
- Making either section mandatory or hard-gated.

## Decision Log
- **DEC-001**: Port exactly two ops-toolkit SDD sections (I/O contract + Failure modes), both optional + lane-scoped. Rationale: highest value, lowest bloat; the rest of the ops-toolkit template is the deep-and-narrow trap.
- **DEC-002**: Reuse Reviewers 2 + 5 with one pointer bullet each; no Reviewer 6. Rationale: the failure-modes table is Reviewer 2's existing job made concrete; the I/O contract is Reviewer 5's boundary lens made concrete. The kit stays at 5.
- **DEC-003**: I/O contract lives under Technical Design (not a top-level section, not folded into Solution). Rationale: it is design detail that frames Data model / API; top-level would over-weight it, folding into Solution would bury it.
- **DEC-004**: Failure modes is a new section after Edge Cases, not a replacement. Rationale: specific-scenario vs systemic-class are complementary; replacing breaks the template + the demo-spec test.
- **DEC-005**: Both sections optional, asserted by presence-in-template only. Rationale: "shallow and wide" + the SPEC-008 precedent that A-grade template scaffolding is followed ~70% and the reviewer (not a hard gate) is the enforcement.
- **DEC-006 (validation)**: The template carries a one-line distinction between the I/O contract (concrete declared interface) and SPEC-008's "Extensibility & boundaries" (qualitative design lens). Rationale: the two overlap and would confuse authors about where interface info belongs; complementary, not redundant (Reviewer 5 W1).

## Source citations
- The two ported sections: ops-toolkit `tools/agency-lead-radar/docs/SPEC.md` (Input/Output contract, Failure modes) and `tools/tide/docs/specs/` shape.
- The template + reviewers this extends: `commands/spec.md` and `commands/spec-validate.md` (Reviewers 2 + 5), both as shipped by SPEC-008.
- Philosophy bars this respects: `docs/PHILOSOPHY.md` ("Shallow and wide beats deep and narrow", "Detect, don't dictate", "every file justifies its existence").
- Field context on heavier SDD templates and their cost: `~/workspace/tieubao/ops-toolkit/research/2026-05-20-agent-workflow-enforcement-patterns.md`.

## Validation
5 reviewers run 2026-05-20 (security, failure-mode, assumption-destroyer, scope-critic, solution-design & extensibility; the post-SPEC-008 set). Pre-fix verdict: NEEDS REVISION (one design-overlap warning).
- Reviewer 5: `### Interfaces (I/O contract)` overlapped SPEC-008's `### Extensibility & boundaries` -> template now distinguishes them (DEC-006, TASK-1).
- Reviewer 3 (accepted, no change): the Edge-Cases-vs-Failure-modes line is inherently blurry; the distinguishing note is kept crisp, advisory.
- Security N/A (template/prose); scope atomic; count math `127 -> 129` confirmed.
Status flipped to VALIDATED after inline resolution.
