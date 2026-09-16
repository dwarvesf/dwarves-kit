# SPEC-290: dispatch keeps an Attempt state apart from the Task state

**Status:** BUILT (the code and wiring land in this PR; this spec records the contract they implement)
Lane: full
**Source:** the board row. **Board:** ID-882. **Proof:** `docs/verification/dispatch-attempt-state.md`.

## Problem

`/kit:dispatch` reads worker silence as failure. Its Step 3 contract says a worker that returns no
`STATUS:` line, errors, or exceeds its timeout is FAILED. A lead who believes a worker failed
re-dispatches the spec. The original worker was often alive: a Claude API drop kills the stream,
not the agent, and `SendMessage` resumes it on the branch it already owns.

Both then land. Two agents commit to one branch, and the second overwrites or duplicates the
first. The memory note `resume-a-dead-subagent-never-respawn-on-its-branch` records that incident.
The prose rule it produced (resume, never respawn) is advice the lead may forget under load.

The root cause is one state where two are needed. `goal-registry.sh` tracks one status per goal,
so "the worker is gone" and "the work is gone" are the same field. Nothing can express a worker
whose outcome is unknown.

## Solution

`lib/goal/attempt-state.sh`: two state machines, one per grain, with a legal-transition table
that refuses anything absent from it.

```
TaskState     queued ──────► dispatched ──────► done
                 ▲                │
                 │                ├──► lost          (abandon: no worker left)
                 └────────────────┘                  (lose-attempt frees it)

AttemptState  running ──► disconnected ──► lost      (grace expired)
                 │   ◄──── resume  │
                 ├──► committed ◄──────────┘         (a result inside the window)
                 └──► superseded  ◄─────────         (another attempt won)
```

A disconnect moves the ATTEMPT to `disconnected` and starts a grace window. The TASK stays
`dispatched` for the whole window, so no dispatch path can pick it up. `dispatch` refuses outright
while any attempt is live, which is the duplicate-dispatch bug closed at the command surface.

Only after the window expires does `lose-attempt` mark the attempt `lost`, add that worker to the
task's `excluded` set, and move the task back to `queued`. A lost attempt is an unknown outcome,
not a failure: the worker is excluded because we cannot ask it again, not because it was wrong.

`commit-result` is idempotent on the TASK id, never the attempt id. The first attempt to commit
wins and sets `winner` plus `result_ref`. Every later commit for that task is a no-op that exits 0
and names the winner, and the losing attempt is recorded `superseded`. Exit 0 matters: the caller
must be able to acknowledge a duplicate result without treating it as an error.

### Verbs

| Verb | Contract |
|---|---|
| `dispatch <task> <worker> [attempt]` | creates the next attempt; refuses an excluded worker and refuses any second live attempt |
| `mark-disconnected <task> [attempt] [--grace N]` | attempt to `disconnected`, window starts; the task does not move |
| `resume <task> [attempt]` | `disconnected` back to `running`, window cleared |
| `lose-attempt <task> [attempt]` | refuses while the window has time left; on expiry: attempt `lost`, worker excluded, task `queued` |
| `commit-result <task> <attempt> <ref>` | idempotent on the task; a second call is a no-op naming the winner |
| `abandon <task> <reason>` | task to `lost` when no worker remains |
| `status <task>` | task state, winner, excluded workers, and each attempt with its grace remaining |
| `list` / `release <task>` / `dir` | the store surface |

The underscore spellings (`mark_disconnected`, `lose_attempt`, `commit_result`) are accepted
aliases, so prose quoting either form resolves.

### Grace window

One default, `ATTEMPT_GRACE_DEFAULT_SECONDS=120`, and one flag, `--grace N`. No call site repeats
a literal. 120 seconds covers a Claude API drop and a `SendMessage` round trip without holding a
genuinely dead worker's task hostage for long.

### Store

`$(git rev-parse --git-common-dir)/kit-attempts/<task>.task`, the convention `goal-registry.sh`
already uses, so the lead reads both in one place and a different machine structurally cannot
share the state. `ATTEMPT_REGISTRY_DIR` overrides it for tests, mirroring `GOAL_REGISTRY_DIR`.
`ATTEMPT_NOW` pins the clock, so grace expiry is tested without sleeping.

## Consumers

`commands/dispatch.md` Step 3: a worker that stops reporting is DISCONNECTED, not FAILED. The lead
calls `mark-disconnected`, resumes with `SendMessage`, and may only call `lose-attempt` after the
window expires. No second `Agent` dispatch inside the window.

`commands/execute.md` Step 2d: the retry loop consults the attempt state before re-dispatching, so
a worker that vanished mid-task is resumed rather than replaced, and the retry budget is not spent
on an attempt whose outcome nobody knows.

The `megagoal-agent-drive` skill lives outside this repo and is a follow-up, not part of this
spec.

## Verification

```bash
bash tests/test-attempt-state.sh
bash tests/run-all.sh
```

## After state

`lib/goal/attempt-state.sh` exists with the verbs above. `tests/test-attempt-state.sh` covers the
legal walk, three refused illegal transitions, the refused and then allowed `lose-attempt` around
the window, a double `commit-result`, and the resume-then-late-replacement race. Both consumer
commands name the attempt-state verbs where they used to name silence as failure.
