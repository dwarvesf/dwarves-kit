---
title: ECC (affaan-m/ECC) vs dwarves-kit, scored against the five orchestration wants
date: 2026-05-24
purpose: >
  Code-level read of affaan-m/ECC (not the README marketing) scored against the
  five things Han wants from dwarves-kit: concurrent execution, multi-spec support,
  a real orchestration layer, LLM-interactive-driven gates, and SDD/TDD/V-model
  methodology. Use when deciding what to borrow from ECC for dwarves-kit, or when
  the "orchestrator layer is missing" gap from the 2026-05-20 enforcement-patterns
  note needs a concrete reference architecture to study.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: as-needed
next_review: 2026-08-24
status: active
---

# ECC vs dwarves-kit

Read of `affaan-m/ECC` at HEAD on 2026-05-24 (shallow clone, code read, nothing executed).
Pairs with `2026-05-20-dwarves-kit-vs-claude-plan-orchestration.md` (kit vs Claude builtin)
and `2026-05-20-agent-workflow-enforcement-patterns.md` (the landscape survey).

## What ECC actually is (from the tree, not the pitch)

A **maximalist cross-harness operator system**. Verified counts: **232 skills, 60 agents,
75 commands, 4 hooks**, fanned out across 7+ harnesses (Claude Code, Cursor, Zed, OpenCode,
Codex, Copilot, Gemini, Kiro, Qwen, Trae) via per-harness dotdirs. This is the polar opposite
of dwarves-kit's thesis (hooks + commands + agents + **1** skill, minimal-but-enforced).

The non-obvious part is **`ecc2/`**: a real Rust control-plane, **~52K LOC**, alpha. Not prose.

```
ecc2/src/  (tokio async, clap CLI, SQLite)
  session/manager.rs   8190   spawn/route delegates, assignment actions
  session/store.rs     7109   SQLite session + output persistence
  session/daemon.rs    1322   background daemon mode
  worktree/mod.rs      2672   git-worktree-isolated sessions
  tui/dashboard.rs    15162   live multi-session dashboard
  main.rs             12595   CLI: start --task --agent --worktree, sessions, resume
```

So ECC has **two orchestration layers**: a prompt-encoded one (like the kit) AND an emerging
compiled runtime (which the kit lacks entirely). That distinction drives the whole scorecard.

## Scorecard against the five wants

| Want | Verdict | Evidence (file) |
|---|---|---|
| Concurrent execution | **Delivers** (2 flavors) | prompt: `commands/multi-{execute,plan,workflow}.md` run Codex+Gemini in background bash + `TaskOutput` polling. runtime: `ecc2/src/session/manager.rs` spawns/routes worktree-isolated delegates |
| Multi-spec support | **Partial** | `ecc2` runs many concurrent **sessions** (1 task + 1 worktree each), but a "session" is a task, not a tracked spec artifact with a DRAFT→SHIPPED lifecycle. No spec registry/board. PRP makes per-feature PRD+plan files, not a concurrent multi-spec model |
| Orchestration layer | **Delivers, exceeds the kit** | prompt: `/orchestrate custom "a,b,c"` chains + `skills/plan-orchestrate`, `commands/loop-start.md` (patterns: sequential, continuous-pr, rfc-dag, infinite), `agents/loop-operator.md`. runtime: the whole `ecc2/` engine |
| LLM-interactive-driven | **Delivers** | `commands/prp-prd.md` is an interactive hypothesis-driven PRD interview; `multi-execute` requires explicit user "Y" before proceeding; `AskUserQuestion` on loop-timeout; loop-start confirms repo state first |
| SDD / TDD / V-model | **SDD yes, TDD yes, V-model partial** | SDD: PRP pipeline `prp-prd → prp-plan → prp-implement → prp-pr → prp-commit` (adapted from PRPs-agentic-eng). TDD: `skills/tdd-workflow` (tests-first, 80% gate, unit/integration/E2E) + `agents/tdd-guide.md` + language `*-tdd` skills. V-model: no explicit left-arm/right-arm; closest is `commands/santa-loop.md` adversarial dual-review (two independent models must both approve before ship) |

Net: **4 of 5 strong**, partial on multi-spec and V-model. The orchestration want (Han's hardest
one) is ECC's strongest answer, precisely because of `ecc2`.

## The finding that updates the 2026-05-20 note

That note's Part 6 said the kit's missing piece is "the orchestrator layer that sequences atomic
commands into an enforced lifecycle" and named **harness-experimental's AGENTS.md** as the model to
study. **`ecc2` is a better reference architecture** for that gap: it is a working (alpha) runtime
that does worktree-isolated multi-session management with a SQLite state store and a delegate
spawn/route manager. That is the compiled engine the kit's prompt-encoded retry loop drifts without,
and it overlaps Ouroboros's territory (the other "real engine" we flagged) without Ouroboros's
event-sourcing weight.

## Orchestration topology (read from the code, 2026-05-24)

ECC has two orchestration layers. Layer A is prompt-encoded inside one harness session
(dwarves-kit style). Layer B (`ecc2`) is a compiled control plane that orchestrates many
instances of Layer A. They connect through (1) `runtime.rs` spawning a real agent OS process
and (2) the SQLite store acting as a shared blackboard.

![ECC orchestration topology: Layer A prompt orchestration over the ecc2 Rust control plane, with route-or-spawn assignment, merge queue, SQLite blackboard, and the alpha agent-cooperation seam](assets/ecc-orchestration-topology.svg)

The ASCII below is the same topology in detail; the SVG above is the shareable summary.

```
LAYER A  prompt-encoded orchestration (INSIDE one harness session)
  /orchestrate custom "a,b,c"     sequential agent chain, HANDOFF-fed
  skills/plan-orchestrate         emits chains from a plan (generative only)
  loop-start {sequential | continuous-pr | rfc-dag | infinite}
  santa-loop                      2 independent model reviewers, both must PASS
  multi-*  -> background bash -> Codex / Gemini   (Claude = sole filesystem writer)
  60 agents · 232 skills · 4 hooks(gates)
        │
        │ ecc2 `start --agent claude` spawns an OS process running Layer A
        ▼
LAYER B  ecc2 compiled control plane (ACROSS many sessions)
  ~52K LOC Rust · tokio · SQLite · orchestrates many Layer-A instances
```

### Runtime component graph (Layer B)

```
   operator --CLI(clap)--┐                       ┌- TUI dashboard (live board)
                         ▼                       │   tui/dashboard.rs
                  ┌────────────┐  coordinate ┌───┴──────────────┐
                  │   daemon   │────────────►│  SessionManager   │ manager.rs
                  │ daemon.rs  │             │  route-or-spawn   │
                  └────────────┘             └──┬────────────┬───┘
                                  spawn process │            │ create/merge
                                  (tokio)       ▼            ▼
                               ┌──────────┐         ┌─────────────────┐
                               │ runtime  │ agent   │  worktree mgr   │
                               │ runtime  │ OS proc │  + MERGE QUEUE  │ worktree/mod.rs
                               └────┬─────┘         └─────────────────┘
                          output/heartbeat
                                    ▼
   ┌──────────────── SQLite StateStore (store.rs) ───────────────────┐
   │ sessions · messages(comms bus) · decisions · metrics · tool spans│
   └─────────────────────────────────────────────────────────────────┘
            ▲                                          │
   observability/OTLP (ExportOtel)            comms bus: TaskHandoff /
   observability/mod.rs                       Query / Response / Completed / Conflict
```

### The heart: delegation tree + route-or-spawn assignment

From `assign_session` / `preview_assignment_for_task`:

```
                 LEAD session (Running)
                   │ inbox = unread TaskHandoffs {task, context, priority}
                   ▼
        assign_session(lead, task, agent)
        look at lead's direct delegates + each one's handoff backlog
                   │
   ┌───────────────┼───────────────┬────────────────────┐
   ▼               ▼               ▼                    ▼
ReusedIdle    ReusedActive      Spawned          DeferredSaturated
idle delegate, absorb onto a   new delegate +   all delegates full ->
empty backlog  busy delegate    new worktree     DEFER  (backpressure)
   │               │               │                    │
   ▼               ▼               ▼                    ▼
  D1              D2              D3            queued; escalate if
                                               operator_escalation_required
```

Delegation via `from_session` forms a tree (lead -> delegates -> sub-delegates),
inspectable with `ecc team <lead> --depth N`.

### Work lifecycle (state machine + merge convergence)

```
 task in (ecc start/delegate/assign)
   ▼
 Pending -> Running ─┬─► Idle ──► (reused by assignment policy)
                     ├─► Stale ─► Stopped
                     ├─► Failed ─► Resume ─► Running
                     └─► Completed
                            │  worktree has a branch + diff
                            ▼
                     MERGE QUEUE (WorktreeStatus -> merge-readiness)
                       auto-rebase clean blocked worktrees, merge what is
                       ready, flag conflicts (WorktreeResolution)
                            ▼
                     merged into base ─► PruneWorktrees
```

### Coordination loop (daemon, across all teams)

```
 daemon tick:
   AutoDispatch ........ sweep EVERY lead's unread handoffs -> assignment policy
   CoordinateBacklog ... dispatch, THEN RebalanceTeam (move work off backed-up
                         delegates onto clearer capacity) [--until-healthy, max passes]
   CoordinationStatus .. backlog_leads · absorbable vs saturated · health
                         └─► sets operator_escalation_required when wedged
```

Layer-A attach points: `rfc-dag` = a DAG of tasks that becomes handoffs/sessions;
`santa-loop` dual-review is a gate before `Completed -> merge`; the 4 hooks fire on
tool events to enforce gates (type-check, secret-scan, session-persist) inside each session.

### Component legend (file · status)

| Component | File | Status |
|---|---|---|
| Session state machine (`can_transition_to`) | `session/mod.rs` | wired |
| Route-or-spawn assignment policy | `session/manager.rs` | wired |
| Coordination + rebalance + backpressure | `session/manager.rs` | wired |
| Inter-session comms bus (5 message types) | `comms/mod.rs` | wired |
| SQLite persistence | `session/store.rs` | wired |
| Agent process spawn + heartbeat | `session/runtime.rs` | wired |
| Worktree isolation + merge queue + conflict protocol | `worktree/mod.rs` | wired |
| Decision log (decision + rationale + alternatives) | `main.rs` LogDecision | wired |
| Observability / OTLP export | `observability/mod.rs` | wired |
| Daemon background coordination | `session/daemon.rs` | wired |
| Orchestration templates (`ecc2.toml`) | `main.rs` Template | wired, config-driven |
| Hermes/OpenClaw workspace `Migrate` | `main.rs` Migrate | alpha |
| Risk-scoring | observability | alpha (primitives) |
| Agent honoring the handoff protocol autonomously | Layer A cooperation | **soft**: engine routes, but the spawned agent must read its inbox + emit `TaskHandoff`/`Completed`; prompt-dependent, not Rust-enforced |
| Whole `ecc2` | `ecc2/README.md` | alpha / not GA |

### Three things the topology surfaces

1. **Real backpressure** (`DeferredSaturated` + saturation metrics + escalation). The single
   biggest thing dwarves-kit lacks: the kit's retry loop has no "system is full, defer." ECC
   enforces it in compiled code.
2. **The merge queue is the convergence layer** (auto-rebase clean blocked worktrees, merge when
   ready, surface conflicts). Exactly how you safely run concurrent agents on one repo; the part
   dwarves-kit and Ouroboros would each still need to build.
3. **The decision log is the institutional-memory item** the 2026-05-20 note wished for, shipped
   as a first-class persisted, cross-session command.

Soft seam: the Rust engine is genuinely wired, but the agent's autonomous participation (a spawned
Claude reading its SQLite inbox and emitting structured handoffs without a human steering each step)
is the alpha, unproven part. The control plane can route and merge; whether agents behave like
cooperating swarm workers is not guaranteed by the engine.

## Task lanes, full flow, and user flow (read from the code, 2026-05-24)

### Task lanes: lanes exist, but the key is NOT task type

ECC has several lane axes; none is an automatic "classify by task type then route".

| Lane axis | Keyed on | Mechanism (file) | Status |
|---|---|---|---|
| Board lane | session **state** | `board_lane_for_state`: Inbox/In Progress/Review/Blocked/Done (`store.rs`) | wired |
| Routing pool | **agent_type** (operator-chosen) + content affinity | `direct_delegate_sessions(agent_type)` + `delegate_selection_key` = graph-context term match + recency (`manager.rs`) | wired |
| Capability profile | named **agent profile** (e.g. reviewer) | `AgentProfileConfig` w/ inheritance, `default_agent_profile`, used by templates (`config/mod.rs`) | wired (config) |
| Priority | **urgency** Low/Normal/High/Critical | `TaskPriority` on handoffs, drives rebalance (`comms/mod.rs`) | wired |
| Model tier | **complexity/risk/budget** | `/model-route` -> haiku/sonnet/opus | advisory, prompt-layer |
| Domain | frontend vs backend | `multi-workflow`: frontend->Gemini, backend->Codex | prompt convention |
| Strictness | gate level | `ECC_HOOK_PROFILE` minimal/standard/strict | config |

No engine-enforced task-type classifier. Closest equivalents: agent profiles + templates
(manually-declared typed lanes) and the graph-context affinity in `delegate_selection_key`
(content overlap, not type). This is the same risk-tiered-intake gap the 2026-05-20 note flagged.

### Full orchestration flow (end to end)

```
PHASE 0  INTAKE  (any of)                                              [layer]
  operator: ecc start --task "..." --agent claude [--profile reviewer] [--worktree]   ecc2
  lead session emits TaskHandoff -> delegate inbox (priority Low..Critical)            ecc2
  Remote / Schedule / computer-use 'goal' dispatch                                     ecc2
  (optional) /model-route -> recommend haiku|sonnet|opus  [advisory]                   prompt
                                   v
PHASE 1  ASSIGN / LANE  (ecc2 SessionManager)                                          ecc2
  assign_session(lead, task, agent_type):
     pool = delegates filtered by agent_type ; pick = graph-context affinity + recency
     outcome -> ReusedIdle | ReusedActive | Spawned(+worktree) | DeferredSaturated(backpressure)
  session enters board lane by state: Inbox -> In Progress
                                   v
PHASE 2  PLAN  (prompt, optional SDD)                                                  prompt
  /prp-prd (interactive PRD interview) -> /prp-plan   OR   /multi-plan (Codex+Gemini -> plan)
                                   v
PHASE 3  EXECUTE  (inside the session worktree)                                        prompt
  /prp-implement (validate each change) | /multi-execute (ext model diff -> Claude writes)
  | loop pattern sequential|continuous-pr|rfc-dag|infinite ; TDD tests-first 80% ; hooks per edit
                                   v
PHASE 4  VERIFY  (gate, state -> Idle/Review)                                          prompt
  /santa-loop: 2 independent model reviewers, BOTH must PASS, else fix+re-run (max 3)
  quality-gate · security-scan · code-review
                                   v
PHASE 5  CONVERGE / MERGE  (ecc2 worktree)                                             ecc2
  WorktreeStatus -> MergeQueue (auto-rebase clean blocked, merge ready, flag conflicts)
  -> merge to base -> PruneWorktrees ; session -> Completed (Done lane)
                                   v
PHASE 6  COORDINATE  (ecc2 daemon, continuous, across ALL teams)                       ecc2
  AutoDispatch · CoordinateBacklog (dispatch + RebalanceTeam) · CoordinationStatus -> escalate
  throughout: decision log (decision+rationale+alts) · shared context Graph · OTLP export
```

Phases 0/1/5/6 are wired Rust; phases 2/3/4 are prompt-encoded markdown the spawned agent
must follow. The agent autonomously moving its own session Execute->Verify->Completed without
a human nudge is the alpha seam.

### User flow: three control surfaces

```
(1) NATURAL LANGUAGE  -> auto-fires skills + hooks            [no command typed]
    "write tests for auth"  ->  matches a skill desc (232 skills) + hooks on tool/session events
(2) SLASH COMMANDS    -> explicit workflow inside Claude Code [type /]
    /multi-workflow add checkout   ;  discovery: /ecc-guide
    daily: /plan /tdd /code-review /santa-loop /verify /pr /multi-* /orchestrate /loop-start
(3) ecc CLI           -> multi-session control plane          [run `ecc`]  [ALPHA]
    ecc start --task ... --worktree ; ecc dashboard|sessions|assign|delegate|merge-queue|daemon
```

| Surface | What you type | When it fires | Layer |
|---|---|---|---|
| NL intent | plain English | matches a skill description, or a tool/session event | prompt (skills + hooks) |
| Slash command | `/cmd args` | you submit it in the Claude Code chat | prompt (commands) |
| `ecc` CLI | `ecc <subcommand>` | you run the binary in a terminal | ecc2 runtime (alpha) |

Install (pick ONE, never stack): plugin `/plugin marketplace add .../ECC` then `/plugin install ecc@ecc`;
OR manual `./install.sh --profile {minimal|core|full} --target claude` (`npx ecc consult "<topic>"`
recommends packs); ecc2 CLI is a separate `cd ecc2 && cargo run`. Stacking plugin + `--profile full`
duplicates skills/hooks.

Reality check: surfaces 1 and 2 (Claude Code plugin) are the used path. Surface 3 (`ecc` CLI) is
the alpha control plane, powerful on paper but unproven and needs a separate cargo build.

#### Natural-language scenarios (what plain English actually triggers)

The NL surface has two auto-fire mechanisms. Group A is matched on **your words** (intent ->
skill description); group B is matched on **Claude's actions** (the tool it picks). You type no
command in either. Examples below are real ECC skills/hooks.

A. Intent triggers a skill:

| You say | Auto-fires | What it pulls in |
|---|---|---|
| "add a password-reset endpoint" | `tdd-workflow` | tests-first, 80% coverage gate |
| "what breaks in prod?" / "safe to ship?" | `production-audit` | local-evidence readiness audit, nothing leaves repo |
| "find exploitable bugs in this repo" | `security-bounty-hunter` | remote-reachable vuln hunt, report-grade only |
| "research vector DBs, with sources" | `deep-research` | firecrawl/exa multi-source, cited report |
| "this button does nothing the 2nd time" | `click-path-audit` | traces full state-change sequence for cancel-out bugs |
| "build a Grafana dashboard for latency" | `dashboard-builder` | operator-question dashboard, not vanity |
| "harden our training pipeline" | `mle-workflow` | data contracts, reproducible train, eval, rollback |
| "scrape job boards daily into Notion" | `data-scraper-agent` | scheduled scraper + Gemini-Flash enrich |
| "my agent keeps repeating tool calls" | `agent-architecture-audit` | 12-layer agent-stack diagnostic |
| "run tests and push a fix with proof" | `terminal-ops` | evidence-first execute + verify |

B. Action triggers a hook (no words needed; the tool Claude picks fires it):

| Claude's action | Hook (event) | Effect |
|---|---|---|
| edit a `.ts`/`.tsx` file | TypeScript check + Prettier + quality-gate (PostToolUse) | `tsc --noEmit`, auto-format, fast quality scan |
| write frontend UI | Design quality check (PostToolUse) | warns if UI drifts generic-template |
| run `npm run dev` | Dev-server blocker (PreToolUse) | blocks outside tmux (exit 2) so logs stay reachable |
| run `git commit` | Pre-commit quality check (PreToolUse) | lints staged, validates msg, blocks secrets/console.log |
| run `gh pr create` | PR logger (PostToolUse) | logs PR URL + review command |
| ~50 tool calls deep | Strategic compact (PreToolUse) | suggests `/compact` |
| end the session | `continuous-learning-v2` (Stop/SessionEnd) | captures atomic instincts, project-scoped |

Group B strictness is gated by `ECC_HOOK_PROFILE` (minimal / standard / strict).

## Verdict: borrow, do not adopt

Adopting ECC wholesale contradicts the kit's identity (232 skills vs 1; 7-harness parity is scope
the kit deliberately refuses). But four pieces are worth lifting:

1. **`ecc2/src/{session/manager,worktree}.rs` as the study target** for the kit's orchestrator-engine
   gap. Read how it isolates sessions per worktree and how `AssignmentAction` decides spawn-vs-route.
   This is the concrete answer to "make the retry loop a runtime, not pseudocode."
2. **`santa-loop` adversarial dual-review**: two independent models, no shared context, both must
   return approval or it loops (max 3 rounds). Cheap, high-value verification upgrade that sharpens
   the kit's existing programmatic-backpressure moat. Closer to V-model independence than what the
   kit ships today.
3. **Loop-pattern vocabulary + `--mode safe|fast`** (`ECC_HOOK_PROFILE` strictness tiers). Directly
   answers the "full ceremony on a one-line fix" risk-tiered-intake idea from the prior note.
4. **`prp-prd` interactive PRD interview** as the front door to the kit's SDD pipeline (problem-first,
   "TBD - needs research" over invented requirements).

Skip: the multi-MODEL (Codex+Gemini+Claude, Claude as sole filesystem writer) orchestration. Clever,
but it adds external-CLI dependencies and is tangential to Han's five wants.

## Skeptical notes

- GitHub API confirms **189K stars / 29K forks** on a repo **created 2026-01-18**. The numbers are
  real, but ~189K stars in ~4 months is top-tier-of-all-GitHub velocity for a personal harness repo.
  Treat the adoption signal with suspicion; it does not measure whether the orchestration works.
- `ecc2` is **alpha / scaffold** ("not the finished product", Claude-Code-first). The strong
  orchestration verdict is about the architecture to study, not a drop-in dependency.
- Headline "232 skills" is breadth, not depth. Most are language/framework packs. The kit's bet that
  1 enforced skill beats 232 advisory ones is not refuted by ECC; it is the opposite wager.

### Reference
- Repo: github.com/affaan-m/ECC · PRP lineage: PRPs-agentic-eng by Wirasm
- Pairs with: `research/2026-05-20-dwarves-kit-vs-claude-plan-orchestration.md`,
  `research/2026-05-20-agent-workflow-enforcement-patterns.md`
