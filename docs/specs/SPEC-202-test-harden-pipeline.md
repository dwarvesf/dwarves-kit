# Spec: /kit:test-harden, a spec-to-hardened-tests pipeline
Generated: 2026-07-30
Status: DRAFT
Lane: normal
References: [commands/ui-design.md, imitate its exact shape: a thin coordinator that writes a brief, delegates generation to one existing lane, delegates critique to another existing lane, and reports a verdict, without reimplementing either lane's internals. Its Step 4 verdict vocabulary (SOLID/REVISE/RECONSIDER) is the one this spec reuses directly. commands/ship.md Step 1, imitate specifically its "the referenced section can be ABSENT, WARN explicitly, never silently skip" half, the half /kit:spec-validate Reviewer 3 found missing from the first draft of this spec (SPEC-202 v1 claimed to mirror ship.md's whole pattern; validation found it only borrowed the branch-on-verdict half and dropped the missing-section-WARN half).]

## Problem
Getting from an idea to a hardened set of test cases today needs the maintainer to manually run three separate commands in the right order (`/kit:spec`, `/kit:test-plan`, `/kit:test-plan-review-team`), and to know that order exists (nothing in the kit's own next-step suggestions names it). The operator described this as wanting "the input is the spec, the output is the test scenarios," run as one step, not three manual ones, with the kit itself surfacing the step exists.

## Solution

### Approaches considered
1. **Build a new bounded auto-revise loop around `/kit:test-plan`.** Rejected: `/kit:test-plan-review-team` already IS a bounded auto-revise loop (max 3 rounds, distinct-reviser-not-lens-reviewer, strictly-falling-findings rule, `[[QL-VERDICT ...]]` markers). Duplicating that loop would be the exact anti-pattern `coding-hygiene.md`'s "rule of three" warns against; two loops with slightly different cap/termination rules would also drift apart over time.
2. **Fold the sequencing into `/kit:test-plan` itself** (add a flag that auto-invokes `test-plan-review-team` at the end). Rejected, not on convention alone but because it loses additivity: `/kit:spec-validate` stays separate from `/kit:spec`, `/kit:review-team` stays separate from `/kit:review`, `/kit:visual-team` stays separate from generation in `/kit:ui-design`, and in every one of those pairs BOTH halves stay independently runnable. Folding critique into `test-plan` would remove the ability to run `test-plan` alone, which the kit's own convention never does to its author/critique pairs.
3. **A router-hint-only change**: teach `/kit:start`'s next-step suggestion and `/kit:test-plan`'s own hand-off to just NAME the manual sequence, with no new command. Rejected as a substitute (it does not satisfy the operator's stated one-invocation requirement), but adopted as a complementary piece of option 3 below, not dropped, discovery was a real gap validation caught (Reviewer 5, finding r5-6).
4. **A thin new coordinator command that only sequences the three existing lanes by reference, PLUS the router-hint wiring from option 3** (chosen). It does not reimplement spec-authoring, matrix generation, or the critique loop; it resolves the active spec once, delegates to `/kit:test-plan`, delegates to `/kit:test-plan-review-team`, reads the final verdict, and reports, while `/kit:start` and `/kit:test-plan` both also learn to point at it.

### Chosen approach + why
Option 4. It is the smallest change that satisfies "one command, spec in, hardened tests out, and I can find it," reusing 100% of the existing critique/revise machinery instead of forking it (option 1's rejection), preserving the kit's author/critique additivity convention (option 2's rejection), and closing the discoverability half of the Problem statement that a router-hint-only change (option 3) cannot close alone.

### Extensibility & boundaries
- What changes when the load-bearing dimension grows: if a fourth test-related lane is ever added (e.g. a dedicated exploratory-testing lane), it slots in as a fourth delegated step after the critique loop terminates, under the lane contract in `### Interfaces` below (a chained lane consumes the resolved spec path, appends exactly one `## ` section, returns one SOLID/REVISE/RECONSIDER verdict). Composition rule: the first non-SOLID verdict in the chain stops it and surfaces that lane's report; a later lane never runs against an unresolved earlier verdict.
- Unit boundaries: this command has exactly one job, resolve the spec once, sequence three existing lanes, and report the final verdict. It owns no test-design logic, no critique logic, and no revise logic; all three live in their existing homes. It also owns no lock/concurrency-control (see `## Failure modes`, inherited exposure, documented not solved).

### Architecture
See `## Design` below.

## Design

### Approaches considered + chosen
See `## Solution` above; same four options, same choice (a thin reference-only coordinator plus router-hint wiring).

### Diagram (ASCII, per operator's global no-mermaid rule; overrides `commands/spec.md`'s own "mermaid-first" default for this one spec)

```
                    /kit:test-harden invoked
                              |
                              v
              Step 1: resolve the ONE active spec
              (branch-aware, ask if several match,
               same as /kit:test-plan Step 1)
                              |
              no spec, or no AC / no per-task
              acceptance checkboxes?
                    |                     |
                   yes                    no
                    |                     |
                    v                     v
          stop, point at          pass the resolved spec
          /kit:spec                path forward (never
                                    re-resolved downstream)
                                          |
                                          v
                        Step 2: delegate to /kit:test-plan
                           (writes ## Test plan)
                                          |
                    lane halted / no ## Test plan written?
                          |                        |
                         yes                       no
                          |                        |
                          v                        v
              stop, name /kit:test-plan     Step 3: delegate to
              as the lane that did          /kit:test-plan-review-team
              not complete                  (internal bounded loop,
                                             max 3 rounds, writes
                                             ## Test plan critique)
                                                     |
                          lane halted / no ## Test plan critique,
                          or verdict unparseable / not fresh to this run?
                                |                              |
                               yes                             no
                                |                              |
                                v                              v
                    stop, name /kit:test-plan-       Step 4: read the
                    review-team as the lane          scoped ### Verdict:
                    that did not complete            line, exactly one
                                                      match required
                                                              |
                          +------------+------------+--------+
                          |            |            |
                          v            v            v
                       SOLID        REVISE      RECONSIDER
                          |            |            |
                          v            v            v
                 report: ready,  report: OPEN   stop: the SPEC
                 suggest         findings;      itself needs
                 /kit:execute    maintainer     rework, point at
                                 fixes or        /kit:spec-validate
                                 proceeds
```

### ADR link(s)
None. This is a reversible, additive command; no lasting architectural commitment beyond the kit's existing lane-separation convention (already precedented by `/kit:ui-design`, `/kit:spec-validate`, `/kit:review-team`).

### Boundaries & failure modes
Out of bounds: this command never edits `## Test plan` or `## Test plan critique` content itself, both belong to the lanes it delegates to; it adds no lock or concurrency control. See `## Failure modes` below for the concrete classes and mitigations.

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** the active `docs/specs/SPEC-NNN-<slug>.md`, resolved EXACTLY ONCE in Step 1 (the `/kit:next` branch-aware way, same detection `/kit:test-plan` and `/kit:test-plan-review-team` already use standalone), specifically its `## Acceptance Criteria` section OR its per-task acceptance checkboxes (matching `/kit:test-plan` Step 1's actual accepted condition, not a narrower one). The resolved absolute path is passed forward explicitly to both delegated steps; neither lane re-resolves independently under this coordinator.
- **Outputs / produces:** the same two spec sections `/kit:test-plan` and `/kit:test-plan-review-team` already produce (`## Test plan`, `## Test plan critique`), unmodified in shape, plus a short final report (verdict + next step) to the user. No new spec sections, no new files. This command itself writes NOTHING to disk; every write belongs to one of the two delegated lanes, each confined to its own spec section.
- **Delegation is prompt-driven, not a guaranteed programmatic call** (same caveat `/kit:ui-design` states for `frontend-design`): if `/kit:test-plan` or `/kit:test-plan-review-team` is missing or errors mid-delegation, this command does not hard-fail silently, it surfaces which lane did not complete (see the diagram's two new stop branches) and stops.
- **The real coupling surface** (5 shapes, not just the verdict vocabulary): (1) the `## Test plan critique` heading string, (2) the `### Verdict:` heading text and level, (3) the verdict vocabulary itself (SOLID/REVISE/RECONSIDER), (4) the spec-first write location convention both lanes already use, (5) the 3-round cap semantics carried in the `[[QL-VERDICT round=N clean=BOOL findings=K]]` marker (used to confirm the read critique belongs to this run, not a stale prior one). A change to any of these five in either lane requires a matching change here; this supersedes the narrower "unless the verdict vocabulary changes" framing from the first draft.
- **Lane contract for future chaining:** a lane this command can chain to must (a) consume the resolved spec path, (b) append exactly one `## `-level section to that spec, (c) return exactly one SOLID/REVISE/RECONSIDER verdict. Composition rule when a lane is added: the first non-SOLID verdict in the chain stops it there.
- **Autonomous-caller contract:** under `bypassPermissions`, this command still terminates on its own diagram (a lane-absent stop, or a SOLID/REVISE/RECONSIDER report); it never proceeds past the report. An autonomous caller (a `/goal` loop, `/kit:execute` pipeline) must treat REVISE and RECONSIDER as stop-and-surface, since no maintainer is present to act on "fixes or proceeds anyway." The final report always names what the delegated critique lane's reviser subagent changed across its rounds, so an unattended caller's log shows what was revised even though no human watched it happen.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: Create `commands/test-harden.md` with frontmatter `description` (one line, states input/output/opt-in, matching the kit's existing style) and a `## Source` footer stub., Acceptance: `head -3 commands/test-harden.md` shows valid YAML frontmatter with a non-empty `description` field.
- [ ] TASK-002: Write the full process (Steps 1-4) exactly matching the ASCII diagram above: single spec resolution with the OR-condition from `### Interfaces`, delegation to `/kit:test-plan` with its own lane-absent stop branch, delegation to `/kit:test-plan-review-team` with its own lane-absent/unparseable/stale stop branch, the scoped-and-freshness-checked verdict read, and all four terminal branches (SOLID / REVISE / RECONSIDER / lane-did-not-complete). Include the bypassPermissions/autonomous-caller note from `### Interfaces` and the gate-ledger timing brackets (`bash lib/gate/gate-ledger.sh outcome <rid> test-harden start/end`) around the whole process., Acceptance: `grep -c "happy-path\|boundary/edge\|failure-injection" commands/test-harden.md` returns `0` (no duplicated category taxonomy from `test-plan.md`); a manual dry run against a spec with a deliberately-stale `## Test plan critique` produces "verdict unreadable" or an explicit stop, never a false SOLID.

### Phase 2: Core
- [ ] TASK-003: Add a `## Failure modes` table to this spec (see the new section below, already written into this revision) listing: lane not installed/errored, critique section unwritten, verdict unparseable or stale; each row with a detection signal and a mitigation. Then implement each row's mitigation inside `commands/test-harden.md` Step 2-4 (covered by TASK-002's stop branches; this task is the traceability link, not new logic)., Acceptance: every `## Failure modes` row in this spec has a corresponding stop branch in the ASCII diagram and in the shipped command file.
- [ ] TASK-004: Wire discovery: add a line to `/kit:start`'s post-VALIDATED suggestion naming `/kit:test-harden` as the spec-to-hardened-tests option, and add a one-line "Next:" pointer in `commands/test-plan.md` Step 4 naming `/kit:test-harden` as the single-invocation alternative to running `test-plan-review-team` manually., Acceptance: `grep -l "test-harden" commands/start.md commands/test-plan.md` returns both files.
- [ ] TASK-005: Fix the gate-ledger telemetry pairing: add `bash lib/gate/gate-ledger.sh record <rid> test-harden ran "<SOLID|REVISE|RECONSIDER|lane-incomplete>"` alongside the existing `outcome ... start/end` bracket from TASK-002 (matching the record+outcome pairing every verdict-bearing lane, e.g. `test-plan-review-team`, already uses), and add a `test-harden` row to `docs/WORKFLOW.md`'s lane x phase matrix., Acceptance: `bash tests/test-outcome-emit-sweep.sh` stays green after the change; the WORKFLOW matrix has a `test-harden` row.

### Phase 3: Polish
- [ ] TASK-006: Bump the kit's pinned "31 commands" count to 32 everywhere it is asserted: `tests/test-command-emit-sweep.sh`'s file-count assertion, `tests/test-meta.sh`'s README layout count / header count / Commands table row count, `docs/architecture.md`'s headline total and per-command inventory table (add a `test-harden` row), and `docs/MANUAL.md`'s Check row / `docs/WORKFLOW.md`'s opt-in lane tables if they also pin the count., Acceptance: `bash tests/test-command-emit-sweep.sh && bash tests/test-meta.sh` both pass green with `commands/test-harden.md` present.
- [ ] TASK-007: Add the `## Source` footer to `commands/test-harden.md` naming what it reuses (`test-plan.md`, `test-plan-review-team.md`) and what it imitates the shape of (`ui-design.md`'s delegation style, `ship.md`'s missing-section-WARN half), phrased as "matching the lanes that do cite lineage" (not "every command", since only 11 of 31 currently do)., Acceptance: footer present, all four files named, no "every command" overclaim.
- [ ] TASK-008: Record the proof this spec's global Acceptance Criteria are actually met: run the full meta test-suite green (`bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh && bash tests/test-outcome-emit-sweep.sh`) and a manual dry run of `/kit:test-harden` against a real spec, capturing one full pass through each of the four terminal branches (SOLID / REVISE / RECONSIDER / lane-incomplete) at least once across test specs., Acceptance: all three test files green; four dry-run transcripts exist, one per branch.

## After state
- [ ] A single `/kit:test-harden` command exists that takes the active spec as input and leaves a critique-hardened `## Test plan` as output, without the maintainer manually sequencing three commands, and both `/kit:start` and `/kit:test-plan` point at it. (Today: the maintainer must know to run `/kit:spec` -> `/kit:test-plan` -> `/kit:test-plan-review-team` in that order, unassisted, with no kit surface naming the sequence.)
- [ ] Zero duplicated logic: `commands/test-harden.md` contains no copy of `test-plan.md`'s category taxonomy or `test-plan-review-team.md`'s lens/round logic, verifiable by `grep`. (Today: N/A, command does not exist.)
- [ ] The kit's own pinned command-count assertions (31 -> 32) and lane x phase matrix stay green with the new command present. (Today: N/A, command does not exist so the count is still accurate at 31.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Running `/kit:test-harden` against a spec with no `## Acceptance Criteria` AND no per-task acceptance checkboxes stops and points at `/kit:spec`, does not proceed
- [ ] Running it against a valid spec produces the same `## Test plan` and `## Test plan critique` shapes the two existing lanes already produce, using exactly one spec resolution shared across both delegations
- [ ] A missing or unparseable verdict (either delegated lane incomplete, or a stale/ambiguous `### Verdict:` match) produces an explicit stop, never a false SOLID
- [ ] No regressions to `/kit:test-plan` or `/kit:test-plan-review-team` when run standalone (this command is additive, not a replacement)
- [ ] `bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh && bash tests/test-outcome-emit-sweep.sh` all pass green with the new command present

## Verification
`grep -c "happy-path\|boundary/edge\|failure-injection" commands/test-harden.md` returns `0` (no duplicated category taxonomy). `grep -E "outcome \+\(<rid>\) \+test-harden \+(start|end)" commands/test-harden.md` (the real call shape, not just a boilerplate-sentence match) returns non-empty. Negative control: temporarily rename `commands/test-plan-review-team.md` and re-run `/kit:test-harden`; it must stop at the new lane-incomplete branch, not report SOLID. `bash tests/test-meta.sh && bash tests/test-command-emit-sweep.sh && bash tests/test-outcome-emit-sweep.sh` all green.

## Edge Cases
1. No active spec at all -> stop at Step 1, point at `/kit:spec`, do not fabricate a spec.
2. Active spec exists but has no `## Acceptance Criteria` AND no per-task acceptance checkboxes -> same stop as case 1 (matches `/kit:test-plan`'s real Step 1 condition, not a narrower one).
3. `## Test plan critique`'s bounded loop hits its 3-round cap still at REVISE, OR halts early because findings failed to strictly fall between rounds (`test-plan-review-team.md` Step 4.3) -> either non-convergence exit reports the OPEN findings plainly; do not claim SOLID for either, do not retry a 4th round (that logic belongs to `test-plan-review-team.md`, not here).
4. `/kit:test-plan` or `/kit:test-plan-review-team` halts, errors, or leaves its expected section unwritten -> stop, name the specific lane that did not complete, never infer a verdict from its absence.
5. Multiple specs match the branch-aware resolution -> ask the user which one ONCE, at Step 1, exactly as `/kit:test-plan` Step 1 already does; do not auto-pick, and do not re-ask at Steps 2 or 3 since the resolved path is forwarded.
6. A `## Test plan critique` exists but is stale (from a prior, unrelated run on the same spec) -> the freshness check in `### Interfaces` (matching this run's round markers) must catch it; treat an unconfirmed-fresh critique the same as case 4 (lane-did-not-complete-THIS-run), not as a valid verdict.
7. Re-running `/kit:test-harden` on a spec with a hand-edited `## Test plan` -> both delegated lanes are replace-not-stack; this command does not add its own guard beyond what those lanes already do, an operator who hand-edited the matrix should expect a re-run to replace it (documented, not solved here; see `## Failure modes`).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Delegated lane (`/kit:test-plan` or `/kit:test-plan-review-team`) not installed, errors, or halts mid-run | Expected section (`## Test plan` or `## Test plan critique`) absent after the delegation step | Stop, name the specific lane, point the operator at running it manually; never infer a verdict from silence (Edge Case 4) |
| Verdict text unparseable, ambiguous, or matches the wrong section (`## Review`'s own verdict line, the critique template's placeholder line) | The scoped, exactly-one-match read in `### Interfaces` fails its own precondition | Fail closed: report "verdict unreadable," never emit SOLID (Edge Case 6) |
| Stale `## Test plan critique` from an unrelated prior run persists on re-entry | Round/date markers do not match this run | Treat as lane-incomplete-this-run, same stop as the absent case (Edge Case 6) |
| Two sessions operate on the same active spec concurrently (both lanes read-modify-write the same file's sections) | Last-writer-wins symptom: a section silently reverts or one session's write disappears | Inherited exposure, not solved by this command (no lock added); re-resolve/re-read at Step 4 rather than trusting the Step-1 snapshot, and document last-writer-wins as the accepted behavior |
| Re-running on a spec whose `## Test plan` was hand-edited by the operator | Both delegated lanes are replace-not-stack | Not solved here (inherited from the two lanes); operator expectation only, documented in Edge Case 7 |

## Out of Scope
- Auto-running `/kit:execute` after a SOLID verdict. This pipeline stops at hardened test cases (the operator's stated input/output boundary); execution is a separate, explicit step.
- A new critique loop, lens set, or cap. All critique logic stays owned by `commands/test-plan-review-team.md`.
- Any change to `commands/spec.md`'s interactive intent-gathering. A missing spec is a stop-and-point, not an auto-invoke (spec authoring needs the user's own answers).
- A lock or other concurrency-control mechanism for the shared spec file. The concurrent-access window this command widens (holding one resolved spec across three delegated steps) is documented in `## Failure modes` as inherited exposure, not fixed here.

## Decision Log
- DEC-001: Command name is `/kit:test-harden` (working name). Rationale: distinct from `test-plan`/`test-plan-review-team` (no collision), "harden" names the generate-then-critique-then-revise outcome. Alternative rejected: `/kit:spec-tests` (read as "tests for a spec," ambiguous with "does this spec have tests" rather than the pipeline verb).
- DEC-002: Delegate by reference to the two existing lanes rather than inlining their steps. Rationale: avoids drift between two copies of the same category taxonomy / critique-loop logic; matches `/kit:ui-design`'s own delegation-by-reference style for `frontend-design` and `/kit:visual-team`.
- DEC-003 (from `/kit:spec-validate` round 1): diagram converted from mermaid to ASCII, overriding `commands/spec.md`'s own "mermaid-first" default for this one spec, per the operator's explicit global no-mermaid rule. Reviewer 6 had confirmed the mermaid version's diagram TYPE (flowchart) was correct; only the rendering syntax changed, the decision-path content is unchanged.
- DEC-004 (from `/kit:spec-validate` round 1): TASK-002 through the original TASK-005 collapsed into one task (new TASK-002), per Reviewer 4's over-atomization finding (7 tasks all writing one ~80-line file, 5 one-sentence each, no declared inter-task deps). Still fits well under 50% of a fresh context window.
- DEC-005 (from `/kit:spec-validate` round 1): discovery/router-wiring (the original Problem statement's second half, "and to know that order exists") kept IN SCOPE of this spec rather than split into a follow-up, per operator direction. Realized as TASK-004 and as the 3rd/4th considered approaches in `## Solution`.
- DEC-006 (from `/kit:spec-validate` round 1): spec resolution changed from three independent per-lane resolutions to exactly one resolution in Step 1, forwarded explicitly to both delegated steps, per Reviewers 3 and 5 independently finding the same three-resolutions-can-disagree bug.
- DEC-007 (from `/kit:spec-validate` round 1): verdict read changed from an unscoped "the final `### Verdict:` line" to a scoped, exactly-one-match, freshness-checked read that fails closed, per Reviewers 1/2/3 all independently finding the original read could fail open toward a false SOLID.
- DEC-008 (from `/kit:spec-validate` round 1): added the `## Failure modes` table (was a dangling pointer to a non-existent section in round 1), per Reviewers 1/2/4/6 all independently flagging the dangling reference.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)

## Review
### Verdict: NEEDS REVISION (round 1, this document is the revision)
6-lens `/kit:spec-validate` run (2026-07-30): Reviewer 6 (Design Record, blocking) PASSED clean. Reviewers 1-5 (advisory) returned 2 CRITICAL + 6 HIGH + 13 MEDIUM/LOW findings across the original draft; every finding above has either been fixed in this revision (Decision Log DEC-003 through DEC-008, plus the new `## Failure modes` table, the `Lane:` header, the collapsed Task Breakdown, the corrected `### Interfaces`, and the wired-in discovery task) or is explicitly carried forward as a documented, accepted limitation (the concurrency window and the replace-not-stack re-run behavior, both in `## Failure modes` and Out of Scope). Re-running `/kit:spec-validate` against this revision is the natural next step before `/kit:execute`.
