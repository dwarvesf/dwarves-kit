# Workflow map (one-page ASCII edition)

> Every flow the kit sets up, drawn in one file. This is a RENDERING, not a
> second contract: the rules, the exact tables, and the canonical diagrams
> live in [`WORKFLOW.md`](WORKFLOW.md) ("Flow and loop reference"); when the
> two disagree, WORKFLOW.md wins.

## Contents

| # | Diagram | What it shows |
|---|---------|---------------|
| 0 | Inventory | the flow census: 1 backbone, 5 lanes, 3 loops (+1 micro-loop), 11 side-flows, 7 alternate flows, 4 hard stops |
| 1 | The spine (backbone) | session start -> /kit:start -> /kit:assign -> the normal/full command chain -> ship -> retro |
| 2 | State stores | BACKLOG.md -> SPEC-NNN file <-> .claude/goals/ drafts; nothing re-entered between phases |
| 3 | Pick a lane | the intake decision tree: bug / backfill / tiny / normal / full |
| 4 | The cycle | the phase list Think..Reflect with each phase's enforcer (advisory vs hard) + Debug off-cycle |
| 5 | The 12 type loops | one right-sized cycle per non-code work type, entry -> phases -> exit |
| 6 | The V-model | left arm builds + statically reviews, right arm dynamically tests; test-plan crossbar at the vertex |
| 7 | Goal loop | bounded engine: increment -> verify -> done/blocker stops; anti-rationalization backstop |
| 8 | Debug loop | bounded engine: Phase 0..4 under the iron law (no fix without recorded root cause) |
| 9 | Execute pipeline | bounded engine: worker -> task-verifier -> fix-agent (max 2) -> integration-verifier |
| 10 | Mid-flight amend | the add-only spec amend excursion off the execute pipeline |
| 11 | 11 opt-in side-flows | trigger -> writes-to -> stop for each advisory flow |
| 12 | 7 alternate flows | the edges that fire when the happy path does not hold |
| 13 | 4 hard stops | the only blockers; everything else advises or warns |

## 0 · Inventory

```
+--------------------------------------------------------------------------+
|  1 backbone (the spine)          5 primary intake lanes                  |
|  3 bounded loops (engines)       +1 mid-flight amend micro-loop          |
|  11 opt-in side-flows            7 alternate / branch flows              |
|  4 hard stops (the ONLY blockers)                                        |
|                                                                          |
|  everything except the 4 hard stops suggests and routes; it never blocks |
+--------------------------------------------------------------------------+
```

## 1 · The spine (backbone)

```
  session start
       |
       v
  /kit:start ........ render the BACKLOG Active queue + goal drafts (read-only)
       |
       v
  /kit:assign ....... goal draft + scope fence + lane pick (the ONLY mutator)
       |
       v            lane runs, normal/full chain:
  /kit:spec ......... spec exists, Status: DRAFT
       |
       v
  /kit:spec-validate  Status: VALIDATED
       |
       v
  /kit:execute ...... verification pipeline (worker -> task-verifier -> fix-agent, max 2)
       |
       v
  /kit:review ....... review verdict recorded
       |
       v
  /kit:docs ......... README/CHANGELOG match code
       |
       v
  /kit:ship ......... tagged + PR; ship gate blocks on DO NOT SHIP
       |
       v
  /kit:retro ........ docs/retro/v<version>.md written
       |
       v
  on ship: ID-NNN drops off the BACKLOG queue
           (CHANGELOG is the canonical shipped record)
```

## 2 · State stores

```
  _meta/BACKLOG.md            docs/specs/SPEC-NNN-<slug>.md      .claude/goals/<slug>.md
  +-----------------+         +--------------------------+      +----------------------+
  | the Active queue|         | the contract             |      | ephemeral goal drafts|
  | ID-NNN rows     | ------> | Status: DRAFT            | <--> | (gitignored,         |
  | status:         |  assign |        -> VALIDATED      |      |  per-machine)        |
  | queued/speccing/|         |        -> SHIPPED        |      | one draft per ID     |
  | validated/      |         | tasks, AC, Verification  |      +----------------------+
  | executing/      |         +--------------------------+        the built-in /goal owns
  | shipped (parked)|                                             .claude/last-goal.md;
  +-----------------+                                             the kit NEVER writes it
```

## 3 · Pick a lane

```
                 is it a defect / regression / failing test ?
                             | yes            | no
                             v                v
                           bug          new work on an existing repo
                                        with no operate-layer docs ?
                                             | yes        | no
                                             v            v
                                          backfill    how big / how risky ?
                                                      |- trivial edit ....... tiny
                                                      |- one bounded change . normal
                                                      +- risk-list match .... full

  when in doubt between two lanes, take the heavier one
```

## 4 · The cycle

```
  Think -> Design -> Design critique -> Spec -> Validate -> Test plan
  (adv)   (opt-in)     (opt-in)       [HARD:    (full)     (default
                                       spec-drift          normal/full)
                                       guard]
     -> Build -> Review -> Docs -> Ship -> Reflect
       [HARD:    (adv)     (adv)  [HARD:    (adv)
        verification              ship gate +
        pipeline]                 push-to-main]

  off-cycle entry:  Debug (/kit:debug) .. [HARD: iron law + guess-fix guard]

  legend: [HARD] = enforced blocker; everything else advisory
```

## 5 · The 12 type loops

Phase 0 is universal: `/kit:grill`, then the done scenario, before any loop runs.

```
  research  : frame question -> multi-modal sweep -> adversarial verify -> cited report
  review    : scope artifact -> pick lens count -> read-only reviewers -> verdict -> record
  eval      : frame + metrics -> hand-verify seed -> test ladder -> TEST-REPORT -> verdict
  doc       : diff sweep OR content brief -> update/rewrite -> doc-verifier confirms
  migration : inventory -> dry-run on copy -> staged apply -> verify -> rollback proven
  data-tool : spec surface -> build -> recorded live run + negative control -> Done gate
  incident  : alert -> triage -> root cause BEFORE fix -> fix -> INC-NNN -> monitoring
  reconcile : inventory estate -> classify drift -> migrate/fix -> reference-fix -> gate
  operate   : trigger -> pre-checks -> run procedure -> record run -> alert on deviation
  planning  : gather state -> prioritize -> enqueue/re-rank board -> digest
  learning  : ingest -> explain/companion -> practice -> self-check >= track bar
  spec-feature : (code) pick a lane in "Pick a lane" above
```

## 6 · The V-model

```
   LEFT · BUILD (produce + review)                 RIGHT · TEST (execute the mirror)

   Brief / Requirement ........................... Acceptance test
   build /kit:think · review brief-reviewer        acceptance-verifier · /kit:verify
    Solution design .............................. System test
    build /kit:design · review /kit:devs-team      system-verifier · /kit:verify
     Spec ....................................... Integration test
     build /kit:spec · review /kit:spec-validate   integration-verifier
      Code ..................................... Unit / task test
      build /kit:execute · review /kit:review      task-verifier (fix-agent repairs)
       \                                        /
        +--- test design: /kit:test-plan writes the tests ---+
                 (vertex: BUILD = code + test code)

   any right-arm PASS -> recheck-verifier (fresh-context re-audit)
   whole assembled work -> advisor (kit-default extra lens)
```

## 7 · Goal loop

```
   activator starts the objective
            |
            v
   +---> do the next increment ---> run ## Verification
   |            ^                        |
   |            |                  pass? |
   |            |              +---------+---------+
   |            |           no |                   | yes
   |            |              v                   v
   |            |     anti-rationalization     ALL done? --no--+
   |            |     blocks "done";           | yes           |
   |            +-----  keep working <---------+               |
   |                                                           |
   |   hit a blocker you can't resolve?                        v
   +-- write a note to spec ## Open questions ----------->   STOP
```

## 8 · Debug loop

```
   /kit:debug -> Phase 0 -> Phase 1 -> Phase 2
                 Feedback    Root       Pattern
                 loop        cause         |
                                           v  (wrap)
                 Phase 3 -> Phase 4 -> verified? -> human-confirm -> DONE
                 Hypothesis  Implement    |  ^
                     ^                 no |  | (re-verify)
                     +--------------------+  |
                                             |
   guard: a fix/done claim is BLOCKED while ## Root cause is empty
   3 failed fixes in a row -> STOP: architecture wall (rethink design)
```

## 9 · Execute verification pipeline

```
   /kit:execute  (record pre-build base ref)
        |
        v
   +-- for each task ------------------------------------------------+
   |   worker subagent (fresh context) --> task-verifier (read-only) |
   |                +-------------------+-------------------+        |
   |             PASS             FAIL:fixable        FAIL:escalate  |
   |                |                  |                    |        |
   |                |                  v                    |        |
   |                |           fix-agent (scoped)          |        |
   |                |           re-verify; retry < 2 --+    |        |
   |                |           retries == 2 ----------+--> |        |
   |                v                                  |    v        |
   |          mark task done <-------------------------+  ESCALATE   |
   +---------+-------------------------------------------------------+
             | all tasks PASS
             v
   phase checkpoint (human: continue / review / stop)
             |
             v
   integration-verifier (read-only, diffs whole build from base ref)
        +----+---------------+
      PASS  FAIL:fixable  FAIL:escalate
        |     | (fix-agent)    |
        v     v                v
     build complete <-- re-check   ESCALATE
```

## 10 · Mid-flight amend micro-loop

```
   BUILDING (mid /kit:execute, spec is VALIDATED)
        |  trigger: "also do Y"
        v
   reach a task checkpoint
   (in-flight task verified + committed; - [x] rows frozen)
        |
        v
   SPECIFYING (amend, not restart)
     - append new - [ ] TASK rows only (add-only)
     - record an ## Amendments entry
     - re-validate the DELTA only; Status STAYS VALIDATED
        |
        v
   /kit:next --> BUILDING (resume; runs only the amended tasks)
```

## 11 · The 11 opt-in side-flows

Advisory, never blocking. Output binds to the active spec (replace-not-stack).

```
  flow                     trigger                        writes to                 stop
  -----------------------  -----------------------------  ------------------------  -------------------
  /kit:design              between /think and /spec       DECISION-BRIEF.md         solution agreed
  /kit:devs-team           before the spec hardens        ## Design critique        verdict recorded
  /kit:visual-team         a visual/UI design exists      ## Visual critique        verdict recorded
  /kit:ui-design           downstream UI, after /design   ## UI design              SOLID / max-2 revise
  /kit:test-plan           before /execute                ## Test plan              matrix written
  /kit:test-plan-review-team  after /test-plan, 6 lenses  ## Test plan critique     SOLID / REVISE / RECONSIDER
  /kit:test-write          after a SOLID test-plan critique ## test files            rows covered, tests execute
  /kit:review-team         PR-grade review, 3 lenses      ## Review                 SHIP / FIX / DO NOT
  /kit:absorb              maintainer absorption audit    docs/absorption/ report   proposal-only
  /kit:kit-health          self-assessment vs PHILOSOPHY  report (stdout)           assessment rendered
  /kit:gauntlet            before outside-dev access, or  docs/verification/        SOLID / REVISE /
                           after contributor-surface edits  gauntlet/<run>/ records   RECONSIDER
```

## 12 · The 7 alternate / branch flows

```
  happy path breaks here
        |
        |--> retry ............ FAIL:fixable -> scoped fix-agent -> re-verify; cap 2
        |--> escalate ......... FAIL:escalate or cap hit -> stop, hand to human
        |--> ambiguous spec ... 2+ active specs, slug ambiguous -> ask, never guess
        |--> no activator ..... /goal, ralph-loop, goal-craft all absent -> draft
        |                       stays a plain reusable file
        |--> idempotent re-run  /kit:assign on an existing draft -> re-surface it,
        |                       never duplicate or double-advance
        |--> DO-NOT-SHIP gate . /kit:ship reads ## Review first: DO NOT SHIP =
        |                       stop; FIX THEN SHIP = fix, then ship
        +--> completeness ..... decision-translation + doc-update self-checks
                                warn + log only; reviewed at /kit:ship + /kit:retro
```

## 13 · The 4 hard stops

The ONLY blockers; everything else advises or warns.

```
  +---------------------+  +---------------------+  +----------------------+  +---------------------+
  | safety-gate         |  | push-to-main        |  | anti-rationalization |  | verification        |
  |                     |  | blocker             |  |                      |  | pipeline            |
  | destructive Bash    |  | push to main/master |  | premature "done";    |  | unmet acceptance    |
  | (rm -rf, DROP       |  | /protected          |  | phantom-impl stub;   |  | criteria; tests     |
  | TABLE, git reset    |  |                     |  | guess-fix while      |  | that did not run    |
  | --hard, kubectl     |  | PreToolUse hook,    |  | ## Root cause empty  |  |                     |
  | delete)             |  | exit 2              |  |                      |  | /execute gate       |
  | PreToolUse, exit 2  |  |                     |  | Stop hook            |  | (worker->verifier)  |
  +---------------------+  +---------------------+  +----------------------+  +---------------------+
```
