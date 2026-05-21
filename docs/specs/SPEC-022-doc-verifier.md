# Spec: Doc-verifier agent (independent doc-vs-code fact-check)

Generated: 2026-05-21
Status: VALIDATED
Source: agent-scene research 2026-05-21 (the deep dig on adoptable non-persona agent archetypes), ranked #2 after the integration-checker (SPEC-021, shipped). Traces to GSD `agents/gsd-doc-verifier.md` (read-only adversarial doc fact-checker). Adopted now that the integration-checker proved the read-only-verifier-twin pattern on a real cycle.
Depends on: the verification-pipeline thesis (ADR-0005, a read-only verifier in a fresh window) which this extends to the Docs phase; `commands/docs.md` (Step 4 -> Step 5), where it is dispatched. Sibling of SPEC-021 (integration-checker is the Build twin; doc-verifier is the Docs twin). Produces a new ADR-0016.
Lane: full. Adds an agent and wires a command (`commands/docs.md`).

## Problem

`/docs` both writes and "verifies" documentation in the same context: Step 2 scans for drift, Step 4 applies the fixes, Step 5 commits. Nothing independently checks the result. This is the exact fox-guards-henhouse problem the kit rejects for self-verifying workers (ADR-0005: "the worker who writes code is not the right judge"). The same context that just wrote a doc claim is biased toward believing it.

The Build phase has independent verification (`task-verifier` per task, `integration-checker` for cross-task wiring). The Docs phase has none. So a documented flag that does not exist, a stale count (`14 hooks` when the code has 15), a renamed command still referenced by its old name, or a "phantom feature" the doc describes but the code never shipped, all survive `/docs` because the only reader was the writer. A fresh read against the live code catches them. That fresh read is what is missing.

## Solution

### Approaches considered
1. **A read-only `doc-verifier` agent dispatched by `/docs` (CHOSEN).** After Step 4 applies the doc updates and before Step 5 commits, a fresh-context agent extracts the checkable claims from the updated docs and verifies each against the live code, returning the three-verdict shape. The docs-phase twin of `task-verifier`.
2. **Extend `/review` to also fact-check docs.** Tradeoff: `/review` is code-focused, human-triggered, and not part of `/docs`; doc drift would only be caught if the human happens to run `/review`, not automatically when docs are written. Misses the in-`/docs` check. Rejected.
3. **A `/doc-verify` command.** Tradeoff: human-invoked guidance; the value is automatic dispatch inside `/docs`, and this is verification work a fresh context does best (an agent), not a methodology a human runs. Rejected.

### Chosen approach + why
Approach 1. It applies the kit's own already-proven mechanism (a read-only verifier in a fresh window) to the one lifecycle phase that lacks it, the same way SPEC-021 did for Build. It runs once per `/docs` invocation (bounded cost) and changes nothing about how `/docs` writes; it only adds an independent gate before the docs commit.

### Extensibility & boundaries
- Load-bearing dimension: the claim-extraction + verify-against-code loop. If the kit later wants typed doc contracts (e.g. an assertion that a documented count matches a computed count), the agent's checklist grows; the dispatch model is stable.
- Unit boundaries: `agents/doc-verifier.md` owns the fact-check; `commands/docs.md` Step 4.5 owns dispatch. Clean seam vs the existing agents: `task-verifier` = is this task correct; `integration-checker` = do the tasks connect; `doc-verifier` = do the docs match the code. No overlap.
- Fix routing differs from SPEC-021 on purpose (DEC-003): `/docs` is a main-thread command, not the `/execute` worker pipeline, so a `FAIL:fixable` is fixed by `/docs` re-editing the named drift (bounded, max 2), not by `fix-agent`.

### Architecture (diagram if it helps)
```
/docs
  Step 2: scan for drift (main thread)            [unchanged]
  Step 4: apply doc updates (main thread)         [unchanged]
      |
      +-- (NEW) Step 4.5: dispatch doc-verifier (read-only, fresh context)
            extracts checkable claims from the updated docs, verifies each vs the live code
            +--> PASS: continue to Step 5 (commit)
            +--> FAIL:fixable: /docs re-edits the named drift (max 2), then re-verify
            +--> FAIL:escalate (or retry >= 2): stop, report the contradiction, do not commit
  Step 5: commit                                  [gated on PASS]
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** the doc files `/docs` just updated. Step 4.5 runs BEFORE the Step 5 commit, so those edits are uncommitted; the agent reads the **uncommitted doc diff** (`git diff -- '*.md' 'docs/**'` and the like) to get exactly the changed docs, then Read/Grep/Glob over the live code to confirm each claim (DEC-006). No base ref needed (unlike SPEC-021): the changes are still in the working tree.
- **Outputs / produces:** exactly one verdict, mirroring `task-verifier`/`integration-checker`: `PASS` / `FAIL:fixable` (with the specific doc claim that contradicts code + the precise correction) / `FAIL:escalate` (when the doc/code mismatch needs human judgment, e.g. it is unclear which is right). Read-only: it never edits docs or code.
- **Invariants:** dispatched ONCE per `/docs` run, after Step 4, before the Step 5 commit; **read-only with SCOPED tools only** (Read/Grep/Glob + `Bash(git diff*)`/`Bash(git log*)`; NO `Edit`/`Write`/`MultiEdit`/bare `Bash`, DEC-002); it verifies doc claims against code, it does NOT rewrite docs (that is `/docs`'s job, DEC-003); it flags only claims it can check against the code, it does not invent required documentation (DEC-004).

### Data model changes
None. The agent reads existing artifacts.

### API / UI / Infrastructure changes
- New: `agents/doc-verifier.md` (frontmatter: `name`, `description`, scoped read-only `tools`, `model: sonnet`, mirroring `task-verifier`/`integration-checker`).
- Edit: `commands/docs.md` gains Step 4.5 (dispatch the doc-verifier; route PASS -> commit, FAIL:fixable -> `/docs` re-edit max 2, FAIL:escalate -> stop).
- Tests: `tests/test-meta.sh` (agent presence + no-write-tools assertion + `commands/docs.md` wiring assertion; the generic agent-loop + MANUAL cross-ref already cover frontmatter/model).
- Docs: MANUAL.md agents table (+1 row, required by the agent<->MANUAL cross-ref test), README/architecture/CLAUDE agent count 10 -> 11, CHANGELOG; ADR-0016.

## Task Breakdown

**Phase 1 (full lane): the agent**
- [x] **TASK-1: write `agents/doc-verifier.md`.** Read-only doc fact-checker mirroring `task-verifier`/`integration-checker`: frontmatter with SCOPED read-only `tools` only (Read/Grep/Glob, `Bash(git diff*)`, `Bash(git log*)`; NO Edit/Write/MultiEdit/bare Bash, DEC-002), `model: sonnet`. Checklist: extract each checkable claim from the updated docs (counts, command/flag/env names, file paths, "feature X exists", code-structure claims) and verify it against the live code; flag claims that contradict the code; "assume each claim is wrong until the code proves it"; do NOT invent required docs (DEC-004); read-only, never edits (DEC-003). Three verdicts (PASS / FAIL:fixable with the contradicting claim + precise correction / FAIL:escalate). Cite GSD `gsd-doc-verifier` + ADR-0005.
  - Acceptance: `agents/doc-verifier.md` exists; `bash tests/test-meta.sh` agent-loop passes (frontmatter + model in {sonnet,haiku,opus}); the file states read-only, the three verdicts, and the no-invent rule.

**Phase 2 (full lane): wire the command**
- [x] **TASK-2: add Step 4.5 to `commands/docs.md`.** After Step 4 (apply updates) and before Step 5 (commit), dispatch the doc-verifier; route PASS -> Step 5, FAIL:fixable -> `/docs` re-edits the named drift (max 2 rounds), FAIL:escalate / retry>=2 -> stop and report the contradiction, do not commit (DEC-003).
  - Acceptance: `commands/docs.md` references the doc-verifier dispatch between apply and commit; the routing mirrors the three-verdict handling and the max-2 cap.

**Phase 3 (full lane): tests + ADR**
- [x] **TASK-3: `tests/test-meta.sh` + ADR-0016.** Add meta assertions that `agents/doc-verifier.md` exists, that it carries NO write tools (no `Edit`/`Write`/`MultiEdit`/bare `Bash`, DEC-002), and that `commands/docs.md` wires the dispatch; write `docs/decisions/0016-doc-verifier.md`.
  - Acceptance: `bash tests/test-meta.sh` green with the new assertions; ADR-0016 exists and cites GSD + ADR-0005.

**Phase 4 (full lane): docs + counts**
- [x] **TASK-4: MANUAL / README / architecture / CLAUDE / CHANGELOG.** Add the MANUAL.md agents-table row (required by the agent<->MANUAL cross-ref test); bump agent count 10 -> 11 in README/architecture/CLAUDE; add a CHANGELOG entry.
  - Acceptance: agent<->MANUAL cross-ref test green; agent count consistent (10 -> 11) across README/architecture/CLAUDE; `bash tests/test-meta.sh && bash tests/test-hooks.sh` both green; no em-dash introduced.

## Acceptance Criteria (global)
- [x] `agents/doc-verifier.md` exists: read-only, three-verdict, verifies doc claims against code (does not rewrite docs)
- [x] `/docs` dispatches it once between apply (Step 4) and commit (Step 5), routing fixable -> `/docs` re-edit (max 2) and escalate -> human, gating the commit on PASS
- [x] It is read-only (no write/bare-Bash tools, meta-asserted) and does not invent required documentation
- [x] MANUAL lists the agent (agent<->MANUAL cross-ref test green); agent count 10 -> 11 everywhere
- [x] ADR-0016 records the adoption (GSD lineage, the Docs-phase twin of task-verifier)
- [x] `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` both green; no em-dash introduced

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh`. Spot-checks: `test -f agents/doc-verifier.md`; `grep -q doc-verifier commands/docs.md`; the meta agent-loop reports doc-verifier with a valid model; `grep -c '11 agents' README.md docs/architecture.md CLAUDE.md` is consistent.

## Edge Cases
1. **Docs and code genuinely disagree and it is unclear which is right.** `FAIL:escalate` -> human; the agent does not guess which side to trust.
2. **A doc claim the agent cannot check against code** (a design rationale, a future plan, a subjective description). The agent does not flag it; it only verifies checkable claims (DEC-004).
3. **`/docs` invoked with no doc changes** (nothing drifted). Step 4.5 has nothing to verify; it PASSes trivially (or `/docs` skips the dispatch when Step 4 made no edits).
4. **Re-edit loop does not converge** (the same drift fails twice). `FAIL:escalate` after 2 rounds -> human; no unbounded loop (mirrors the kit's max-2 cap).
5. **A correct doc claim phrased differently than the code** (e.g. "the kit has fourteen hooks" vs `14`). The agent confirms the meaning, not the literal string; it flags only real contradictions, not phrasing.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| doc-verifier false-positive (flags a correct claim) | a true doc is "corrected" wrongly | the agent must cite the `file:symbol`/value in code that contradicts the doc; phrasing differences are not contradictions (Edge Case 5) |
| Agent mis-scoped with a write tool | a "read-only" agent could edit docs/code | meta assertion rejects `Edit`/`Write`/`MultiEdit`/bare `Bash` (DEC-002) |
| Unbounded re-edit loop on stubborn drift | tokens burned, no progress | `/docs` re-edit capped at 2, then escalate (DEC-003) |
| Agent invents required documentation | `/docs` told to add docs nobody asked for | the agent verifies existing claims only; "undocumented feature" surfacing stays `/docs`'s existing job (DEC-004) |
| Agent missing from MANUAL | agent<->MANUAL cross-ref meta test fails | TASK-4 adds the row; the test is the guard |
| Stale agent count in docs | README says 10, repo has 11 | TASK-4 pins 10 -> 11 across README/architecture/CLAUDE |

## Out of Scope
- **A `simplify`/slop-reducer agent** (the survey's #3): held until slop is measured (`/review` + the `simplify` skill already cover it).
- **Generating documentation**: the agent verifies; writing/adding docs stays `/docs`'s job.
- **Verifying prose quality / tone**: out of scope; it checks factual claims against code, not style.
- **`fix-agent` for doc fixes**: `/docs` is not the `/execute` pipeline; the main-thread re-edit is the fix path (DEC-003).

## Decision Log
- **DEC-001**: A read-only `doc-verifier` agent dispatched by `/docs`, not an extension of `/review` (code-focused, human-triggered, not in `/docs`) and not a `/doc-verify` command (verification a fresh context does best is an agent). It is the Docs-phase twin of `task-verifier`, sibling to SPEC-021's Build twin.
- **DEC-002**: Scoped read-only tools only (Read/Grep/Glob, `Bash(git diff*)`/`Bash(git log*)`); no `Edit`/`Write`/`MultiEdit`/bare `Bash`. A meta assertion enforces it (same foot-gun guard as SPEC-021 DEC-006).
- **DEC-003**: `FAIL:fixable` is fixed by `/docs` re-editing the named drift (max 2 rounds), NOT by `fix-agent`. Rationale: `/docs` is a main-thread command, not the `/execute` worker pipeline; the fix belongs to the writer, the verification to the fresh agent. Same separation as ADR-0005, different actor.
- **DEC-004**: The agent verifies CHECKABLE claims against code and flags contradictions; it does NOT invent required documentation or flag unchecked prose. Surfacing undocumented features stays `/docs`'s existing job (Step 2/Rules).
- **DEC-005**: Adopt now (the survey's #2) because SPEC-021 proved the read-only-verifier-twin pattern on a real cycle; `simplify` (the #3) stays deferred until slop is measured.
- **DEC-006 (validation, R2)**: the agent gets its target set from the UNCOMMITTED doc diff (`git diff` of doc files), because Step 4.5 runs before the Step 5 commit, so `/docs`'s edits are still in the working tree. No base ref needed (unlike SPEC-021, which diffs across already-committed task work). Keeps the check scoped to what changed and avoids the base-ref ambiguity SPEC-021's review flagged.
- **DEC-007 (validation, R5)**: doc-verifier is the THIRD read-only-three-verdict agent (task-verifier, integration-checker, doc-verifier). That meets the kit's rule-of-three for abstraction, so a shared "read-only verifier" agent template/convention is now a legitimate consideration. Deliberately NOT done in this spec (it would couple three otherwise-independent agents and is out of SPEC-022's scope); recorded so a future consolidation is a conscious choice, not drift, and flagged for `/user:retro`.

## Known limitations
1. **Checks claims, not completeness.** It catches a doc claim that contradicts the code; it does not guarantee every code feature is documented (that remains `/docs`'s "flag undocumented features" job).
2. **Value is anticipated, not yet observed, and this is the third such verifier.** Like SPEC-013 and SPEC-021, no retro yet records stale-docs-passing-`/docs` in kit usage; the value concentrates when `/docs`'s self-scan is optimistic. With doc-verifier the kit now has THREE read-only verifiers all adopted on anticipated pain (task-verifier was the original, integration-checker and doc-verifier are the new twins). `/user:retro` should evaluate whether the trio collectively earns its token cost before any fourth verifier, and whether DEC-007's shared template is warranted.
3. **Main-thread re-edit, not isolated fix.** Unlike `/execute`'s write-scoped `fix-agent`, the `FAIL:fixable` fix happens in `/docs`'s own context (DEC-003); the independence is in the verify step, not the fix step.

## Open questions
(none blocking. A `/goal` loop building from this spec that hits an uncovered decision appends here, then stops.)

## Source citations
- Archetype + ranking: agent-scene research, this session, 2026-05-21 (doc-verifier was #2 after integration-checker).
- Pattern: GSD `agents/gsd-doc-verifier.md` (https://github.com/glittercowboy/get-shit-done) - read-only adversarial doc fact-checker ("assume every claim is wrong until the filesystem proves it").
- Mechanism reused: ADR-0005 (read-only verifier in a fresh window).
- Shape mirrored: `agents/task-verifier.md` + `agents/integration-checker.md` (SPEC-021): frontmatter, scoped read-only tools, three-verdict output.
- Philosophy bars: `docs/PHILOSOPHY.md` ("Verify before proceeding", "No phantom features", "Synthesize, don't originate", no persona theater / swarm, every file justifies its existence).

## Validation
5 reviewers run 2026-05-21 (security, failure-mode, assumption-destroyer, scope-critic, solution-design), inline `/user:spec-validate` (dogfooding the kit). Verdict: NEEDS REVISION -> 1 clarification folded + 2 warnings recorded -> VALIDATED. No criticals (read-only agent).
- Security (R1): scoped read-only tools + meta assertion (DEC-002), mirroring SPEC-021. Confirmed it cannot be steered into edits.
- Failure-mode (R2): the "Step 4 edit list" input was vague -> made concrete as the uncommitted doc diff, since Step 4.5 precedes the commit (DEC-006). False-positive guard: cite the contradicting code value; phrasing is not a contradiction (Edge Case 5).
- Assumption-destroyer (R3): the seam is real (it verifies `/docs`'s OUTPUT, catching a wrong "fix" the self-scan would not), but it is the third read-only verifier on anticipated-not-observed pain -> Known limitation 2 strengthened; the retro evaluates the trio. Owner-accepted timing call.
- Scope-critic (R4): four tasks atomic (TASK-4 at the 5-file doc limit, low-risk). The fix-routing divergence from SPEC-021 (`/docs` re-edit vs fix-agent, DEC-003) is correct because `/docs` is not the `/execute` pipeline. Not a third framework; an instance of the one pattern.
- Solution-design (R5): rule-of-three for read-only verifiers is now met -> a shared template is a conscious future option, deliberately deferred (DEC-007), not done here.
Status flipped to VALIDATED after the R2 clarification was folded into the I/O contract / Decision Log and the warnings into Known limitations.

### Code review (post-implementation, fresh-context reviewer)
Verdict: **SHIP** (0 critical/high/medium, 4 LOW). The reviewer proved the read-only contract by experiment (injected `- Write` and bare `- Bash` -> the DEC-002 meta assertion went red each time, reverted byte-identical -> green), confirmed the three-verdict shape is parser-consistent with task-verifier/integration-checker, the Step 4.5 placement gates the commit on PASS, counts are consistent at 11, no em-dash, and ADR-0016 is cross-referenced. Both suites green (meta 196, hooks 92). Two LOW polish items applied: the meta wiring assertion now also requires `Step 4.5` (parity with the integration-checker test), and the agent's diff-scope hint was broadened beyond `*.md` (rst/adoc/openapi). One pre-existing, out-of-scope finding noted for follow-up: the kit's own `CLAUDE.md` dev-commands block still says `42`/`121` test counts (actual 92/196), stale before this spec, exactly the kind of drift the doc-verifier is built to catch.
