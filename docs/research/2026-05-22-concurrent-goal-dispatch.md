---
title: Concurrent goal dispatch (parallelism model for the kit) + the gsd-2 correction
date: 2026-05-22
source: maintainer Q&A session; live verification of gsd-build/gsd-2 via gh API; claude-code-guide check of native parallel-agent primitives
feeds: a future SPEC for concurrent goal dispatch in /kit:execute
benchmarked_against: docs/PHILOSOPHY.md (shallow-and-wide, one-session, runtime-integration boundary), SPEC-010 (worktree concurrency), SPEC-002 (v2 candidates), README.md
clarifies: README.md + docs/PHILOSOPHY.md (the "GSD v1.4x" plugin vs "GSD v2" runtime naming implied one product; disambiguated 2026-05-22). NOTE: an earlier draft of this note claimed several docs "label gsd-2 as a plugin"; on review that was an overstatement (see section 1).
status: active
---

# Concurrent goal dispatch

This note captures a maintainer discussion that started as "is gsd-2 a separate app?" and converged on a concrete parallelism model for the kit. Two outputs: (1) a factual correction about gsd-2 that several existing kit docs get wrong, (2) a decided execution model for "fire a goal, walk away, get it done concurrently," with its build scope and the DAG question answered.

---

## TL;DR

- **gsd-2 is NOT a Claude Code plugin.** It is a standalone coding agent (npm `gsd-pi` v3.x, TypeScript, built on the Pi SDK, ~7.7k stars). It has its own harness, CLI, VS Code extension, web UI. The "29 skills/12 agents/2 hooks" plugin is gsd **v1** (`gsd-build/get-shit-done`), a different piece of software with the same brand. The kit docs mostly already distinguish them (PHILOSOPHY says "Pi SDK runtime"); the real defect was the *naming*: "GSD v1.4x" (plugin) vs "GSD v2" (runtime) reads like one product's version bump. Disambiguated in README + PHILOSOPHY 2026-05-22.
- **"Runtime" = the execution engine that runs a task DAG unattended**: schedule, dispatch, track state, recover from crashes, auto-advance. Today the kit's runtime IS Claude Code (one session); the kit rides on top as guidance + guardrails.
- **There are 7 real ways to get parallelism**, not 4. "Sequential" is the baseline (not parallelism); "worktree" is an isolation primitive (not an executor). They split into ATTENDED-speed vs WALK-AWAY-autonomy, which are different axes the menu kept blurring.
- **Decided model (maintainer answers: tab-away + several concurrent):** native single-lead orchestrator that fans out N background worktree subagents, each running the kit's spec-first V-model lifecycle, escalating to the human only on blockers. No gsd-2, no in-kit runtime.
- **Kit build scope is three thin things:** (1) fan-out dispatch, (2) a parallel-safety / file-disjointness check (plan layer, the moat), (3) a blocker-escalation contract in the worker. No scheduler, no state machine.
- **Do we need a DAG? No.** For independent goals the DAG degenerates to a flat set + a pairwise interference gate + a wait-queue. The moment a real DAG (topological scheduling, wave execution) is required, you have crossed back into runtime territory (the rejected Option 4); that need is the tripwire to hand off to gsd-2, not to build a scheduler.

---

## 1. The gsd-2 correction (factual)

Verified live via `gh api repos/gsd-build/gsd-2`:

| Field | Value |
|---|---|
| npm package | `gsd-pi`, v3.0.0 |
| Language | TypeScript, own runtime (`bin: gsd`, `gsd-cli`) |
| Harness | Pi SDK (`badlogic/pi-mono`), own agent loop |
| Surfaces | CLI + TUI + VS Code extension + web UI + studio |
| Model-agnostic | Bedrock, OpenAI Codex, Gemini, etc. direct |
| Created / stars | 2026-03-11 / ~7.7k |

README, verbatim: *"The original GSD went viral as a prompt framework for Claude Code... This version is different. GSD is now a standalone CLI built on the Pi SDK, which gives it direct TypeScript access to the agent harness itself."*

So gsd-2 is a **Claude Code alternative/competitor**, a separate app that runs its own agent loop. The earlier "it's a CC plugin (29 skills/12 agents/2 hooks)" framing describes gsd **v1** (`gsd-build/get-shit-done`). The two share a brand and are different software.

What was actually checked, doc by doc (the "mislabel" turned out narrower than first claimed):

| Doc | gsd-2 reference | Verdict |
|---|---|---|
| `docs/PHILOSOPHY.md` | "GSD v2 (Pi SDK runtime)", "custom TypeScript runtime", "requires Pi SDK" | already correct; added a one-time "GSD v2 = separate product" disambiguation note |
| `README.md` line ~208 | "use GSD v2 or Agent Teams" | clarified GSD v2 = standalone gsd-build/gsd-2 / gsd-pi runtime |
| `README.md` Credits | "GSD / get-shit-done" (v1 plugin) | correct for v1; relabeled "GSD v1" + added a line distinguishing v2 |
| `docs/specs/SPEC-010`, `docs/decisions/0010` | gsd-2 cited as *external* orchestration / worktree lineage | already correct (treat gsd-2 as external); left as-is |
| `docs/specs/SPEC-002` | only references GSD v1.42.1 / v1.43-rc2 (the plugin) | correct; left as-is |
| `docs/research/2026-05-20-orchestration-deep-scan.md` | per-repo row = GSD v1.42.1 plugin (correct); "route to GSD v2" (correct) | not a mislabel; left as-is (dated snapshot) |

Net: no doc flatly called gsd-2 a plugin. The only real fix was disambiguating the v1-vs-v2 *naming* in the two reader-facing docs (README, PHILOSOPHY). The worktree-per-active-spec lineage point stands everywhere it appears.

---

## 2. What "runtime" means here

Two layers, kept separate because the whole discussion blurred them:

```
PLAN layer     "what to do, in what order, gated how"   ← the kit produces this
RUNTIME layer  "actually do it, unattended"             ← who owns this?
               schedule → dispatch → track state →
               detect stuck → recover from crash → merge
```

Today the runtime is Claude Code (one session); the kit is a passenger. Everything in gsd-2's changelog (single-writer engine v3 control plane, dispatch adapter, stuck-loop detection, provider-500 retry, crash/worktree recovery, auto-advance) IS a runtime. That is why "borrow gsd-2" and "build your own" are the two runtime-owning options.

**Building a runtime is hard in a specific way:** the scheduler core is a weekend; the operational reliability (crash recovery, stuck detection, per-provider error handling, cross-platform sqlite quirks) is months and never "done". gsd-2 being on v3 with a dedicated SDK and still shipping these fixes is the evidence. For the kit it is worse than hard: it breaks the bash+jq, shallow-and-wide thesis and the runtime-integration boundary in PHILOSOPHY.

---

## 3. The full parallelism menu (7 options)

"Sequential" = the zero point (not an option). "Worktree" = isolation primitive that layers under most options (not an executor).

| # | Option | Native? | Attended / Unattended | Persistence + recovery | Kit effort | Walk-away? |
|---|---|---|---|---|---|---|
| 1 | Concurrent subagents (N Agent calls / turn) | native | attended | none | ~0 | no |
| 2 | `/batch` (mechanical fan-out, worktree+PR per task)* | native | attended | none | low | no |
| 3 | Agent Teams (coordinated teammates, one goal) | native, experimental | attended | none (lead dies → team dies) | low-med | no |
| 4 | Background multi-session (`claude agents` / Agent View) | native | semi | per-session, no coordination | low | partial |
| 5 | External runtime handoff (gsd-2 / Nimbalyst / Conductor / Ultrapilot) | external | unattended | full | med | yes |
| 6 | In-kit DAG executor (build your own) | you build | unattended | if you build it | very high | yes |
| 7 | OS-level fan-out (CI matrix / cron / `xargs -P claude --print`) | external | unattended | crude | low-med | partial |

\* `/batch` reported by claude-code-guide; verify it exists on the target CC version before relying on it.

Grouping that matters:

```
SPEED ONLY (parallel, attended, no durability):   1, 2, 3, 4
WALK-AWAY (parallel + persistence + recovery):     5, 6, 7
```

Native Claude Code has **no cross-session persistence or crash recovery**. `/goal` and `/loop` live in one session and die on exit. `/schedule` routines are cloud cron, not a local runtime. True walk-away needs the Agent SDK or an external runtime.

Agent Teams specifics (claude-code-guide, current as of 2026-05-22): real but **experimental, off by default** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), needs CC v2.1.32+, 3-5 teammates recommended, **not resumable** (`/resume` and `/rewind` don't restore teammates; lead dies → team dies), teammates get **no automatic worktree isolation** and **no auto-merge**, token cost scales linearly.

---

## 4. The decided model

Maintainer requirement, in their words: *"when I've done requirement clarification, I can shoot a goal and then you will spawn new worktree and get it done, follow v-model, sdd (spec-first), only loop me when you need... concurrently."*

This is **not** Agent Teams (many workers, one goal, attended). It is **one autonomous worker per goal, each in its own worktree, fire-and-step-away, escalate only on blockers, several in flight at once.** Name: **goal-scoped autonomous worktree session.**

Maintainer answers to the two architecture-flipping questions:
- Away-ness: **tab-away, session stays open** (rules out needing gsd-2/durability).
- Concurrency: **several goals concurrently** (rules out single-session-only).

Decided shape:

```
        YOU (interactive)
          │  /kit:think + /kit:spec  →  N specs (SDD, spec-first)
          ▼
   ┌─────────────────────────────────────────────┐
   │  LEAD SESSION  (stays open, you tab away)     │
   │  - reads N specs, checks file-disjointness    │
   │  - fans out independent goals                 │
   └───────┬───────────────┬───────────────┬──────┘
           ▼               ▼               ▼
      subagent A       subagent B       subagent C      ← run_in_background
      worktree A       worktree B       worktree C      ← isolation: worktree
      worker→verify    worker→verify    worker→verify   ← V-model gates
      →fix (max 2)     →fix (max 2)     →fix (max 2)
           │               │               │
           └──── BLOCKED? ─┴──── BLOCKED? ─┘
                           ▼
              LEAD pauses → AskUserQuestion(you)   ← "only loop me when you need"
                           │
                  done → branch/PR per goal, lead reports
```

Runs on tools that exist today: background agents + `isolation: worktree` + AskUserQuestion. Not a runtime.

### Kit build scope (three thin things)

| # | Build | Layer | Why |
|---|---|---|---|
| 1 | Fan-out dispatch (extend `/kit:execute` or new `/kit:dispatch`) | execution | launch N background worktree subagents from N independent specs |
| 2 | Parallel-safety check (file-disjointness + dep tag) | plan (the moat) | only run goals concurrently when they touch disjoint files; else serialize |
| 3 | Blocker-escalation contract (worker prompt rule) | execution | escalate irreversible/ambiguous, proceed on reversible (the Vibe-Coding rubric, already written) |

No scheduler, no state machine. Shallow-and-wide preserved.

### Caveats that bite this exact model

1. **No durability (accepted).** Lead dies → orchestration lost. Mitigation at zero cost: subagents commit to their worktree branch frequently; progress survives as commits; restart the lead, it picks up branches.
2. **Merge is the sharp edge.** Concurrency is only safe on disjoint files. Build-item #2 is non-negotiable; overlapping files must serialize, not parallelize.
3. **Blocker quality decides whether "loop me only when needed" holds.** Too much escalation = babysitting; too little = silent wrong defaults. Port the existing CLAUDE.md rubric into the worker contract (build-item #3).

### Naming flag

Backlog lists this as "Agent Teams parallel task dispatch in /execute" (README line ~264, SPEC-002 line ~150). It is **not** Agent Teams; it is background-subagent fan-out. Rename so the wrong (coordinated-teammates, attended) thing doesn't get built.

---

## 5. Do we need a DAG?

**No, not for this solution.** A DAG (with topological sort + wave scheduling) is for many tasks with rich inter-dependencies, and a DAG *executor* is a scheduler, which is a runtime, which is the rejected Option 4. The chosen model parallelizes across **independent goals**, so the structure degenerates:

```
fired goals → for each pair: do declared file-globs overlap?
            → any goal tagged "blocked-by: <other>"?
   NO overlap AND NO blocker  → dispatch concurrently now
   overlap OR blocker         → queue; re-check when the blocker finishes
```

That is an **interference check + a wait-queue**, O(n²) pairwise over a handful of goals. No topological sort, no graph library, no acyclicity invariant, no DAG executor.

Distinguish the levels:
- **Across goals (this model):** flat set + disjointness gate + wait-queue. No DAG.
- **Within one spec (intra-spec task parallelism):** would need a task dependency DAG. Out of scope; the kit runs spec tasks sequentially by design.
- **Rich goal ordering chains (C needs A+B merged, D needs C...):** that is genuine DAG scheduling = a runtime = Option 4 (rejected) or hand off to gsd-2 (Option 5).

**The rule:** "we need a DAG" is the tripwire that says you have outgrown the native model. When that day comes, hand execution to gsd-2; do not build a scheduler inside the kit. Until then, build the disjointness gate, not a graph.

---

## 6. Agent Teams vs the decided model (deferred, not discarded)

Earlier in this session the proposed answer was "bounded parallelism via Agent Teams" (menu option 3). It is the wrong tool for *this* requirement but the right tool for a different one the kit may hit later. Recorded here so the distinction is not relitigated, and so Agent Teams is reconsidered on purpose, not by accident.

One-line difference: **Agent Teams parallelizes the work inside ONE goal (collaboration); the decided model parallelizes across MANY independent goals (independence).** Collaboration needs coordination; independence needs only isolation, which is why the decided model is the cheaper, shallow-and-wide one.

```
AGENT TEAMS (proposed, deferred)        DECIDED MODEL (background fan-out)
────────────────────────────────       ─────────────────────────────────
          ONE goal                      goal A    goal B    goal C   (independent specs)
            │                             │         │         │
     ┌──────┼──────┐                      ▼         ▼         ▼
     ▼      ▼      ▼                    worker A  worker B  worker C  (1 each, own worktree)
   mate1  mate2  mate3                  verify→   verify→   verify→
     │  shared task │                   fix(≤2)   fix(≤2)   fix(≤2)
     └── list + msg ┘                      └─── blocked? ──┘
     (talk, unblock, same tree)                  ▼
                                         lead asks YOU (else tab away)

   many workers, 1 goal                 1 worker per goal, N goals
   COORDINATE                           DON'T TALK (can't interfere by design)
```

| Axis | Agent Teams (deferred) | Decided model (background fan-out) |
|---|---|---|
| Unit of parallelism | tasks *within* one goal | whole *goals*, across specs |
| Workers per goal | many (3-5 teammates) | exactly one |
| Coordination | tight: shared task list, dependency edges, mailbox messaging | none: workers never talk; lead only gates dispatch + collects blockers |
| Why it's safe | lead must hand-partition files so teammates don't overwrite | hard worktree isolation + file-disjointness gate before dispatch |
| Isolation | none by default (shared tree, overwrite warning) | `isolation: worktree` per worker (separate branch) |
| Needs a DAG? | yes: the dependency edges *are* an intra-goal DAG the harness schedules | no: flat set + pairwise disjointness check + wait-queue |
| Verification | native `TaskCompleted` / `TeammateIdle` gate hooks (exit 2) | the kit's existing worker→verify→fix(≤2) run *inside* each worktree |
| Native primitive | experimental Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, v2.1.32+) | stable: background subagents + worktree + AskUserQuestion |
| Attended? | yes, you watch the lead synthesize | no, tab away; pulled back only on a blocker |
| Merge | implicit (same tree, collisions possible mid-flight) | explicit branch/PR per goal; disjointness keeps merges clean |
| Durability | none, not resumable, no auto-merge | none, but mitigated: workers commit to their branch, progress survives as commits |

(Raw Agent Teams specifics, version-gated and experimental, are in section 3.)

### Why the decided model wins for "fire N goals, tab away"

1. **The requirement is inter-goal; Agent Teams solves intra-goal.** "Fire a goal, tab away, several concurrently" is N independent objectives, not one objective split among helpers. Agent Teams answers a question we did not ask.
2. **Independence is cheaper than coordination.** Agent Teams' shared task list, dependency edges, messaging, and DAG all exist to make workers cooperate on shared state. The decided model deletes the shared state (separate worktrees), so there is nothing to coordinate: no DAG, no scheduler, no team protocol. That is the difference between three thin build items and a graph plus an experimental flag.
3. **Isolation beats partitioning.** Agent Teams relies on the lead correctly carving files among teammates in a shared tree, and the docs warn that getting it wrong causes overwrites. The decided model makes interference structurally impossible (separate worktrees) and only allows concurrency when files are provably disjoint. Safety by construction, not by careful instruction.

### When to reconsider Agent Teams (the tripwire)

Agent Teams comes back the day a *single spec* needs its **own internal tasks** run in parallel with real dependencies, i.e. the intra-spec task DAG that section 5 fences as out of scope (the kit runs spec tasks sequentially by design today). Note this is a *different* tripwire from section 5's "rich cross-goal ordering chain → gsd-2":

- cross-**goal** ordering chains (C needs A+B merged) → external runtime (gsd-2), section 5.
- intra-**goal** task collaboration (one spec's tasks must cooperate, attended) → Agent Teams, this section.

Until a spec actually needs its tasks to cooperate, leave Agent Teams off (experimental, non-resumable, no worktree isolation by default). It is **deferred, not discarded**, and explicitly **not on the ID-035 path**.

---

## Open follow-ups

- Write the SPEC for concurrent goal dispatch (the three build items, the disjointness rule, the blocker contract, V-model gates). This is backlog **ID-035**; the disjoint-file fan-out is the build, NOT a DAG executor.
- ~~Fix the gsd-2 "plugin" mislabel~~ DONE 2026-05-22: disambiguated v1/v2 naming in README + PHILOSOPHY; SPEC-010 / ADR-0010 / SPEC-002 / deep-scan were already correct (see section 1 table).
- The in-kit DAG executor (Option 4) is parked in `_meta/BACKLOG.md` parking lot with its tripwire condition. Revisit only when goals develop real ordering chains; then hand off to GSD v2, do not build a scheduler.
- Agent Teams (menu option 3) is **deferred, not discarded** (see section 6). Reconsider only on the intra-spec task-parallelism tripwire (one spec's own tasks must cooperate, attended), distinct from the cross-goal-ordering tripwire that routes to gsd-2. Not on the ID-035 path.
- Backlog naming: the v2-candidate "Agent Teams parallel task dispatch" was already promoted to ID-035 (2026-05-22 re-eval). ID-035's title says "parallel execution", not "Agent Teams", good. Confirm the SPEC, when written, frames it as background-subagent fan-out, not coordinated teammates.
