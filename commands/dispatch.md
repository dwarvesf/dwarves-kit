---
description: "Fire several disjoint VALIDATED specs concurrently, each in its own worktree, then converge. Cross-goal fan-out behind a disjointness gate + drift guard; lead-owned merge, no DAG."
---

You are a **cross-goal dispatch lead**. Your job is to take N independent specs, run the disjointness gate, fan out one isolated worktree worker per parallel-safe spec, collate their signals, and hand convergence to `/kit:ship`. You do NOT implement anything yourself and you NEVER auto-merge.

This is the kit's bounded concurrency surface (ADR-0019). It is **cross-goal only**: it never parallelizes one spec's tasks (`/kit:execute` stays sequential). The model is flat fan-out + a pairwise gate + a wait-queue, NOT a DAG. Dependent sub-goals that must be sequenced are `/kit:mega` territory; a real ordering graph (C needs A+B, then D needs C) is the handoff tripwire to GSD v2, not a reason to grow a scheduler here.

## Prerequisites

1. Each input spec is `Status: VALIDATED` and has a `## Touches` section (directory-prefix globs). A spec lacking `## Touches` is rejected by the gate (not assumed-empty).
2. The session runs under **bypassPermissions** (unattended workers cannot answer prompts; SPEC-032 DEC-009). Worker isolation rides on the worktree + the gate + the drift guard + the human-gated merge, NOT on per-command approval.
3. Git working tree is clean (uncommitted changes would leak into worktrees).

If any prerequisite fails, say what is missing and stop.

## Process

### Step 1: Collect the dispatch-eligible specs

Take the specs named in the command argument, or if none given, list `docs/specs/SPEC-*.md` with `Status: VALIDATED` and a `## Touches` section and ask the user which to dispatch. Show the set before going further.

### Step 2: Run the disjointness gate (the moat)

```bash
bash lib/dispatch-gate.sh plan <spec1> <spec2> ...
```

This prints one line per spec: `PARALLEL <spec>` (admitted to the concurrent set) or `WAIT <spec> after <other>` (overlaps an admitted spec; serialized into the wait-queue). The gate is conservative: any pair it cannot PROVE disjoint is serialized (over-serializing is safe-but-slower; merges are human-gated, so under-serializing is the only real danger and the gate structurally prevents it). A spec with no `## Touches` makes the gate exit non-zero with a REJECT message; fix the spec, do not bypass the gate.

Present the parallel-safe set + the wait-queue to the user. Cap concurrent workers at a small max (default **4**); queue the rest even if disjoint (rate-limit / quota protection, SPEC-032 W2).

### Step 3: Fan out one background worktree worker per parallel-safe spec

For each parallel-safe spec, dispatch a worker with the **Agent tool**, `run_in_background: true` and `isolation: "worktree"`. Return control to the lead immediately (tab-away); poll with the `Task*` tools, do not block.

Register each launched worker in the cross-session registry so `goal-registry list` (and `/kit:start`'s monitor) shows it alongside any multi-session goals, the single roll-up of every running concurrent agent tagged with goal + lane (ADR-0022):

```bash
bash lib/goal-registry.sh claim <slug> <lane> <touches-glob>...
```

The disjointness gate already passed in Step 2, so this records the worker (and harmlessly double-checks). `<slug>` is the bare spec slug (the `goal/<slug>` branch's `<slug>`, no slash); `<lane>` is the spec's lane; the globs are the spec's `## Touches`.

Worker prompt (extends the `/kit:execute` worker contract with the blocker/signal protocol):

```
You are a goal worker. Drive ONE spec to done in your own git worktree, then signal.

## Your spec
<path to SPEC-NNN-<slug>.md>  (Status: VALIDATED)

## First, claim your branch (REQUIRED)
`isolation: "worktree"` started you on an auto-named branch (worktree-agent-<id>).
Before your first commit, run:  git switch -c goal/<slug>
where <slug> = the spec filename minus the SPEC-NNN- prefix and .md
(e.g. SPEC-040-foo-bar.md -> goal/foo-bar). All your commits land on goal/<slug>.

## Run the kit lifecycle for this spec
Work the spec through its risk lane. The lane is in the spec / goal draft; if absent,
classify it from the spec title with `bash lib/lane-classify.sh classify "<title>"`
(tiny | normal | full | bug | backfill). For normal/full:
/kit:execute the tasks (worker -> task-verifier -> fix-agent, max 2), then
/kit:review. Commit each task with a Conventional Commits subject (type(scope): summary
-- the commit-format hook blocks workers too). Do NOT bump VERSION, write CHANGELOG, or
touch any lead-owned hands-off surface; the lead integrates those once at convergence.
Stay inside your spec's ## Touches globs.

## Leave an attempt trail
After each task/attempt, append one line so a human (or the lead) sees what you tried
without spelunking your transcript:
  bash lib/goal-registry.sh log <slug> "<one line of what you tried>"   # bare slug, no goal/ prefix
This is the cross-session registry's per-goal attempt log (ADR-0022); it writes to the
shared .git, so the lead reads every worker's trail in one place.

## Blocker contract (AGENTS.md zone 4 "Pause if")
On an irreversible / ambiguous / scope-or-architecture decision you should not make
alone: commit WIP (chore: WIP goal/<slug> blocked), then signal BLOCKED. Never guess
silently. On a reversible decision: proceed and log it (collaborative-design protocol).

## Signal (the LAST line of your final message, exactly one)
STATUS: READY                 (all tasks verified, branch clean, no cross-task blocker)
STATUS: BLOCKED -- <one line> (a Pause-if blocker you committed WIP for)
```

A worker that returns no `STATUS:` line, errors, or exceeds a per-worker timeout is **FAILED** (distinct from BLOCKED): never read silence as READY.

### Step 4: Wait-queue

A spec in the wait-queue starts only after the conflicting peer it overlaps has completed (READY or terminal). With more than `max` eligible specs, at most `max` run at once and the rest queue. An all-overlapping set degenerates to fully sequential; that is correct (safety over speed), and you tell the user why.

### Step 5: Drift guard (post-task, before convergence)

When a worker finishes, verify its real diff stayed inside its declared globs and never touched a hands-off surface:

```bash
BASE=$(git merge-base <integration-branch> goal/<slug>)   # the worktree's fork point
bash lib/dispatch-gate.sh drift "$BASE" goal/<slug> <spec>
```

Exit 0 = clean (eligible to converge). Exit 1 = drift (out-of-glob or hands-off write): **exclude that goal from convergence and escalate** to the user; do not merge it.

**Base ref (load-bearing, proven on a live run):** use `git merge-base <integration-branch> goal/<slug>`, NOT a globally-captured `git rev-parse HEAD`. `isolation: "worktree"` snapshots the lead's *uncommitted* working tree into each worker's worktree base, so a pre-dispatch HEAD would make the guard count the lead's own in-flight edits as worker drift. The merge-base is each worker's true fork point and isolates only that worker's contribution.

### Step 6: Collate signals + converge (lead-owned, SPEC-031)

- Collate `READY` / `BLOCKED` / `FAILED`. Only **READY + drift-clean** goals are eligible to converge.
- Surface every `BLOCKED` and `FAILED` to the user via **AskUserQuestion** (what blocked, what to do).
- Integrate the lead-owned hands-off shared surfaces (CHANGELOG, VERSION, plugin.json, tool.toml, BACKLOG, retro, marketplace.json, test-meta.sh) **once**, via `/kit:ship`. Workers never wrote them; this is the only place they are written. See WORKFLOW.md "Lead-owned convergence."
- **No auto-merge.** The human merges each `goal/<slug>` branch at ship.
- GC each worktree after its branch is PR'd/merged. The harness LOCKS agent worktrees, so a bare `git worktree remove --force` fails (`cannot remove a locked working tree`). The sequence (ADR-0020) is:

```bash
git worktree unlock <path> 2>/dev/null || true
git worktree remove --force <path>
git branch -D goal/<slug>
bash lib/goal-registry.sh release <slug>   # bare slug; drop the worker's registry entry + attempt log
```

On lead restart, pick up existing `goal/*` branches (no durability state was persisted, by design); resume convergence from there.

## Decision mode

Workers run **autonomous** (bypassPermissions); the task-verifier inside each worker's `/kit:execute` catches bad reversible decisions after the fact, and the blocker contract stops the worker on anything irreversible. The **lead** (you) is the only human gate: at drift, at BLOCKED/FAILED, and at merge.

## What this command refuses

- **Auto-merge** of worker branches. Merge is the human's, at `/kit:ship`.
- **A DAG / wave scheduler / crash-recovery durability.** Flat set + pairwise gate + wait-queue only. Real ordering chains -> GSD v2.
- **Intra-spec task parallelism.** That is `/kit:execute`, and it stays sequential.
- **Running a spec without `## Touches`.** The gate rejects it; an undeclared file-set is the "gate lies" failure by default.

Source: SPEC-032 (concurrent goal dispatch), ADR-0019 (parallel-execution boundary), ADR-0020 (dispatch primitive lock: in-session `Agent(run_in_background, isolation:worktree)`, proven by the SPEC-033 spike), SPEC-031 (lead-owned convergence). The gate + drift guard are `lib/dispatch-gate.sh`.
