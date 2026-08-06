# Spec: Systematic debug loop (`/user:debug` + guess-fix guard)

Generated: 2026-05-21
Status: VALIDATED
Source: maintainer request 2026-05-21 ("besides our SDLC, anything else from superpowers worth picking up"). The gap analysis named systematic-debugging as the one real lifecycle hole. This reverses the deferral in ADR-0008 ("adopt `systematic-debugging` ... deferred, no pain signal; if it becomes a real gap, build as a hook, not a skill"). Cross-framework survey 2026-05-21: obra/superpowers `systematic-debugging`, glittercowboy/get-shit-done `gsd-debugger`, doraemonkeys/claude-code-debug-mode, SuperClaude `/sc:troubleshoot`. Lineage anchors: David Agans, "Debugging: The 9 Indispensable Rules" (2002); Andreas Zeller, "Why Programs Fail" (delta debugging).
Depends on: the verification pipeline (worker -> task-verifier -> fix-agent, ADR-0005), which Phase 4's failing-test-first feeds into; the anti-rationalization Stop hook (`hooks/anti-rationalization.sh`), which the guess-fix guard augments. Produces a new ADR-0012 recording the command+hook hybrid as a refinement of ADR-0008.
Lane: full. It touches a hook (`anti-rationalization.sh`), which the WORKFLOW.md intake table puts in the full lane regardless of size.

## Problem

The kit's lifecycle is entirely feature-shaped: `/think -> /spec -> /execute -> /review -> /ship -> /retro`. The WORKFLOW.md risk lanes (tiny / normal / full) are all sized by *feature* surface (typo, one bounded feature, auth-touching feature). **There is no debugging path.**

The kit guards two ends of correctness already:
- premature "done" -> `anti-rationalization.sh` (Stop hook) blocks it
- unverified completion -> `task-verifier` (read-only subagent) catches it

But both are about the *completion* side. Nothing covers the *diagnosis* side. When a defect, regression, or test failure lands mid-`/execute` or on a Monday triage, the agent (or contractor) freelances: guess a fix, re-run, guess again. That is exactly the guess-and-check thrash the rest of the kit exists to prevent, and it is the single highest-leverage gap because a wrong fix built on an un-found root cause poisons every downstream task.

ADR-0008 deferred this in v1.3 on two grounds: (a) no observed pain signal, and (b) a preference to build it "as a hook, not a skill." Both are addressed below: (a) the pain is structural (a named hole in the lane model), acknowledged as anticipated-not-yet-observed and handed to `/spec-validate` to stress; (b) the primitive question is resolved as a hybrid, because a four-phase reasoning loop is irreducibly judgment-driven and cannot live in a bash hook, while the *smell* of guess-fixing can.

### Fit check (/eval-tool rubric)
- **Layer fit (high):** fills the Build/Review boundary with a missing off-cycle entry point; reuses the existing verification pipeline rather than competing with it.
- **Pain match (anticipated, not yet observed):** no retro records debugging thrash yet. This is the spec's central risk; see Open questions and the Validation-pending note. The maintainer made the timing call by selecting build (DEC-006).
- **Adoption cost (low):** +1 command file, 1 hook edit (no new hook file), runtime artifacts under `.claude/debug/`. No new dependency (`git bisect` is git-native).
- **Timing:** proposed now because the lifecycle hole is structural and the lineage (superpowers, already a cited source) is mature.

## Solution

### Approaches considered
1. **Command-only (`/user:debug`).** The four-phase method as a slash command, like `/think` and `/review`. Tradeoff: pure guidance (~70% adherence per "Guardrails over guidance"); nothing stops an agent from skipping the command and guess-fixing anyway.
2. **Hook-only (augment `anti-rationalization.sh`).** Pattern-match guess-fix language ("let me just try", "quick fix") and block on Stop. Tradeoff: 100% adherence on the *smell*, but a bash hook cannot run a four-phase root-cause loop; it catches the symptom of bad debugging without teaching the method. ADR-0008's literal preference, but insufficient alone.
3. **Hybrid: command runs the method, hook guards the smell (CHOSEN).** `/user:debug` carries the judgment-heavy four-phase loop; an augment to `anti-rationalization.sh` blocks a premature "fixed" claim *only when a debug session is active and no root cause has been recorded*. Tradeoff: two surfaces instead of one, but the hook edit is to an existing file (no new file), and the gating keeps false positives near zero.

### Chosen approach + why
Approach 3. The method needs reasoning a hook cannot do, so it must be a command; the enforcement that ADR-0008 wanted is preserved as a *scoped* augment to the hook that already owns "premature done." The two halves reinforce each other the way `/execute` and `task-verifier` do: the command teaches and structures, the hook is the backstop. This is a deliberate, documented refinement of ADR-0008 (recorded in ADR-0012), not a silent reversal: the "as a hook, not a skill" rule held for pure enforcement, but debugging is a judgment task, and the kit already ships judgment tasks as commands.

### Extensibility & boundaries
- Load-bearing dimension: the **evidence ledger** (`.claude/debug/<slug>.md`) is the contract that survives context compaction and makes a debug session resumable. If the loop grows later (more phases, structured hypothesis matrix), it extends the ledger schema rather than adding new files.
- Unit boundaries: the command (`commands/debug.md`) owns the method; the hook augment (`hooks/anti-rationalization.sh`) owns the smell-block; the ledger and `.claude/debug/` artifacts are runtime state, not kit files. The verification pipeline is reused unchanged: Phase 4 writes a failing test and lets the existing worker/verifier/fix-agent path drive it. `git bisect` is invoked, never wrapped.
- The guess-fix guard is gated on an active, root-cause-empty ledger so it never fires during normal (non-debug) sessions. This honours "Detect, don't dictate": the guard is dormant unless a debug session is open.

### Architecture (diagram if it helps)
```
bug / regression / test-failure
        |
        v
/user:debug  ->  writes .claude/debug/<slug>.md (ledger), then:
   Phase 1 Root cause   read errors; reproduce; `git diff`/`git log`;
                        if regression -> `git bisect`; trace data flow back;
                        instrument with [DEBUG Hn] -> .claude/debug/<slug>.log
   Phase 2 Pattern      find working example; diff working vs broken
   Phase 3 Hypothesis   ONE falsifiable hypothesis; test minimally (one variable)
   Phase 4 Fix          write FAILING TEST first --------------------+
                        |                                            |
                        |   single fix; verify; remove instrumentation
                        |   (region-marker sed); human-confirm before "fixed"
                        v                                            v
   IRON LAW: no fix without a recorded root cause          existing verification
   3+ failed fixes -> STOP, question architecture          pipeline (worker ->
        ^                                                   task-verifier ->
        |                                                   fix-agent, max 2)
        |
  anti-rationalization.sh (Stop hook), AUGMENTED:
  if ledger active AND `## Root cause` empty AND a "fixed/done"
  claim with guess-fix smell -> block, point back to Phase 1
```

Ledger schema (append-only; write BEFORE acting so a context reset is recoverable):
```
## Symptoms        (immutable: what was reported)
## Root cause      (filled only when found; the guard reads this field)
## Evidence        (append: timestamp / checked / found / implication)
## Eliminated      (append: falsified hypothesis + the evidence that killed it)
## Fix attempts    (append: N; the 3+ wall reads the count)
## Resolution      (evolving: the fix + verification result)
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** a bug description (chat, a failing test name, an error/stack trace, or "regression since X"); the repo (`git diff`, `git log`, `git bisect`); existing project test command.
- **Outputs / produces:**
  - `.claude/debug/<slug>.md` (the evidence ledger) and `.claude/debug/<slug>.log` (tagged instrumentation output).
  - a failing test (Phase 4), then a single root-cause fix routed through the existing verification pipeline.
  - instrumentation is removed before completion via region markers (`# #region DEBUG ... # #endregion`, one `sed` pass).
- **Invariants:**
  - no fix is applied before `## Root cause` in the ledger is non-empty (iron law; the hook enforces it on Stop).
  - one variable changes per hypothesis test (Agans rule 5).
  - the agent does not declare "fixed" or strip instrumentation until the human confirms (matches "verify, then trust").
  - the guess-fix guard fires ONLY when a non-resolved ledger exists whose `## Root cause` is empty; it is silent otherwise (zero impact on non-debug sessions).
  - `git bisect` is used as-is; the kit never wraps or reimplements it.

### Data model changes
New runtime directory `.claude/debug/` (per-bug ledger `.md` + instrumentation `.log`). Listed in "Where things write to disk" (architecture.md) alongside `.claude/session-state/`. Not committed by default; recommend a `.gitignore` line in the downstream template (the kit's own repo ignores `.claude/debug/`).

### API / UI / Infrastructure changes
- `commands/debug.md` (new): the four-phase command, enriched per DEC-002.
- `hooks/anti-rationalization.sh` (edit): add guess-fix smell patterns, gated on an active root-cause-empty ledger; block with exit 2 and a message pointing at Phase 1. Must stay under the 500ms hook budget (the gate is a single file existence check plus one `grep` of a small ledger).
- `WORKFLOW.md` (edit): add a `bug` row to the risk-tier intake table and a Debug entry point to the cycle table.
- `docs/decisions/0012-debug-loop-hybrid.md` (new ADR): records command+hook hybrid as a refinement of ADR-0008.
- `tests/test-meta.sh` (edit): structural assertions (debug.md exists; carries the four phase headings, the iron law, the ledger schema; anti-rationalization carries the guess-fix patterns).
- `tests/test-hooks.sh` (edit): behavior tests for the guard (blocks guess-fix on Stop when ledger active + root cause empty; does NOT block when no ledger; does NOT block when root cause recorded).
- `MANUAL.md`, `README.md`, `docs/architecture.md`, `CHANGELOG.md` (edits): document the command, bump the command count, add the `.claude/debug/` write target and the debug flow.

## Task Breakdown

**Phase 1 (the method): the `/user:debug` command**
- [x] **TASK-1: write `commands/debug.md`.** Four phases (root cause -> pattern -> hypothesis -> fix), the iron law (no fix without a recorded root cause), the 3-failed-fixes-question-architecture wall, the evidence-ledger schema (write-before-acting), `git bisect` for regressions, `[DEBUG Hn]`-tagged logs to `.claude/debug/<slug>.log` inside region markers, failing-test-first routed into the verification pipeline, and human-confirm-before-"fixed". Cite Agans + Zeller + the four source repos in a Source line.
  - Acceptance: `commands/debug.md` exists; `grep` finds the four phase headings, the iron-law line, the ledger schema, and the `git bisect` step; the command instructs sanitizing `<slug>` to `[a-z0-9-]+` (no path separators) before writing `.claude/debug/<slug>.md` (DEC-008); no em-dash introduced.

**Phase 2 (the backstop): guess-fix guard**
- [x] **TASK-2: augment `hooks/anti-rationalization.sh` + behavior tests.** Depends on TASK-1's ledger schema (the `## Root cause` heading). Add guess-fix smell patterns (e.g. "let me just try", "quick fix", "let me try changing", "probably .* let me fix"), gated: fire only if `.claude/debug/` has ANY non-resolved ledger whose `## Root cause` is empty and the Stop event carries a fix/done claim (DEC-009). Block with exit 2 and a message pointing to Phase 1. Add `tests/test-hooks.sh` cases.
  - Acceptance: `bash tests/test-hooks.sh` green with three new cases (block when active+root-cause-empty; no-block when no ledger; no-block when root cause recorded); hook stays under 500ms (`time` spot-check).

**Phase 3 (wire + guard the structure): lane, meta tests, ADR**
- [x] **TASK-3: WORKFLOW.md `bug` lane + `tests/test-meta.sh` assertions + ADR-0012.** Add the `bug` row (`defect / test-failure / regression -> /debug, then /review`) and a Debug cycle entry. Add meta assertions for the new command structure. Write `docs/decisions/0012-debug-loop-hybrid.md`.
  - Acceptance: `bash tests/test-meta.sh` green with the new assertions; a meta assertion pins the literal `## Root cause` string in BOTH `commands/debug.md` and `hooks/anti-rationalization.sh` so the heading cannot drift on one side and silently disable the guard (DEC-010); WORKFLOW.md shows the bug lane; ADR-0012 exists and references ADR-0008 + ADR-0005.

**Phase 4 (document): operator + reference docs**
- [x] **TASK-4: MANUAL.md / README.md / architecture.md / CHANGELOG.md / `.gitignore`.** New `/user:debug` MANUAL section; command count bumped (README inventory + architecture.md table, currently understated at 12, set to the true new count); architecture.md "Where things write to disk" gains `.claude/debug/`; add `.claude/debug/` to the kit's own `.gitignore` (DEC-008); CHANGELOG [Unreleased] Added; suite-total line matches the real test count.
  - Acceptance: counts consistent across README/architecture/CLAUDE.md; CHANGELOG total equals the actual `test-meta.sh` + `test-hooks.sh` counts; `bash tests/test-meta.sh && bash tests/test-hooks.sh` green.

## Acceptance Criteria (global)
- [x] `/user:debug` exists and runs the four-phase loop with the iron law and the 3-fix architecture wall
- [x] The evidence ledger (`.claude/debug/<slug>.md`) is written before acting and carries the documented schema
- [x] Phase 4 writes a failing test first and routes the fix through the existing verification pipeline (no new fix machinery)
- [x] `anti-rationalization.sh` blocks a guess-fix "done" claim ONLY when a debug session is active and no root cause is recorded; it is silent in all non-debug sessions
- [x] WORKFLOW.md carries a `bug` lane; ADR-0012 records the hybrid as a refinement of ADR-0008
- [x] `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` both green; every hook under 500ms
- [x] No em-dash introduced; command/test counts consistent across all docs

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh` (meta proves the command + hook carry the required structure; hooks prove the guard's three-way behavior and no regression). Spot-checks: `grep -cE '^### Phase [1-4]' commands/debug.md` returns `4`; `grep -q 'let me just try' hooks/anti-rationalization.sh`; a manual Stop simulation with a root-cause-empty ledger is blocked, and the same with `## Root cause` filled is allowed.

## Edge Cases
1. **Bug with no reproduction.** Phase 1 cannot reproduce. The command routes to "gather more data, do not guess" (Agans rule 2) and records the gap in the ledger rather than fabricating a root cause. The guard keeps blocking premature fixes until a root cause is recorded.
2. **Not a regression (always broken).** `git bisect` is skipped; the command says so explicitly. Bisect is conditional on "worked before, broken now".
3. **False positive on the guard.** A legitimate one-line fix during a debug session where the root cause IS obvious. Mitigation: the gate requires `## Root cause` empty; the operator fills one line in the ledger and the guard goes silent. The guard never fires outside an open debug session.
4. **3+ fixes still failing.** The command stops and escalates to the human with the eliminated-hypotheses list (architectural-problem signal), instead of attempting fix #4. This reuses the kit's existing escalate-to-human posture.
5. **Instrumentation left behind.** Region markers (`# #region DEBUG`) make cleanup a single `sed` pass; the human-confirm gate is the backstop if the agent forgets. The `slop-cleaner` hook is an additional net.
6. **Tiny-lane bug.** A one-character obvious fix does not need the full loop; the bug lane is for defects/regressions/test-failures, not for the tiny lane (consistent with how the spec lanes already exempt trivial work).
7. **`git bisect` with no known-good commit.** Bisect needs a known-good ref; if none is known, the command says so and falls back to data-flow tracing (Phase 1) instead of starting an unbounded bisect.
8. **Multiple open debug sessions.** Two ledgers exist at once. The guard checks for ANY non-resolved ledger with an empty `## Root cause` (DEC-009), so an open session without a recorded root cause still blocks a guess-fix; a resolved ledger is ignored.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Guard false-positives in normal coding | Stop blocked outside any debug session | gate requires an active ledger with empty `## Root cause`; test asserts no-block when no ledger exists |
| Guard never fires (gate too strict) | guess-fixes slip through during a debug session | test asserts block when ledger active + root cause empty; the command itself also teaches the iron law |
| Ledger not written before acting | a context reset loses the investigation state | the command instructs write-before-act; ledger is the resumability contract (Known limitation 2 if an agent ignores it) |
| `git bisect` left mid-session | repo stuck on a detached bisect HEAD | the command pairs every `git bisect start` with a `git bisect reset` in the cleanup step; Edge Case + human-confirm gate |
| Instrumentation shipped to prod | debug prints in committed code | region-marker `sed` cleanup + human-confirm + `slop-cleaner` hook + `/review` |
| Hook exceeds 500ms budget | slow Stop events | gate is one file check + one small-file `grep`; TASK-2 acceptance pins a `time` spot-check |
| Stale command/test counts in docs | README says one count, suite reports another | TASK-4 pins counts across README/architecture/CLAUDE.md and the CHANGELOG total to the real number |
| Secret captured in `.claude/debug/<slug>.log` | a token/key appears in instrumentation output | `.claude/debug/` gitignored (DEC-008); region-marker cleanup removes instrumentation; human-confirm gate before completion; `/review` is the last net |
| `## Root cause` heading drifts on one side | the guard greps a heading that no longer exists and silently never fires | meta-test pins the literal `## Root cause` in both the command and the hook (DEC-010); a rename on one side breaks the suite |
| Unsanitized `<slug>` escapes `.claude/debug/` | a ledger path with `..` or `/` writes outside the dir | command sanitizes `<slug>` to `[a-z0-9-]+` before any write (DEC-008) |

## Out of Scope
- **Multi-agent / swarm debugging** (claude-flow, oh-my-claudecode style). Out of scope by the "one agent session at a time" boundary.
- **Production tracing / telemetry corpora** (Anthropic-cookbook style observability). The kit produces local artifacts, not a tracing platform.
- **A standalone debugger subagent** (GSD `gsd-debugger` style). Deferred; the command + existing verification pipeline cover the need without a new agent file. Re-open if the command proves too heavy to run inline.
- **Auto-`git bisect` driving** (scripted `bisect run`). v1 invokes bisect manually; scripted bisect-run is a candidate enrichment once there is usage data.
- **Backfilling a debug lane into legacy specs.** Forward-only.

## Decision Log
- **DEC-001**: Hybrid (command + hook), not command-only or hook-only. Rationale: the four-phase method needs judgment a bash hook cannot run (rejects hook-only); pure guidance has ~70% adherence and nothing stops guess-fixing (rejects command-only). The hook augment is the scoped backstop. Maintainer decision 2026-05-21.
- **DEC-002**: Enriched scope, not minimal spine. Include the evidence ledger, `[DEBUG Hn]` tagged logs to `.claude/debug/`, region-marker cleanup, `git bisect` for regressions, and failing-test-first into the verification pipeline. Rationale: the cross-framework survey showed these are the genuinely high-value mechanisms beyond the four-phase floor, and all are bash/sed/git-native (no new dependency). Maintainer decision 2026-05-21.
- **DEC-003**: Augment `anti-rationalization.sh` rather than add a new hook. Rationale: it already owns "premature done"; reusing it avoids a new file ("every file justifies its existence") and keeps the guess-fix block in the one place that already gates Stop.
- **DEC-004**: Gate the guard on an active root-cause-empty ledger. Rationale: keeps false positives near zero and honours "Detect, don't dictate" (dormant unless a debug session is open).
- **DEC-005**: Reuse the existing verification pipeline for the fix; do not build fix machinery in `/debug`. Rationale: Phase 4's failing-test-first feeds worker/task-verifier/fix-agent directly (ADR-0005); "One kit, whole cycle".
- **DEC-006**: Build now despite no observed pain signal (reversing ADR-0008's deferral). Rationale: the gap is structural (a named hole in the lane model), the lineage is mature and already cited, and the cost is +1 file. The anticipated-not-observed pain is handed to `/spec-validate` R3 to stress; if it cannot defend the timing, the spec holds at DRAFT.
- **DEC-007**: Record the primitive choice in a new ADR-0012 as a refinement of ADR-0008, not a silent reversal. ADR-0008's "as a hook, not a skill" rule stands for pure enforcement; debugging is a judgment task, and the kit already ships judgment tasks (`/think`, `/review`) as commands.
- **DEC-008 (validation, R1+R4)**: The command sanitizes `<slug>` to `[a-z0-9-]+` before writing the ledger (closes a path-traversal write). On gitignore: the kit's `.gitignore` and the demo template (`examples/hello-spec/.gitignore`) already ignore `.claude/`, which covers `.claude/debug/` (ledgers + possibly-secret-bearing logs). No redundant `.claude/debug/` line was added during execution ("every line justifies itself"); the coverage is recorded in `docs/architecture.md` ("Where things write to disk") instead. Found by Security + Scope reviewers.
- **DEC-009 (validation, R2)**: The guard scopes to ANY non-resolved ledger with an empty `## Root cause`, resolving the previously-undefined behavior when multiple debug sessions are open. Found by Failure-mode reviewer.
- **DEC-010 (validation, R5)**: A `tests/test-meta.sh` assertion pins the literal `## Root cause` string in both `commands/debug.md` and `hooks/anti-rationalization.sh`. Without it, a heading rename on one side silently disables the guard (the worst failure for a safety backstop). Found by Solution-design reviewer.

## Known limitations
1. **Pain signal is anticipated, not observed.** No retro yet records debugging thrash. The spec argues from a structural hole, not from telemetry. This is the central risk and the first thing `/spec-validate` must confront (DEC-006).
2. **Ledger discipline is agent-dependent.** The command can instruct write-before-act, and the guard enforces "root cause before fix," but it cannot force a rich ledger. A terse ledger still satisfies the guard as long as `## Root cause` is filled.
3. **The guard reads a field, not the reasoning.** It enforces that *a* root cause is recorded, not that the root cause is *correct*. Correctness is the human-confirm gate's job, same separation as task-verifier vs human escalation.

## Open questions
(none blocking; the pain-signal timing in DEC-006 / Known limitation 1 is the live question for `/spec-validate` R3 to resolve before VALIDATED. A `/goal` loop building from this spec that hits an uncovered decision appends here, then stops.)

## Source citations
- Maintainer request + gap analysis: this session, 2026-05-21.
- Method floor: obra/superpowers `systematic-debugging` SKILL.md (https://github.com/obra/superpowers) - four phases, iron law, 3-fix architecture wall.
- Evidence ledger + falsifiability: glittercowboy/get-shit-done `gsd-debugger` (https://github.com/glittercowboy/get-shit-done).
- Tagged logs + `.claude/debug` redirection + region-marker cleanup: doraemonkeys/claude-code-debug-mode (https://github.com/doraemonkeys/claude-code-debug-mode).
- Fix-gated-behind-confirm: SuperClaude `/sc:troubleshoot` (https://github.com/SuperClaude-Org/SuperClaude_Framework).
- Classic lineage: David Agans, "Debugging: The 9 Indispensable Rules" (2002); Andreas Zeller, "Why Programs Fail" (delta debugging).
- Prior decision reversed/refined: ADR-0008 (adopt superpowers patterns; deferred systematic-debugging). Pipeline reused: ADR-0005 (verification pipeline).
- Philosophy bars: `docs/PHILOSOPHY.md` ("Guardrails over guidance", "Detect, don't dictate", "One kit, whole cycle", "Synthesize, don't originate", "every file justifies its existence").

## Validation
5 reviewers run 2026-05-21 (security, failure-mode, assumption-destroyer, scope-critic, solution-design), dogfooding `/user:spec-validate`. Verdict: NEEDS REVISION -> 3 critical findings folded in -> VALIDATED. The remaining warnings are acknowledged, owner-accepted risks (no correctness blocker).
- Security (R1): small surface (markdown command + one hook edit). Two findings folded: slug path-traversal on ledger write -> sanitize to `[a-z0-9-]+` (DEC-008); secret capture in `.claude/debug/<slug>.log` -> gitignore + cleanup + human-confirm (failure-modes row). No auth/network/secret-handling in kit code.
- Failure-mode (R2): the failure-modes table carries detection + mitigation per row. Folded: undefined behavior with multiple concurrent ledgers -> guard scopes to any non-resolved root-cause-empty ledger (DEC-009, Edge Case 8).
- Assumption-destroyer (R3): confronted DEC-006 (build with no observed pain). Verdict: the structural-hole argument defends the lane addition, but the *enriched* scope is speculative by "No speculative features"; flagged as the standing warning (Known limitation 1), owner-accepted. Also folded: `git bisect` with no known-good commit -> graceful fallback (Edge Case 7).
- Scope-critic (R4): the four tasks are atomic (each <=5 files, TASK-4 the heaviest at 5 with the gitignore add). Acceptance is grep-testable. Folded: missing `.gitignore` task ownership -> added to TASK-4 (DEC-008); undeclared TASK-2 -> TASK-1 dependency -> declared.
- Solution-design (R5): hybrid is the simplest design satisfying the requirement; alternatives honest; the ledger is the load-bearing interface between command and hook. Folded the one real fragility: the hook<->ledger `## Root cause` contract is stringly-typed and could silently break -> meta-test pins the literal on both sides (DEC-010).
Status flipped to VALIDATED after the three criticals were folded into Tasks / Edge cases / Failure modes / Decision Log. The DEC-006 timing warning remains the live, owner-accepted risk to revisit at `/user:retro`.
