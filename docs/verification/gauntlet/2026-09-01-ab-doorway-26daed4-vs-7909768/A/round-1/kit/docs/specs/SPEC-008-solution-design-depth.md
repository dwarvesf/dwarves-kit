# Spec: Solution-design depth lane (forked from brainstorming, kit idiom)

Generated: 2026-05-20
Status: VALIDATED
Source: maintainer dogfooding signal 2026-05-20. While using the kit to spec features on a downstream project, the spec produced a shallow `## Solution` (no alternatives, no extensibility) and the flow advanced to validate with no solution-design feedback beat. (The session transcript was not captured, so whether `/think` was run or skipped is inferred; the template + validate gaps below are confirmed by direct inspection regardless.) Backlog: ID-009.
Depends on: nothing in code. Conceptual lineage: `superpowers:brainstorming` (5.1.0) + its `spec-document-reviewer-prompt.md`.
Lane: normal (touches `commands/spec.md`, `commands/spec-validate.md`, tests, README/MANUAL, CHANGELOG; no auth/data/hook/migration risk). `/user:spec-validate` recommended because it changes the spec-authoring contract every downstream spec inherits.

## Problem

The kit's pre-build pipeline has two kinds of depth and is missing a third.

| Phase (command) | Has a user-feedback beat? | Has solution-design depth? |
|---|---|---|
| `/think` (`commands/think.md`) | yes: 6 forcing questions, one at a time via `AskUserQuestion` | no: product framing only (pain, 10x, MVP, cut-list, scale, exit-metric). No question asks "which architecture, what tradeoffs, how does it extend" |
| `/spec` (`commands/spec.md`) | once, at Step 4 ("Approve this spec?") | no: the `## Solution` template is a single line, `[High-level approach. Architecture diagram if needed.]` |
| `/spec-validate` (`commands/spec-validate.md`) | after each reviewer | no: 4 reviewers (security / failure-mode / assumption / scope). None reviews design quality; scope-critic pushes the *opposite* way (cut, anti-gold-plating) |

Net: nothing in the pipeline forces "here are 2-3 ways to solve this, the tradeoffs, the one chosen and why, and how it extends." `/think` decides *whether to build*, `/spec` writes the *contract*, `/spec-validate` *attacks* the contract. No phase owns *the depth of the solution*. A shallow `## Solution` is the predictable output, not an accident.

Two amplifiers made it visible in the reporting session, but neither is the root cause:
- **bypassPermissions mode** lets the agent auto-chain phases and answer its own `AskUserQuestion`s, then suggest `/spec-validate` immediately. It amplifies; it does not remove the loop.
- **`/think` has no extended-thinking cue**, so it runs at default reasoning depth. But even at maximum thinking, a one-line Solution template and a validate set with no design reviewer still yield a shallow design. Extended thinking is necessary, not sufficient.

The root cause is structural: a template gap (A) and a validation gap (B). The downstream consequence is the real cost: a goal/anti-rationalization loop (the kit's own in-session primitive, SPEC-006) iterates against whatever the spec says. A shallow `## Solution` means the loop optimizes a weak design. Garbage in, garbage out.

### Why not just hard-gate it (the core adjudication)

The intuitive fix is "block until the user has reviewed the solution design." **The kit's PHILOSOPHY rejects that.** "Detect, don't dictate" explicitly rejects "a phase-locking system that blocks `/execute` unless `/spec-validate` has been run"; "Guardrails over guidance" reserves *hard blocks* for irreversible/safety cost. SPEC-006 already adjudicated the same shape (item d's "must follow WORKFLOW" became surface+log+gate-review, DEC-009). A spec with a shallow solution ships a weaker design; it destroys nothing, so it is not in the hard-block class.

Therefore the honest delivery is: **enrich the structure (so depth is cheap to produce), add an advisory reviewer (so shallowness is caught), and make the rigorous interactive pass an opt-in lane the user pulls (so enforcement is self-imposed, not kit-imposed).** A lane the user chooses to run may hold itself to a design-approval beat; that is the user dictating to themselves, which "Detect, don't dictate" permits. The kit never globally blocks the flow on design depth.

## Decision: chosen version

**Fork the *substance* of `superpowers:brainstorming` into two existing surfaces now (A enriches the `/spec` Solution template; B adds a fifth reviewer to `/spec-validate`), and fully design but defer the *interactive loop* (C, an opt-in `/user:design` beat) behind the PHILOSOPHY §5 "test on a real project first" bar.**

Lineage note (per "synthesize, don't originate"): `superpowers` is already a cited source in PHILOSOPHY (the slop-PR rejection wall). We do **not** add it as a runtime dependency. We take three patterns and rewrite them in the kit's markdown/prompt idiom:
1. brainstorming's "propose 2-3 approaches with trade-offs + recommendation" -> the Solution template (A).
2. brainstorming's "design for isolation and clarity" (one purpose, defined interface, independently testable, "a large file is a signal it does too much") -> the reviewer's lens (B).
3. `spec-document-reviewer-prompt.md`'s calibration ("only flag issues that would cause real problems; minor wording / 'this section could be longer' are not issues") -> the reviewer's calibration (B), which is also the kit's own anti-false-positive discipline (SPEC-006 DEC-013).

What we drop from brainstorming: the Visual Companion (node server, browser mockups; violates "bash over binaries"), the `writing-plans` handoff and `docs/superpowers/specs/` path (the kit has `/spec` + `docs/specs/`), and the global HARD-GATE (PHILOSOPHY-rejected; re-homed as the opt-in lane's self-imposed beat in C).

### Part A: enrich the `/spec` Solution template (the structure)

Replace the one-line `## Solution` block in `commands/spec.md`'s SPEC.md template with sub-sections that make depth cheap to produce:

```markdown
## Solution

### Approaches considered
2-3 candidate approaches. For each: one line of description + its main tradeoff.
(If only one approach is viable, say why the obvious alternatives were not.)

### Chosen approach + why
Which one, and what the rejected alternatives traded away.

### Extensibility & boundaries
- What changes when the load-bearing dimension grows (more data, more scale,
  a new variant)? Name the dimension; do not hand-wave "it scales".
- Unit boundaries: each piece has one purpose, a defined interface, and is
  testable independently. A unit that needs >3 sentences to describe is a
  split candidate.

### Architecture (diagram if it helps)
High-level shape / data flow.
```

This is template-grade (guidance, not enforcement). On its own it suffers the "rule followed ~70%" problem PHILOSOPHY names: a heading can still be filled shallowly. A is the cheap scaffold; B is what makes it load-bearing.

### Part B: add Reviewer 5 to `/spec-validate` (the enforcement)

Append a fifth reviewer to `commands/spec-validate.md`, after Scope Critic, in the existing one-reviewer-at-a-time idiom:

```markdown
### Reviewer 5: Solution-Design & Extensibility Critic
Look for:
- Is the chosen approach the simplest design that satisfies the requirements,
  or is it over- or under-engineered for what the problem needs?
- Are the 2-3 alternatives real and distinct, or strawmen? Are the tradeoffs honest?
- Coupling & boundaries: does each unit have one clear purpose and a defined
  interface? Can internals change without breaking consumers? A unit that can't be
  described without reading its internals has a boundary problem.
- Extensibility: does the design state what changes when the load-bearing dimension
  grows, and is that claim grounded or hand-waved? Flag "it scales" with no mechanism.
- Is there a materially lower-coupling or more extensible design the spec didn't consider?

**Calibration (critical):** only flag issues that would produce a flawed implementation
or a design that cannot evolve. Do NOT flag stylistic preferences, "this section could
be longer", or theoretical extensibility nobody asked for (YAGNI). Approve unless there
is a real design weakness. If a spec predates this template (no `Approaches
considered` section), raise the absent structure as ONE advisory recommendation,
not a per-point critical flag; do not storm legacy or downstream specs.
```

Reviewer 5 is advisory, exactly like the existing four (PHILOSOPHY "Detect, don't dictate"). It feeds the existing `Spec Validation Report` output and the same `VALIDATED` flip. The calibration clause is mandatory: without it the reviewer becomes the false-positive storm the kit already guards against.

### Part C (designed, deferred): opt-in `/user:design` beat

The interactive part of brainstorming (one question at a time, propose 2-3, present design in sections, approval after each) re-homed as a single opt-in command between `/think` and `/spec`:

```
/user:think      product framing (unchanged)
/user:design     OPT-IN. solution-design conversation:
                 explore alternatives one beat at a time, present the design in
                 sections, hold for user approval per section, then write the
                 Solution block /spec will consume. The user PULLS this lane; the
                 lane holds itself to the approval beat (self-imposed, not kit-imposed).
/user:spec       writes the contract (unchanged; consumes the design if present)
```

Deferred, not built this cycle, for two reasons: the maintainer chose A+B first, and PHILOSOPHY §5 sets a "test on one real project for 1 week before merging" bar for any new component. C is recorded here so the design is ready when a real signal (A+B prove insufficient) arrives. Until then, the rigorous interactive pass is served by `/think` + the user manually using the already-installed `superpowers:brainstorming`.

### Tradeoff table

| Fork | CHOSEN | Rejected alt |
|---|---|---|
| Where depth lives | template scaffold (A) + advisory reviewer (B) | (1) reviewer only: depth is caught but never scaffolded, so every spec re-derives the structure. (2) template only: the 70%-followed problem, shallow fills pass unchecked. |
| Enforcement | advisory reviewer + opt-in self-imposed lane | hard mid-flow gate: PHILOSOPHY- and field-wide-rejected (Spec Kit `/clarify`, BMAD HALT force it and annoy experienced users); reserved for irreversible/safety cost. |
| brainstorming adoption | fork the pattern into kit idiom, cite lineage | depend on `superpowers` at runtime: adds a hard dependency the kit cannot version; violates "external tools are dependencies, not features". |
| Interactive loop (C) | design now, defer behind §5 bar | build C now: unproven; A+B may already close the gap; §5 says test first. |

### NO-list check

Per-part one-sentence descriptions (the spec is multi-part, like SPEC-003/005/006):
- *"The `/spec` Solution template requires 2-3 approaches, the chosen one with reasoning, and an extensibility/boundaries note."*
- *"`/spec-validate` gains a fifth reviewer that flags shallow or non-extensible designs, calibrated against false positives."*
- *"An opt-in `/user:design` beat (deferred) re-homes brainstorming's interactive design loop as a lane the user pulls."*

| Gate | Compliance |
|---|---|
| Guardrails over guidance | partial-and-honest: A is template-grade guidance (weak); B is an advisory reviewer (stronger, not a hard block). No hard gate added. Labeled, not papered over. |
| Synthesize, don't originate | yes: forked from `superpowers:brainstorming` + its spec-document-reviewer prompt; lineage cited; not depended on at runtime. |
| Shallow and wide | yes-with-watch: deepens the Spec+Validate phases that sit at ~70%. Risk = pushing one phase to 100% (the principle warns against). Mitigated by B's calibration and A being structure, not an essay requirement. |
| Detect, don't dictate | yes: B is advisory like the other 4; C is opt-in; no mid-flow block. |
| Bash over binaries | yes: template is markdown, reviewer is prompt text; the Visual Companion (node) is dropped. |
| Serves 2+ phases | yes: serves Spec + Validate now, and Build downstream (a deeper spec = a stronger goal loop). |
| One sentence describable | yes, per part (above). |
| No speculative config | yes: no env var, no flag, no new settings.json field; one reviewer + one template edit; C deferred until a real signal. |

## Solution

| Task | Files | Type | Depends on |
|---|---|---|---|
| TASK-1 | `commands/spec.md` (enrich `## Solution` template) | Command (template) | - |
| TASK-2 | `commands/spec-validate.md` (add Reviewer 5 + calibration + legacy-grace) | Command (reviewer) | - |
| TASK-3 | `tests/test-meta.sh` (assert new Solution sub-headings + 5th reviewer present) | Tests | TASK-1, TASK-2 |
| TASK-4 | `README` + `MANUAL` (note the richer Solution + the 5-reviewer set) + `CHANGELOG` | Docs + hygiene | TASK-1..3 |

(Part C is design-of-record in the Decision section above; it adds no task this cycle. The earlier "record C" task was dropped as a phantom per validation F2.)

### Task Breakdown

**Phase 1: Substance (A + B)**
- [x] **TASK-1: enrich `commands/spec.md` Solution template.** DONE (verified; not yet committed). Replace the one-line `## Solution` block with the four sub-sections (Approaches considered / Chosen approach + why / Extensibility & boundaries / Architecture). Keep it scaffold-grade: prompts, not mandatory essays. Add a one-line lineage comment crediting brainstorming.
  - Acceptance: `commands/spec.md` `## Solution` block contains the four sub-headings; the wording is prompt-style (asks for content, does not demand a fixed length); lineage credited.
- [x] **TASK-2: add Reviewer 5 to `commands/spec-validate.md`.** DONE (verified; not yet committed). Append "Reviewer 5: Solution-Design & Extensibility Critic" after Scope Critic, in the existing per-reviewer idiom, including the mandatory calibration clause. Wire it into the existing `Spec Validation Report` output (no new output format).
  - Acceptance: a 5th reviewer section exists with the isolation/clarity + extensibility lens and the calibration clause ("only flag real problems; not stylistic / 'could be longer' / YAGNI extensibility"); it feeds the existing report; the `VALIDATED` flip is unchanged.

**Phase 2: Verify + hygiene**
- [x] **TASK-3: tests.** DONE (test-meta 126/126; not yet committed). `tests/test-meta.sh`: assert `commands/spec.md` contains the new Solution sub-headings and `commands/spec-validate.md` contains a fifth reviewer (assert on heading/marker presence, not exact prose, to avoid brittle coupling). Note: AC "prompt-grade, not fixed-length" (TASK-1) is review-verified, not test-verified; the suite asserts only structural presence.
  - Acceptance: `bash tests/test-meta.sh` passes with the documented count delta; `bash tests/test-hooks.sh` 42/42 (no hook touched).
- [x] **TASK-4: cross-refs + CHANGELOG.** DONE (verified; not yet committed). README/MANUAL note the richer Solution section and the 5-reviewer validate set; CHANGELOG entry.
  - Acceptance: README/MANUAL updated; CHANGELOG entry present.

(Part C is recorded in the Decision section as design-of-record and adds no task this cycle, deferred behind PHILOSOPHY §5.)

## Acceptance Criteria (global)
- [x] `commands/spec.md` `## Solution` template requires Approaches considered (2-3), Chosen approach + why, and Extensibility & boundaries; prompt-grade, not fixed-length
- [x] `commands/spec-validate.md` has a 5th reviewer (Solution-Design & Extensibility) with the isolation/clarity + extensibility lens and the mandatory calibration clause; advisory, feeds the existing report
- [x] No hard gate added; Reviewer 5 is advisory like the existing four; C is opt-in and deferred
- [x] Lineage to `superpowers:brainstorming` + its spec-reviewer prompt is cited; no runtime dependency on superpowers
- [x] `bash tests/test-hooks.sh` 42/42; `bash tests/test-meta.sh` passes (121 -> 126)
- [x] README/MANUAL/CHANGELOG updated; exactly one reviewer added and one template enriched; no new command, env var, or settings.json field this cycle

## Known limitations
1. **Part A is guidance-grade.** A template heading can be filled shallowly; the "rule followed ~70%" problem PHILOSOPHY names applies. B (the reviewer) is the actual enforcement; A only makes depth cheap to produce. This is stated, not hidden.
2. **Reviewer 5 is advisory, not a hard gate.** A user who skips `/spec-validate` (allowed; normal lane) gets no design review. Consistent with "Detect, don't dictate"; the cost (a weaker design) is reversible, so it is not hard-blocked.
3. **The deferred `/user:design` beat (C) has not met the §5 "1 week on a real project" bar.** It is designed, not built. If A+B prove sufficient in practice, C may never be built; if they do not, C is ready.
4. **No command-behavior harness.** TASK-3 asserts only structural presence of the headings/reviewer, not that the reviewer actually produces good design critique (that is review-verified in use, like the other four reviewers).
5. **A+B serve the *depth* half of the reporting complaint, not the *enforced-feedback* half.** The original signal was twofold: shallow solution AND the flow advancing without the user. A+B fix depth and give `/spec-validate` a design-review beat (its per-reviewer "address this?" prompt fires even under bypass, since `AskUserQuestion` is not permission-gated). But a fully *enforced* design-approval gate is C (deferred), and in bypassPermissions the agent can still auto-run `/spec-validate` and auto-resolve findings without stopping. The practical mitigation until C exists: do not run the design phase under bypass. Surfaced so the maintainer can decide whether to pull C forward.

## Edge Cases
1. **A spec with genuinely one viable approach.** The "Approaches considered" sub-section says so and why the obvious alternatives were rejected; it is not padded with strawman alternatives. Reviewer 5's calibration treats an honest single-approach justification as a pass, not a gap.
2. **A tiny-lane change.** No spec is written (WORKFLOW tiny lane = edit, verify, done), so neither A nor B applies. The depth lane is a normal/full-lane concern.
3. **Reviewer 5 over-flags.** The calibration clause is the guard; if it still storms in practice, the retro signal is to tighten the calibration, not to remove the reviewer (PHILOSOPHY §5 iteration).
4. **User runs `/spec` but skips `/spec-validate`.** They get the richer template (A) but no reviewer (B). Acceptable by design; the suggestion to run `/spec-validate` is surfaced, never forced.
5. **`/spec-validate` run on a spec written before Part A** (any of SPEC-001..007, or a downstream pre-A spec). Reviewer 5 raises the absent `Approaches considered` structure as ONE advisory recommendation, not a per-point critical storm (the legacy-grace clause). The spec still passes on its other merits.
6. **Reviewer 5 and Scope Critic pull opposite ways** (extensibility vs YAGNI/cut). They are read together: Reviewer 5's calibration already exempts "extensibility nobody asked for", so a Scope-Critic cut and a Reviewer-5 pass can coexist on the same design. A genuine conflict is surfaced in the report for the maintainer to adjudicate, not auto-resolved.

## Out of Scope
- A hard gate on solution-design depth (the PHILOSOPHY- and field-rejected pattern).
- Building the `/user:design` command this cycle (deferred behind §5).
- The Visual Companion / any browser mockup tooling (dropped: violates "bash over binaries").
- A runtime dependency on the `superpowers` plugin (we fork the pattern, not the package).
- An extended-thinking cue in `/think` (a separate, smaller change; can be a follow-up if A+B leave a residual depth gap).
- Optimizing Reviewer 5's prompt via AutoResearch (needs a corpus per §5; premature now).

## Decision Log
- **DEC-001**: Fork the substance of brainstorming into A (template) + B (reviewer) now; defer the interactive loop (C). Rationale: A+B close the structural gap; C is unproven and the maintainer chose A+B first.
- **DEC-002**: Enforcement is advisory reviewer + opt-in self-imposed lane, not a hard mid-flow gate. Rationale: hard-gating process depth is the PHILOSOPHY- and field-wide-rejected pattern; the cost of a shallow design is reversible (SPEC-006 DEC-009 set the precedent).
- **DEC-003**: A is acknowledged guidance-grade; B is the load-bearing enforcement. Rationale: a template heading is followed ~70% (PHILOSOPHY); the reviewer is what catches the 30%.
- **DEC-004**: Fork brainstorming's pattern into kit idiom, do not depend on the plugin. Rationale: "synthesize, don't originate" + "external tools are dependencies, not features"; the kit cannot version superpowers.
- **DEC-005**: Reviewer 5 carries the mandatory calibration clause from `spec-document-reviewer-prompt.md`. Rationale: an uncalibrated design reviewer becomes a false-positive storm (SPEC-006 DEC-013 precedent).
- **DEC-006**: The Visual Companion and the global HARD-GATE are dropped; the gate is re-homed as C's self-imposed beat. Rationale: bash-over-binaries; detect-don't-dictate.
- **DEC-007**: bypassPermissions and the missing extended-thinking cue are named as amplifiers, not the root cause. Rationale: even at max thinking with the loop intact, a one-line template + no design reviewer yields a shallow Solution; the gap is structural.
- **DEC-008 (validation)**: Reviewer 5 gains a legacy-grace clause (absent `Approaches considered` -> one advisory recommendation, not a per-point storm). Rationale: every existing/downstream pre-A spec lacks the section; without grace the reviewer storms on day 1 (failure-mode F1; SPEC-006 DEC-013 precedent).
- **DEC-009 (validation)**: The phantom "record C" task was dropped; C is design-of-record in the Decision section, adding no task. Rationale: a task with nothing to implement violates "no phantom features" (scope F2).
- **DEC-010 (validation)**: The root-cause attribution is stated as inferred (no transcript), with the template/validate gaps confirmed by inspection. Rationale: the spec asserted session history with more certainty than the evidence supports (assumption W1).
- **DEC-011 (validation)**: Known limitation 5 added: A+B serve the depth half; the enforced-feedback half is C (deferred) + a bypass-mode dimension. Rationale: the original signal was twofold and A+B only fully close one half; honest scoping over an overclaim (assumption W2).

## Source citations
- The pipeline this enriches: `commands/think.md`, `commands/spec.md`, `commands/spec-validate.md`, `WORKFLOW.md`.
- Forked patterns: `superpowers:brainstorming` 5.1.0 SKILL.md ("propose 2-3 approaches", "design for isolation and clarity", one-question-at-a-time, per-section approval) and its `spec-document-reviewer-prompt.md` (the calibration clause).
- Philosophy adjudication this follows: `docs/PHILOSOPHY.md` ("Detect, don't dictate", "Guardrails over guidance", "Synthesize, don't originate", "Shallow and wide", §5 the "1 week on a real project" bar) and SPEC-006 DEC-009 (the surface+log+gate-review precedent over a hard gate).
- Field context (force-the-design-conversation patterns and their cost): the orchestration deep scan `docs/research/2026-05-20-orchestration-deep-scan.md` (Spec Kit `/clarify`, BMAD HALT as field-wide-rejected hard gates).

## Validation
4 reviewers run 2026-05-20 (security, failure-mode, assumption-destroyer, scope-critic; the current `/spec-validate` set, which is the set this spec would extend with Reviewer 5). Aggregate pre-fix verdict: NEEDS REVISION (design sound; one storm risk, one phantom task, four honesty/scope warnings).

Critical concerns, resolved inline:
- Reviewer 5 would storm specs lacking the new sub-sections -> legacy-grace clause added (DEC-008).
- Phantom "record C" task -> dropped, C folded to design-of-record (DEC-009).

Warnings addressed:
- Root-cause inferred, not transcript-verified -> stated as inferred (DEC-010).
- A+B cover the depth half only; enforced-feedback is C + bypass-mode -> Known limitation 5 (DEC-011).
- Reviewer 5 vs Scope Critic tension -> edge case 6 (read together; YAGNI calibration already exempts unwanted extensibility).
- Untestable "prompt-grade" AC -> marked review-verified in TASK-3.

Security: N/A (doc/prompt change; no auth/input/secret/data/dependency surface); no manufactured issues.

Status flipped to VALIDATED after inline resolution. Re-run `/user:spec-validate` if the design changes materially before execute.
