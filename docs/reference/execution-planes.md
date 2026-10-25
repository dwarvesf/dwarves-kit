# Execution planes

The kit runs agents four different ways: the orchestrator, the overnight queue, `/kit:dispatch`
and the gauntlet. The board sits beside them and is not an executor. Two of the four live in the
same directory and are separate engines, which is the single most confusing thing in the layout.
This doc is the map.

`docs/reference/architecture.md` owns each component's internals. This doc owns the comparison: what
each plane is for, how they hand off, where they deliberately do not connect, and which one
to reach for.

## The four planes, plus the board

```
                        ┌──────────────────────────────────────────┐
                        │  BOARD   (not an executor)               │
                        │  lib/board/     rows, states, admission  │
                        │                 runs no agent at all     │
                        └───────────────┬──────────────────────────┘
                                        │ a row carries #queue{repo=,pointer=}
                        ┌───────────────┴──────────────┐
                        ▼                              ▼
        ┌───────────────────────────┐   ┌──────────────────────────────┐
        │ ORCHESTRATOR              │   │ QUEUE                        │
        │ lib/queue/orchestrate.sh  │   │ lib/queue/queue.sh           │
        │                           │   │                              │
        │ headless `claude -p`      │   │ REAL interactive `claude`,   │
        │ one fresh session per     │   │ driven by typing into a      │
        │ sub-goal, waves of them   │   │ tmux window, one row at a    │
        │ running concurrently      │   │ time                         │
        └───────────────────────────┘   └──────────────────────────────┘
                        │                              │
                        └──────────────┬───────────────┘
                                       ▼
                        ┌──────────────────────────────┐
                        │ a branch, a PR, a journal row│
                        └──────────────────────────────┘

        ┌──────────────────────────────────────────────────────────┐
        │ /KIT:DISPATCH   commands/dispatch.md                      │
        │                                                           │
        │ the lead session fans out Agent-tool workers, one         │
        │ worktree per disjoint VALIDATED spec. No board row, no    │
        │ queue; the lead converges through /kit:ship.              │
        └──────────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────────────────┐
        │ GAUNTLET      tests/gauntlet/cleanroom/                   │
        │                                                           │
        │ a DISPOSABLE probe in a fresh Docker container each round.│
        │ Connects to none of the above. It measures an ARTIFACT,   │
        │ it does not execute work.                                 │
        └──────────────────────────────────────────────────────────┘
```

`lib/queue/orchestrate.sh` and `lib/queue/queue.sh` sit in one directory and are separate
engines. `queue.sh` never calls `orchestrate.sh`; its only mention of that file is a comment.
The reverse link is one line: `orchestrate.sh queue <src>` is an alias that execs
`queue.sh run <src>`, so the orchestrator CLI can start the queue and nothing more. A
queue-launched session may also invoke the orchestrator as one of its own tool calls.

## Side by side

| | board (not an executor) | orchestrator | queue | `/kit:dispatch` | gauntlet |
|---|---|---|---|---|---|
| Unit of work | a table row | a ROADMAP sub-goal | a tsv row | a VALIDATED spec with `## Touches` | a probe card |
| Runs an agent | no | `claude -p`, headless | `claude`, interactive | Agent-tool workers, in the background | a probe in a container |
| Concurrency | n/a | a wave, `WAVE_CAP` (2) | one row at a time | the PARALLEL set, a cap of 4 held by hand | one probe per round |
| Auth | n/a | the host's session | the operator's live login | the lead session | a spend-capped API key |
| Isolation | n/a | a worktree per wave session; the serial path uses the real checkout | none, the real checkout | a worktree per worker | a fresh container per round |
| Mutates | the row | the code | the code | the code, on `goal/<slug>` | the artifact under test |
| Ends when | a human sets a state | every box is checked | the journal has a verdict, and `done` needs a HEAD move or a new PR | the READY branches go to `/kit:ship` | a probe passes unaided twice |

## What each is for

**Board.** Not an executor: the ledger and the admission gate. States run `queued → claimed → speccing →
validated → executing → shipped`, plus `parked` and `dropped`. It runs nothing. A row becomes
executable only when it carries a `#queue{repo=<name>,pointer=<path>}` token, and
`lib/board/parse-board.sh` is the sole authority that validates it: charset, repo
self-consistency, and path containment under `_meta/megagoals/*` or `.claude/goals/*`.

**Orchestrator.** Drives a mega-goal's sub-goals to completion. It picks the ready set,
injects the pointer prompt plus a capped `HANDOFF.md`, spawns a fresh headless session per
sub-goal, and waits. It never flips a checkbox itself: completion is grounded on the session
writing its own box, or for a `gate` sub-goal on a real PR existing. A wave admits sub-goals
greedily in roadmap order, but only where each declares its own `## Touches` and proves
disjoint against every already-admitted member.

An opt-in trial backend runs the same roadmap through Orca instead: `run <dir> --backend orca`
(or `MEGA_BACKEND=orca`, the flag wins) maps each sub-goal to an Orca Task and starts supervised
Claude workers. The runner stays non-LLM, and each sub-goal's state is derived from Orca plus
the ROADMAP box each time it is read, never stored. `status <dir>` prints those states and
`orca-reset <dir>` rolls a run back. An Orca `completed` never advances a sub-goal: the box is
still the only proof of done. The default path never loads the backend.

**Queue.** Runs one prepared pointer at a time, overnight. It opens a tmux window, launches a
real interactive session, and types `/goal <pointer body>` into it. The header states why this
beats a headless worker: a headless token can expire or be killed independently, and the run
dies with it. Driving the operator's live session sidesteps that class, at the cost of running
under the operator's own authority.

A completion claim is not a result. The run's `RUNNER_DONE` marker or `EXIT_SIGNAL: true` file
only says it believes it finished. The conductor journals `done` when the repo's HEAD moved or a
pull request was created since the window opened; a claim with neither is journaled `gated` with
reason `no-delta`, so a human looks. The reaper (`watch-board.sh`) cannot check the delta for a
slug whose conductor died, so it journals such a claim `gated` too, never `done`.

**Dispatch.** Several disjoint specs, now, with you watching. `/kit:dispatch` runs
`lib/gate/dispatch-gate.sh plan` over the specs, fans out one background worktree worker per
parallel-safe spec, drift-guards each worker, and hands convergence to `/kit:ship`. It never
auto-merges and is not a DAG. It needs no board row and no pointer file, and it runs under the
lead's `bypassPermissions` session. It shares the disjointness check with the orchestrator, not
code.

**Gauntlet.** It runs agents but executes no work. It converges an artifact, usually docs, until a fresh probe
agent can complete a fixed task using only that artifact. See the duality below.

## The gauntlet is the dual of `/goal`

```
  /goal and the executors               the gauntlet
  ──────────────────────────            ──────────────────────────
  ONE agent, persistent                 MANY probes, one per round
  context ACCUMULATES                   context FRESH, torn down
  mutates the WORK                      mutates the ARTIFACT
  the verifier stays fixed              the outcome contract stays fixed
```

The fresh room is the whole point. A persistent agent learns to compensate for a bad artifact,
which hides exactly the defect the gauntlet hunts. Three consequences follow, and each looks
like a mistake until the goal is clear:

- **The probe runs on a mid-tier model on purpose.** A stronger model succeeds despite a bad
  artifact and destroys the signal.
- **A pass must replicate.** The final green round repeats once, so two consecutive unaided
  passes are required.
- **An unanswerable probe question is a finding, not a support request.** The probe is never
  coached.

## How work flows

```
  an idea
     │  /kit:mega  or  /kit:assign          (a human runs one)
     ▼
  a goal pointer file           .claude/goals/<slug>.md  or  _meta/megagoals/*
     │                          context, task, scope fence, self-verification,
     │                          worktree discipline, done-means
     ├──────────────────────────────┐
     │ board row + #queue{} + #auto │      (a human tags the row)
     ▼                              ▼
  orchestrate.sh run <dir>      watch-board.sh --apply   →   queue.sh run
     │                                                          │
     └──────────────────┬───────────────────────────────────────┘
                        ▼
                  branch → PR (draft by default) → journal row
```

Every link marked with a human is a human. Nothing walks this path end to end on its own, and
the pointer file is the join: the orchestrator and the queue both need one, and only `/kit:assign` and `/kit:mega`
produce one. A staged candidate row is prose, so it is not runnable until it has been through
that step.

## What they share

Almost nothing, and the exceptions are worth knowing.

| Shared | Between | What it is |
|---|---|---|
| `lib/gate/gate-ledger.sh` | orchestrator, gauntlet | the telemetry rail. The orchestrator writes a START record and token counts for each dispatched sub-goal. The gauntlet reaches it only through the commands its prompt tells the lead to run (`commands/gauntlet.md`). The queue and `watch-board.sh` never call it; they write `queue-journal.tsv` |
| `lib/gate/dispatch-gate.sh` | orchestrator, `/kit:dispatch` | the one disjointness authority: the orchestrator uses it to admit a wave, `/kit:dispatch` to plan its parallel set. `goal-registry.sh` sources it too, and `/kit:dispatch` claims its workers there |
| `lib/queue/pane-tail.jq` | orchestrator, gauntlet | a display filter for streamed transcripts: `orchestrate.sh panes` and the gauntlet's cleanroom `watch.sh` use it. `queue.sh` never does |

That is the full list. The gauntlet shares no orchestration logic, no state, and nothing at all
with the board or `/kit:dispatch`. The planes are independent engines; only the orchestrator and the gauntlet write
to the gate ledger, and the queue keeps its own journal.

## Trust and isolation

This is where the planes differ most, and the difference is not documented anywhere else.

**The orchestrator and the queue run unsandboxed on the operator's machine**, in the real checkout, with
`--dangerously-skip-permissions`. That is a deliberate tradeoff, not an oversight: the queue's
own spec centres on avoiding a headless auth failure, and never discusses confinement.

Because nothing can intercept those writes, the compensating controls are **detection, not
prevention**. `QUEUE_PROTECTED_GLOBS` names paths an unattended run must not write
(`.claude/*`, `CLAUDE.md`, `AGENTS.md`, `.github/*`, `_meta/BACKLOG.md`). A write there does not
fail. It ends the row `gated` so a human sees it.

**The gauntlet is the opposite.** A fresh container per round, a tarball of committed state,
tool binaries baked into the image but never config or keys, and the probe key passed at run
time. On a remote runner the key is resolved by that host from a 1Password reference; it never
travels over ssh and never lands in shell history.

Untrusted input is fenced where it enters. A hand-authored tsv is exempt by design, because
operator authorship IS the trust boundary. A row from a board is not: `--from-boards` implies
`--sanitize-prompt`, which runs the free-text cell through an ordered pipeline (entity decode,
strip invisible codepoints, strip ANSI, delete HTML comments, strip code fences, neutralize
non-https URLs, size cap) and wraps it in explicit untrusted-text fences. It fails closed.

## Which one to reach for

| You want to | Use |
|---|---|
| track work and decide what is next | the board |
| drive a multi-step plan whose steps depend on each other | `/kit:mega`, then the orchestrator |
| fan out several disjoint, validated specs now, in worktrees | `/kit:dispatch` |
| run prepared, independent work unattended overnight | the queue |
| find out whether your docs actually work for a stranger | the gauntlet |
| execute one thing right now, watching it | `/goal` in your own session |

## Bounds, at a glance

Every plane fails closed. The knobs below are the ones worth knowing before starting a run;
`lib/config/module-registry.md` carries the full set with defaults.

| Plane | Stops on |
|---|---|
| orchestrator | `WAVE_CAP`, a non-disjoint `## Touches`, a `gate!` sub-goal halting the loop, a failing gate ledger refusing the merge |
| queue | `QUEUE_TIMEOUT_SECS` per row, two consecutive failures ending the night, stall quarantine, breaker cooldown, a tool-call ceiling |
| `/kit:dispatch` | a spec with no `## Touches`, a gate `WAIT`, drift past the spec's touches, a lost worker attempt |
| gauntlet | a hard round cap, a spend-capped key, an honest halt when severity stops falling |
