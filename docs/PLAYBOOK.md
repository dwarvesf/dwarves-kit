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
| **`/user:*` commands** | **Invoked** - you type `/user:x`, OR Claude reads your intent and runs it | `/user:start`, `/user:assign`, `/user:spec`, `/user:execute`, `/user:ship` |
| **Skills** | **Invoked** - Claude recognizes the situation and loads the skill | `goal-craft`, `superpowers:brainstorming`, `content-spec` |

So when you say "apply SDD," no hook fires on the word "SDD." What happens is **Claude
interprets** the phrase and **invokes** the right command/skill. The kit's hooks then act
as guardrails around whatever runs. Keep this split in mind for every scenario below.

A second load-bearing fact: the kit's orchestration is **BACKLOG-ID-first**. `/user:assign`
takes an `ID-NNN`. A freeform intent with no ID ("apply SDD to this feature", a vague brief)
has **no auto-path today**; Claude bridges it manually (Section 8). A real freeform front
door is proposed in Section 9 (SPEC-026 / ID-022).

---

## Scenario 1: session start, "what's next / what's left"

**Context.** Fresh session, you want orientation before doing anything.

**What you say.** "what's next", "what's left to do", "where were we", or `/user:start`
(`--brief` for one line, `--full` for the task checklist + recent commits).

**Automatic vs interpreted.**
- *Automatic*: the `context-readiness` hook already injected a one-line `next:` suggestion into
  Claude's context when the session started. You may see Claude reference it unprompted.
- *Interpreted*: Claude reads "what's next" and runs the `/user:start` behavior (a **detector**):
  render the `_meta/BACKLOG.md` Active queue and the active `.claude/goals/` drafts. Read-only.

**Resulting flow.** Detector only, no mutation:
```text
  "what's next" -> /user:start -> renders:
     - BACKLOG Active queue (open ID-NNN + status: queued/speccing/validated/executing)
     - active goal drafts in .claude/goals/
     - the suggested next command
```

**Decision / approval points.** None (nothing is changed). You then choose the next move:
`/user:assign ID-NNN` to start an item, or `/user:next` to pick up the next undone task of the
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

**Resulting flow (today).** Because there is no ID, Claude runs the **freeform -> ID bridge**
(Section 8), then routes into the lane. By default Claude does **not** auto-run the whole flow;
it sets up and starts the first step, checking the lane + scope with you:
```text
  "apply SDD to X"
     -> Claude picks the lane (normal vs full) and confirms scope with you
     -> bridge: crystallize (/user:think if fuzzy) -> write a BACKLOG row (new ID) -> /user:assign ID
     -> /user:spec  (-> /user:spec-validate on full)
     -> /user:execute (verification pipeline)
     -> /user:review[-team] -> /user:docs -> /user:ship -> /user:retro
```

**Decision / approval points.** Lane + scope confirmation before the spec; spec approval; the
spec-validate verdict (full lane); execute phase checkpoints. Claude stops at each unless you
pre-authorize autonomy (Scenario 3).

**Honest caveat.** "Apply SDD" does not auto-launch the full orchestration. Claude interprets it
and drives it, with the hooks as guardrails. If you want "apply SDD" to be a real one-shot front
door, that is the SPEC-026 enhancement (Section 9).

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
for X", "explore approaches for X", or `/user:design`.

**Automatic vs interpreted.**
- *Interpreted*: Claude invokes `/user:design` (the opt-in interactive solution-design beat) and/or
  `/user:devs-team` (5-lens engineering critique). For open-ended exploration, `superpowers:brainstorming`.

**Resulting flow (a human-in-the-loop loop).**
```text
  /user:think (optional, if the idea needs challenging: 6 forcing questions)
     -> /user:design  ── proposes 2-3 approaches, ONE question at a time,
     │                   holds for your approval PER SECTION, appends the
     │                   agreed Solution to docs/specs/DECISION-BRIEF.md
     │   <iterate: you redirect, it revises, re-presents> ◀──┐
     └───────────────────────────────────────────────────────┘
     -> (optional) /user:devs-team  ── critique appended to the spec/brief
     -> /user:spec  ── folds the DECISION-BRIEF Solution into the spec
```

**Stop condition.** The loop continues until **you approve** the solution section by section.
It never auto-advances; every section pauses for you. `/user:design` is explicitly the
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
  grilling is `/user:think` (6 forcing questions) and/or `superpowers:brainstorming` (intent +
  requirements exploration). The `goal-craft` skill **sharpens** a fuzzy intent into an
  outcome-shaped `/goal` (verification, scope fence, termination-on-blocker).

**Resulting flow.**
```text
  vague brief
     -> Claude interviews: /user:think  and/or  superpowers:brainstorming
        (challenge the idea, surface requirements, name the real outcome)
     -> crystallize into a clear objective
     -> [YOU APPROVE the crystallized objective]
     -> bridge: write a BACKLOG row (new ID) -> /user:assign ID -> lane (Scenario 2's flow)
```

**Will Claude auto-hook it into the SDD orchestration after you approve?** Yes, **on your "go"** -
Claude chains it: write the BACKLOG row, `/user:assign` the new ID, and start the lane's first
command. But understand this is **Claude chaining the steps**, not the kit auto-wiring a freeform
brief. And Claude will ask **how autonomous** to be from there (ties to Scenario 3).

**Decision / approval points.** Claude will **not** write the spec or start the lane until you
approve the crystallized objective. That approval gate is deliberate: a vague brief turned
straight into a spec is how scope drift starts.

---

## 8. The freeform -> ID bridge (the step the kit does not auto-do)

Scenarios 2 and 5 are freeform (no ID). The orchestration is ID-first, so Claude bridges:

```text
  freeform intent
     1. crystallize   -> /user:think or brainstorming until the outcome is clear
     2. allocate      -> pick the next ID-NNN, write a row into _meta/BACKLOG.md Active queue
                         (Title, Source, Target artifact, Lane, Status: queued)
     3. assign        -> /user:assign ID-NNN  (writes the goal draft, flips status, routes)
     4. run the lane  -> Scenario 2's flow
```

This bridge is **manual today** (Claude runs it). It preserves ID-first traceability: even an
ad-hoc idea gets a backlog row and an ID, so nothing ships untracked. The cost is the bookkeeping
detour every time. Section 9 proposes removing it.

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
| "what's next / what's left" | `/user:start` (detector) | context-readiness suggestion | nothing (read-only) |
| "assign ID-007" / "start ID-007" | `/user:assign ID-007` | (none) | hands off to the lane |
| "apply SDD to X" (no ID) | bridge -> `/user:spec` lane | spec-drift-guard once a spec exists | lane + scope confirm, then per-phase |
| "discuss / iterate the design" | `/user:design` (+ `/user:devs-team`) | (none) | every section (human-in-loop) |
| "vague idea about X" | `/user:think` / brainstorming | (none) | your approval of the objective |
| "run the full lane, your call" | the lane, autonomously | anti-rationalization (in a /goal loop) | hard stops + push/PR |
| "fix this bug / it regressed" | `/user:debug` (bug lane) | guess-fix guard | root cause + human-confirm |
| "review this" / "ship it" | `/user:review[-team]` / `/user:ship` | ship gate, push-to-main | DO-NOT-SHIP verdict; the push/PR |

---

## 11. Proposed enhancement: a real freeform front door

Scenarios 2 and 5 expose a real gap: freeform intent ("apply SDD to X", a vague brief) has no
auto-path; Claude bridges it by hand every time (Section 8). SPEC-024 deliberately deferred the
"freeform griller entry" to keep BACKLOG-ID-first canonical.

**Proposed**: extend `/user:assign` (the one mutator) to accept **freeform intent** in addition
to `ID-NNN`. The freeform path runs the crystallize step, auto-allocates the next ID, writes the
BACKLOG row, then proceeds exactly as ID-first, so "apply SDD to X" becomes a genuine one-shot
front door without losing ID traceability.

- Spec: `docs/specs/SPEC-026-freeform-front-door.md` (DRAFT).
- Backlog: ID-022.

Until that ships, the bridge in Section 8 is the supported path.

---

## See also
- `docs/operating-layer-vision.md` - the design-first vision + the SDLC state machine this playbook projects (the formal model behind these scenarios).
- `docs/ORCHESTRATION.md` - the flow/loop view (lanes, loops, triggers, stop conditions, ASCII diagrams).
- `WORKFLOW.md` - the rules contract (the cycle, the lanes, the gates).
- `MANUAL.md` - per-command operator detail.
- `AGENTS.md` - the operate-contract the goal loop projects from.
