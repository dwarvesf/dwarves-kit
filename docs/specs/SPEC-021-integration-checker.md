# Spec: Integration-checker agent (cross-task wiring verification)

Generated: 2026-05-21
Status: VALIDATED
Source: agent-scene research 2026-05-21 (the deep dig on adoptable non-persona agent archetypes). Of ~90 agents across 7 toolkits, the integration-checker was the single genuine archetype gap in the kit's 9-agent set; everything else was persona theater, swarm, or a command-dup. Traces to GSD `agents/gsd-integration-checker.md` (read-only adversarial cross-phase verifier).
Depends on: the existing verification pipeline (worker -> task-verifier -> fix-agent, ADR-0005) which this extends at the phase/build boundary; `commands/execute.md` Step 4 (Completion), where it is dispatched. Produces a new ADR-0015.
Lane: full. Adds an agent and wires the orchestrator (`commands/execute.md`).

## Problem

The kit verifies two things and misses the seam between them:
- **per-task**: `task-verifier` runs after each worker, checking that task's acceptance criteria. It is scoped to one task by design.
- **whole-build**: `/execute` runs the full test suite once at each phase checkpoint and at Step 4 completion.

Nothing verifies that the tasks actually **wire together**. The full-suite run silently passes when integration tests do not exist, which is the common case: each unit task passes its own criteria, the suite is green, and yet the new component is never imported, the handler is never registered on a route, or the data chain (form -> handler -> store -> display) is broken at a seam no single task owned. The result is a build that is "all tasks verified, tests green" and still does not work end to end.

This is the one real archetype gap the kit's 9 agents leave open. It is exactly the kind of work a fresh, adversarial context window does better than the orchestrator (which has normalized each task as it passed): assume every cross-task connection is broken until a grep proves the link.

## Solution

### Approaches considered
1. **Extend `task-verifier` to also do cross-task checks.** Tradeoff: `task-verifier` is per-task and runs N times; cross-task wiring is only fully present at the end, so folding it in either runs the expensive global check N times or muddies a single-purpose agent. Rejected.
2. **A new read-only `integration-checker` agent dispatched once at Step 4 (CHOSEN).** Mirrors the proven `task-verifier` shape (read-only, three-verdict) but runs ONCE after all phases pass, checking cross-task wiring and the global acceptance criteria no single task owns. On `FAIL:fixable` it reuses the existing fix-agent retry loop; on `FAIL:escalate` or >2 retries it stops for the human.
3. **A `/integration-check` command.** Tradeoff: a command is human-invoked guidance; the value is automatic dispatch inside the build, and it is verification work a fresh context does best (an agent), not a methodology a human runs. Rejected (it would also duplicate the agent).

### Chosen approach + why
Approach 2. It fills the exact seam (per-task PASS -> [gap] -> full-suite) with the kit's own already-blessed mechanism: a read-only adversarial verifier in a fresh window, reusing fix-agent for fixable gaps. It runs once (bounded cost), is gated to multi-task specs (a single-task spec has nothing to wire), and changes nothing about per-task verification. No new dependency, no persona, no swarm.

### Extensibility & boundaries
- Load-bearing dimension: the cross-task wiring contract (component-defined -> imported -> called; data chain end to end; global acceptance criteria met). If the kit later wants typed integration contracts, the agent's checklist grows; it does not change the dispatch model.
- Unit boundaries: `agents/integration-checker.md` owns the cross-task check; `commands/execute.md` Step 4 owns dispatch; `task-verifier`/`fix-agent` are unchanged. Clear seam: task-verifier answers "is this task correct?", integration-checker answers "do the tasks connect?".
- Reuse: on `FAIL:fixable` it hands the named gap to the existing fix-agent (same max-2 retry cap), not a new fix path.

### Architecture (diagram if it helps)
```
/execute
  Step 2: per phase -> worker -> task-verifier -> fix-agent (max 2)   [unchanged]
  Step 3: phase checkpoint (full suite + human checkpoint)            [unchanged]
  Step 4: Completion
      |
      +-- (NEW) if the spec had >1 task: dispatch integration-checker (read-only)
            |
            checks: every new component is imported AND called (not just defined);
                    data chains flow end to end (form->handler->store->display);
                    global ## Acceptance Criteria that no single task owns are met;
                    no orphaned/dead new code
            +--> PASS: declare build complete
            +--> FAIL:fixable: fix-agent on the named wiring gap (retry < 2) -> re-check
            +--> FAIL:escalate (or retry >= 2): stop, report the broken seam to the human
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** the active spec (`docs/specs/SPEC-NNN-<slug>.md`): its `## Task Breakdown` (what was built) and `## Acceptance Criteria (global)` (the end-to-end claims); **the pre-build base ref**, passed by `/execute` (the commit SHA before Step 2 began), so the agent diffs the WHOLE build via `git diff <base>..HEAD --name-only`, not just the last task's commit (DEC-008); the repo (Read/Grep/Glob to trace links).
- **Outputs / produces:** exactly one verdict, mirroring task-verifier: `PASS` / `FAIL:fixable` (with the named gap + a precise fix instruction for fix-agent) / `FAIL:escalate` (with the broken seam and why it needs a human). Read-only: it never modifies code.
- **Invariants:** dispatched ONCE at Step 4, only when the spec had >1 task (single-task specs skip it); **read-only with SCOPED tools only** (Read/Grep/Glob + `Bash(git diff*)`/`Bash(git log*)` + the test runners, exactly like task-verifier; NO `Edit`/`Write`/`MultiEdit` and NO bare `Bash`, DEC-006); it verifies **each new component reaches its activation point** (a hook registered in `settings.json`/`hooks.json`, a handler mounted on a route, an export imported AND called) plus the spec's STATED end-to-end claims, and it does NOT invent links between independent tasks (DEC-007); it checks cross-task wiring + global acceptance, NOT per-task acceptance (already run by task-verifier); a `FAIL:fixable` reuses the existing fix-agent + max-2 retry, no new fix loop.

### Data model changes
None. The agent reads existing artifacts.

### API / UI / Infrastructure changes
- New: `agents/integration-checker.md` (frontmatter: `name`, `description`, read-only `tools`, `model: sonnet`, mirroring `task-verifier`).
- Edit: `commands/execute.md` Step 4 (Completion) dispatches the integration-checker before declaring the build complete; the verdict routes to fix-agent (fixable) or the human (escalate), reusing the existing retry cap.
- Tests: `tests/test-meta.sh` (agent file present + frontmatter/model already covered by the agent loop; add a presence assertion + a `commands/execute.md` wiring assertion + the MANUAL.md row, which the existing agent<->MANUAL cross-ref test already enforces).
- Docs: MANUAL.md agents table (+1 row, required by the agent<->MANUAL cross-ref test), README/architecture/CLAUDE agent count 9 -> 10; ADR-0015.

## Task Breakdown

**Phase 1 (full lane): the agent**
- [x] **TASK-1: write `agents/integration-checker.md`.** Read-only adversarial cross-task verifier mirroring `task-verifier`'s shape: frontmatter with SCOPED read-only `tools` only (Read/Grep/Glob, `Bash(git diff*)`, `Bash(git log*)`, the test runners; NO Edit/Write/MultiEdit, NO bare Bash, DEC-006), `model: sonnet`. Checklist: every new component reaches its activation point (registered/mounted/imported AND called), the spec's STATED end-to-end chains hold, no orphaned new code, "assume broken until grep proves the link"; explicitly does NOT invent links between independent tasks (DEC-007). Three verdicts (PASS / FAIL:fixable with a precise fix instruction / FAIL:escalate). Cite GSD `gsd-integration-checker` + ADR-0005.
  - Acceptance: `agents/integration-checker.md` exists; `bash tests/test-meta.sh` agent-loop passes (frontmatter + model in {sonnet,haiku,opus}); the file states read-only, the three verdicts, the activation-point rule, and the no-invented-links rule.

**Phase 2 (full lane): wire the orchestrator**
- [x] **TASK-2: dispatch integration-checker in `commands/execute.md` Step 4.** After all phases complete and the final suite runs, if the spec had >1 task, dispatch the integration-checker, passing it the **pre-build base ref** (the SHA recorded before Step 2 began) so it diffs the whole build (DEC-008); route PASS -> complete, FAIL:fixable -> fix-agent (reuse the max-2 retry), FAIL:escalate / retry>=2 -> stop and report the broken seam. Single-task specs skip it.
  - Acceptance: `commands/execute.md` Step 4 references the integration-checker dispatch, the >1-task gate, and handing it the base ref; the routing mirrors the existing verdict handling.

**Phase 3 (full lane): tests + ADR**
- [x] **TASK-3: `tests/test-meta.sh` + ADR-0015.** Add meta assertions that `agents/integration-checker.md` exists, that it carries NO write tools (no `Edit`/`Write`/`MultiEdit`/bare `Bash` in its frontmatter, DEC-006), and that `commands/execute.md` wires the dispatch; write `docs/decisions/0015-integration-checker.md`.
  - Acceptance: `bash tests/test-meta.sh` green with the new assertions; ADR-0015 exists and cites GSD + ADR-0005.

**Phase 4 (full lane): docs + counts**
- [x] **TASK-4: MANUAL / README / architecture / CLAUDE.** Add the MANUAL.md agents-table row (required by the agent<->MANUAL cross-ref test); bump agent count 9 -> 10 in README/architecture/CLAUDE.
  - Acceptance: agent<->MANUAL cross-ref test green; agent count consistent (9 -> 10) across README/architecture/CLAUDE; `bash tests/test-meta.sh && bash tests/test-hooks.sh` both green; no em-dash introduced.

## Acceptance Criteria (global)
- [x] `agents/integration-checker.md` exists: read-only, three-verdict, checks cross-task wiring + global acceptance (not per-task)
- [x] `/execute` Step 4 dispatches it once, only for specs with >1 task, routing fixable -> fix-agent (max 2) and escalate -> human
- [x] It reuses the existing fix-agent retry; it does not add a new fix loop or modify per-task verification
- [x] MANUAL lists the agent (agent<->MANUAL cross-ref test green); agent count 9 -> 10 everywhere
- [x] ADR-0015 records the adoption (GSD lineage, read-only adversarial cross-phase verifier)
- [x] `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` both green; no em-dash introduced

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh`. Spot-checks: `test -f agents/integration-checker.md`; `grep -q integration-checker commands/execute.md`; the meta agent-loop reports integration-checker with a valid model; `grep -c '10 agents' README.md docs/architecture.md CLAUDE.md` is consistent.

## Edge Cases
1. **Single-task spec.** Nothing to wire; the Step 4 gate skips the integration-checker (no cost, no false finding).
2. **Spec with no global acceptance criteria.** The agent still checks import-and-call wiring of new components; it does not invent criteria.
3. **Integration gap that is not fixable in scope** (the design is wrong, not the wiring). `FAIL:escalate` -> human, never an unbounded fix loop.
4. **Greenfield with no integration tests.** This is the exact case the agent exists for: it greps the links directly rather than trusting a (nonexistent) integration test.
5. **`/next` (manual) instead of `/execute`.** The integration-checker is an `/execute` Step 4 dispatch; manual `/next` users self-verify wiring (documented), as they already do for the rest of verification.
6. **Independent multi-task spec** (e.g. two unrelated hooks, like this session's SPEC-014). The agent verifies each component reaches its activation point (each hook registered in `settings.json`/`hooks.json`), but does NOT demand the unrelated tasks link to each other (DEC-007). A defined-but-unregistered hook IS a real finding; an invented cross-link is not.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Integration-checker false-positive (flags a real, working link) | a correct build is blocked at Step 4 | the checklist requires grep-proof of the missing link, not suspicion; FAIL must name the file:symbol that is defined-but-unused |
| It silently re-does per-task work (overlaps task-verifier) | redundant token cost | scope invariant: it checks cross-task wiring + global acceptance only; per-task acceptance is out of scope (already verified) |
| Unbounded fix loop on a design-level gap | tokens burned, no progress | FAIL:escalate for design gaps; fixable path reuses the existing max-2 cap |
| Runs on a single-task spec | wasted dispatch / spurious finding | >1-task gate in Step 4 |
| Agent mis-scoped with a write tool | a "read-only" agent could modify code | meta assertion rejects `Edit`/`Write`/`MultiEdit`/bare `Bash` in the frontmatter (DEC-006) |
| False-flag on an independent-task spec | a spec of unrelated changes is blocked at Step 4 | activation-point check only, no invented inter-task links (DEC-007, Edge Case 6) |
| Agent reads only the last commit, misses earlier-task wiring | a seam introduced in Phase 1 is not checked | `/execute` passes the pre-build base ref; the agent diffs `<base>..HEAD` (DEC-008) |
| Agent missing from MANUAL | agent<->MANUAL cross-ref meta test fails | TASK-4 adds the row; the test is the guard |
| Stale agent count in docs | README says 9, repo has 10 | TASK-4 pins 9 -> 10 across README/architecture/CLAUDE |

## Out of Scope
- **A `doc-verifier` agent** (the research's #2): the independent-verification twin for the `/docs` phase. Deferred; revisit after the integration-checker proves the pattern.
- **A `simplify`/slop-reducer agent**: `/review` + the `simplify` skill already cover it; hold until slop is measured.
- **Parallel or multi-agent integration testing**: out by the one-session boundary.
- **Generating integration tests**: the agent verifies wiring by reading/grepping; it does not write tests (that is worker/main-thread work).

## Decision Log
- **DEC-001**: A new read-only agent dispatched once at Step 4, not an extension of `task-verifier` (which is per-task and would run the global check N times) and not a `/integration-check` command (verification a fresh context does best is an agent, not human-invoked guidance).
- **DEC-002**: Gated to specs with >1 task. A single-task spec has nothing to wire; running it there is cost without signal.
- **DEC-003**: Reuse the existing fix-agent + max-2 retry for `FAIL:fixable`; escalate design-level gaps. No new fix loop (mirrors ADR-0005).
- **DEC-004**: `model: sonnet`, matching `task-verifier`. The check is cross-cutting reasoning over greps, well within sonnet; revisit to opus only if real runs show missed seams.
- **DEC-005**: Adopt as the ONLY agent from the survey now; `doc-verifier` and `simplify` deferred (the agent-scene research found the 9-agent set otherwise complete).
- **DEC-006 (validation, R1)**: the agent's `tools` are pinned to scoped read-only forms (Read/Grep/Glob, `Bash(git diff*)`/`Bash(git log*)`, test runners); no `Edit`/`Write`/`MultiEdit`/bare `Bash`. A meta assertion enforces it. A "read-only" verifier with a write tool is the worst foot-gun (it could "fix" by silently rewriting, the exact thing ADR-0005 separates verifier from fix-agent to prevent).
- **DEC-007 (validation, R2)**: the agent verifies each new component reaches its activation point (registered/mounted/imported AND called) plus the spec's STATED end-to-end chains; it does NOT invent links between independent tasks. Without this it false-flags every independent-task spec (e.g. SPEC-014's two unrelated hooks). A defined-but-unactivated component IS a finding; an invented cross-link is not.
- **DEC-008 (validation, R5)**: `/execute` passes the pre-build base ref so the agent diffs the whole build (`<base>..HEAD`), not just the last task's commit. Without it the agent misses any seam introduced before the final commit.
- **DEC-009 (validation, R4)**: TASK-3 split into TASK-3 (tests + ADR) and TASK-4 (docs + counts); the original bundled 6 files.

## Known limitations
1. **Wiring-by-grep, not by execution.** The agent proves a link exists in the code (imported + called); it does not run the end-to-end path. A link that exists but is logically wrong is the task-verifier's and human's job, not this agent's.
2. **`/next` users are not covered.** Only `/execute` dispatches it; manual builders self-verify wiring (Edge Case 5).
3. **Quality depends on the spec's global acceptance criteria.** If the spec under-specifies the end-to-end claims, the agent has less to check against (it falls back to activation-point wiring).
4. **Value is anticipated, not yet observed, and concentrates in under-tested code.** In a project with real integration tests the full-suite run already catches broken wiring; this agent earns its token cost mainly in greenfield/thin-test code. No retro yet records broken-wiring-passing-CI in kit usage (the same anticipated-not-observed posture as SPEC-013 DEC-006). The maintainer made the timing call by greenlighting it; `/user:retro` should confirm it pays off.

## Open questions
(none blocking. A `/goal` loop building from this spec that hits an uncovered decision appends here, then stops.)

## Source citations
- Archetype + gap analysis: agent-scene research, this session, 2026-05-21.
- Pattern: GSD `agents/gsd-integration-checker.md` (https://github.com/glittercowboy/get-shit-done) - read-only adversarial cross-phase verifier ("assume every connection is broken until grep proves it").
- Mechanism reused: ADR-0005 (verification pipeline: read-only verifier + write-scoped fix-agent + max-2 retry).
- Shape mirrored: `agents/task-verifier.md` (frontmatter, three-verdict output).
- Philosophy bars: `docs/PHILOSOPHY.md` ("Verify before proceeding", "Synthesize, don't originate", no persona theater / swarm, every file justifies its existence).

## Validation
5 reviewers run 2026-05-21 (security, failure-mode, assumption-destroyer, scope-critic, solution-design), inline `/user:spec-validate`. Verdict: NEEDS REVISION -> 4 findings folded -> VALIDATED. No criticals (read-only agent). The R3 warning is owner-accepted.
- Security (R1): "Bash test+git" was too loose -> pinned to scoped read-only tools with a meta assertion rejecting any write tool (DEC-006). A read-only verifier that can write is the worst foot-gun.
- Failure-mode (R2): the agent would false-flag independent-task specs (no cross-link to find) -> rule changed to "each component reaches its activation point + the spec's stated chains, no invented inter-task links" (DEC-007, Edge Case 6).
- Assumption-destroyer (R3): the task-verifier boundary is clean (per-task vs cross-task + global acceptance). But the value is anticipated-not-observed and concentrates in under-tested code (in a well-tested project the suite already catches wiring) -> Known limitation 4, owner-accepted timing call, revisit at retro.
- Scope-critic (R4): TASK-3 bundled 6 files -> split into TASK-3 (tests + ADR) / TASK-4 (docs) (DEC-009). Confirmed it does not balloon into a second verification framework (reuses fix-agent; one dispatch).
- Solution-design (R5): the commit range was unspecified -> `/execute` passes the pre-build base ref so the agent diffs the whole build (DEC-008). The >1-task gate via counting task lines is sound.
Status flipped to VALIDATED after the four findings were folded into I-O invariants / Tasks / Edge cases / Failure modes / Decision Log / Known limitations.

### Code review (post-implementation, fresh-context reviewer)
Verdict: **SHIP** (0 critical/high/medium, 3 LOW). The reviewer proved the read-only contract by experiment (injected `- Write` into the agent frontmatter -> the DEC-006 meta assertion went red, reverted -> green), confirmed the verdict shape is parser-compatible with task-verifier, and confirmed both suites green (meta 187, hooks 92). Two LOW hardenings applied: a "record the pre-build base ref" line added to `/execute` Step 1 (the base-ref primary path, not just the fallback), and the meta wiring assertion strengthened to also require the base-ref hand-off. The third LOW (a cosmetic `..` in `git diff <base>..HEAD`) was left as harmless.
