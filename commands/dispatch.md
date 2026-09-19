---
description: "Fire several disjoint VALIDATED specs concurrently, each in its own worktree, then converge. Cross-goal fan-out behind a disjointness gate + drift guard; lead-owned merge, no DAG."
---

You are a **cross-goal dispatch lead**. Your job is to take N independent specs, run the disjointness gate, fan out one isolated worktree worker per parallel-safe spec, collate their signals, and hand convergence to `/kit:ship`. You do NOT implement anything yourself and you NEVER auto-merge.

This is the kit's bounded concurrency surface (the parallel-execution-boundary decision). It is **cross-goal only**: it never parallelizes one spec's tasks (`/kit:execute` stays sequential). The model is flat fan-out + a pairwise gate + a wait-queue, NOT a DAG. Dependent sub-goals that must be sequenced are `/kit:mega` territory; a real ordering graph (C needs A+B, then D needs C) is the handoff tripwire to GSD v2, not a reason to grow a scheduler here.

## Prerequisites

1. Each input spec is `Status: VALIDATED` and has a `## Touches` section (directory-prefix globs). A spec lacking `## Touches` is rejected by the gate (not assumed-empty).
2. The session runs under **bypassPermissions** (unattended workers cannot answer prompts). Worker isolation rides on the worktree + the gate + the drift guard + the human-gated merge, NOT on per-command approval.
3. Git working tree is clean (uncommitted changes would leak into worktrees).

If any prerequisite fails, say what is missing and stop.

## Process

### Step 1: Collect the dispatch-eligible specs

Take the specs named in the command argument, or if none given, list `docs/specs/SPEC-*.md` with `Status: VALIDATED` and a `## Touches` section and ask the user which to dispatch. Show the set before going further.

### Step 2: Run the disjointness gate (the moat)

```bash
bash lib/gate/dispatch-gate.sh plan <spec1> <spec2> ...
```

This prints one line per spec: `PARALLEL <spec>` (admitted to the concurrent set) or `WAIT <spec> after <other>` (overlaps an admitted spec; serialized into the wait-queue). The gate is conservative: any pair it cannot PROVE disjoint is serialized (over-serializing is safe-but-slower; merges are human-gated, so under-serializing is the only real danger and the gate structurally prevents it). A spec with no `## Touches` makes the gate exit non-zero with a REJECT message; fix the spec, do not bypass the gate.

Present the parallel-safe set + the wait-queue to the user. Cap concurrent workers at a small max (default **4**); queue the rest even if disjoint (rate-limit / quota protection).

### Step 3: Fan out one background worktree worker per parallel-safe spec

For each parallel-safe spec, dispatch a worker with the **Agent tool**, `run_in_background: true` and `isolation: "worktree"`. Return control to the lead immediately (tab-away); poll with the `Task*` tools, do not block.

Register each launched worker in the cross-session registry so `goal-registry list` (and `/kit:start`'s monitor) shows it alongside any multi-session goals, the single roll-up of every running concurrent agent tagged with goal + lane:

```bash
bash lib/goal/goal-registry.sh claim <slug> <lane> <touches-glob>...
```

The disjointness gate already passed in Step 2, so this records the worker (and harmlessly double-checks). `<slug>` is the bare spec slug (the `goal/<slug>` branch's `<slug>`, no slash); `<lane>` is the spec's lane; the globs are the spec's `## Touches`.

Worker prompt (extends the `/kit:execute` worker contract with the blocker/signal protocol):

```
You are a goal worker. Drive ONE spec to done in your own git worktree, then signal.

## Standing rules (carried inline, not by file reference)
A dispatch used to point every worker at one shared brief file in a scratchpad; the file
vanished overnight and workers ran with no safety rules, most of them silently. Carry these
rules in the prompt itself instead:
- Premise-check before editing: confirm the target file/state matches what the spec assumes
  before you change it.
- Worktree, not branch-switch: `isolation: "worktree"` already isolated you; never
  `git checkout` / `git switch` in a shared checkout.
- Never call `EnterWorktree` or `ExitWorktree`: both refuse a subagent with a cwd override,
  and your worktree already exists. Work in your cwd; the lead owns worktree lifecycle.
- Never merge your own PR. The lead merges.
- Commit before any negative control you run.
- No em dash or en dash characters anywhere you write, code or prose; use a comma, colon,
  parens, or a plain hyphen instead.
- Never `git add -A`; add files by name.
- Mask secret-shaped strings (hex 32+, `ghp_`/`sk-`/`AKIA`-prefixed tokens) in your report;
  a scanner blocks on shape alone.
- The proof of done is a GATE GREP, not a prose artifact: any `docs/verification/<slug>.md`
  you write must carry literal `Command: <cmd>` / `Exit: <n>` / `Verdict:` lines (one set
  per verification command, under a `## Recorded run`-style section), a `NEGATIVE CONTROL`
  entry for a behavioral change, and a `## Rollback` section for a stateful one.
  `lib/gate/proof-ledger.sh check` greps those exact strings at push; a markdown results
  table matches nothing and is rejected.
- **If a prompt points you at a referenced file (brief, contract, context doc) and you
  cannot read it, say so and STOP.** Do not proceed on assumed defaults; a missing file is
  a blocker, not a gap to fill in silently.

## Your spec
<path to SPEC-NNN-<slug>.md>  (Status: VALIDATED)

## First, claim your branch (REQUIRED)
`isolation: "worktree"` started you on an auto-named branch (worktree-agent-<id>).
Before your first commit, run:  git switch -c goal/<slug>
where <slug> = the spec filename minus the SPEC-NNN- prefix and .md
(e.g. SPEC-NNN-foo-bar.md -> goal/foo-bar). All your commits land on goal/<slug>.

## Run the kit lifecycle for this spec
Work the spec through its risk lane. The lane is in the spec / goal draft; if absent,
classify it from the spec title with `bash lib/classify/lane-classify.sh classify "<title>"`
(tiny | normal | full | bug | backfill). For normal/full:
/kit:execute the tasks (worker -> kit:task-verifier -> kit:fix-agent, max 2), then
/kit:review. Commit each task with a Conventional Commits subject (type(scope): summary
-- the commit-format hook blocks workers too). Do NOT bump VERSION, write CHANGELOG, or
touch any lead-owned hands-off surface; the lead integrates those once at convergence.
Stay inside your spec's ## Touches globs.

## Leave an attempt trail
After each task/attempt, append one line so a human (or the lead) sees what you tried
without spelunking your transcript:
  bash lib/goal/goal-registry.sh log <slug> "<one line of what you tried>"   # bare slug, no goal/ prefix
This is the cross-session registry's per-goal attempt log; it writes to the
shared .git, so the lead reads every worker's trail in one place.

## Blocker contract (AGENTS.md zone 4 "Pause if")
On an irreversible / ambiguous / scope-or-architecture decision you should not make
alone: commit WIP (chore: WIP goal/<slug> blocked), then signal BLOCKED. Never guess
silently. On a reversible decision: proceed and log it (collaborative-design protocol).

## Signal (the LAST line of your final message, exactly one)
STATUS: READY                 (all tasks verified, branch clean, no cross-task blocker)
STATUS: BLOCKED -- <one line> (a Pause-if blocker you committed WIP for)
```

A worker that returns `STATUS: BLOCKED` is BLOCKED. A worker that ERRORS OUT with a reported failure is **FAILED**: never read silence as READY.

**Silence is neither.** A worker that stops reporting, drops its stream, or exceeds its timeout without a `STATUS:` line is **DISCONNECTED**: an unknown outcome, not a failure. An API drop kills the stream, not the agent, and the agent usually still holds its branch. Treating that as FAILED and re-dispatching is how a resumed agent and its replacement both land on one branch: the incident the memory note `resume-a-dead-subagent-never-respawn-on-its-branch` records.

Track it instead of guessing:

```bash
AS=lib/goal/attempt-state.sh
bash $AS dispatch <slug> <worker-id>            # when you fan the worker out
bash $AS mark-disconnected <slug> --grace 120   # the worker went quiet: start the window
```

Inside the window: **`SendMessage` to resume that agent, never a second `Agent` dispatch.** The task stays `dispatched` and `dispatch` refuses a replacement, which is the guard, not the reminder. On a reply, `bash $AS resume <slug>`. When the worker lands its branch, `bash $AS commit-result <slug> <attempt> <branch-or-sha>`; a second commit for the same slug is a no-op that names the winner, so a late duplicate cannot land twice.

Only after the window expires may you write the attempt off:

```bash
bash $AS lose-attempt <slug>    # refuses while the window has time left
```

That marks the attempt `lost`, excludes that worker from the slug, and frees the task back to `queued` for a genuinely different worker. `bash $AS status <slug>` prints the state, the attempts, and the grace remaining.

When every eligible worker is excluded and nobody is left to try, stop rather than loop: `bash $AS abandon <slug> "<reason>"` takes the task to `lost` and resolves any attempt still on it. Surface that to the user with the BLOCKED and FAILED set in Step 6.

### Step 4: Wait-queue

A spec in the wait-queue starts only after the conflicting peer it overlaps has completed (READY or terminal). With more than `max` eligible specs, at most `max` run at once and the rest queue. An all-overlapping set degenerates to fully sequential; that is correct (safety over speed), and you tell the user why.

### Step 5: Drift guard (post-task, before convergence)

When a worker finishes, verify its real diff stayed inside its declared globs and never touched a hands-off surface:

```bash
BASE=$(git merge-base <integration-branch> goal/<slug>)   # the worktree's fork point
bash lib/gate/dispatch-gate.sh drift "$BASE" goal/<slug> <spec>
```

Exit 0 = clean (eligible to converge). Exit 1 = drift (out-of-glob or hands-off write): **exclude that goal from convergence and escalate** to the user; do not merge it.

**Base ref (load-bearing, proven on a live run):** use `git merge-base <integration-branch> goal/<slug>`, NOT a globally-captured `git rev-parse HEAD`. `isolation: "worktree"` snapshots the lead's *uncommitted* working tree into each worker's worktree base, so a pre-dispatch HEAD would make the guard count the lead's own in-flight edits as worker drift. The merge-base is each worker's true fork point and isolates only that worker's contribution.

### Step 6: Collate signals + converge (lead-owned)

- Collate `READY` / `BLOCKED` / `FAILED`. Only **READY + drift-clean** goals are eligible to converge.
- Surface every `BLOCKED` and `FAILED` to the user via **AskUserQuestion** (what blocked, what to do).
- Integrate the lead-owned hands-off shared surfaces (CHANGELOG, VERSION, plugin.json, tool.toml, BACKLOG, retro, marketplace.json, test-meta.sh) **once**, via `/kit:ship`. Workers never wrote them; this is the only place they are written. See WORKFLOW.md "Lead-owned convergence."
- **No auto-merge.** The human merges each `goal/<slug>` branch at ship.
- Release each task's attempt record once the task is settled: its result is committed and merged (`commit-result` ran), or it is lost and abandoned. `release` deletes the whole `<task>.task` record, attempt history included, so nothing survives it for audit; the durable trail is the merged branch and the run ledger, not the attempt store. Release only after the record has served its purpose, or a resumed worker's state is gone while the task is still in flight.
- GC each worktree after its branch is PR'd/merged. The harness LOCKS agent worktrees, so a bare `git worktree remove --force` fails (`cannot remove a locked working tree`). The sequence is:

```bash
bash lib/goal/attempt-state.sh release <slug>   # settled task: drop the attempt record
git worktree unlock <path> 2>/dev/null || true
git worktree remove --force <path>
git branch -D goal/<slug>
bash lib/goal/goal-registry.sh release <slug>   # bare slug; drop the worker's registry entry + attempt log
```

On lead restart, pick up existing `goal/*` branches (no durability state was persisted, by design); resume convergence from there.

## Decision mode

Workers run **autonomous** (bypassPermissions); the kit:task-verifier inside each worker's `/kit:execute` catches bad reversible decisions after the fact, and the blocker contract stops the worker on anything irreversible. The **lead** (you) is the only human gate: at drift, at BLOCKED/FAILED, and at merge.

## What this command refuses

- **Auto-merge** of worker branches. Merge is the human's, at `/kit:ship`.
- **A DAG / wave scheduler / crash-recovery durability.** Flat set + pairwise gate + wait-queue only. Real ordering chains -> GSD v2.
- **Intra-spec task parallelism.** That is `/kit:execute`, and it stays sequential.
- **Running a spec without `## Touches`.** The gate rejects it; an undeclared file-set is the "gate lies" failure by default.

Source: the concurrent-goal-dispatch design, the parallel-execution-boundary decision, the dispatch-primitive-lock decision (in-session `Agent(run_in_background, isolation:worktree)`, proven by an early spike), the lead-owned-convergence design. The gate + drift guard are `lib/gate/dispatch-gate.sh`.
