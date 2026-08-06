# Spec: Goal-loop fidelity (pointer-`/goal`-ready specs)

Generated: 2026-05-21
Status: VALIDATED
Source: maintainer decision Q3 (2026-05-20) + goal-readiness convergence (2026-05-21). Backlog: ID-012.
Depends on: SPEC-008 (Solution depth) and SPEC-009 (I/O contract + Failure modes) already in the `/spec` template; this adds the last two stop-criteria sections. Conceptual lineage: the user's `/goal` orchestration loop + the `goal-craft` skill contract ("named verification command, scope fence, termination-on-blocker clause").
Lane: P1 = normal (template addition + tests/docs; no auth/data/hook/migration risk). P2 = full (touches the autonomous loop + verification pipeline), held.

## Problem

A "pointer-`/goal`" hands a long-running, self-re-injecting loop a single spec as its source of truth. For that loop to run unattended it needs two things from the spec, and the `/spec` template provided neither:

1. **A machine-runnable done-check.** The loop must know, without a human, when the work is finished. `## Acceptance Criteria (global)` is human-readable prose checkboxes; nothing named the exact command(s) the loop runs to prove completion.
2. **A blocker landing zone.** When the loop hits a decision the spec does not cover, it must stop and record the blocker rather than guess. There was no designated place for that, so a loop either guesses (scope drift) or halts silently.

Without these, every spec had to be hand-massaged before it could back a `/goal` loop. The goal: any spec the template produces is natively pointer-`/goal`-ready.

The theme has two parts, deliberately split:
```
P1  make specs loop-READY        -> template emits the contract     -> BUILD NOW (normal lane)
P2  make the loop CONSUME it      -> QA gate around the loop itself   -> HELD (full lane)
```

## Solution

### Approaches considered
1. **Pin two sections in the `/spec` template (`## Verification`, `## Open questions`).** Every generated spec carries the contract by default; tests assert their presence. Tradeoff: relies on the author filling `## Verification` with real commands (placeholder risk), but that is what `/spec-validate` Reviewer 4 already checks for testability.
2. **A Stop-hook that refuses to flip a spec to VALIDATED without a Verification command.** Tradeoff: a kit-wide hard gate on spec shape, which PHILOSOPHY ("Detect, don't dictate") rejects; also the `tests/test-meta.sh` assertion already gives us the cheap structural guard without a runtime gate.
3. **A separate `/user:goal-prep` command that retrofits a spec for loop use.** Tradeoff: a new command and a second source of truth for "what makes a spec done"; over-engineered when the template is the natural home.

### Chosen approach + why
Approach 1. The template is where every spec is born, so pinning the two sections there makes loop-readiness the default with the smallest surface: two headings plus two structural test assertions. Approach 2 was rejected as a PHILOSOPHY-barred hard gate (the test assertion covers the structural need without blocking). Approach 3 was rejected for adding a command and a competing definition of "done".

### Extensibility & boundaries
- Load-bearing dimension: the spec-to-loop contract (what a `/goal` loop reads out of a spec). P1 fixes the two fields the loop needs; if the loop contract grows later (e.g. a structured machine-readable block), it extends these two sections rather than replacing the lane model.
- Unit boundaries: the change lives entirely in `commands/spec.md` (the template) and `tests/test-meta.sh` (the guard). It does not touch hooks, the `/goal` loop, or any other command. P2 (loop consumption) is a separate unit, separately specced/built.

### Architecture (diagram if it helps)
```
/user:spec  ->  SPEC-NNN now always contains:
                  ## Verification      the exact command(s) that prove the spec done
                  ## Open questions    "(none)"; a /goal loop appends a blocker here, then stops
                          |
                          v
        pointer-/goal loop  ->  runs ## Verification to decide done
                            ->  on an uncovered decision, appends to ## Open questions and STOPS
                            (consumption side; P2 + the goal-craft skill, NOT built here)
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** none new at authoring time; the spec author fills `## Verification` with the project's real check command(s).
- **Outputs / produces:** two new headings in every generated spec. `## Verification` carries one runnable line a loop (or human) executes to confirm completion. `## Open questions` is the append target a loop writes a blocker into before halting.
- **Invariants:** the two headings are present in the template verbatim (`tests/test-meta.sh` asserts this); `## Verification` is distinct from `## Acceptance Criteria (global)` (machine-runnable command vs human prose) and must not be merged into it; the template change is forward-only (it does not rewrite specs already written).

### Data model changes
None.

### API / UI / Infrastructure changes
`commands/spec.md`: two headings added to the generated-spec template; the `## Decision Log` example line de-em-dashed in the same edit (commas, per the no-em-dash house rule, so downstream-generated specs do not inherit em-dashes). `tests/test-meta.sh`: two presence assertions. `CHANGELOG.md` + `MANUAL.md`: documented. `_meta/BACKLOG.md`: ID-012 split into P1 (build now) / P2 (held).

## Task Breakdown

**Phase 1 (P1, normal lane): make specs loop-ready**
- [x] **TASK-1: add the two stop-criteria sections to the `/spec` template.** In `commands/spec.md`, add `## Verification` (instructed to name real commands, not "tests pass") after `## Acceptance Criteria (global)`, and `## Open questions` (defaulting to "(none; a /goal loop appends here ... then stops)") at the end. De-em-dash the `## Decision Log` example line in the same pass.
  - Acceptance: `commands/spec.md` contains both headings with the instructional body text; no em-dash introduced.
- [x] **TASK-2: guard the template + document the change.** Add two `grep -qF` assertions to `tests/test-meta.sh` (one per heading). Document in `CHANGELOG.md` ([Unreleased] Changed) and `MANUAL.md` (`/user:spec` section). Split `_meta/BACKLOG.md` ID-012 into P1 (executing) / P2 (held) with the dependency note.
  - Acceptance: `bash tests/test-meta.sh` passes with the two new assertions (suite 133 -> 135); CHANGELOG/MANUAL/BACKLOG reflect P1; the CHANGELOG suite-total line matches the actual count.

**Phase 2 (P2, full lane): HELD, not built here**
- [ ] **TASK-3 (held): QA gate around the autonomous `/goal` loop** (verify-into-loops + the SPEC-006 completeness clauses + a Reviewer-5 pass on loop output). Held until the pointer-`/goal` pattern has real runs, because it overlaps the still-unbuilt SPEC-006 completeness clauses and the existing verification pipeline, and building it before there is loop telemetry risks designing the gate against an imagined loop. Re-open when 3+ real pointer-`/goal` runs exist to design against.

## Acceptance Criteria (global)
- [x] The `/spec` template emits `## Verification` and `## Open questions` so any generated spec is pointer-`/goal`-ready
- [x] `## Verification` is distinct from `## Acceptance Criteria (global)` (a runnable command, not prose)
- [x] `tests/test-meta.sh` asserts both headings; `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` both green
- [x] CHANGELOG / MANUAL / BACKLOG document P1 and explicitly mark P2 as held
- [x] No em-dash introduced into the template; no legacy spec rewritten

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh` (the two added meta assertions prove the template carries both stop-criteria headings; hooks suite proves no regression). Spot-check: `grep -c -E '^## (Verification|Open questions)$' commands/spec.md` returns `2`.

## Edge Cases
1. **Author leaves `## Verification` as the example text.** The spec validates structurally but a downstream pointer-`/goal` would run the wrong command. Caught by `/spec-validate` Reviewer 4 (acceptance criteria must be testable / commands must be real); the template body explicitly says "Name real commands, not 'tests pass'."
2. **Tiny-lane work with no spec.** No spec means no `## Verification`; that is by design (tiny lane skips the spec), not a regression. Pointer-`/goal` is a normal/full-lane pattern.
3. **A loop hits an uncovered decision.** It appends to `## Open questions` and stops, instead of guessing; the maintainer resolves and re-runs. (This is the consume-side behavior P1 enables; the loop wiring itself is P2 / the goal-craft skill.)
4. **Legacy specs (SPEC-001..011) lack the two sections.** Forward-only by design; backfilling is out of scope and `/spec-validate` Reviewer 5 is calibrated not to storm legacy specs.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `## Verification` left as placeholder / non-runnable | a pointer-`/goal` runs a command that does not exist or never passes | template instructs "real commands, not 'tests pass'"; `/spec-validate` Reviewer 4 flags untestable acceptance before VALIDATED |
| `## Verification` collapsed into `## Acceptance Criteria` by a future refactor | specs lose the single runnable done-check; loops can't self-verify | invariant + DEC-002 record why they are separate; the test asserts `## Verification` presence so a merge breaks the suite |
| Loop ignores `## Open questions` and guesses | scope drift; spec's intent diverges from output | consume-side guarantee is P2 + the goal-craft skill, not P1; P1 only guarantees the landing zone exists (Known limitation 1) |
| Stale suite-total in CHANGELOG after adding assertions | CHANGELOG says one count, `test-meta.sh` reports another | TASK-2 acceptance pins the CHANGELOG total to the real count (133 -> 135) |

## Out of Scope
- **P2: the loop-consumption QA gate** (held; separate full-lane build once real runs exist).
- Backfilling `## Verification` / `## Open questions` into already-written specs (forward-only).
- Wiring the `/goal` loop to read these sections (that lives in the user's `/goal` + `goal-craft` skill, outside the kit).
- A Stop-hook / hard gate enforcing a Verification command (PHILOSOPHY-rejected; the structural test is the chosen guard).

## Decision Log
- **DEC-001**: Split ID-012 into P1 (template stop-criteria, build now) and P2 (loop QA gate, held). Rationale: P1 is a low-risk template change with immediate value; P2 should be designed against real loop telemetry, not an imagined loop, and overlaps unbuilt SPEC-006 work.
- **DEC-002**: `## Verification` is deliberately separate from `## Acceptance Criteria (global)`: the former is the single machine-runnable command a loop executes, the latter is human-readable prose. Recorded to prevent a future "these look redundant, merge them" refactor that would break loop-readiness.
- **DEC-003**: Guard the template with a `tests/test-meta.sh` structural assertion rather than a Stop-hook gate. Rationale: PHILOSOPHY "Detect, don't dictate"; the cheap structural test gives the guarantee without a runtime block.
- **DEC-004**: De-em-dash the template's `## Decision Log` example in the same edit, so downstream-generated specs do not inherit em-dashes (house rule).
- **DEC-005 (validation)**: the placeholder-`## Verification` risk is mitigated by the template instruction + `/spec-validate` Reviewer 4, not by a new check (failure-mode + assumption reviewers). No new machinery.

## Known limitations
1. **P1 produces the contract; it does not consume it.** Making a `/goal` loop actually read `## Verification` and append to `## Open questions` is the pointer-`/goal` author's job (the `goal-craft` skill) plus P2. P1's guarantee is that every spec now *carries* the contract, not that any loop honors it.
2. **`## Verification` quality is author-dependent.** The template can require the section's presence (tested) but not the realism of its command; `/spec-validate` Reviewer 4 is the human-in-the-loop backstop.

## Open questions
(none; P2's design is intentionally deferred until real pointer-`/goal` runs exist to design the QA gate against. A `/goal` loop that hits an uncovered decision while building from this spec would append here, then stop.)

## Source citations
- The backlog item: `_meta/BACKLOG.md` ID-012 (P1 / P2 split).
- The contract this aligns to: the user's `/goal` orchestration loop + the `goal-craft` skill ("named verification command, scope fence, termination-on-blocker clause").
- Template sections it builds on: SPEC-008 (Solution depth), SPEC-009 (I/O contract + Failure modes).
- Philosophy bar: `docs/PHILOSOPHY.md` ("Detect, don't dictate").

## Validation
5 reviewers run 2026-05-21 (security, failure-mode, assumption-destroyer, scope-critic, solution-design & extensibility), dogfooding the reviewer set SPEC-008/009 built. Verdict: APPROVED (warnings are acknowledged limitations, no correctness blocker).
- Security (R1): N/A. The change is a markdown template edit plus two grep assertions; no auth, input, secret, or data surface.
- Failure-mode (R2): the `## Verification` placeholder risk is real -> captured as a failure-modes row + Edge Case 1, mitigated by the template instruction and Reviewer 4 (DEC-005). No SPOF.
- Assumption-destroyer (R3): surfaced the implicit "the loop will read these sections" assumption -> made explicit as Known limitation 1 + the P1/P2 boundary; P1 only guarantees the sections exist.
- Scope-critic (R4): P1 is atomic (two headings + two assertions, 1 session); P2 is correctly held out of P1's task list; legacy-spec backfill correctly scoped out. Acceptance is testable (grep). Passed.
- Solution-design (R5): the template addition is the simplest design that makes specs loop-ready; alternatives (Stop-hook gate, separate command) are heavier and rejected with reasons. Flagged the `## Verification` vs `## Acceptance Criteria` overlap -> resolved by DEC-002 (kept separate, with rationale). Passed.
Status flipped to VALIDATED after the warnings were folded into Failure modes / Known limitations / Decision Log (no code change required; P1 was already implemented and green).
