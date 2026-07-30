# Spec: kit:test-writer + spec-less test-plan entry (Gap A)
Generated: 2026-07-30
Status: DRAFT
Lane: normal
References: [drafts/test-writer.md, the kit:meta-agent-drafted subagent this spec promotes into agents/test-writer.md, imitate its tool-scoping (Read/Write/Edit/Grep/Glob + Bash scoped to test-runner invocations only, matching agents/task-verifier.md's exact Bash allowlist) and its "done = file executes, not passes" contract. commands/spec.md Step 1, imitate its greenfield/brownfield branch shape for the new Step 0 in test-plan.md. docs/impl-playbook/exploratory-testing.md and docs/impl-playbook/test-case-design.md, the two technique references both new pieces defer to rather than re-deriving.]

## Problem
The operator wants an end-to-end path from "a feature exists" to "it has proper test coverage," run through the kit rather than ad hoc. SPEC-202 (`/kit:test-harden`) already closes the middle of that path (spec's acceptance criteria -> hardened, critiqued `## Test plan` matrix) but explicitly declines two things, naming both as separate, later steps: (1) what happens when there is no spec at all because the feature is already live and nothing is being changed, and (2) what happens after a SOLID verdict, turning the matrix into real, runnable test code. This spec builds exactly those two declined pieces, changing neither SPEC-202's scope nor its files' `## Test plan`/`## Test plan critique` logic.

## Solution

### Approaches considered
1. **A new standalone command for the no-spec case** (e.g. `/kit:spec-from-behavior`). Rejected: `kit:research-features` already does the read-only feature-mapping this needs; a whole new command duplicates 90% of an existing lane for one small branch. Ladder rung 2 applies (reuse before build).
2. **Auto-chain `kit:test-writer` onto a SOLID verdict** (test-harden or test-plan-review-team calls it automatically). Rejected on the same additivity grounds SPEC-202 itself used to reject folding critique into `test-plan`: every author/critique/materialize triple in this kit (`spec`/`spec-validate`, `test-plan`/`test-plan-review-team`) stays independently runnable, and SPEC-202 already declined this exact auto-chain in its own Out of Scope. A third silent auto-chain would be the one place the kit breaks its own convention.
3. **Chosen**: (a) a `Step 0` branch inserted into `commands/test-plan.md`'s existing Step 1, gated on "no spec AND feature already live," delegating to `kit:research-features` and writing a minimal spec stub with only `## Acceptance Criteria`; (b) a new `agents/test-writer.md` (promoted from the already-drafted `drafts/test-writer.md`) plus a thin `commands/test-write.md` dispatcher that resolves a SOLID-verdict `## Test plan critique`, dispatches `kit:test-writer` per matrix row, and reports, mirroring `test-plan.md`'s own thin-command shape.

### Chosen approach + why
Reuses `kit:research-features` unchanged (no new research logic), reuses the exact author/critique/materialize additivity convention already precedented twice in this kit, and closes precisely the two gaps SPEC-202 named and declined, no more.

### Extensibility & boundaries
- What changes when the load-bearing dimension grows: if a repo has no existing test framework at all (greenfield-inside-brownfield), `kit:test-writer` reports that as a blocking finding rather than inventing a framework choice; framework selection is out of scope for this spec.
- Unit boundaries: Step 0 owns only spec-stub authoring (no critique, no test-writing). `kit:test-writer` owns only turning matrix rows into test code (no critique, no spec-stub authoring). `commands/test-write.md` owns only resolution + dispatch + report (no test-design logic of its own, same as `test-harden.md`'s coordinator shape).

### Architecture
See `## Design` below.

## Design

### Approaches considered + chosen
See `## Solution` above; same three options, same choice.

### Diagram (ASCII, per operator's global no-mermaid rule, same override precedent as SPEC-202 DEC-003)

```
              commands/test-plan.md Step 1
                          |
          spec has Acceptance Criteria?
              |                      |
             yes                     no, feature already live
              |                      |
              v                      v
        Step 1 (unchanged)    Step 0 (NEW)
              |                 kit:research-features,
              |                 one-line charter (SBTM,
              |                 personal-scale per
              |                 exploratory-testing.md)
              |                      |
              |                 write minimal spec stub:
              |                 Status: DRAFT (reverse-engineered)
              |                 ## Acceptance Criteria only
              |                      |
              +----------+-----------+
                         v
              (existing) Step 2-4: enumerate matrix,
              write ## Test plan into the spec
                         |
                         v
              /kit:test-plan-review-team
              (existing bounded critique loop)
                         |
                         v
              SOLID verdict on ## Test plan critique
                         |
                         v
              commands/test-write.md (NEW, thin)
              resolves the SAME spec + SOLID verdict,
              dispatches kit:test-writer (NEW agent)
              per matrix row
                         |
                         v
              kit:test-writer writes real test code,
              one case per row, technique-tagged
              (EP/BVA/decision-table/state-transition
              per test-case-design.md), layer chosen
              per testing-strategy.md (Fowler pyramid)
                         |
                         v
              real test suite executes (done = file
              runs, not "tests pass" -- failing
              assertions are kit:fix-agent's job)
```

### ADR link(s)
None. Both pieces are reversible and additive, same class of decision as SPEC-202 (no ADR).

### Boundaries & failure modes
Out of bounds: Step 0 never invents acceptance criteria beyond what `kit:research-features` actually observes (an unobserved behavior is a gap, not a guess). `kit:test-writer` never edits the spec's `## Acceptance Criteria` or `## Test plan critique` sections (frozen-evaluator rule, same convention as `execute.md:424,434` / ID-325's grader-freeze check) and never asserts a test passes, only that it runs. See `## Failure modes` below.

## Technical Design

### Interfaces (I/O contract)

**Step 0 (in `commands/test-plan.md`):**
- Inputs: a target feature area (files/routes/behavior) with no existing spec, and an explicit signal from the operator that nothing is being built, only backfilling test coverage.
- Outputs: `docs/specs/SPEC-NNN-<slug>.md` with `Status: DRAFT (reverse-engineered)` and a `## Acceptance Criteria` section only. No `## Solution`/`## Design`/`## Task Breakdown`, those describe work being planned, and none is.
- Falls through to the existing Step 1 unchanged once the stub exists.

**`agents/test-writer.md`:**
- Inputs: one or more reviewed `## Test plan` matrix rows (post-`test-plan-review-team` SOLID verdict), the target repo's existing test framework/conventions (detected from existing test files, never invented).
- Outputs: real test code, one case per row, each traceable to its technique (EP/BVA/decision-table/state-transition) via a terse comment or test-name suffix. Layer choice (`testing-strategy.md`) decides where the case lives; personal-scale calibration (`test-case-design.md`) decides whether decision-table/state-transition scaffolding is warranted for a given row.
- Frozen-evaluator: MUST NOT edit `## Acceptance Criteria` or `## Test plan critique` in the spec it is grading against.
- Done condition: the written test file is syntactically valid and executes under the project's test runner. A failing assertion is not this agent's failure; that is `kit:fix-agent`'s job downstream.
- Tools: `Read, Write, Edit, Grep, Glob` + `Bash` scoped to `npm test*`/`go test*`/`pytest*`/`cargo test*`/`bash tests/*`/`make test*`/`just test*` only (matches `agents/task-verifier.md`'s existing allowlist verbatim; no bare Bash).

**`commands/test-write.md` (new, thin dispatcher):**
- Inputs: the active spec (same branch-aware resolution as `test-plan.md`/`test-harden.md` Step 1), requires its `## Test plan critique` to carry a fresh SOLID verdict (same freshness/scoping rule SPEC-202 Reviewers 1/2/3 hardened into `test-harden.md`'s own verdict read, reused, not reimplemented).
- Not SOLID, or lane-incomplete -> stop, name what is missing, point at `/kit:test-harden`. Never dispatch `kit:test-writer` against an unreviewed or stale matrix.
- Dispatches `kit:test-writer` once per matrix row (or batched, implementer's choice, as long as every row is covered or explicitly reported skipped with a reason).
- Reports: files written, rows covered, rows skipped + why, and whether the written tests executed cleanly.
- Autonomous-caller contract: under `bypassPermissions`, stops and surfaces on missing-SOLID exactly like `test-harden.md` does; never fabricates a SOLID to proceed.

### Data model changes
None.

### API changes
None (all changes are markdown command/agent definitions + docs).

### UI changes
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Foundation (Gap A)
- [ ] TASK-001: Insert `### Step 0: No active spec, feature already live` into `commands/test-plan.md`, positioned before the existing Step 1, per the `## Design` diagram above. Delegates to `kit:research-features` with a one-line charter, writes the minimal spec stub, falls through to Step 1 unchanged. Acceptance: `grep -A5 "Step 0" commands/test-plan.md` shows the new section; `grep -c "Solution\|Task Breakdown" <(sed -n '/Step 0/,/Step 1/p' commands/test-plan.md)` returns `0` (the stub-authoring text does not describe planning sections it must not write).

### Phase 2: Core (test-writer materialization)
- [ ] TASK-002: Promote `drafts/test-writer.md` to `agents/test-writer.md` (move, do not recreate), matching `agents/task-verifier.md`'s frontmatter shape exactly (tools list, model tier). Acceptance: `agents/test-writer.md` exists, `drafts/test-writer.md` does not; frontmatter `tools:` line matches the Bash allowlist named in `### Interfaces` above verbatim.
- [ ] TASK-003: Write `commands/test-write.md` per the `### Interfaces` contract above (resolve spec + SOLID verdict, dispatch `kit:test-writer` per row, report). Acceptance: `head -3 commands/test-write.md` shows valid frontmatter with a non-empty `description`; `grep -c "SOLID" commands/test-write.md` is non-zero (the freshness/verdict gate is present, not skipped).

### Phase 3: Discovery + docs
- [ ] TASK-004: Add a one-line "Next:" pointer in `commands/test-harden.md`'s SOLID branch (if SPEC-202 has landed by the time this runs) or in `commands/test-plan-review-team.md`'s own hand-off (if it has not) naming `/kit:test-write` as the step after a SOLID verdict. Acceptance: `grep -l "test-write" commands/test-harden.md commands/test-plan-review-team.md` returns at least one file.
- [ ] TASK-005: Bump every pinned command/agent count assertion to include the new command (`test-write.md`) and new agent (`test-writer.md`): `tests/test-command-emit-sweep.sh`'s command-count assertion, `tests/test-meta.sh`'s README/header/table counts, `docs/architecture.md`'s command and agent inventory tables, `docs/MANUAL.md`/`docs/WORKFLOW.md` if they also pin a count. Acceptance: `bash tests/test-command-emit-sweep.sh && bash tests/test-meta.sh` both pass green with both new files present.
- [ ] TASK-006: Add the `## Source` footer to `commands/test-write.md` (naming `test-plan-review-team.md`'s verdict shape it reuses and `agents/test-writer.md` it dispatches) and to `agents/test-writer.md` (naming `test-case-design.md`, `testing-strategy.md`, and the `execute.md:424,434` frozen-evaluator convention it follows). Acceptance: both footers present, files named, no overclaim.

### Phase 4: Verification
- [ ] TASK-007: Add a dedicated test (e.g. `tests/test-test-writer-contract.sh`) asserting: `agents/test-writer.md`'s Bash tool grant contains no bare `Bash`, only the scoped test-runner patterns; `commands/test-write.md` stops (does not dispatch) when the resolved spec's `## Test plan critique` is absent or not SOLID (fixture-driven negative control, mirroring `test-harden.md`'s own negative-control style from SPEC-202's Verification section). Acceptance: the new test file passes; a fixture spec with a REVISE verdict causes `commands/test-write.md`'s documented logic to stop (verified by inspecting the command's stop-branch text against the fixture, same static-assertion style `test-meta.sh` already uses for other commands).
- [ ] TASK-008: Run the full existing suite green with both new files present and record the proof: `bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh && bash tests/test-outcome-emit-sweep.sh && bash tests/test-test-writer-contract.sh`. Acceptance: all four pass.

## After state
- [ ] `commands/test-plan.md` can produce a coverage matrix for a live, spec-less feature without sending the operator to `/kit:spec` (which wants a feature idea, not a description of what already exists). (Today: no spec, no acceptance criteria -> dead end.)
- [ ] A SOLID-verdict `## Test plan critique` can be turned into real, executing test code via `/kit:test-write` + `agents/test-writer.md`, without hand-writing every case. (Today: the matrix is the end of the line; nothing materializes it into code.)
- [ ] Zero duplicated logic: neither new piece re-implements `kit:research-features`, `test-plan-review-team`'s critique loop, or `kit:fix-agent`'s retry logic. (Today: N/A, pieces do not exist.)
- [ ] Pinned command/agent counts stay accurate with both new files present.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Step 0 never fabricates an acceptance criterion `kit:research-features` did not actually observe
- [ ] `kit:test-writer` never edits a spec's `## Acceptance Criteria` or `## Test plan critique` sections
- [ ] `commands/test-write.md` refuses to dispatch against a missing, stale, or non-SOLID verdict
- [ ] No regressions to `commands/test-plan.md`'s existing Step 1-4 behavior, or to SPEC-202's `test-harden.md` once it lands
- [ ] `bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh && bash tests/test-outcome-emit-sweep.sh && bash tests/test-test-writer-contract.sh` all pass green

## Verification
`bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh && bash tests/test-outcome-emit-sweep.sh && bash tests/test-test-writer-contract.sh` all green. Negative control: a fixture spec with a `REVISE` (not `SOLID`) verdict in `## Test plan critique` must cause `commands/test-write.md`'s documented stop branch to fire, never a false dispatch.

## Edge Cases
1. Step 0 invoked on a feature with genuinely no observable behavior yet (stub code, unimplemented) -> `kit:research-features` reports nothing to map; Step 0 says so and does not write a spec stub with fabricated criteria.
2. `kit:test-writer` dispatched against a repo with no existing test framework -> reports this as a blocking finding, does not invent a framework choice.
3. A matrix row's `Proof` column is `TBD` (per `test-plan.md`'s own honesty rule) -> `kit:test-writer` writes the test with a clearly marked incomplete assertion and flags it in its report, does not silently invent a proof.
4. `commands/test-write.md` invoked on a spec whose `## Test plan critique` is stale (same freshness check SPEC-202 hardened) -> same stop as a missing verdict, never treated as valid.
5. Re-running `/kit:test-write` after a hand-edit to the generated tests -> not solved here (inherited exposure, same class as SPEC-202's Edge Case 7); documented, not guarded.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Step 0 fabricates acceptance criteria beyond what was actually observed | Spec stub's `## Acceptance Criteria` entries have no corresponding `kit:research-features` finding | Prevented by construction: Step 0 only transcribes findings, never invents; treated as a review-time check, not an automated one |
| `kit:test-writer` invents a test framework | Written test files use a framework absent from the repo's existing test files | Blocking finding in the agent's report, no file written |
| `commands/test-write.md` dispatches against a stale/non-SOLID verdict | The freshness/verdict-scope check (reused from SPEC-202) fails | Stop, report which check failed, never dispatch |
| Concurrent edits to `commands/test-plan.md` (this spec's Step 0) and `commands/test-harden.md` (SPEC-202, if still in flight) | Both specs modify files in the same family; a merge could silently drop one side | Both specs are additive to different sections/files where possible; a human resolves any real merge conflict, not auto-merged |

## Out of Scope
- Auto-chaining `kit:test-writer` onto a SOLID verdict without an explicit `/kit:test-write` invocation (same additivity reasoning as SPEC-202's own Out of Scope).
- Choosing or scaffolding a test framework for a repo that has none.
- Any change to SPEC-202's own `test-harden.md`, `test-plan.md` Steps 1-4, or `test-plan-review-team.md`'s critique logic.
- A lock or concurrency-control mechanism for specs edited by multiple sessions (inherited exposure, same as SPEC-202).

## Decision Log
- DEC-001: `kit:test-writer` is an AGENT (`agents/test-writer.md`), not a standalone command, dispatched by the new thin `commands/test-write.md`. Rationale: matches `kit:fix-agent`'s shape (a dispatched worker, not directly user-invoked) since its job is narrow and mechanical; the thin command owns resolution/gating, the agent owns writing.
- DEC-002: Gap A is a `Step 0` inserted into the EXISTING `commands/test-plan.md`, not a new command. Rationale: ladder rung 2 (reuse), and `commands/test-plan.md` already owns "what goes into the matrix"; a spec-less entry point is the same ownership, just an earlier gate.
- DEC-003: This spec explicitly does not auto-chain onto SPEC-202. Rationale: preserves the kit's own additivity convention that SPEC-202 itself used to reject folding critique into `test-plan.md`.
- DEC-004: Numbered SPEC-203 via `spec-next.sh reserve` (not `next`) to atomically claim the number given a live concurrent session was actively committing to SPEC-202 on the same branch at spec-authoring time.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)

## Review
(not yet run; `/kit:spec-validate` is the natural next step before `/kit:execute`, same as SPEC-202)
