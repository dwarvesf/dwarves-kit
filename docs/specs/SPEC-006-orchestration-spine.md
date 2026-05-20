# Spec: Orchestration spine (backlog -> goal-crafter -> WORKFLOW, airtight Reflect)

Generated: 2026-05-20
Status: VALIDATED
Source: maintainer braindump 2026-05-20 (items d + f), plus the goal-store command + queue rendering deferred here from SPEC-005 (ID-005, ID-006). Backlog: ID-005 (command half), ID-006 (rendering half), ID-007, ID-008.
Prior spec: docs/specs/SPEC-005-backlog-and-goal-state.md
Depends on: SPEC-005 (state model: backlog queue schema, `.claude/goals/` draft-store contract, dual-detect) + `docs/research/2026-05-20-orchestration-deep-scan.md` (the deep scan that scoped this).
Validation: 4 reviewers run 2026-05-20 (scope-critic, assumption-destroyer, failure-mode, philosophy-fidelity). Pre-fix verdict NEEDS REVISION (design sound; overclaims + 2 factual errors + incompleteness). All resolved inline; see Decision Log DEC-009..DEC-020 and the Validation section.
Reconciled: 2026-05-21, after SPEC-005 shipped (its `.claude/goals/` contract + backlog schema + branch-aware dual-detect, exactly as this spec depends on) and SPEC-013 shipped concurrently (the `/user:debug` bug lane). No design change: the dependency is satisfied as written. Two execution adjustments: the command-count baseline is now 14 (SPEC-013's `/user:debug`), so `/user:assign` makes 15 and TASK-7's ripple must also fix `.claude-plugin/{plugin,marketplace}.json` (left stale at 13); and TASK-6's §3 loop note now frames BOTH bounded in-session loops (goal + the SPEC-013 debug loop). See DEC-021.

## Problem

The braindump's capstone (item d): when a session starts, the user asks "what's left to do?" and wants a real loop:
1. the open work is enumerated;
2. they assign an item;
3. a goal-crafter breaks it down and sets the objective;
4. completing it follows the full SDD WORKFLOW (spec, well-tested code, review, well-documented), and
5. **even the trial-and-error iterations of the goal loop follow the WORKFLOW** rather than going around it.

And item f: during Reflect, every change must be re-checked and **every affected doc updated**, with omissions surfaced.

The honest finding from the deep scan (`docs/research/2026-05-20-orchestration-deep-scan.md`): **the spine already exists.** WORKFLOW.md (SPEC-003) names the phases, the lanes, and the gates. The verification pipeline is the field's converged-on moat. SPEC-005 built the *state* the spine reads (backlog queue schema, `.claude/goals/` draft-store contract, dual-detect). What is missing is small and specific:

- **Wiring + the user-facing surface SPEC-005 deferred.** Nothing connects "what's left?" (the BACKLOG queue) to "break it down" (goal-crafter) to "run the lane" (WORKFLOW). SPEC-005 shipped only the `.claude/goals/` *contract* and deferred the command + the `/start`-`/next` queue rendering to here, because their consumer is this spine (SPEC-005 DEC-011). So this spec owns the wiring, the one command that drives it, and the read-only rendering.
- **Two completeness leaks.** The scan named one net-new mechanism worth building (a decision-translation check) and item f names a second of the same shape (a doc-update completeness check). Both are the gap between "an agent iterated on a goal" and "the decisions and docs that iteration implied actually landed."
- **A framing gap (not, as an earlier draft wrongly said, in PHILOSOPHY §3).** PHILOSOPHY has no explicit loop stance; the "outer loops declined, autonomous-runtime territory" framing actually lives in SPEC-003 DEC-005 (shipped) and the deep-scan note. That framing is too blunt: the scan showed Anthropic ships a first-party in-session Stop-hook loop primitive (the `ralph-loop` plugin), which is exactly the kit's anti-rationalization architecture. So the in-session goal loop is a native kit primitive, not foreign autonomous-runtime territory; this spec adds that distinction to PHILOSOPHY.

### The enforcement reality (the core adjudication)

Item d says the goal loop "**must** follow WORKFLOW." But **hard-gating process completeness is the pattern the kit's PHILOSOPHY explicitly rejects**: "Detect, don't dictate" rejects "a phase-locking system that blocks `/execute` unless `/spec-validate` has been run," and the deep scan found hard phase gates (Spec Kit / BMAD HALT) are a field-wide reject. "Guardrails over guidance" reserves *hard blocks* for **irreversible / safety** cost (premature-done, push-to-main, failed verify, all already firing). A goal loop that skips its docs ships *incomplete*, it does not destroy anything, so it is not in the hard-block class.

Therefore the honest delivery of "must" is **surface + log + gate-review**, not a mid-loop hard block (maintainer decision 2026-05-20):
- The kit **hard-enforces** only the safety subset, which it already does (anti-rationalization Stop hook, the verification pipeline, the push-to-main blocker).
- For decision/doc completeness, the kit **warns AND logs** to a completeness log, and `/user:ship` + `/user:retro` **review that log at the gate** before shipping. Nothing falls through silently, but nothing hard-blocks mid-loop.
- This is recorded plainly, not papered over: `anti-rationalization.sh` matches only 5 literal phrases (none of these leaks), and the verifier runs inside `/user:execute` (a free-form goal loop can bypass it). So the completeness checks are NOT backed by an existing hard stop; they are surfaced + logged + reviewed at ship. (Known limitation 4.)

So this spec is deliberately thin: wire the seam, give it one command + read-only rendering, add two **warn-and-log** completeness clauses reviewed at the ship gate, and add one PHILOSOPHY note.

## Decision: chosen version

**Wire backlog -> goal-crafter -> WORKFLOW through one new command (`/user:assign`) plus read-only rendering added to the existing `/user:start` and `/user:next`; document the spine in a WORKFLOW.md section; add two warn-and-log completeness clauses (decision-translation, scoped to tagged build-decisions; and doc-update, against a doc-impact map) that log to a completeness log reviewed by `/user:ship` and `/user:retro`; and add a bounded-vs-unbounded loop distinction to PHILOSOPHY (refining SPEC-003 DEC-005).**

### Part 1: The wiring + the surface (items d, ID-005 command, ID-006 rendering)

```
session start
  -> /user:start          RENDER the BACKLOG Active queue (SPEC-005 schema) = "what's left?"
                          and list active .claude/goals/ drafts. (read-only; a detector)
  -> /user:assign ID-NNN   goal-crafter: break the item down, set objective + scope fence,
                          WRITE .claude/goals/<slug>.md (SPEC-005 contract), pick the lane,
                          surface the draft body for the user to start a goal loop with
                          whatever activator is present, hand off to the lane's first command.
                          (mutator; does NOT execute, does NOT write last-goal.md)
  -> the lane runs         tiny | normal | full   (WORKFLOW.md, unchanged)
       normal/full -> /user:spec -> /user:spec-validate -> /user:execute (verify pipeline)
                      -> /user:review -> /user:docs -> /user:ship -> /user:retro
  -> on ship              /user:ship reviews the completeness log; ID-NNN -> shipped, drops off
```

**Detector/mutator split preserved.** `/user:start` and `/user:next` only READ and render; `/user:assign` is the only mutator. This is why rendering folds into the existing detectors while creation is a single new command, not a second `/user:goals` command.

**Activator-agnostic, never owns `last-goal.md`.** `/user:assign` writes only the `.claude/goals/<slug>.md` draft and surfaces its body. Activation (starting the in-session goal loop) is done by whatever primitive the maintainer has: the built-in `/goal` if installed, or the `ralph-loop` plugin's loop, or the `goal-craft` skill that crafts the loop text, or manual use. The command DETECTS which is present and degrades gracefully (if none, the draft is a plain reusable file). The kit never writes `last-goal.md` (SPEC-005 DEC-004); it does not assume any specific activator exists.

**"Even the goal loop follows WORKFLOW."** See "The enforcement reality" above: the safety subset is hard-enforced by existing hooks; the two completeness clauses warn + log + are reviewed at `/user:ship`. The honest claim is: a goal loop is *warned and logged* if it skips its decisions or docs, and `/user:ship` surfaces that log before shipping; it is *not* mid-loop hard-blocked, by design.

### Part 2: Two warn-and-log completeness clauses (items d + f)

Both are added to the WORKFLOW.md **completion contract** as self-check clauses that LOG to a completeness log (`~/.claude/dwarves-kit/logs/completeness.log`, the same logging shape `spec-drift-guard.sh` uses), and both are reviewed by `/user:ship` (gate) and `/user:retro`. Warn + log, never mid-loop block. Promote to a hook only on a real drift signal (PHILOSOPHY §5 bar).

| Clause | What it checks | Scope (no false-positive storm) | Source |
|---|---|---|---|
| **Decision-translation** | each decision in the spec's **"Build decisions" sub-list** is referenced (by ID or `Implements:` target) in a task/AC; warn+log on an orphan | ONLY the explicit "Build decisions" list. Rationale, rejected-alternative, and `(validation)` decisions are exempt (they legitimately need no task). If a spec has no "Build decisions" list, the clause is a no-op | GSD v1.40+ decision-locking, adapted to grep-grade warn+log (deep scan ADOPT #1); the cited GSD mechanism is a hard gate, this is the warn+log adaptation |
| **Doc-update completeness** | the diff (against the merge-base of the integration branch, pinned) is checked against the **doc-impact map**; warn+log when a change touches X without its companion docs | normal/full lanes only (tiny-lane ship suppresses it, consistent with the lane model) | spec-drift-guard shape applied to docs (deep scan: same family) |

**The doc-impact map** (item f's core): a table in WORKFLOW.md naming, per change-type, the companion docs that must move with it.

| If a change touches | Companion docs that must update |
|---|---|
| `hooks/*` | `RUNBOOK.md`, README hook table, `tests/test-meta.sh` count, `tests/test-hooks.sh` |
| `commands/*` (new) | `MANUAL.md`, README command table, `.claude-plugin/plugin.json`, `tests/test-meta.sh` |
| `agents/*` | README agent list, `tests/test-meta.sh` frontmatter checks |
| `settings.json` (hook wiring) | README hook table, `RUNBOOK.md`, `install.sh` merge logic |
| `install.sh` | README install steps, `tests/` |
| `rules/*` | README path-scoped-rules note, `docs/architecture.md` |
| `skills/*` | README, `MANUAL.md` |
| `examples/hello-spec/*` | `examples/hello-spec/README.md`, the downstream-template note |
| a PHILOSOPHY principle | `docs/PHILOSOPHY.md`, `commands/kit-health.md` reject-list |
| a new `docs/decisions/ADR` | README/architecture cross-refs |
| a new `docs/specs/SPEC-NNN` | `_meta/BACKLOG.md` status, the spec's `Status:` header |
| **a new top-level dir under the kit root** | **the doc-impact map itself (WORKFLOW.md)**, README "Project structure", `docs/architecture.md` |
| any shipped change (normal/full lane) | `CHANGELOG.md`, `VERSION`, `.claude-plugin/plugin.json` version, `docs/retro/v<ver>.md` |

The last-but-one row is the **self-maintenance row**: adding a new top-level dir is a change whose companion list includes updating this map, so the map names its own maintenance. This is honest, not airtight: **the map covers the enumerated change-types; an unenumerated change-type is a gap, surfaced as a warning, not a guarantee** (Known limitation 2). The Reflect/ship pass runs the pinned diff against the map and logs any companion that did not move.

### Part 3: PHILOSOPHY loop-framing note (deep scan ADAPT)

PHILOSOPHY currently has no explicit loop stance; the "outer loops declined" framing lives in SPEC-003 DEC-005 (shipped, not edited in place per the spec-README rule). This spec ADDS a short note to PHILOSOPHY §3 (Design boundaries) refining that framing:
- **Unbounded outer bash loop** (an external `while` driving repeated sessions): declined; autonomous-runtime territory (GSD v2 / OMC). The fence stays firm.
- **Bounded in-session Stop-hook loop** (the goal/anti-rationalization continuation): native and first-party-blessed (Anthropic `ralph-loop` plugin: "the loop happens inside your current session"). The kit already owns this primitive.

Doc-only, one paragraph, source-cited, naming SPEC-003 DEC-005 as the prior framing. It removes the contradiction between "we decline loops" and "our anti-rationalization Stop hook IS a loop primitive," and keeps the unbounded outer loop firmly declined so the note cannot read as "loops are fine now."

### Tradeoff table

| Fork | CHOSEN | Rejected alt |
|---|---|---|
| Spine shape | thin router + 2 warn+log clauses + a PHILOSOPHY note | (A) GSD-style 5-gate staged machine: trades "readable in 30s" for enforcement the verifier already gives cheaper. (B) Shipyard `STATE.json` runtime: a product, not a kit. |
| Item-d enforcement | surface + log + ship-gate review (warn, not mid-loop block) | (A) fire-and-forget warn: weakest, the loop reads its own warning. (C) hard gate: the field-wide + PHILOSOPHY-rejected pattern; reserved for irreversible/safety cost. |
| Decision clause | scoped to tagged "Build decisions" + log | naive "every DEC referenced" grep: false-positives on rationale/rejected/validation decisions, becomes ignored noise. |
| Goal-store surface (deferred from SPEC-005) | one `/user:assign` (create); rendering folds into `/user:start`/`/user:next`; `--switch` deferred | (A) a separate `/user:goals` command. (B) ship `--switch` now: thin value (can't block the activator; re-activating a draft = open the file). |

### NO-list check
Per-part one-sentence descriptions (gate 4; the spec is multi-part, like SPEC-003/005):
- *"`/user:assign` turns a backlog item into a scoped goal draft and routes it into the right WORKFLOW lane."*
- *"`/user:start`/`/user:next` render the backlog queue + goal drafts read-only."*
- *"Two warn-and-log completion clauses surface lost decisions/docs to a log that `/user:ship` reviews before shipping."*

| Gate | Compliance |
|---|---|
| Guardrails over guidance | ✓ hard blocks reserved for the safety subset (existing hooks); process-completeness is surfaced + logged + gate-reviewed, the honest non-rejected option |
| Synthesize, don't originate | **✓-with-caveat.** Router = CCGS `/start` + GSD intake; loop note = Anthropic `ralph-loop`. The decision-translation clause and the doc-impact map are net-new/originated-in-kit (the cited GSD mechanism is a hard gate; this is a warn+log adaptation grounded on the kit's own `spec-drift-guard` shape, whose header is `Source: Novel`). Labeled in Known limitations, not hidden (mirrors SPEC-003 DEC-003, SPEC-005 DEC-014). |
| Shallow and wide | ✓ connective tissue across phases; the rendering is the same justification SPEC-003 DEC-008 used (connective tissue, not "serves 2+ phases" gaming) |
| Detect, don't dictate | ✓ warn+log, never mid-loop block; `/user:assign` suggests the lane |
| Bash over binaries | ✓ doc + one command prompt + read-only renders + a log line; if/when promoted, the guards are bash+grep |
| Serves 2+ phases | ✓ `/user:assign` serves Think+Spec+Build; the clauses serve Build+Review+Reflect; the rendering is connective tissue (per above) |
| One sentence describable | ✓ per-part (above) |
| No speculative config | ✓ no env var, no flag; the command now has a real consumer (this spine); `--switch` deferred until a real need |

## Solution

| Task | Files | Type | Depends on |
|---|---|---|---|
| TASK-1 | `WORKFLOW.md` (new "The spine" section) | Doc (wiring) | SPEC-005 shipped |
| TASK-2 | `commands/assign.md` (new: `/user:assign ID-NNN`) | New command | SPEC-005 (goal-store contract + backlog schema) |
| TASK-3 | `commands/start.md` + `commands/next.md` (render queue + drafts, read-only) | Command rendering | SPEC-005 (schema + dual-detect) |
| TASK-4 | `WORKFLOW.md` completion contract: 2 warn+log clauses + doc-impact map + "Build decisions" convention + log sink | Doc (clauses) | TASK-1 |
| TASK-5 | `commands/ship.md` + `commands/retro.md` + `commands/docs.md`: run the pinned diff vs the map + review the completeness log at the gate | Gate review | TASK-4 |
| TASK-6 | `docs/PHILOSOPHY.md` §3: add the bounded/unbounded loop note | Doc (framing add) | - |
| TASK-7 | `tests/test-meta.sh` + `README` + `MANUAL` + `CHANGELOG` | Tests + hygiene | TASK-1..6 |

### Task Breakdown

**Phase 1: Wire the seam + the command**
- [x] **TASK-1: `WORKFLOW.md` "The spine" section.** Pinned header `## The spine`; the backlog -> `/user:start` -> `/user:assign` -> lane -> ship diagram; the activator-agnostic handoff (kit never writes `last-goal.md`); the "enforcement reality" summary (safety subset hard-enforced; completeness warned+logged+ship-reviewed). Short; link to SPEC-005 + the cycle table.
  - Acceptance: `## The spine` exists; references the BACKLOG queue + `.claude/goals/` (SPEC-005) and the cycle table; states the no-`last-goal.md`-write rule and the warn+log+ship-review posture; ASCII-clean headers; no CAPS coercion.
- [x] **TASK-2: `commands/assign.md`.** `/user:assign ID-NNN`: read the backlog item, goal-craft the breakdown (objective + scope fence + termination-on-blocker), write `.claude/goals/<slug>.md` linked to `ID-NNN` (SPEC-005 contract, frontmatter keys pinned: `slug, id, target_spec, status, created`), pick the lane from the item's Lane column, detect the available goal-loop activator and surface the draft body for it (graceful-degrade to plain file if none), hand off to the lane's first command, set the backlog item status. Does NOT execute; does NOT write `last-goal.md`.
  - Acceptance (one checkbox each):
    - [x] frontmatter `description:` (parity check)
    - [x] reads the backlog by `ID-NNN`; errors clearly if the id is absent
    - [x] writes a draft via the SPEC-005 contract with the pinned frontmatter keys
    - [x] detects the activator (built-in `/goal` / `ralph-loop` / `goal-craft`) and degrades gracefully to a plain file if none; never assumes a specific one exists
    - [x] never writes `last-goal.md`; surfaces the body + hands off without executing
    - [x] idempotent: re-running for the same `ID-NNN` re-surfaces the existing draft rather than creating a duplicate (one draft per id; mirrors SPEC-005 edge 6)
    - [x] updates the backlog item status (`queued`->`speccing`/`executing`)

**Phase 2: Read-only rendering (SPEC-005 ID-006 deferred)**
- [x] **TASK-3: Render the queue + drafts in `/user:start` and `/user:next`.** `/user:start`: render the `_meta/BACKLOG.md` Active queue (SPEC-005 schema) as "what's left?" and list `.claude/goals/` drafts (`slug, target_spec, status`). `/user:next`: when no in-spec task remains, surface the backlog queue. Both read-only; both use SPEC-005 dual-detect. Both degrade gracefully on a malformed queue (render what parses, note unparseable rows, never error out of session start).
  - Acceptance: `commands/start.md` references `_meta/BACKLOG.md` + `.claude/goals/` (greppable); `/user:next` falls back to the queue when the active spec is complete; neither mutates; malformed-queue degradation stated; **rendering correctness is review-verified, not test-verified** (the kit has no command-behavior harness; TASK-7 asserts only the structural references).

**Phase 3: Close the two leaks (warn + log)**
- [x] **TASK-4: Completion-contract clauses + doc-impact map + conventions.** In `WORKFLOW.md`: add the decision-translation clause (scoped to a spec's optional "Build decisions" sub-list; no-op if absent; DEC-ID regex handles `(validation)`/suffixes) and the doc-update clause (pinned diff base = merge-base of the integration branch; normal/full lanes only). Add the doc-impact map (the table above, incl. the self-maintenance row). Add the "Build decisions" sub-list convention to the spec format note. State the completeness-log sink path. Both clauses warn + log, never block.
  - Acceptance: both clauses present and warn+log (no "block"/"halt"); the decision clause is scoped to "Build decisions" and is a no-op without that list; the doc-update clause pins the diff base and the lane scope; the doc-impact map present with the self-row; the log path stated; the "Build decisions" convention documented.
- [x] **TASK-5: Gate review at ship + Reflect.** Extend `commands/ship.md` to read the completeness log and surface un-cleared decision/doc warnings as part of the ship gate (report, the maintainer decides; consistent with the existing ship gate that blocks only on FIX-REQUIRED). Extend `commands/retro.md` + the `docs` step to run the pinned diff against the doc-impact map and list un-updated companions.
  - Acceptance: `/user:ship` reviews the completeness log at the gate and surfaces un-cleared warnings (does not auto-block on them); `/user:retro` + `/user:docs` run the pinned diff against the map and list un-updated companions; all report, none hard-block on completeness (hard-block stays reserved for the existing FIX-REQUIRED/safety gates).

**Phase 4: Framing**
- [x] **TASK-6: PHILOSOPHY §3 loop note.** ADD (not "replace") a one-paragraph bounded/unbounded distinction to PHILOSOPHY §3, naming SPEC-003 DEC-005 as the prior framing and Anthropic `ralph-loop` as the source for the in-session primitive. Keep the unbounded outer bash loop firmly declined so the note cannot read as license for outer-loop creep.
  - Acceptance: §3 gains the bounded/unbounded distinction; cites SPEC-003 DEC-005 + `ralph-loop`; the unbounded outer loop stays explicitly declined; the spec's prose no longer claims "§3 declines loops wholesale" (it did not).

**Phase 5: Verify + hygiene**
- [x] **TASK-7: Tests + cross-refs.** `tests/test-meta.sh`: assert `WORKFLOW.md` has `## The spine` + the doc-impact map heading + the "Build decisions" convention note; `commands/assign.md` exists with `description:`; PHILOSOPHY §3 contains the bounded/unbounded distinction. Assert for the PRESENCE of headings/markers, not exact prose (avoid brittle coupling). README/MANUAL row for `/user:assign` + note the `/start`-`/next` rendering. CHANGELOG entry.
  - Acceptance: `bash tests/test-meta.sh` passes (count rises by the documented delta); `bash tests/test-hooks.sh` 42/42 (no hook touched in this spec); `/user:assign` in the MANUAL inventory; CHANGELOG entry.

## Acceptance Criteria (global)
- [x] `WORKFLOW.md` has a `## The spine` section wiring backlog -> assign -> lane -> ship, with the no-`last-goal.md`-write rule and the warn+log+ship-review posture
- [x] `/user:assign ID-NNN` exists, is a mutator-dispatcher (no execution, no `last-goal.md` write), detects the activator + degrades gracefully, is idempotent per id
- [x] `/user:start` + `/user:next` render the queue + drafts read-only via SPEC-005 schema/dual-detect, degrade on malformed input; correctness review-verified
- [x] Both clauses warn + log (decision-translation scoped to "Build decisions"; doc-update pinned-diff, normal/full lanes); doc-impact map present incl. the self-row; "covers enumerated change-types" not "airtight"
- [x] `/user:ship` reviews the completeness log at the gate; `/user:retro` + `/user:docs` run the pinned diff against the map
- [x] PHILOSOPHY §3 gains the bounded/unbounded loop note (added, not a correction of nonexistent text); unbounded outer loop stays declined
- [x] No hard gate added for completeness; hard stops remain the existing safety/verify/FIX-REQUIRED gates
- [x] `bash tests/test-hooks.sh` 42/42; `bash tests/test-meta.sh` passes (new count documented)
- [x] No new dependency, env var, settings.json field; exactly one new command (`/user:assign`); `/start`/`/next`/`/ship`/`/retro`/`/docs` extended, not added; `--switch` deferred
- [x] CHANGELOG entry; consistent with SPEC-005 (consumes its state, owns its deferred command + rendering) and the deep-scan note

## Known limitations
1. **The completeness clauses and the doc-impact map are net-new/originated-in-kit, warn+log (not the cited GSD hard gate), and have not met the PHILOSOPHY §5 "1 week on a real project" bar.** Grounded on the kit's own `spec-drift-guard` shape; labeled, not hidden (mirrors SPEC-003 DEC-003 / SPEC-005 DEC-014).
2. **The doc-impact map is incomplete by construction.** It covers the enumerated change-types; an unenumerated type is a gap surfaced as a warning, not a guarantee. "Airtight / no omission" was downgraded to this honest claim.
3. **Activation depends on an external goal-loop primitive the kit cannot version** (built-in `/goal`, `ralph-loop`, or `goal-craft`). The command detects what is present and degrades to a plain draft file; it never assumes one exists and never writes `last-goal.md`.
4. **Decision/doc completeness is surfaced + logged + ship-reviewed, NOT hard-blocked mid-loop.** `anti-rationalization.sh` matches only 5 literal phrases (none of these leaks) and the verifier runs inside `/user:execute` (a free-form goal loop can bypass it). Hard-gating process completeness is the rejected pattern; the ship-gate log review is the chosen non-rejected enforcement.

## Edge Cases
1. **`/user:assign` on a `tiny`-lane item.** Crafts a goal draft but routes to "edit, verify, done" (no /spec). The doc-update clause is suppressed for tiny-lane (no CHANGELOG/version ceremony); the decision clause is a no-op (no "Build decisions" list). Tiny work stays out of ceremony.
2. **A goal loop lands work with an orphan build-decision or a missed companion doc.** The clause warns + logs; `/user:ship` surfaces the log at the gate before shipping. Not blocked mid-loop (Known limitation 4); not silent either.
3. **A change touches `hooks/` but RUNBOOK was not updated.** The doc-update clause (pinned merge-base diff) logs RUNBOOK as un-updated; `/user:retro` + `/user:ship` list it. The maintainer decides.
4. **An unenumerated change-type appears** (a new top-level dir). The self-maintenance row says adding a dir must update the map; if a type is still missing, it is a logged gap and a retro signal to extend the map (or promote the clause to a hook). Honest, not airtight.
5. **`/user:assign` for a `queued` item with no spec.** Normal/full lane: hand off to `/user:spec` first.
6. **Re-running `/user:assign ID-NNN`.** Idempotent: re-surfaces the existing draft (one draft per id), does not duplicate; does not double-advance status.
7. **Malformed `_meta/BACKLOG.md` at `/user:start`.** Render what parses, note unparseable rows, never error out of session start (matching the detector-never-blocks stance).
8. **Branch-vs-queue mismatch.** `/user:start` renders the full queue; the dual-detect active spec is branch-selected (SPEC-005). If the branch matches no open item, the render lists the full queue and notes "no item matches the current branch."

## Out of Scope
- A staged-gate state machine or a `STATE.json` runtime (rejected).
- A hard gate on decision/doc completeness (the rejected pattern; surfaced+logged+ship-reviewed instead).
- Promoting either clause to a hook now (deferred behind a retro signal per PHILOSOPHY §5).
- `--switch` between drafts (deferred: thin value now, cannot block the activator; re-activating an existing draft = open the file or re-run `/user:assign`).
- An unbounded outer execution loop / multi-session orchestration (still declined).
- Parallel multi-goal *execution* (the kit is one-session).
- Reimplementing goal-crafting or any activator; the kit writes only `.claude/goals/` and hands off (SPEC-005 DEC-004).
- A new permission taxonomy (orthogonal per the scan).

## Decision Log
- **DEC-001**: The spine is wiring + one command + rendering + two warn+log clauses + a PHILOSOPHY note, not a controller. The deep scan found the spine already exists; do less.
- **DEC-002**: Completeness checks ship as completion-contract clauses (warn+log), hooks deferred behind a retro signal (PHILOSOPHY §5).
- **DEC-003**: One new command (`/user:assign`); rendering folds into `/user:start`/`/user:next`; `--switch` deferred. Resolves SPEC-005's deferred surface with +1 command.
- **DEC-004**: The goal loop is routed through the gates via surface+log+ship-review, not declined and not hard-gated. The in-session Stop-hook loop is the kit's own architecture and first-party-blessed (`ralph-loop`).
- **DEC-005**: Item f is solved by an enumerated doc-impact map + a pinned-diff closing check, not a heavyweight doc generator.
- **DEC-006**: Decision-translation is grep-grade, warn+log, scoped to "Build decisions". The kit already trusts the `spec-drift-guard` shape.
- **DEC-007**: Activation never writes `last-goal.md` (inherits SPEC-005 DEC-004); the command detects the activator and degrades gracefully.
- **DEC-008**: `/user:assign` lands here (not SPEC-005) because here it has a real consumer (this spine); in SPEC-005 it was a phantom (SPEC-005 DEC-011).
- **DEC-009 (validation)**: Item-d enforcement = surface + log + ship-gate review, NOT a mid-loop hard block. Rationale: hard-gating process completeness is the field-wide + PHILOSOPHY-rejected pattern; "Guardrails over guidance" reserves hard blocks for irreversible/safety cost (philosophy adjudication; maintainer decision 2026-05-20).
- **DEC-010 (validation)**: The "cannot ship" overclaim is removed; the spec states plainly that `anti-rationalization.sh` (5 phrases) and the verifier (in `/execute`) do NOT back these leaks, so the enforcement is the ship-gate log review (assumption + failure + philosophy reviewers).
- **DEC-011 (validation)**: TASK-6 ADDS a loop note to PHILOSOPHY §3; it does not "replace" §3 text (§3 has no loop language). The prior framing is SPEC-003 DEC-005, not edited in place (spec-README rule). The spec's false "§3 declines loops wholesale" claim is corrected (scope + philosophy C1).
- **DEC-012 (validation)**: Stop calling it "the built-in `/goal`" as guaranteed. `/goal` is not confirmed present; the command detects the activator (built-in `/goal` / `ralph-loop` / `goal-craft`) and degrades to a plain file. SPEC-005's wording gets the same correction (assumption + failure C3/C2).
- **DEC-013 (validation)**: Decision-translation scoped to a spec's "Build decisions" sub-list (no-op without it); rationale/rejected/`(validation)` decisions exempt; DEC-ID regex handles suffixes. Rationale: the naive grep false-positives on this spec's own decisions (assumption + failure C3/C4; maintainer decision 2026-05-20).
- **DEC-014 (validation)**: Doc-impact map completed (install.sh, settings.json, examples, rules, skills, ADRs, the self-row) and the "any shipped change" row scoped to normal/full lanes; "airtight/no omission" downgraded to "covers enumerated change-types, gaps surfaced as warnings" (assumption + failure + philosophy C5).
- **DEC-015 (validation)**: Clauses LOG to `completeness.log` and `/user:ship` reviews the log at the gate; not fire-and-forget. Rationale: a warn read by the same loop that ignores it is no record (failure C2; maintainer decision 2026-05-20).
- **DEC-016 (validation)**: Doc-update clause pins the diff base to the integration-branch merge-base. Rationale: a floating `git diff` base produces non-deterministic false positives/negatives across the existing command conventions (failure C4).
- **DEC-017 (validation)**: TASK-2 right-sized to a single create command with checkbox ACs; `--switch` deferred. Rationale: the original TASK-2 exceeded the atomicity heuristic and `--switch` is thin value now (scope C2/W2).
- **DEC-018 (validation)**: Rendering correctness is review-verified, not test-verified; TASK-7 asserts only structural references. Rationale: the kit has no command-behavior harness; the AC must not claim a green suite proves rendering (scope C3).
- **DEC-019 (validation)**: Synthesize row downgraded to ✓-with-caveat + a Known-limitations section added. Rationale: the clauses + map are net-new/warn+log (the cited GSD source is a hard gate); match the SPEC-003/005 honesty register (philosophy C2).
- **DEC-020 (validation)**: TASK-7 asserts presence of headings/markers, not exact prose; draft frontmatter keys pinned (`slug, id, target_spec, status, created`) and aligned with SPEC-005. Rationale: brittle prose coupling + an unpinned `target` vs `target_spec` field name (assumption W2/W3).
- **DEC-021 (reconciliation, 2026-05-21)**: No design reconcile needed (unlike SPEC-005): SPEC-005 shipped the `.claude/goals/` contract, backlog schema, and branch-aware dual-detect exactly as this spec depends on, and SPEC-006 carries no `.planning`/ADR-0002 assumption. Two execution adjustments from concurrent SPEC-013: (a) the command count is now 14 (SPEC-013's `/user:debug`), so `/user:assign` makes 15 and the TASK-7 ripple also fixes `.claude-plugin/plugin.json` + `marketplace.json`, which SPEC-013 left stale at 13; (b) TASK-6's §3 loop note frames BOTH bounded in-session loops (goal + debug) as native, keeping the unbounded outer loop declined.

## Source citations
- Deep scan that scoped this spec (do-less steer, ADOPT/ADAPT/REJECT, the `ralph-loop` finding): `docs/research/2026-05-20-orchestration-deep-scan.md`.
- The spine, lanes, gates this wires into: `WORKFLOW.md` + `docs/specs/SPEC-003-orchestration-layer.md` (DEC-005 = the prior loop framing this refines).
- State + deferred surface this consumes/owns: `docs/specs/SPEC-005-backlog-and-goal-state.md` (DEC-011 deferred the command + rendering here; DEC-004 the no-`last-goal.md` rule).
- Decision-translation pattern: GSD v1.40+ decision-locking (a hard gate; adapted here to warn+log; via the deep scan).
- In-session Stop-hook loop is native/blessed: Anthropic `ralph-loop` plugin (via the deep scan).
- Dispatcher pattern: `commands/next.md` + CCGS `/start` router; goal breakdown: the `goal-craft` skill.
- Logging shape: `hooks/spec-drift-guard.sh` (the `LOG_DIR` + append pattern the clauses reuse).

## Validation
4 reviewers run 2026-05-20 (scope-critic, assumption-destroyer, failure-mode, philosophy-fidelity). Aggregate pre-fix verdict: NEEDS REVISION (design sound; overclaims + 2 factual errors + incompleteness).

Critical concerns, all resolved inline:
- TASK-6 targeted nonexistent PHILOSOPHY §3 loop text -> reframed as an ADD, naming SPEC-003 DEC-005 (DEC-011).
- "built-in `/goal`" assumed present -> activator-detection + graceful degradation; SPEC-005 wording corrected too (DEC-012).
- "cannot ship" enforcement overclaim -> surface+log+ship-review, honest about the 5-phrase anti-rationalization + verifier bypass (DEC-009, DEC-010, DEC-015).
- decision-translation false-positive storm -> scoped to "Build decisions", no-op without it (DEC-013).
- doc-impact map incomplete + "airtight" overclaim -> completed map + self-row + honest "covers enumerated types" (DEC-014); pinned diff base (DEC-016).
- TASK-2 oversized + `--switch` thin -> right-sized create command, `--switch` deferred (DEC-017).
- unverifiable rendering AC -> review-verified, structural-only tests (DEC-018).
- unqualified "✓ Synthesize" -> ✓-with-caveat + Known limitations (DEC-019).

Warnings addressed: brittle prose-coupled tests + unpinned frontmatter keys (DEC-020); rendering connective-tissue justification (not 2-phase gaming); malformed-queue degradation (edge 7); idempotency (edge 6); promote-cost split noted; the §3 note keeps the unbounded outer loop declined.

Status flipped to VALIDATED after inline resolution. Re-run `/user:spec-validate` if the design changes materially before execute.
