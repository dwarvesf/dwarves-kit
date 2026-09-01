---
title: DAG / dependency orchestration in coding-agent frameworks (July 2026 refresh)
date: 2026-07-25
purpose: >
  Prior-art refresh feeding ID-394 (own the ordering graph: retire the GSD-v2
  boundary, extend the shipped ADR-0030 wavefront to fan-in/fan-out). Surveys
  every framework with a real (or claimed) dependency scheduler as of
  2026-07-25, diffs against the kit's shape, and ranks pickups/avoids.
  Produced by a dispatched research subagent; sibling of
  2026-07-25-packaging-prior-art-refresh.md and the 2026-05-20 surveys.
status: active
---

# DAG/dependency orchestration in coding-agent frameworks (July 2026)

Consuming row: ID-394. Companion brief: `docs/briefs/DECISION-BRIEF-dag-wavefront.md`
(DRAFT 2026-07-02; ADR-0030 has since shipped the wavefront half).

All repos below are active (pushed within days-to-weeks of 2026-07-25) unless flagged.

## (a) Per-framework findings

### Tier 1: genuine DAG/dependency schedulers

| Framework | Dependency representation | Scheduling mechanics | Failure semantics | Merge/integration | Notable mechanism |
|---|---|---|---|---|---|
| **gsd-pi** ([open-gsd/gsd-pi](https://github.com/open-gsd/gsd-pi), [parallel-orchestration.md](https://raw.githubusercontent.com/open-gsd/gsd-pi/main/docs/user-docs/parallel-orchestration.md), [git-strategy.md](https://raw.githubusercontent.com/open-gsd/gsd-pi/main/docs/user-docs/git-strategy.md)) | `dependsOn` field on milestone objects (exact schema undocumented); eligibility = not complete AND all `dependsOn` complete AND no file-overlap blocker | **Static single-pass eligibility, not waves.** All eligible milestones spawn workers upfront (`max_workers` 1-4, default 2), one worktree per milestone at `.gsd-worktrees/<MID>/` on branch `milestone/<MID>`. SQLite (WAL) coordination DB (heartbeats, leases). No dynamic ready-queue, no dependency recalculation after start | Per-unit retry with a dispatch ledger (`next_run_at`); **no cascading failure / no sibling cancellation on a dependency's failure** (undocumented) | Milestones squash-merge to main **sequentially in ID order** even though execution was parallel. On conflict: **halts entirely**, reports conflicting files, human resolves, re-trigger via `/gsd parallel merge <MID>` | File-overlap checked as a *soft warning* at eligibility, pre-check only (vs our blocking gate). `GSD_MILESTONE_LOCK` scopes worker state visibility |
| **Claude Code native Agent Teams** ([docs](https://code.claude.com/docs/en/agent-teams)) | Shared JSON task list at `~/.claude/tasks/{team}/`; tasks carry pending/in_progress/completed + explicit dependency links | **Dynamic self-claim queue, not waves.** A pending task with unresolved deps cannot be claimed; teammates self-claim the next unblocked task; claiming uses **file locking**; unblocking on completion is automatic | No auto-retry; an erroring teammate stops and notifies the lead (v2.1.198 distinguishes failed-stop from normal-stop); recovery manual. `TeammateIdle`/`TaskCreated`/`TaskCompleted` **hooks can block a state transition (exit 2)**, a genuine quality-gate primitive | **No merge machinery.** Teammates share one working copy by default; docs tell you to partition file ownership in the prompt; worktrees are a separate manual pattern | Mailbox = per-agent JSON inbox (`~/.claude/teams/{team}/inboxes/{agent}.json`) with malformed-entry skip. Plan-approval gate (teammate read-only until lead approves). Experimental, off by default; docs themselves say sequential/same-file work is better in a single session |
| **spec-kit-schedule** ([jfranc38/spec-kit-schedule](https://github.com/jfranc38/spec-kit-schedule), 2 stars) | Parses `tasks.md` into a typed graph: IDs, skill tags, token-estimate durations, file read/write footprints, explicit `(depends on T###)` **plus implicit edges** (phase barriers, same-file write ordering, TDD rules). Validates duplicates/unknown-deps/cycles | **The real thing**: MS-RCPSP solved with **Google OR-Tools CP-SAT**. Constraints: per-agent cardinality cap (calibrated to "empirical hallucination thresholds"), context-token budget per agent, **file-conflict constraint** (same-file writers cannot run concurrently). Stochastic durations; networkx warm start; preflight infeasibility check | `solver.replan` **freezes completed/in-flight assignments, re-solves only the residual**: genuine online replanning on duration overrun. Mid-graph task FAILURE story undocumented | A planner, not a merge tool; outputs schedule + Plotly Gantt + critical-path DAG view | Most sophisticated scheduling model in the sweep, but a 2-star hobby extension, unverified in the wild |
| **open-multi-agent (OMA)** ([repo](https://github.com/open-multi-agent/open-multi-agent), 6.6k stars, launched 2026-04) | Coordinator builds a task DAG **at runtime**; schema not published; persisted via TraceStore with execution receipts for replay | Claims deterministic scheduler over the runtime DAG, token/cost budgets, timeouts, loop detection. LLM-agnostic. No documented fan-in/fan-out primitives | Retries + resume-from-checkpoint; no halt/prune/escalate distinction documented | Shared memory + multi-agent consensus for output verification; branch merge semantics unspecified | **Approval gates** (preview/approve a plan or dispatch) + **frozen-plan deterministic replay** are the verifiable standouts; real downstream users |

### Tier 2: parallel-but-not-DAG (contrast)

| Framework | Model | Merge/integration | Source |
|---|---|---|---|
| **Multiclaude** | **No dependency graph, by philosophy.** "Brownian ratchet": supervisor + workers + merge-queue agent; workers fully independent in tmux + worktrees; CI is the only gate | Singleplayer: merge-queue **auto-merges any PR whose CI passes**, no human, no ordering. Multiplayer: PR-shepherd tracks human approvals | [intro](https://dlorenc.medium.com/a-gentle-introduction-to-multiclaude-36491514ba89), [repo](https://github.com/dlorenc/multiclaude) |
| **Gas Town** (17.2k stars) | TOML formulas with real `needs = [...]` step syntax; Beads (git-backed) issue tracker; "capacity governor" scheduler (`scheduler.max_polecats`); wave/ready-queue logic undocumented | **The Refinery**: batches merge requests, runs gates, merges via a **Bors-style bisecting queue**: on red, bisects to isolate the failing MR and lands the rest. The one genuinely novel concrete piece | [repo](https://github.com/gastownhall/gastown) |
| **Helmor** | No graph; one worktree+branch per task, independence by human assignment | PR/MR-centric UI: stacked PRs, agent-assisted conflict fixes, human-triggered | [helmor.ai](https://helmor.ai/) |
| **spec-kit native** (123.6k stars) | `tasks-template.md`: `[ID] [P?]` + inline `(depends on T###)`; phase/story checkpoints as sync barriers. **A planning artifact, not a live scheduler**; execution lives in low-star community extensions (spec-kit-schedule/worktree/orchestrator/maqa-ext), quality varies | n/a | [template](https://github.com/github/spec-kit/blob/main/templates/tasks-template.md), [catalog](https://github.com/github/spec-kit/blob/main/extensions/catalog.community.json) |

### Tier 3: checked, ruled out honestly

| Framework | Verdict |
|---|---|
| **ruflo** (ex claude-flow, 65.8k stars) | Feature-rich in breadth, opaque in depth: no documented config format, DB schema, or topology DSL; GOAP A* replanning is real-sounding but zero documented merge/conflict logic; "queen-led hierarchy / SONA neural patterns / 89% routing accuracy" asserted without algorithmic detail. Marketing surface over a real product; do not reverse-engineer mechanics from its docs |
| **BMAD-METHOD** (51k stars) | Sequential, not DAG: one story at a time through 12+ role agents with human checkpoints; no parallel execution documented |
| **agent-os** (5.1k stars, staler: last push 2026-05-05) | Not an executor; explicitly outsources scheduling to the host agent |
| **ralph-orchestrator** (3k stars) + multi-agent-ralph-loop | Single-agent pub/sub event-chain ("hats" with triggers/publishes); dependencies implicit in trigger-name wiring, no "wait for A AND C" primitive. multi-agent variant layers CC Agent Teams on top. Its backpressure gates (tests/lint reject incomplete work) are the one reusable idea |
| **harness-experimental** (1.1k stars) | Repo-context/contract layer, no execution engine; orthogonal |
| **Shipyard** | Not a framework, a comparison blog ([post](https://shipyard.build/blog/claude-code-multi-agent/)) |
| **LangGraph** | Real mature DAG engine but a general agent-graph substrate; nobody visibly builds a coding-orchestrator on it; the "build your own from scratch" reference point, not adoptable prior art |
| **gsd-pi lineage note** | Hard-reset to v1.0.0 with archived history ([opengsd.net](https://opengsd.net/)); not dead, re-baselined |

## (b) Differences vs our shape

| Dimension | dwarves-kit today | What the field does differently |
|---|---|---|
| Dependency representation | Implicit: flat fan-out needs pairwise disjointness; sequenced work is a linear chain; `depends SG-NN` parsed for wavefront ready-set | Everyone real uses an **explicit `depends_on`/`needs` list per task**, sometimes with implicit edges layered on (phase barriers, same-file-write ordering). We have no "B needs both A and C" representation at the dispatch layer |
| Ready-detection | Pre-computed waves (ADR-0030) | Two patterns: **static single-pass eligibility** (gsd-pi) vs **dynamic self-claim with auto-unblock** (CC Agent Teams: a task unblocks the instant its dep completes). The second is architecturally nicer for fan-in convergence |
| Concurrency cap | `WAVE_CAP=2` global | Same everywhere (gsd-pi `max_workers`, Gas Town `max_polecats`); we are not behind. spec-kit-schedule adds a per-agent cardinality cap tied to hallucination thresholds |
| Failure semantics | Undefined for fan-in/out (we refused the shape) | **Weakest-documented dimension industry-wide.** Best partials: Gas Town bisect-on-red, spec-kit-schedule freeze-and-replan-residual, ralph backpressure gates. Nobody documents "prune descendants of a failed node" as a named policy: a gap we could be first to nail cleanly |
| Merge/integration | Worktree per session, lead-mediated merge | Spectrum: fully automated (Multiclaude CI-pass=merge) to halt-on-conflict-for-human (gsd-pi). The transferable trick: **sequential merge in deterministic ID order even though execution was parallel** (gsd-pi), removes most conflict surface with zero conflict-resolution logic |
| Artifact passing between nodes | None (no fan-in yet); the brief's per-edge `HANDOFF-<id>.md` design anticipates it | CC Agent Teams **mailbox** (per-agent JSON inbox, validated, skip-malformed) is the cleanest concrete pattern for "B needs A's finding" without shared memory |
| Human gating | Understanding-gate/DEBT philosophy, decision-type pauses | Transferable: **plan-approval mode** (node read-only until lead approves) and **hooks on task-state transitions that can reject (exit 2)** |

## (c) Ranked PICKUP list

1. **Dynamic ready-queue with auto-unblock, not static waves.** Explicit `depends_on: [ids]` per task; the instant a dep flips done, recompute just that task's readiness. This is what makes real fan-in work (a join node with 3 parents needs no hand-authored wave boundary). Source: CC Agent Teams.
2. **Sequential merge order under parallel execution.** Run nodes concurrently in worktrees as today, but land to the integration branch one at a time in deterministic ID order. One-line policy on top of the existing worktree gate; removes most of the conflict surface. Source: gsd-pi git-strategy.
3. **Bisect-on-red for the merge queue.** When a batch of ready merges fails the gate, bisect to isolate the culprit, land the rest, block/retry only it. The most concrete failure-semantics idea in the sweep; natural once (2) exists. Source: Gas Town Refinery.
4. **File-footprint as a scheduling constraint, not just a pre-merge gate.** Extend the existing dispatch-gate pairwise check to gate DAG-node CONCURRENCY (same-file writers never run simultaneously), not just node admission. Source: spec-kit-schedule's file-conflict edges.
5. **Hook points on task-state transitions.** `TaskCreated`/`TaskCompleted`-style hooks that can reject a transition: "no node marks itself done without passing X" enforced once, not per-node. Source: CC Agent Teams hooks.

## (d) AVOID list

- **Pub/sub "hat"/event-topology as the dependency mechanism** (ralph): the graph becomes implicit in trigger-name wiring, the hidden coupling our explicit-gate philosophy exists to avoid.
- **Chaos + CI-as-ratchet, no coordination** (Multiclaude): legitimate for solo/high-trust, but trades away the auditability the gate system is built on.
- **"Queen-led hierarchy" / self-learning swarm claims** (ruflo): least-verifiable mechanisms in the sweep; copying the framing without the undisclosed implementation is cargo-culting marketing.
- **Scheduler-resolved merge conflicts.** Every framework with a real answer punts conflicts to a human or CI/bisection; that boundary is correctly placed everywhere we looked.
- **CP-SAT/MS-RCPSP solver before the simple ready-queue exists** (spec-kit-schedule): fine reference for WHICH constraints matter (skill caps, token budgets, file-conflict edges), but building a solver now optimizes scheduling before basic dependency fan-in even ships.

## Honesty note

Star count was not a proxy for scheduling rigor: the highest-star projects (ruflo 65.8k, BMAD 51k) are the worst-documented on these exact mechanics. The best concrete mechanisms came from a first-party doc (CC Agent Teams), a mid-size opinionated tool (gsd-pi ~950 stars), and a 2-star extension (spec-kit-schedule).
