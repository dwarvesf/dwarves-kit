---
title: Workflow paths (the complete path map)
date: 2026-07-31
status: GENERATED projection
sources: docs/research/2026-07-31-feature-trigger-map.md, docs/workflow-map.md, docs/WORKFLOW.md, hooks/hooks.json, settings.json
---

# Workflow paths: every path through the kit

GENERATED projection. This file enumerates every entry point and where each path leads. It is a rendering, not a second contract: when it disagrees with [`WORKFLOW.md`](WORKFLOW.md), WORKFLOW.md wins. Regenerate per the last section.

## 1 · Legend

| Class | Mark | Meaning | Examples |
|---|---|---|---|
| human-typed | `[H]` | the operator types the command; nothing else can start it | `/kit:wayfind` (human ONLY), `/kit:start` |
| intent-read | `[I]` | Claude infers the intent from context and invokes it | `/kit:execute` after a VALIDATED spec; skill auto-fire |
| event-fired | `[E]` | a harness event fires it; no one invokes it | every hook (PreToolUse, Stop, SessionEnd, ...) |
| dispatched | `[D]` | a command dispatches it as a subagent | every agent (`task-verifier`, `advisor`, ...) |

Enforcement marks: `HARD` = blocking (exit 2 or pipeline gate); `adv` = advisory (warns, logs, never blocks); `conv` = convenience (never blocks, no verdict). The four hard stops are safety-gate, the push-to-main blocker (inside safety-gate + ship-gate), anti-rationalization, and the execute verification pipeline; everything else advises.

Stage grouping (Shape / Build / Watch / Check / Learn) follows the README's five stages. Stages are metadata: a feature sits where its work happens, and Check gates every boundary rather than owning a segment.

## 2 · Flow topology (the one big picture)

Every workflow, lane, loop, side-flow, and alternate path in one connected picture: the spine, the 5 intake lanes, the 3 bounded engines plus the amend micro-loop, the side-flows at their real attach points, the type-loop intake rail, the 7 alternate flows as `alt:` branch notes, and the 4 hard stops as the bottom rail. Where the picture simplifies, it names the section that carries the detail (the per-stage maps in section 4; the flow census in [`workflow-map.md`](workflow-map.md)); [`WORKFLOW.md`](WORKFLOW.md) stays canonical and wins on any disagreement.

```
 LEGEND   ->  forward flow      ==>  loop-back / re-entry      alt:  an alternate flow fires here
 [H] human-typed  [I] intent-read  [E] event-fired  [D] dispatched   (trigger classes per section 1)
 ⚡1..⚡4  a hard stop can fire at this point; the four stops are the HARD-STOP RAIL at the bottom

                 [E] session start ........ hooks inject context (Watch, section 4.4)
                          |
                          v
                 [H] /kit:start ........... read-only board render; recommends, never executes
                          |
                          v
                 [H/I] /kit:assign ........ goal draft + scope fence + lane pick (the ONLY mutator)
                          |    alt: idempotent re-run -> re-surface the draft, never duplicate
                          |    alt: no activator present -> the draft stays a plain reusable file
                          |    too foggy -> [H] /kit:wayfind: map + tickets -> spec / ROADMAP
                          v
                 type classification ---- non-code type? ---> TYPE-LOOP INTAKE RAIL
                          |                                   one right-sized loop per type, names
                          | code (spec-feature)               only (shapes: workflow-map.md sec 5):
                          v                                     research | review | eval | doc
                 pick a lane                                    migration | data-tool | incident
                 (in doubt -> heavier)                          reconcile | operate | planning
                          |                                     learning
     +---------------+----+-----------+--------------------+----------------------+
     |               |                |                    |                      |
     v               v                v                    v                      v
  tiny lane      backfill lane     bug lane           normal lane             full lane
  one obvious    brownfield:          |               one bounded             risk-list match
  edit ->        review code ->       |               change                  (auth, data model,
  run-lite       write operate-       |                    |                  migration, ...)
  review ->      layer docs ONLY      |                    +----------+-----------+
  done           (no app-code         |                               |
                 edits) -> done       v                               v
                              DEBUG LOOP (just below)        GOAL LOOP wrapper (below)

 +- DEBUG LOOP  /kit:debug (also the off-cycle entry from ANY point when a defect appears) ---+
 |                                                                                            |
 |  Phase 0 feedback loop -> 1 root cause -> 2 pattern -> 3 hypothesis -> 4 implement         |
 |                                              ^                            |                |
 |                                              +===== no == verified? ======+                |
 |                                                             | yes                          |
 |                                                             v                              |
 |                                              human-confirm -> DONE -> /kit:review          |
 |                                                             -> resume prior state          |
 |  iron law: a fix or done claim is BLOCKED while ## Root cause is empty (guess-fix guard)   |
 |  3 failed fixes in a row -> STOP: the architecture wall (rethink the design)               |
 +--------------------------------------------------------------------------------------------+ <- ⚡3

 +== GOAL LOOP (outer wrapper around the whole normal/full chain; activated at assign by an ======
 |             activator: /goal | ralph-loop | goal-craft; kit never writes .claude/last-goal.md)
 |  loop rule: do the next increment -> run ## Verification -> pass? -> all done? -> STOP
 |             not done ==> keep working; premature "done" is blocked                       <- ⚡3
 |             unresolvable blocker -> write spec ## Open questions -> STOP
 |
 |   [H/I] /kit:grill ........ typed interview, one question at a time -> phase-0 Done=
 |        |
 |        v                       side-flows attach here (opt-in, advisory):
 |   [H/I] /kit:think -------+--> [H] /kit:design ..... solution, one decision at a time -> brief
 |   -> DECISION-BRIEF.md    +--> [H] /kit:devs-team .. 5 engineering lenses, report-only
 |        |                  +--> [H] /kit:prototype .. spike branch, decision folds back
 |        v
 |   [H/I] /kit:spec ......... [D] 4 research agents (brownfield) -> SPEC-NNN DRAFT
 |        |   +--> downstream UI offshoot: [H] /kit:ui-design -> frontend-design skill ->
 |        |        [H] /kit:visual-team (5 design lenses) -> fix-agent revise (max 2) -> SOLID
 |        v
 |   [H/I] /kit:spec-validate  6 lenses (1 HARD on the design record)
 |        |     NEEDS REVISION ==> back to /kit:spec
 |        v  Status: VALIDATED
 |   [H] /kit:test-plan ...... coverage matrix -> ## Test plan (default on normal/full)
 |        |
 |        v
 |   +- REVISE LOOP  /kit:test-plan-review-team -------------------------------+
 |   |  6 test-design lenses -> findings -> revise ==> re-critique             |
 |   |  bounded: max 3 rounds; findings must strictly FALL, by severity        |
 |   |  not raw count, or halt honestly; exits early at 0 findings             |
 |   |  verdict: SOLID / REVISE / RECONSIDER                                   |
 |   +-------------------------------------------------------------------------+
 |        | SOLID
 |        v
 |   [H] /kit:test-write ..... [D] test-writer, one test per matrix row
 |        |                    (the V-model vertex: BUILD = code + test code;
 |        |                     the full V shape: workflow-map.md section 6)
 |        v
 |   [H/I] /kit:execute  (or [H] /kit:next: human-paced, same pipeline)
 |        |     alt: 2+ active specs and the slug is ambiguous -> ASK, never guess
 |        v
 |   +- EXECUTE PIPELINE  (the HARD verification pipeline) ----------------------------+
 |   |                                                                                 |
 |   |  per task: [D] worker (data-etl | db-migration | generic | meta-agent synth)    |
 |   |       |                                                                         |
 |   |       v                                                                         |
 |   |  [D] task-verifier --PASS--> task done ([D] recheck-verifier may re-audit)      |
 |   |       |                                                                         |
 |   |       +- FAIL:fixable ==> [D] fix-agent -> re-verify       alt: retry (cap 2)   |
 |   |       |       retries == 2 -------------------+                                 |
 |   |       +- FAIL:escalate ---------------------->+--> ESCALATE  alt: escalate      |
 |   |                                                    to human                     |
 |   |  +- AMEND MICRO-LOOP  (mid-flight "also do Y") ------------------+              |
 |   |  |  reach a task checkpoint -> append new - [ ] TASK rows ONLY   |              |
 |   |  |  (add-only) -> ## Amendments entry -> re-validate the DELTA   |              |
 |   |  |  (Status STAYS VALIDATED) -> /kit:next resumes amended tasks  |              |
 |   |  +---------------------------------------------------------------+              |
 |   |                                                                                 |
 |   |  all tasks PASS -> phase checkpoint (human: continue / review / stop)           |
 |   |       -> [D] integration-verifier (multi-task, whole-build diff)                |
 |   |            FAIL:fixable ==> fix-agent -> re-check                               |
 |   |            FAIL:escalate -> ESCALATE                                            |
 |   +---------------------------------------------------------------------------------+ <- ⚡4
 |        | build complete
 |        v
 |   [H/I] /kit:review (single-pass)  or  [H/I] /kit:review-team
 |        |    ([D] reviewer roster + [D] advisor, in parallel) -> ## Review verdict
 |        v
 |   [H/I] /kit:docs ......... [D] doc-verifier -> docs match code
 |        |
 |        v
 |   [H/I] /kit:ship ......... reads ## Review FIRST: alt: DO NOT SHIP = STOP;
 |        |                    FIX THEN SHIP = fix, then ship
 |        |                    version + changelog + commit + PR                <- ⚡1 ⚡2
 |        |                    alt: completeness warn+log reviewed here (and at retro)
 |        v
 |   [H/I] /kit:retro ........ docs/retro/v<version>.md ==> feeds the next /kit:think
 |
 +== on ship: ID-NNN drops off the board; CHANGELOG is the canonical shipped record ==============

  off-cycle side-flows (attach to the estate, not to one run):
    maintainer offshoot .... [H] /kit:absorb (Credits drift + seed rescan, proposal-only)
                             [H] /kit:kit-health (self-assessment vs PHILOSOPHY, report)
    estate cadence ......... [I] doc-drift (whole-estate doc audit -> fixes on a branch -> PR gate)
                             [I] feature-map (registry vs path-index cross-check -> delta re-place -> PR gate)
                             both Tier 2 ==> [D] audit-scanner (shared read-only evidence pass)

  HARD-STOP RAIL  (the ONLY four blockers; everything else advises, warns, or routes):
  ⚡1 safety-gate ............ destructive Bash (rm -rf, DROP TABLE, git reset --hard); stands over
                              EVERY Bash call at ANY point in this picture, not only at ship
  ⚡2 push-to-main blocker ... push to main/protected branches; plus the ship-gate: no push
                              without recorded proof/gate ledger entries
  ⚡3 anti-rationalization ... premature "done", phantom-impl stub, guess-fix while ## Root cause
                              is empty (Stop hook)
  ⚡4 verification pipeline .. unmet acceptance criteria / tests that did not run (the EXECUTE
                              PIPELINE box above IS this stop)
```

## 3 · System topology

Bird's-eye view: who connects to whom. The per-stage diagrams below show sequence; this shows the standing wiring between the four feature kinds and the stores that carry state between commands. Every edge class here is derived from the path index (section 5): `[H]`/`[I]`/`[E]` are the only ways in, `[D]` is the only command-to-agent edge, and every automated write lands in a store or staging file, never directly on the board.

### 3.1 · Actors and clusters

```
 ┌──────────┐  [H] typed command    ┌──────────┐    [D] dispatch    ┌─────────────────────┐
 │ operator │──────────────────────>│ COMMANDS │───────────────────>│       AGENTS        │
 └──────────┘                       │  /kit:*  │<───────────────────│ read-only research/ │
 ┌──────────┐  [I] inferred intent  │          │ verdicts, findings │ verify/review lenses│
 │  Claude  │──────────────────────>└────┬─────┘                    │ + write-capable     │
 │  intent  │                            │ tool calls               │ workers, fix-agent  │
 └────┬─────┘                            │ (Bash, Edit, push, ...)  └──────────┬──────────┘
      │ [I] auto-fire                    v                                     │ tool calls
      │      ┌────────┐         ┌─────────────────┐<───────────────────────────┘
      └─────>│ SKILLS │         │      HOOKS      │<──[E]── harness events
             └───┬────┘         └────────┬────────┘   (SessionStart, UserPromptSubmit,
                 │                       │             PreToolUse, Stop, SessionEnd, ...)
                 v                       v
     context injected, audit    HARD block (safety-gate, ship-gate, commit-format,
     PRs, dashboards, renders   secrets-guard, anti-rationalization) or advise,
                                then the tool call passes through
```

### 3.2 · Stores: how one command hands off to the next

Commands never hand off in memory; the baton passes through stores on disk.

```
                  write                                       read
 /kit:assign ──────────> .claude/goals/<draft> ──────────────────> /kit:grill, /kit:spec
 /kit:think ───────────> DECISION-BRIEF.md ──────────────────────> /kit:design, /kit:spec
 /kit:spec ────────────> docs/specs/SPEC-NNN ────────────────────> /kit:spec-validate, /kit:execute
 verifiers + gates ──record──> gate/proof ledgers ───────────────> ship-gate [E, HARD] at push
 hooks (harvest,
  backlog-stage) ──stage──> staging files ──human promote──> _meta/BACKLOG.md (board)
 _meta/BACKLOG.md (board) ───────────────────────────────────────> /kit:start, /kit:assign --next
 /kit:retro ───────────> docs/retro/v<version>.md ───────────────> next /kit:think
```

## 4 · Master map

### 4.1 · SHAPE: intake and contract-making

```
 [E] SessionStart ── context-readiness (spec/board state) + codebase-index (opt-in)
 [E] UserPromptSubmit ── context-hints + prose-rag (opt-in) inject before every turn
        |
        v
 [H] /kit:start ──> board + telemetry render ──> recommends next command (never executes)
        |
        v
 [H/I] /kit:assign ID-NNN | --next ──> goal draft + scope fence + lane pick
        |                                  (advisory lane-floor check: warn, never block)
        |-- too foggy ──> [H] /kit:wayfind ──> decision map + typed tickets
        |                    tickets route: grill / prototype / research / task
        |                    map clear ──> /kit:spec or ROADMAP (/kit:mega)
        |
        v
 [H/I] /kit:grill ──> typed interview, one question at a time ──> phase-0 Done=
        |
        v                                      [D] brief-reviewer + advisor critique
 [H/I] /kit:think ──> DECISION-BRIEF.md ──┬──> [H] /kit:design ──> Solution in brief
        |                                 |      +── [H] /kit:devs-team (5 lenses, report-only)
        |                                 +──> [H] /kit:prototype ──> spike branch, folds back
        v
 [H/I] /kit:spec ──> [D] research-architecture + research-features
        |                + research-pitfalls + research-stack (brownfield, read-only)
        v
     SPEC-NNN DRAFT ──> [H/I] /kit:spec-validate (6 lenses, 1 HARD on the design record)
        |                        NEEDS REVISION ──> back to /kit:spec
        v
     Status: VALIDATED ──> Build
```

Off-ramp entries that also land in Shape: `[H] /kit:onboard` (first run, orchestrates `/kit:adopt` + `/kit:start` + config), `[H/I] /kit:adopt` (injects the operate-contract into a target repo so the ship-gate engages there).

### 4.2 · BUILD: test design, execution engines, agent-making

```
 VALIDATED spec
    |
    v
 [H] /kit:test-plan ──> ## Test plan matrix ──> [H] /kit:test-plan-review-team
    |                                              (6 lenses + bounded revise ──> SOLID)
    |                                              ──> [H] /kit:test-write ──> [D] test-writer
    v
 [H/I] /kit:execute  (or [H] /kit:next, human-paced, same pipeline)
    |
    |   per task, HARD pipeline:
    |   [D] worker (data-etl-worker | db-migration-worker | generic | meta-agent synthesis)
    |        ──> [D] task-verifier ──PASS──> done   (any PASS may get [D] recheck-verifier)
    |                 └─FAIL:fixable──> [D] fix-agent ──> re-verify (max 2) ──> ESCALATE
    |   all tasks PASS ──> checkpoint ──> [D] integration-verifier (multi-task)
    v
 build complete ──> Check (review chain)

 Alternate engines off the same trunk:
 [H/I] /kit:dispatch ──> N disjoint VALIDATED specs ──> isolated worktree workers
                          (fix-agent + task-verifier per worker) ──> lead converges ──> /kit:ship
 [H/I] /kit:mega ─────> roadmap of 3-8 sub-goals ──> /goal loop per sub-goal
                          (each runs the spec..ship chain) ──> ship-gate merge per tag
 [H/I] /kit:debug ────> off-cycle: Phase 0..4, iron law (no fix without recorded root cause),
                          3-fix architecture wall ──> verified fix ──> resume prior state
 [H] /kit:ui-design ──> UI brief ──> frontend-design skill ──> /kit:visual-team critique
                          ──> [D] fix-agent revise (bounded) ──> SOLID
 [H/I] /kit:draft-agent ──> [D] meta-agent draft ──> [D] agent-effectiveness ──> install (--draft stops staged)
 Build-support skill: get-api-docs [I] auto-fires before coding against a third-party API.
 Build-time hooks: auto-format [E, conv] on every edit; spec-drift-guard [E, adv] on Write.
```

### 4.3 · CHECK: review, verification, gates

```
 build complete
    |
    v
 [H/I] /kit:review (single-pass inline)   or   [H/I] /kit:review-team:
    |        [D] code-reviewer x2 + security-reviewer + advisor (+ api/frontend/infra/performance
    |            reviewers when the diff touches their domain) + responding-to-review
    v
 ## Review verdict ──> [H/I] /kit:docs ──> [D] doc-verifier ──> docs match code
    |
    v
 [H/I] /kit:ship ──> reads ## Review (DO NOT SHIP = stop, HARD) ──> version + changelog
    |                 + [D] advisor ──> commit ──> PR
    |                 [E] ship-gate HARD: no push without recorded proof/gates
    |                 [E] safety-gate HARD: push-to-main / force-push / destructive Bash
    v
 shipped ──> Learn (/kit:retro)

 On-demand re-verification, read-only, no rebuild:
 [H/I] /kit:verify ──> [D] task-verifier + integration-verifier
                        + acceptance-verifier + system-verifier ──> verdict only
 Ad hoc on any load-bearing claim: [D] claim-verifier ──> HOLDS / REFUTED majority verdict.
 Standing Check hooks: secrets-guard [E, HARD], commit-format [E, HARD],
 anti-rationalization [E, HARD on Stop], citation-guard [E, adv; strict mode blocks],
 money-gate [E, inert until MONEY_GATE_REPOS], tool-policy-guard [E, wired PreToolUse *
 but inert until tool-policy.json exists].
```

### 4.4 · WATCH: recording what happened

```
 [E] Stop ────────────> session-state-save (persist last-state.md)  [conv]
 [E] SubagentStop ────> session-state-save (same)                   [conv]
 [E] PreCompact ──────> pre-compact-backup + harvest (stage learnings) [conv]
 [E] PostToolUse * ───> output-offload (oversized output to file)   [adv]
 [E] PostToolUse compact ─> post-compact-reinject (restore rules)   [conv]
 [E] SessionEnd ──────> backlog-stage (stage work-items; --surface runs intake-sweep)
                        + harvest --lab-log (stage LAB_LOG draft)   [conv]
 [E] SessionStart ────> intake-sweep (via backlog-stage --surface; config-gated no-op) [conv]
 [E] Notification ────> notification (desktop notify, async)        [conv]
 [E] PermissionRequest > permission-auto-approve (read-only ops)    [conv]
 [E] StatusLine ──────> statusline (HUD render)                     [conv]
 [I] observe skill ───> control-plane dashboards via lib/bench      read-only
 [I] stats skill ─────> ledger queries (kit/tide/learned/debt)      read-only + one staging write
 Every automated Watch path ends at a staging file or a render, never a direct board/ledger write.
```

### 4.5 · LEARN: distill the record into the next cycle

```
 shipped
    |
    v
 [H/I] /kit:retro ──> docs/retro/v<version>.md ──> feeds the next /kit:think
    |
    +── [H/I] /kit:explain ──> literate-diff explainer ──> [H] /kit:quiz-gate
    |         (the ★-tap nudge) ──> engage / defer / wave logged (never must-pass)
    +── [H] /kit:pitch <rid> ──> buy-in doc from spec + proof + notes + ledger
    +── [H] /kit:kit-health ──> self-assessment vs PHILOSOPHY (report)
    +── [H] /kit:absorb ──> Credits drift + seed rescan ──> proposal, human merges

 Learn-side skills (auto-fire [I] unless noted):
 doc-drift ──> whole-estate doc audit ──> fixes on a branch ──> PR gate
 feature-map ──> FEATURES.md vs path-index cross-check ──> delta re-placed ──> PR gate
   (both dispatch [D] audit-scanner for Tier 2: read-only evidence, skill applies)
 memory-tidy ──> evidence-gated memory audit ──> PR-gated merges/deletions
 skill-review [H] ──> reviews staged skill drafts ──> promote or reject
 loop-engineering ──> gate + anatomy walkthrough for a proposed loop ──> design hand-off
 Staged harvest/backlog output re-enters Shape via board promote (the human gate).
```

## 5 · Complete path index

One line per live feature: `entry -> ... -> terminal`. Grouped by kind; every feature in `commands/`, `agents/`, `skills/`, `hooks/` appears exactly once.

### Commands

| Path |
|---|
| `[H] /kit:start -> board + telemetry render -> recommendation (never executes)` |
| `[H] /kit:onboard -> detect install mode -> orchestrate adopt/start/config -> confirmed writes` |
| `[H/I] /kit:adopt -> inject operate-contract into target repo -> ship-gate engaged there` |
| `[H/I] /kit:assign -> goal draft + lane pick -> grill / think / spec / dispatch / ship per lane` |
| `[H/I] /kit:grill -> typed interview -> phase-0 Done= -> lane routing` |
| `[H] /kit:wayfind (human ONLY) -> decision map + tickets -> /kit:spec or ROADMAP` |
| `[H/I] /kit:think -> brief-reviewer + advisor critique -> DECISION-BRIEF.md -> design or spec` |
| `[H] /kit:design -> one decision at a time -> Solution in brief -> /kit:spec` |
| `[H] /kit:prototype -> spike on prototype/<name> branch -> decision folds into brief/spec` |
| `[H] /kit:devs-team -> 5 engineering lenses -> report-only -> feeds /kit:design` |
| `[H/I] /kit:spec -> 4 research agents -> SPEC-NNN DRAFT -> spec-validate or ui-design` |
| `[H/I] /kit:spec-validate -> 6 lenses (1 HARD) -> VALIDATED or back to /kit:spec` |
| `[H] /kit:test-plan -> coverage matrix -> ## Test plan -> review-team or execute` |
| `[H] /kit:test-plan-review-team -> 6 lenses + revise loop -> SOLID verdict -> test-write or execute` |
| `[H] /kit:test-write -> test-writer per matrix row -> runnable tests -> /kit:execute` |
| `[H/I] /kit:execute -> worker -> task-verifier -> fix-agent (max 2) -> integration-verifier -> review` |
| `[H] /kit:next -> load next undone task -> human-paced, same verification path` |
| `[H/I] /kit:dispatch -> N worktree workers behind disjointness gate -> lead converges -> ship` |
| `[H/I] /kit:mega -> roadmap of 3-8 sub-goals -> /goal loop each -> ship-gate merge per tag` |
| `[H/I] /kit:debug -> Phase 0..4 under the iron law -> verified fix -> resume prior state` |
| `[H/I] /kit:review -> single-pass paranoid review -> verdict -> docs or back to execute/spec` |
| `[H/I] /kit:review-team -> reviewer roster + advisor in parallel -> ## Review -> /kit:docs` |
| `[H] /kit:visual-team -> 5 design lenses -> report-only verdict` |
| `[H] /kit:ui-design -> brief -> frontend-design skill -> visual-team -> fix-agent revise -> SOLID` |
| `[H/I] /kit:docs -> diff code vs every doc -> doc-verifier -> /kit:ship` |
| `[H/I] /kit:verify -> 4 verifiers read-only -> verdict, no rebuild, no fix` |
| `[H/I] /kit:explain -> literate-diff explainer -> feeds /kit:quiz-gate` |
| `[H] /kit:quiz-gate -> 5 diff-grounded questions -> engage/defer/wave logged (advisory)` |
| `[H] /kit:pitch <rid> -> assemble buy-in doc from existing sources -> doc (never fabricates)` |
| `[H/I] /kit:ship -> gate check + version + changelog + PR -> /kit:retro (HARD on DO NOT SHIP)` |
| `[H/I] /kit:retro -> capture learnings -> docs/retro/v<version>.md -> feeds next /kit:think` |
| `[H/I] /kit:draft-agent -> meta-agent -> agent-effectiveness -> install (--draft stops staged)` |
| `[H] /kit:kit-health -> self-assessment vs PHILOSOPHY -> report (terminal)` |
| `[H] /kit:absorb -> Credits drift + seed rescan -> proposal-only, human merges` |

### Agents

| Path |
|---|
| `[D] research-architecture <- /kit:spec -> architecture patterns -> findings return (read-only)` |
| `[D] research-features <- /kit:spec, /kit:test-plan -> existing-feature map -> findings return` |
| `[D] research-pitfalls <- /kit:spec -> landmine/risk list -> findings return (read-only)` |
| `[D] research-stack <- /kit:spec -> tech-stack map -> findings return (read-only)` |
| `[D] brief-reviewer <- /kit:think -> static brief review -> feedback into the brief` |
| `[D] test-writer <- /kit:test-write -> one test case per matrix row -> runnable test code` |
| `[D] data-etl-worker <- /kit:execute (domain=data-etl) -> pipeline build -> task-verifier` |
| `[D] db-migration-worker <- /kit:execute (domain=db-migration) -> migration + rollback -> task-verifier` |
| `[D] meta-agent <- /kit:execute (Mode C), /kit:draft-agent -> staged draft -> command promotes` |
| `[D] task-verifier <- /kit:execute, /kit:verify -> AC check -> PASS / FAIL:fixable / FAIL:escalate` |
| `[D] fix-agent <- execute, dispatch, debug, test-write, ui-design, verify -> scoped fix -> re-verify` |
| `[D] integration-verifier <- /kit:execute (multi-task), /kit:verify -> wiring check -> review` |
| `[D] recheck-verifier <- /kit:execute -> fresh-context re-audit of a PASS -> advisory record` |
| `[D] audit-scanner <- doc-drift, feature-map skills (Tier 2) -> per-item verdicts with quoted evidence -> findings return (read-only)` |
| `[D] claim-verifier <- any command, ad hoc -> N-skeptic panel -> HOLDS / REFUTED verdict` |
| `[D] code-reviewer <- review-team, devs-team, visual-team -> focused lens -> findings merged` |
| `[D] security-reviewer <- /kit:review-team -> OWASP-style audit -> findings merged` |
| `[D] api-reviewer <- /kit:review-team (API diffs) -> contract lens -> findings merged` |
| `[D] frontend-reviewer <- /kit:review-team (UI diffs) -> a11y lens -> findings merged` |
| `[D] infra-reviewer <- /kit:review-team (infra diffs) -> deploy/IaC lens -> findings merged` |
| `[D] performance-reviewer <- /kit:review-team (perf diffs) -> hot-path lens -> findings merged` |
| `[D] advisor <- review-team, ship + many others at the final boundary -> additive findings` |
| `[D] responding-to-review <- /kit:review-team -> verify findings, push back -> proposed fixes` |
| `[D] agent-effectiveness <- /kit:draft-agent (diff-keyed) -> 4-lens validation -> advisory` |
| `[D] doc-verifier <- /kit:docs -> docs-vs-code check -> PASS/FAIL back to /kit:docs` |
| `[D] acceptance-verifier <- /kit:verify -> executes spec ## Verification -> verdict` |
| `[D] system-verifier <- /kit:verify -> whole project suite -> verdict` |

### Skills

| Path |
|---|
| `[I] doc-drift -> whole-estate doc audit -> fixes on a branch -> PR gate (terminal: merged PR)` |
| `[I] feature-map -> registry freshness gate -> FEATURES.md vs path index both directions -> delta re-placed on topology -> PR gate` |
| `[I] get-api-docs -> fetch curated API docs -> grounded coding (terminal: context injected)` |
| `[I] loop-engineering -> gate + anatomy walkthrough -> design handed to the loop builder` |
| `[I] memory-tidy -> evidence-gated memory audit -> PR-gated merges/deletions` |
| `[I] observe -> control-plane query/render via lib/bench -> read-only dashboard` |
| `[H] skill-review -> review staged drafts -> promote to ~/.claude/skills/ or reject` |
| `[I] stats -> ledger query -> reply or Artifact; anomalies --propose stages one candidate` |

### Hooks

| Path |
|---|
| `[E] SessionStart -> context-readiness -> inject spec/board state + next step (adv, terminal)` |
| `[E] SessionStart -> codebase-index -> background indexing, opt-in (conv, terminal)` |
| `[E] SessionStart / backlog-stage --surface -> intake-sweep -> staging file (conv, config-gated)` |
| `[E] UserPromptSubmit -> context-hints -> temporal + keyword skill hints (conv, terminal)` |
| `[E] UserPromptSubmit -> prose-rag -> prior-note injection, opt-in PROSE_RAG_INJECT=1 (conv)` |
| `[E] PreToolUse Bash -> safety-gate -> HARD block destructive Bash / push-to-main / force-push` |
| `[E] PreToolUse Bash -> ship-gate -> HARD block ship without recorded proof/gates` |
| `[E] PreToolUse Bash -> commit-format -> HARD block non-conventional commit subjects` |
| `[E] PreToolUse Read/Edit/Bash -> secrets-guard -> HARD block secret-file reads` |
| `[E] PreToolUse Write -> spec-drift-guard -> warn on files the active spec never mentions (adv)` |
| `[E] PreToolUse Edit/Write/MultiEdit -> money-gate -> warn on money-file edits (inert by default)` |
| `[E] PreToolUse * -> tool-policy-guard -> allow/ask/deny per domain (inert until tool-policy.json)` |
| `[E] PostToolUse Write/Edit -> auto-format -> idempotent formatting (conv, terminal)` |
| `[E] PostToolUse * -> output-offload -> oversized output to file + nudge (adv, terminal)` |
| `[E] PostToolUse compact -> post-compact-reinject -> restore stripped rules (conv, terminal)` |
| `[E] PreCompact -> pre-compact-backup -> session snapshot (conv, terminal)` |
| `[E] PreCompact + SessionEnd --lab-log -> harvest -> staged learnings / LAB_LOG draft (conv)` |
| `[E] Stop -> anti-rationalization -> HARD block premature "done" / guess-fix` |
| `[E] Stop -> slop-cleaner -> suggest long-session code trims (adv, terminal)` |
| `[E] Stop + SubagentStop -> session-state-save -> persist last-state.md + archive (conv)` |
| `[E] Stop -> citation-guard -> flag hallucinated file:line (adv; CITATION_GUARD_STRICT=1 blocks)` |
| `[E] SessionEnd -> backlog-stage -> stage work-items to staging file, never the board (conv)` |
| `[E] Notification -> notification -> desktop notify, async (conv, terminal)` |
| `[E] PermissionRequest -> permission-auto-approve -> auto-approve read-only ops (conv, terminal)` |
| `[E] StatusLine -> statusline -> HUD render (conv, terminal)` |

## 6 · How to regenerate

1. Re-derive the backbone from `docs/research/2026-07-31-feature-trigger-map.md` (or regenerate that file first per its own Method section: enumerate `commands/`, `agents/`, `skills/*/SKILL.md`, `hooks/*.sh` by `ls`, never trust a doc's count).
2. Take stage grouping from the README's "The five stages" section; take flow shapes from `docs/workflow-map.md`; take rules and precedence from `docs/WORKFLOW.md` (canonical; it wins on any disagreement).
3. Take hook events from `hooks/hooks.json` and root `settings.json` (same wiring, two install paths; `statusline` rides the `statusLine` key, not a hook event). Live wiring wins over any doc claim: this pass found `tool-policy-guard` wired at PreToolUse `*` in both files although the trigger map called it unwired; it stays inert until a `tool-policy.json` exists.
4. Every live feature gets exactly one line in section 5; verify with `ls commands/*.md agents/*.md skills/*/SKILL.md hooks/*.sh | wc -l` against the index line count (derive the number, never hardcode it here).
5. Re-derive the System topology (section 3) from the finished path index: the `[H]`/`[I]`/`[E]`/`[D]` marks give the actor and dispatch edges; the store hand-offs come from each path's write target and the command that reads it next. Invent no edge the index does not show.
6. Re-derive the Flow topology (section 2) from `docs/workflow-map.md`'s flow census (the backbone, the 5 lanes, the 3 bounded loops + amend micro-loop, the side-flows, the 7 alternate flows, the 4 hard stops) laid onto one connected picture, with `docs/WORKFLOW.md` winning on any disagreement. Where the picture must simplify, point at the section carrying the detail instead of distorting.
