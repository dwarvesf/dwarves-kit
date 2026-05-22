# ORCHESTRATION.md: the flow/loop view

> Reference manual for the dwarves-kit **orchestration layer**: the machinery that
> moves one unit of work from intake to shipped. This is the flow-and-loop view.
> For per-command operator detail read `MANUAL.md`; for the rules contract read
> `WORKFLOW.md`; for component fit read `docs/architecture.md`; for why-decisions
> read `docs/PHILOSOPHY.md` + `docs/decisions/`. This doc cross-links those; it
> does not restate them.

## At a glance

| Kind | Count | Members |
|---|---|---|
| Backbone | 1 | the spine (intake -> shipped) |
| Primary intake lanes | 5 | `tiny`, `normal`, `full`, `bug`, `backfill` |
| Bounded loops (engines) | 3 | goal loop, debug loop, execute verification pipeline |
| Alternate / branch flows | 7 | retry, escalate, ambiguous-spec, no-activator, idempotent re-run, DO-NOT-SHIP gate, completeness warn+log |
| Opt-in side-flows | 8 | `/user:design`, `/user:devs-team`, `/user:visual-team`, `/user:ui-design`, `/user:test-plan`, `/user:review-team`, `/user:absorb`, `/user:kit-health` |
| Hard stops (the only blockers) | 4 | safety-gate, push-to-main blocker, anti-rationalization, verification pipeline |

Everything else **suggests and routes; it does not block**. The four hard stops are
the only places the kit refuses to proceed. Keep that split in mind throughout.

---

## 1. The state model (what the flows move between)

Three stores. Each flow reads and/or writes these; nothing is re-entered between phases.

```text
  _meta/BACKLOG.md            docs/specs/SPEC-NNN-<slug>.md      .claude/goals/<slug>.md
  ┌─────────────────┐         ┌──────────────────────────┐      ┌──────────────────────┐
  │ the Active queue│         │ the contract             │      │ ephemeral goal drafts│
  │ ID-NNN rows     │ ──────▶ │ Status: DRAFT            │ ◀──▶ │ (gitignored,         │
  │ status:         │  assign │        -> VALIDATED      │      │  per-machine)        │
  │ queued/speccing/│         │        -> SHIPPED        │      │ one draft per ID     │
  │ validated/      │         │ tasks, AC, Verification, │      └──────────────────────┘
  │ executing/      │         │ After state, Open Qs     │        the built-in /goal owns
  │ shipped (parked)│         └──────────────────────────┘        .claude/last-goal.md;
  └─────────────────┘                                             the kit NEVER writes it
```

**Detector vs mutator** (load-bearing): `/user:start` and `/user:next` only **read and
render** the queue + drafts. `/user:assign` is the **only mutator**: it writes a goal
draft, flips a backlog status, and hands off. No other entry point mutates state on intake.
`/user:assign` accepts either an `ID-NNN` or **freeform intent** (the freeform front door,
SPEC-026): given freeform it delegates the crystallize interview to `/user:think`, then
allocates the ID + BACKLOG row (approve-before-allocate, sanitized) before routing as usual.

---

## 2. The spine (master lifecycle flowchart)

How a committed backlog item becomes shipped work, end to end. This is the backbone;
every lane is a longer or shorter walk along it.

```text
  session start
       │
       ▼
  /user:start ........... DETECT: render the BACKLOG Active queue + active goal drafts
       │                  (read-only; suggests the next command)
       ▼
  /user:assign <ID|free> .. MUTATE: goal-craft a draft (.claude/goals/<slug>.md);
       │                  pick the lane from the item, detect the goal-loop activator,
       │                  flip status (queued -> speccing | executing), hand off.
       │                  Does NOT execute. Never writes last-goal.md.
       ▼
  ┌─────────────────── pick a lane (Section 3) ───────────────────┐
  │  tiny      normal        full            bug         backfill  │
  └───────┬──────┬─────────────┬──────────────┬─────────────┬─────┘
          │      │             │              │             │
          │      ▼             ▼              ▼             ▼
          │  /user:spec    /user:think    /user:debug   review code,
          │      │         /user:spec        │          write AGENTS.md
          │      │         /user:spec-validate│          /CLAUDE.md/specs
          │      │             │              │          (no app code)
          │      ▼             ▼              │             │
          │  /user:execute (verification pipeline, Section 5.3)      │
          │      │             │              │             │
          │      ▼             ▼              ▼             │
          │  /user:review  /user:review-team  (root cause   │
          │      │             │              recorded,     │
          │      ▼             ▼              fix verified,  │
          │  (normal)      /user:docs         human-confirm)│
          │      │             │                            │
          │      │             ▼                            │
          └──────┴────────▶ /user:ship ◀────────────────────┘
                              │   (ship gate: blocks on DO NOT SHIP;
                              │    push-to-main blocker; flips spec -> SHIPPED;
                              │    ID-NNN drops off the queue)
                              ▼
                           /user:retro (full lane) -> docs/retro/RETRO-YYYY-MM-DD-<slug>.md
```

Opt-in beats (Section 6) slot in along this path: `/user:design` between think and spec;
`/user:devs-team` + `/user:visual-team` before the spec hardens; `/user:test-plan` before
execute; `/user:ui-design` for downstream UI work.

---

## 3. Primary intake lanes (5)

Pick a lane **before** you start. Smaller work skips ceremony. When in doubt between two,
take the heavier one.

| # | Lane | Trigger (when) | Path | Stop / exit |
|---|---|---|---|---|
| 1 | `tiny` | typo, copy, comment, one obvious edit | edit -> verify -> done. No spec. | the edit verifies |
| 2 | `normal` | one bounded feature or fix | `/spec` -> `/execute` -> `/review` -> `/ship` | shipped, ID off queue |
| 3 | `full` | touches auth/authz, hooks, data model, data loss, audit/security, an external provider, an API contract, a migration, or weakens validation | `/think` -> `/spec` -> `/spec-validate` -> `/execute` -> `/review-team` -> `/docs` -> `/ship` -> `/retro` | shipped + retro written |
| 4 | `bug` | a defect, regression, or failing test (not a new feature) | `/debug` (root cause first) -> `/review` | root cause recorded, fix verified, human-confirmed |
| 5 | `backfill` | brownfield: adopt the kit onto existing code | review the code, write the operating-layer docs (AGENTS.md / CLAUDE.md / specs). `/spec` optional. | docs written; **no app-behavior change, no app-code edits** |

```text
                       is it a defect / regression / failing test ?
                                   │ yes            │ no
                                   ▼                ▼
                                 bug          new work on an existing repo
                                              with no operate-layer docs ?
                                                   │ yes        │ no
                                                   ▼            ▼
                                                backfill    how big / how risky ?
                                                            ├─ trivial edit ....... tiny
                                                            ├─ one bounded change . normal
                                                            └─ risk-list match .... full
```

The `full` trigger list is a hard tripwire: anything on it uses `full` unless you explicitly
narrow the scope and say why.

---

## 4. The bounded-loop principle

The kit ships **bounded in-session loops** and declines **unbounded outer loops**. A bounded
loop continues *within* the current session under a model-evaluated stop condition plus the
safety subset; an unbounded loop spawns *new* sessions without one (that is autonomous-runtime
territory: GSD v2 / OMC, out of scope). All three engines below are bounded.

---

## 5. The three bounded loops (engines)

### 5.1 Goal loop

A continuation that keeps the current session working a single objective until a verifiable
stop holds. Wired from the backlog by `/user:assign`, activated by whatever loop primitive is
present.

- **Trigger**: an objective handed to an activator: the built-in `/goal`, the `ralph-loop`
  plugin, or the `goal-craft` skill. `/user:assign` writes the draft and surfaces its body;
  it does **not** start the loop itself (activator-agnostic).
- **Enforcer**: the **anti-rationalization Stop hook** (blocks premature "done"), plus the
  rest of the safety subset (verification pipeline, push-to-main blocker).
- **Stop condition**: the objective's `## Verification` command(s) pass AND the done-definition
  holds (AGENTS.md "Done means" + the spec's `## After state`). On a blocker it cannot resolve,
  it appends a named note to the spec's `## Open questions` and stops (no churn).
- **Branches**: no-activator (degrades to a plain reusable draft file, Section 7.4);
  blocker-hit (write Open-questions note, stop).

```text
   activator starts the objective
            │
            ▼
   ┌───▶ do the next increment ──▶ run ## Verification
   │            ▲                        │
   │            │                  pass? │
   │            │              ┌─────────┴─────────┐
   │            │           no │                   │ yes
   │            │              ▼                   ▼
   │            │     anti-rationalization     ALL done? ──no──┐
   │            │     blocks "done";           │ yes           │
   │            └─────  keep working ◀─────────┘               │
   │                                                            │
   │   hit a blocker you can't resolve?                         ▼
   └── write a note to spec ## Open questions ─────────────▶  STOP
```

### 5.2 Debug loop (`/user:debug`, the `bug` lane)

A systematic four-phase loop under one iron law. Off-cycle: a bug-lane entry point, not a
linear phase.

- **Trigger**: `/user:debug` on a defect, regression, or failing test.
- **Iron law**: **NO FIX WITHOUT A RECORDED ROOT CAUSE.** Evidence accrues in an append-only
  ledger `.claude/debug/<slug>.md` whose `## Root cause` heading is the contract.
- **Enforcer**: the **guess-fix guard** (a gated mode of the anti-rationalization hook): it
  blocks a fix/done claim while an open debug ledger still has an empty `## Root cause`. Silent
  in non-debug sessions.
- **Stop condition**: root cause recorded + fix verified + **human-confirmed**.
- **Branches**: regression -> `git bisect`; failing-test-first -> routed into the execute
  verification pipeline (5.3); the **3-fix architecture wall** (after 3 failed fixes, stop and
  reconsider the design rather than keep patching).

```text
   /user:debug
       │
       ▼
   Phase 1: Root cause ───▶ Phase 2: Pattern ───▶ Phase 3: Hypothesis ───▶ Phase 4: Implementation
       │  (ledger              (reproduce,            (predict, then          (apply the fix)
       │  ## Root cause)       narrow; bisect          test the guess)             │
       │                       if regression)              │                       ▼
       │                                                   │                  verified? ──no──┐
   guess-fix guard: a fix/done claim is BLOCKED            │                       │ yes      │
   while ## Root cause is empty ◀──────────────────────────┘                       ▼          │
                                                                            human-confirm     │
   3 failed fixes in a row ──▶ STOP: architecture wall (reconsider design)         │          │
                                                                                   ▼          │
                                                                                 DONE ◀───────┘ (loop Phase 3-4)
```

### 5.3 Execute verification pipeline (the build engine)

The core build loop: `/user:execute` dispatches one worker per task, verifies each in a fresh
context, retries fixable failures, and checks cross-task wiring at the end. Self-reported
"done" from a worker is never proof; the verifier is.

- **Trigger**: `/user:execute` on a `VALIDATED`/`APPROVED` spec on a feature branch.
- **Enforcer**: the **verification pipeline itself** is a hard stop (it gates each task).
- **Stop condition**: every task PASS **and** the integration-checker PASS (multi-task specs).
- **Branches**: `PASS` (advance), `FAIL:fixable` (retry via fix-agent, **max 2**), `FAIL:escalate`
  or retries exhausted (stop -> human). Single-task specs skip the integration check.

```text
   /user:execute  (record pre-build base ref)
        │
        ▼
   ┌── for each task in phase ──────────────────────────────────────────┐
   │     worker subagent (fresh context) ──▶ task-verifier (read-only)   │
   │                                              │                       │
   │                          ┌───────────────────┼───────────────────┐  │
   │                       PASS              FAIL:fixable        FAIL:escalate
   │                          │                   │                    │  │
   │                          │                   ▼                    │  │
   │                          │            fix-agent (scoped)          │  │
   │                          │            re-verify  ▲                │  │
   │                          │            retry < 2 ─┘                │  │
   │                          │            retries == 2 ──────────────▶│  │
   │                          ▼                                        ▼  │
   │                   mark task done                          ESCALATE to human
   └──────────┬─────────────────────────────────────────────────────────┘
              │ all tasks PASS
              ▼
   phase checkpoint (human: continue / review / stop)
              │
              ▼
   integration-checker (read-only, diffs whole build from base ref)
              │
        ┌─────┼───────────────┐
      PASS  FAIL:fixable   FAIL:escalate
        │     │ (fix-agent,     │
        │     │  reuse cap)     ▼
        ▼     ▼            ESCALATE
      build complete ◀── re-check
```

### 5.4 Mid-flight amend micro-loop (BUILDING -> checkpoint -> amend -> resume)

A side excursion off the execute pipeline, not a fourth engine: when work mid-build reveals
scope that must be added now ("also do Y"), the operator amends the active `VALIDATED` spec in
place and resumes, **without** restarting the lane. The rule (the checkpoint guard, the
add-only + frozen-completed-tasks + Status-stays-VALIDATED invariants, resume-via-`/next`) is
canonical in **`WORKFLOW.md` "## Mid-flight amend"**; the state-model row
(`BUILDING -> SPECIFYING -> BUILDING`) lives in `docs/operating-layer-vision.md` §3.3. This
section only draws the loop; it does not restate the four invariants.

- **Trigger**: operator says "also do Y" / "amend the spec" mid-`/user:execute`.
- **Guard**: amend only at a task checkpoint (the in-flight task verified + committed first,
  or none in flight); completed `- [x]` tasks are frozen.
- **Resume**: `/user:next` (picks the next undone `- [ ]` row, skips done rows), **not** a fresh
  `/user:execute` (which re-presents the whole plan). See `WORKFLOW.md` for why.

```text
   BUILDING (mid /user:execute, spec is VALIDATED)
        │  trigger: "also do Y"
        ▼
   reach a task checkpoint  ──────────────────────────────┐
   (in-flight task verified + committed; - [x] frozen)     │ not at a checkpoint yet?
        │                                                  │ finish the in-flight task first
        ▼                                                  └──────────────────────────────┘
   SPECIFYING (amend, not restart)
        - append new - [ ] TASK rows; delta After-state / AC / Verification
        - record an ## Amendments entry
        - re-validate the DELTA only (full: /spec-validate; normal: advisory)
        │  Status STAYS VALIDATED (no drop to DRAFT)
        ▼
   /user:next  ──▶  BUILDING (resume; runs only the amended tasks)
```

---

## 6. Opt-in side-flows (8)

Advisory, never blocking. They enrich a lane but are not required by any.

| # | Flow | Trigger | Writes to | Stop |
|---|---|---|---|---|
| 1 | `/user:design` | between `/think` and `/spec`, when the solution needs working out | `docs/specs/DECISION-BRIEF.md` (folded into the spec by `/spec`) | solution agreed per section |
| 2 | `/user:devs-team` | before the spec hardens; 5 engineering lenses | `## Design critique` in the active spec (else the brief) | verdict recorded |
| 3 | `/user:visual-team` | a visual/UI design exists (downstream) | `## Visual critique` in the active spec (else brief, else inline) | verdict recorded |
| 4 | `/user:ui-design` | downstream UI work, after `/design` | `## UI design` in the spec; generates via `frontend-design`; critiques via `/visual-team` | SOLID/RECONSIDER verdict or max-2 revise |
| 5 | `/user:test-plan` | before `/execute`; derive a coverage matrix | `## Test plan` in the spec (consumed by `/execute`) | matrix written |
| 6 | `/user:review-team` | PR-grade review; 3 lenses (security/architecture/test-coverage) in parallel | `REVIEW.md` (+ `TODOS.md`) | SHIP / FIX THEN SHIP / DO NOT SHIP |
| 7 | `/user:absorb` | maintainer-only external-absorption audit | dated report under `docs/absorption/` | proposal-only report (human merge gate) |
| 8 | `/user:kit-health` | maintainer self-assessment vs PHILOSOPHY, before tagging | report (stdout) | assessment rendered |

All of these write **into the active spec** when the output binds to a spec (replace-not-stack),
so a later reader and an earlier writer never split across two specs.

---

## 7. Alternate / branch flows (7)

The edges that fire when the happy path does not hold.

### 7.1 Retry (fixable failure)
A `task-verifier` (or `integration-checker`) `FAIL:fixable` dispatches a scoped **fix-agent**,
then re-verifies. Cap: **2 retries**. Rationale: 1-2 cycles catch import/assertion/off-by-one
bugs; 3+ means a design problem, not a code bug.

### 7.2 Escalate (unfixable or exhausted)
`FAIL:escalate`, or retries hitting the cap, **stops the loop and hands to the human** with the
full context (task, every verifier report, every fix attempt). Escalate verdicts are never
auto-retried; they need judgment by definition.

### 7.3 Ambiguous spec
Spec detection is branch-aware. When more than one non-`SHIPPED`/`PARKED` spec is active and the
branch slug does not disambiguate, the detectors emit `spec:ambiguous(...)` and **ask** rather
than silently pick. Resolve by branch or by naming the spec.

### 7.4 No activator installed
`/user:assign` detects the goal-loop activator (`/goal` -> `ralph-loop` -> `goal-craft`). If none
is installed it **degrades gracefully**: the draft is left as a plain reusable file you paste
wherever. Only one-step activation is lost; the draft still works.

### 7.5 Idempotent re-run
Re-running `/user:assign` for an ID that already has a `.claude/goals/<slug>.md` **re-surfaces the
existing draft** instead of duplicating it or double-advancing status. The filesystem is the
source of truth.

### 7.6 DO-NOT-SHIP gate
`/user:ship` reads `REVIEW.md` first. `DO NOT SHIP` -> **stop**, fix first. `FIX THEN SHIP` ->
apply fixes, then ship. No `REVIEW.md` -> **warn and ask** (run `/review`, run `/review-team`,
or ship anyway); never silently skipped.

### 7.7 Completeness warn + log (not a block)
Two self-checks run during Build/Reflect and **warn + log** to
`~/.claude/dwarves-kit/logs/completeness.log` without blocking: **decision-translation** (each
Build-decision is referenced by a task/AC) and **doc-update** (a change touching X moves its
companion docs per the WORKFLOW doc-impact map). `/user:ship` and `/user:retro` review that log
at the gate. Hard blocks stay reserved for the safety subset.

---

## 8. The four hard stops (the only blockers)

Everything above suggests or warns. These four refuse to proceed, because the cost of the
mistake is irreversible:

| Hard stop | Fires on | Mechanism |
|---|---|---|
| safety-gate | destructive Bash (`rm -rf`, `DROP TABLE`, `git reset --hard`, `kubectl delete`; build-artifact allowlist exempt) | PreToolUse hook, exit 2 |
| push-to-main blocker | a push to `main`/`master`/protected | PreToolUse hook, exit 2 |
| anti-rationalization | premature "done" claim; phantom-impl stub in the diff; guess-fix while `## Root cause` empty | Stop hook |
| verification pipeline | a task whose acceptance criteria are unmet or whose tests did not actually run | `/execute` gate (worker -> verifier -> fix -> escalate) |

---

## 9. Quick reference

### 9.1 Trigger -> flow -> stop -> enforcer

| Trigger | Starts | Stop condition | Enforcer |
|---|---|---|---|
| `/user:start` | render queue + drafts | output rendered | none (detector) |
| `/user:assign <ID-NNN or freeform>` | goal draft + lane routing (freeform: delegate crystallize to `/user:think`, then allocate ID + BACKLOG row) | draft written, status flipped, handed off | none (mutator; idempotent; freeform gated by approve-before-allocate) |
| `/user:think` | decision brief | brief written (if BUILD) | advisory |
| `/user:spec` | spec scaffold | spec exists, `Status: DRAFT` | spec-drift-guard hook |
| `/user:spec-validate` | 5-lens adversarial review | `Status: VALIDATED` | advisory (full lane) |
| `/user:execute` | verification pipeline | all tasks + integration PASS | verification pipeline (hard) |
| `/user:debug` | 4-phase debug loop | root cause + fix verified + human-confirmed | iron law + guess-fix guard |
| `/user:review[-team]` | review | verdict recorded in `REVIEW.md` | advisory |
| `/user:docs` | doc sync + doc-verifier | docs match code | advisory |
| `/user:ship` | ship pipeline | tagged/PR; spec `SHIPPED`; ID off queue | ship gate + push-to-main blocker (hard) |
| `/user:retro` | retrospective | `docs/retro/RETRO-<date>-<slug>.md` written | advisory |
| a `/goal` activator | goal loop | `## Verification` passes + done-definition | anti-rationalization (hard) |

### 9.2 Stop-condition index (where each loop terminates)

- **Goal loop**: `## Verification` command(s) pass and the done-definition holds; or a blocker
  note is written to `## Open questions` and it stops.
- **Debug loop**: `## Root cause` recorded, fix verified, human-confirmed; or the 3-fix
  architecture wall halts it for a design rethink.
- **Execute pipeline**: every task PASS and integration-checker PASS; or `FAIL:escalate` /
  2 exhausted retries -> human.
- **ui-design loop**: a SOLID or RECONSIDER verdict, or the max-2 revise cap.
- **Lanes**: `tiny` when the edit verifies; `normal`/`full` when shipped (ID off queue);
  `bug` at human-confirm; `backfill` when the docs are written with no app-behavior change.

---

## See also
- `WORKFLOW.md` - the rules contract this manual visualizes (the cycle table, the lane table, the doc-impact map).
- `MANUAL.md` - per-command operator detail (reads/writes/gotchas for each `/user:*`).
- `docs/architecture.md` - component fit and the state model.
- `docs/PHILOSOPHY.md` - why these boundaries exist (the bounded/unbounded loop note, the hard-stop reservation).
- `AGENTS.md` - the tool-agnostic operate-contract the goal loop projects from.
