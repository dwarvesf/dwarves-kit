# PLAYBOOK.md: operator scenarios (what you say -> what happens)

> How to drive the kit from natural language. Scenario -> trigger phrase ->
> response -> orchestration hook. This is the interaction view. For the flow/loop
> internals read `docs/ORCHESTRATION.md`; for per-command detail read `MANUAL.md`;
> for the rules contract read `WORKFLOW.md`.
>
> Worked examples use the maintainer's own phrasings; the behavior is operator-generic.

## The one thing to understand first: three layers, only one is automatic

Your sentence does not mechanically trigger a flow. There are three layers and only
the first fires on its own:

| Layer | Fires how | Examples |
|---|---|---|
| **Hooks** | **Automatic**, on Claude Code events | `context-readiness` (SessionStart suggestion), `safety-gate`, `anti-rationalization`, `spec-drift-guard`, `push-to-main` |
| **`/kit:*` commands** | **Invoked** - you type `/kit:x`, OR Claude reads your intent and runs it | `/kit:start`, `/kit:assign`, `/kit:spec`, `/kit:execute`, `/kit:ship` |
| **Skills** | **Invoked** - Claude recognizes the situation and loads the skill | `goal-craft`, `superpowers:brainstorming`, `content-spec` |

So when you say "apply SDD," no hook fires on the word "SDD." What happens is **Claude
interprets** the phrase and **invokes** the right command/skill. The kit's hooks then act
as guardrails around whatever runs. Keep this split in mind for every scenario below.

A second load-bearing fact: the kit's orchestration is **BACKLOG-ID-first**. `/kit:assign`
takes an `ID-NNN` **or** freeform intent ("apply SDD to this feature", a vague brief). When you
hand it freeform, `/kit:assign` runs the freeform front door natively (Section 8): it delegates
the interview to `/kit:think`, waits for your approval, then allocates the ID + BACKLOG row
before routing into the lane. The ID stays canonical; it is just minted on the fly. This shipped
in SPEC-026 / ID-022 (Section 11).

---

## Scenario 1: session start, "what's next / what's left"

**Context.** Fresh session, you want orientation before doing anything.

**What you say.** "what's next", "what's left to do", "where were we", or `/kit:start`
(`--brief` for one line, `--full` for the task checklist + recent commits).

**Automatic vs interpreted.**
- *Automatic*: the `context-readiness` hook already injected a one-line `next:` suggestion into
  Claude's context when the session started. You may see Claude reference it unprompted.
- *Interpreted*: Claude reads "what's next" and runs the `/kit:start` behavior (a **detector**):
  render the `_meta/BACKLOG.md` Active queue and the active `.claude/goals/` drafts. Read-only.

**Resulting flow.** Detector only, no mutation:
```text
  "what's next" -> /kit:start -> renders:
     - BACKLOG Active queue (open ID-NNN + status: queued/speccing/validated/executing)
     - active goal drafts in .claude/goals/
     - the suggested next command
```

**Decision / approval points.** None (nothing is changed). You then choose the next move:
`/kit:assign ID-NNN` to start an item, or `/kit:next` to pick up the next undone task of the
already-active spec.

**How to continue.** Say `assign ID-007` (start that item) or `next` (continue the active spec).
If the queue is empty or you have a new idea, jump to Scenario 2 or 5.

---

## Scenario 2: mid-brainstorm, "apply SDD framework on this feature X"

**Context.** You are brainstorming a feature. There is **no BACKLOG ID** for it yet.

**What you say.** "apply SDD to feature X", "let's spec this", "run the spec-driven flow on X".

**Automatic vs interpreted.**
- *Not a keyword trigger.* No hook watches for "SDD". Nothing auto-fires.
- *Interpreted*: Claude maps "SDD" to **the spec-driven lane** (normal or full) and proposes it.
  "SDD" is a keyword **for Claude to interpret**, not a mechanical trigger.

**Resulting flow.** Because there is no ID, Claude invokes `/kit:assign` with the freeform
intent. `/kit:assign` runs the **native freeform front door** (Section 8): it delegates the
interview to `/kit:think`, then allocates the ID + BACKLOG row, then routes into the lane. By
default Claude does **not** auto-run the whole flow; it sets up and starts the first step,
checking the lane + scope with you:
```text
  "apply SDD to X"
     -> Claude picks the lane (normal vs full) and confirms scope with you
     -> /kit:assign "apply SDD to X"   (freeform front door, Section 8):
          delegate crystallize to /kit:think -> [you approve] -> allocate ID + BACKLOG row
     -> /kit:spec  (-> /kit:spec-validate on full)
     -> /kit:execute (verification pipeline)
     -> /kit:review[-team] -> /kit:docs -> /kit:ship -> /kit:retro
```

**Decision / approval points.** Lane + scope confirmation before the spec; the approve-before-allocate
gate inside the freeform front door; spec approval; the spec-validate verdict (full lane); execute
phase checkpoints. Claude stops at each unless you pre-authorize autonomy (Scenario 3).

**Honest caveat.** "Apply SDD" does not auto-launch the full orchestration off a keyword. Claude
still **interprets** the phrase and **invokes** `/kit:assign` with it; the front door is a real
invoked command (SPEC-026, Section 11), not an auto-firing keyword. From there the hooks act as
guardrails.

---

## Scenario 3: "run the full flow, do not interrupt, your call"

**Context.** You trust the call and want autonomy end to end.

**What you say (pick the autonomy level explicitly).**
- "run the full lane autonomously; only stop at hard stops" -> autonomous up to the outward-facing step.
- "run it all the way to a PR, your call" -> fully autonomous to merge-ready (push + PR included).
- Or set a goal loop: `/goal <objective>` then "run it" (the bounded in-session loop).

**Automatic vs interpreted.**
- *Interpreted*: Claude drives the lane end to end without pausing at the **advisory** checkpoints.
- *Automatic*: in a `/goal` loop the **anti-rationalization Stop hook** keeps the session working
  until the stop condition holds; the **4 hard stops** still gate every step.

**Resulting flow.**
```text
  /spec -> /spec-validate -> /execute (auto worker->verifier->fix<=2->integration; escalate on fail)
        -> /review[-team] -> /docs -> /ship
  (advisory phase checkpoints are skipped; the loop runs continuously)
```

**Where it STILL stops (always, even autonomous).**
- The 4 hard stops: `safety-gate` (destructive Bash), `push-to-main` blocker,
  `anti-rationalization` (premature/false "done"), the verification pipeline (a task that fails).
- Outward-facing irreversible steps: the push and the PR. Claude confirms these **unless** you
  said "all the way to a PR." That is the one place "your call" still asks once, by policy.

**Decision / approval points.** Only the above. Everything advisory is auto-advanced.

**The exact phrase to grant maximum autonomy:** *"Run the full lane autonomously, including the
push and PR; only stop at the safety hard-stops or a real blocker."*

---

## Scenario 4: an iteration-heavy phase (discuss solution, revisit design)

**Context.** You want to iterate on one phase (usually solution design) before committing to a spec.
This is the **opposite** of Scenario 3: maximal checkpoints, no autonomy.

**What you say.** "let's discuss the solution", "iterate on the design", "get back on the design
for X", "explore approaches for X", or `/kit:design`.

**Automatic vs interpreted.**
- *Interpreted*: Claude invokes `/kit:design` (the opt-in interactive solution-design beat) and/or
  `/kit:devs-team` (5-lens engineering critique). For open-ended exploration, `superpowers:brainstorming`.

**Resulting flow (a human-in-the-loop loop).**
```text
  /kit:think (optional, if the idea needs challenging: 6 forcing questions)
     -> /kit:design  ── proposes 2-3 approaches, ONE question at a time,
     │                   holds for your approval PER SECTION, appends the
     │                   agreed Solution to docs/specs/DECISION-BRIEF.md
     │   <iterate: you redirect, it revises, re-presents> ◀──┐
     └───────────────────────────────────────────────────────┘
     -> (optional) /kit:devs-team  ── critique appended to the spec/brief
     -> /kit:spec  ── folds the DECISION-BRIEF Solution into the spec
```

**Stop condition.** The loop continues until **you approve** the solution section by section.
It never auto-advances; every section pauses for you. `/kit:design` is explicitly the
"ran without my feedback" antidote.

**Decision / approval points.** Per section in `/design`; the critique verdict (SOLID / REVISE /
RECONSIDER); spec approval. To leave the loop: "the design is good, write the spec."

---

## Scenario 5: a vague / ambiguous goal

**Context.** You have a fuzzy idea, not yet crystallized into something buildable.

**What you say.** "I have a rough idea about X", "help me figure out what to build for X",
"here's a vague brief: ...", or `/goal <fuzzy intent>` (then `goal-craft` sharpens it).

**Automatic vs interpreted.**
- *Interpreted*: Claude **interviews / grills** you. There is **no "goal-griller" skill**; the
  grilling is `/kit:think` (6 forcing questions) and/or `superpowers:brainstorming` (intent +
  requirements exploration). The `goal-craft` skill **sharpens** a fuzzy intent into an
  outcome-shaped `/goal` (verification, scope fence, termination-on-blocker).

**Resulting flow.**
```text
  vague brief
     -> /kit:assign "<vague brief>"   (native freeform front door, Section 8):
          delegate crystallize to /kit:think and/or superpowers:brainstorming
          (challenge the idea, surface requirements, name the real outcome)
     -> crystallize into a clear objective
     -> [YOU APPROVE the crystallized objective]   (approve-before-allocate gate)
     -> allocate ID + BACKLOG row -> route into the lane (Scenario 2's flow)
```

**Will Claude auto-hook it into the SDD orchestration after you approve?** Yes, **on your "go"** -
`/kit:assign`'s freeform path allocates the ID + BACKLOG row and starts the lane's first command.
This is the kit's native front door now, not Claude bridging by hand; the front door is still an
**invoked command** (you, or Claude on your behalf, invoke `/kit:assign`), not an auto-firing
keyword. Claude will ask **how autonomous** to be from there (ties to Scenario 3).

**Decision / approval points.** Claude will **not** write the spec or start the lane until you
approve the crystallized objective. That approval gate is deliberate: a vague brief turned
straight into a spec is how scope drift starts.

---

## Scenario 7: mid-build, "also do Y" (a mid-flight scope change)

**Context.** You are mid-`/kit:execute` on a `VALIDATED` spec (state BUILDING). Partway through,
the work reveals scope that must be added now. You do **not** want to restart the lane or throw
away the tasks already done.

**What you say.** "also do Y", "while you're in here, add Z", "amend the spec to cover Y".

**Automatic vs interpreted.**
- *Not a keyword trigger.* No hook watches for "also do". Nothing auto-fires.
- *Interpreted*: Claude recognizes this as a **mid-flight amend** and runs the declared
  amend micro-loop (BUILDING -> SPECIFYING -> BUILDING) instead of silently editing the spec or
  starting over. The full rule (when you may amend, the checkpoint guard, the recorded entry,
  how to resume) is canonical in **`WORKFLOW.md` "## Mid-flight amend"**; this card is only the
  what-you-say -> what-happens projection of it.

**Resulting flow.** Amend in place at a checkpoint, then resume; the spec stays `VALIDATED`:
```text
  "also do Y"  (mid /kit:execute, spec is VALIDATED)
     -> reach a task checkpoint (finish + verify + commit the in-flight task first)
     -> amend the spec: append new - [ ] TASK rows + delta the After-state / AC / Verification
        (completed - [x] tasks are NOT touched), record an ## Amendments entry
     -> re-validate the DELTA only (full lane: /spec-validate on the new tasks; normal: advisory)
     -> /kit:next  resumes, picking the next undone - [ ] task (skips the done rows)
```

**Decision / approval points.** You confirm the added scope before the amend lands; the
delta-only re-validation verdict (full lane). The Status never drops to `DRAFT` (that would be a
lane restart), and an amend only **adds** scope: rewriting an already-done task's contract is a
heavier re-open decision, not an amend. See `WORKFLOW.md` "## Mid-flight amend" for the four
invariants in full.

**How to continue.** Say `next` to resume on the amended tasks. To add yet more scope later,
repeat: each amend appends a fresh `## Amendments` line. To leave the build instead, `ship` it.

---

## 8. The freeform -> ID front door (what `/kit:assign` does internally)

Scenarios 2 and 5 are freeform (no ID). The orchestration is ID-first, so `/kit:assign` mints the
ID for you. Hand it freeform intent instead of an `ID-NNN` and its freeform path runs:

```text
  /kit:assign "<freeform intent>"
     1. delegate crystallize -> /kit:think (the idea-griller) runs the interview and
                                returns a crystallized objective + a lane. /assign does NOT
                                embed the interview; it consumes /think's result.
     2. approve              -> pause for your approval of the crystallized objective
                                (approve-before-allocate: a vague brief never auto-creates a row)
     3. sanitize + allocate  -> sanitize the intent (escape `|`/newlines for the table cells;
                                reduce the slug to [a-z0-9-]+), re-read the current max ID and
                                write the next ID-NNN row into _meta/BACKLOG.md Active queue in
                                the same step (Title, Source: freeform intake (date), Target
                                artifact, Lane, Status: queued), with a loud equal-ID collision
                                check (atomic-allocate)
     4. rejoin the ID tail   -> write the goal draft, pick the lane, route (Scenario 2's flow),
                                exactly as for an ID-NNN argument
```

This is the **native freeform front door** (`/kit:assign` runs it; you do not bookkeep by hand).
It preserves ID-first traceability: even an ad-hoc idea gets a BACKLOG row and an ID before any
draft is written, so nothing ships untracked. It is still an **invoked command**, not an
auto-firing keyword: Claude interprets "apply SDD to X" and invokes `/kit:assign` with it; the
kit does not watch for the phrase. Shipped in SPEC-026 / ID-022 (Section 11).

---

## 9. Pre-authorization phrases (autonomy dial)

How much to say to set the autonomy level. Say one of these and Claude calibrates:

| You say | Autonomy | Claude stops at |
|---|---|---|
| "propose it, don't run anything" | none | after planning; waits for go |
| "run it, check with me at each phase" | low (default) | every advisory phase checkpoint |
| "run the lane, only stop at hard stops" | high | the 4 hard stops + the push/PR (outward-facing) |
| "run it all the way to a PR, your call" | max | only the 4 hard stops + a real blocker |

The 4 hard stops (`safety-gate`, `push-to-main`, `anti-rationalization`, the verification pipeline)
are **never** waived by any autonomy level.

---

## 10. Cheat-sheet: what you say -> what happens

| You say | Claude invokes | Fires automatically | Stops at |
|---|---|---|---|
| "what's next / what's left" | `/kit:start` (detector) | context-readiness suggestion | nothing (read-only) |
| "assign ID-007" / "start ID-007" | `/kit:assign ID-007` | (none) | hands off to the lane |
| "apply SDD to X" (no ID) | `/kit:assign "<freeform>"` (freeform front door) -> `/kit:spec` lane | spec-drift-guard once a spec exists | approve-before-allocate gate, lane + scope confirm, then per-phase |
| "discuss / iterate the design" | `/kit:design` (+ `/kit:devs-team`) | (none) | every section (human-in-loop) |
| "vague idea about X" | `/kit:think` / brainstorming | (none) | your approval of the objective |
| "run the full lane, your call" | the lane, autonomously | anti-rationalization (in a /goal loop) | hard stops + push/PR |
| "fix this bug / it regressed" | `/kit:debug` (bug lane) | guess-fix guard | root cause + human-confirm |
| "review this" / "ship it" | `/kit:review[-team]` / `/kit:ship` | ship gate, push-to-main | DO-NOT-SHIP verdict; the push/PR |

---

## 11. The freeform front door (shipped)

Scenarios 2 and 5 used to expose a real gap: freeform intent ("apply SDD to X", a vague brief) had
no auto-path, so Claude bridged it by hand every run. SPEC-024 deferred the "freeform griller entry"
to keep BACKLOG-ID-first canonical; SPEC-026 / ID-022 then closed the gap and **shipped**.

**Shipped**: `/kit:assign` (the one mutator) now accepts **freeform intent** in addition to
`ID-NNN`. The freeform path delegates crystallization to `/kit:think`, pauses for your approval,
sanitizes the input, atomically allocates the next ID, writes the BACKLOG row, then proceeds
exactly as ID-first, so "apply SDD to X" is a genuine one-shot front door without losing ID
traceability.

- Spec: `docs/specs/SPEC-026-freeform-front-door.md` (VALIDATED, shipped).
- Backlog: ID-022.
- Command: `commands/assign.md` (the resolver + freeform path).

The four invariants the front door upholds: delegate-to-`/kit:think`, approve-before-allocate,
sanitize, atomic-allocate. The native path is Section 8. It stays an invoked command, not an
auto-firing keyword.

---

## See also
- `docs/operating-layer-vision.md` - the design-first vision + the SDLC state machine this playbook projects (the formal model behind these scenarios).
- `docs/ORCHESTRATION.md` - the flow/loop view (lanes, loops, triggers, stop conditions, ASCII diagrams).
- `WORKFLOW.md` - the rules contract (the cycle, the lanes, the gates).
- `MANUAL.md` - per-command operator detail.
- `AGENTS.md` - the operate-contract the goal loop projects from.
