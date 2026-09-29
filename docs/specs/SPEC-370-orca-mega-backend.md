# Spec: an opt-in Orca backend for the mega runner (trial)

Generated: 2026-09-29
Status: DRAFT (VALIDATE PENDING: the author had no subagent tool)
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-370-orca-mega-backend.md`
Depends on: SPEC-366 (execution view, `board work`, commit bc55dddd) SHIPPED before any build task starts
References: `docs/specs/SPEC-366-execution-view.md` `### Interfaces (I/O contract)` (the `--json` schema 1 contract this spec consumes) and `### Flag rules`; `docs/research/2026-09-29-openrig-absorption.md:196-204` (D7) and `:245-254` (D7a); `lib/queue/orchestrate.sh` (the runner this extends); `orca skills get orchestration --full` on Orca 1.4.209 (the supervised-worker contract; line numbers below are from that output); `lib/queue/harness.sh:1-19` (why a vendor adapter is the wrong seam here)

Lane source: `bash lib/classify/lane-classify.sh classify "Opt-in --backend orca path for lib/queue/orchestrate.sh run ... external provider integration ..."` printed `full`. The change adds an external-provider integration to the mega runner.

## Problem

The mega runner does not know if a worker is stuck. It dispatches one `claude -p` per sub-goal and learns the outcome only when that process exits (`lib/queue/orchestrate.sh:2698-2705`). A session that is alive but waiting on input, or idle, stays invisible until it ends. The stall watchdog is off by default (`lib/queue/orchestrate.sh:159`), and when on it only flags silence (`:154-158`). The default run mode in `/kit:mega` is worse for context: the conductor keeps the whole sequence and every subagent return in its own session (`commands/mega.md:214-219`).

Orca already ships the parts to fix this: Tasks with dependencies, supervised workers with a liveness verdict, and decision gates (`orca orchestration --help`). No kit code calls any of them (`grep -rn orca lib commands` finds nothing). The only Run on this host is the legacy tombstone (`orca orchestration run-list --json`, see Grounding).

D7 in the research record asks for a trial: move one mega run onto Orca Tasks and supervised workers, derive PARKED, HELD and DONE-UNSEEN from status, and let the orchestrator ask the status view for the next ready task instead of holding the sequence in context (`docs/research/2026-09-29-openrig-absorption.md:196-204`). It must stay opt-in, and the research record warns that no one has measured a win yet (`:256-258`).

## Premise check

| Claim in the brief | Checked | Result |
|---|---|---|
| Orca primitives exist and are unused | `orca orchestration --help`; `orca orchestration run-list --json`; grep of `lib/` and `commands/` | Holds. 30 verbs; one Run, `run_legacy_local`; zero kit callers |
| SPEC-366 is available to consume | `docs/specs/SPEC-366-execution-view.md` at bc55dddd, `### Interfaces (I/O contract)` | Holds as a written contract: `board work --json`, schema 1, logic in `lib/board/work.sh`. Not shipped yet, so the build waits for it |
| Devin can be a supervised Orca worker | Orca group addresses name `@claude @codex @opencode @gemini @droid @grok @cursor`, no Devin (skill output line 426-427) | False. Devin could only join through `dispatch --inject`, which Orca reports as unsupervised with no liveness (skill line 372-376) |
| Orca state can be reset per run | `orca orchestration reset` usage: `(--all \| --tasks \| --messages)` (agent-context schema) | False. Reset is global and destructive (skill line 709-710). Rollback therefore stops and releases this run's own Dispatches only |
| A real, small, upcoming mega exists for the trial | `_meta/megagoals/*/ROADMAP.md` in ops-toolkit; `.claude/goals/` in the kit | None fits. `icy-ops-duckdb` has 5 open sub-goals over treasury data with holder names (`ROADMAP.md:13`, `:27-31`); `hermes-multiplex-followups` ends in a live deploy on the Mini (`ROADMAP.md:8`). The trial uses a synthesized public fixture with a local bare git remote (operator decision) |
| Orca can mark one inbox message read | `orca orchestration check --help` (agent-context usage and notes) | False. A consuming `check` returns the oldest FIFO Delivery and replays it until `--ack <delivery_id>` acknowledges the whole batch. `--peek` never marks read. So "mark read after acting" means: ack a Delivery only when every message in it has been acted on |
| The mega runner rejects a DAG | `commands/mega.md:521` says "Single chain only" | Stale against code: the runner already parses `depends` and runs waves (`lib/queue/orchestrate.sh:488-495`, `:602`). This spec adds no new scheduling rule; it mirrors the same `depends` edges into Orca |

## Solution

### Approaches considered

1. **Orca as a fourth harness.** Add `orca` beside codex and pi in `lib/queue/harness.sh`. Tradeoff: a harness resolves a synchronous headless argv whose exit code is the result (`lib/queue/harness.sh:4-19`). A supervised Orca worker is asynchronous and reports through Task status and a mailbox. Forcing it into the harness shape blocks on each worker and throws away the status axis, which is the whole point.
2. **An LLM coordinator that follows Orca's orchestration skill.** The conductor session runs the canonical supervised loop (skill line 93-147). Tradeoff: the conductor holds every Delivery in context again, and the runner header forbids an LLM in the loop for exactly that reason (`lib/queue/orchestrate.sh:6-8`).
3. **A non-LLM Orca backend inside the runner (chosen).** `orchestrate.sh run <dir> --backend orca` sources one new file, `lib/queue/orca-backend.sh`. It maps sub-goals to Orca Tasks, polls Orca, starts supervised workers, and derives states at read time. A new `orchestrate.sh status <dir>` verb prints the view; that is what a conductor reads. Tradeoff: one more code path in a 2,859-line runner, kept out of the default path by only sourcing the file when the flag is set.

### Chosen approach + why

Approach 3. It keeps the runner non-LLM, keeps the default path untouched, and gives the orchestrator a status query instead of a transcript. Approach 1 loses liveness. Approach 2 brings back the context growth D7 is meant to remove.

**Worker choice: Orca `worker-start --agent claude`, not ops-toolkit `worker-launch`.** The PARKED rule needs the fleet liveness verdict and `agentWait` evidence. Only a supervised Dispatch has them (skill line 57-59; `worker-show --help` notes). `worker-launch` opens plain `orca terminal` tabs and detects done by reading `WORKER-DONE` off the screen (`ops-toolkit/tools/worker-launch/README.md:22-30`), so its workers would all render INDETERMINATE. Devin is not an Orca agent (Premise check). Codex is supported by Orca but out of scope for the trial.

### Extensibility & boundaries

- Load-bearing dimension: sub-goal count per mega. Each poll costs three Orca list calls plus one peek, independent of count; `worker-list` pages at 100 (skill line 135), far above a 3-8 sub-goal mega.
- Units: `orca-backend.sh` has four parts, each testable against the stub: `plan` (Run and Tasks), `tick` (dispatch and consume), `derive` (the state join), `reset` (rollback). `orchestrate.sh` gains only flag parsing, two verbs and one branch.

## Picture

```
  ROADMAP.md + goals/NN-*.md                     kit run ledger, orca worktree ps
        |                                                   |
        v                                                   v
  orchestrate.sh run <dir> --backend orca          board work --json (SPEC-366)
        |                                          (flags, rung per item)
        | plan (once): run-create, task-create --deps           |
        v                                                       |
  +------------------ tick every ORCA_POLL_SECS ----------------+----+
  |  read:  task-list --run R   worker-list --run R                  |
  |         gate-list --run R   check --run R (consuming, no ack)    |
  |  derive: join by SG id  ->  READY WAITING RUNNING PARKED HELD    |
  |          DONE-UNSEEN DONE FAILED BLOCKED INDETERMINATE           |
  |  act:   READY + admitted     -> worker-start --task T --agent claude
  |         completed + box      -> event shipped, worker-release    |
  |         gate SG completed    -> gate-create on its accept Task   |
  |         gate resolved accept -> flip box, accept Task completed  |
  |         every message acted -> check --ack <delivery>            |
  |         PARKED / INDETERMINATE -> report only, never stop/retry  |
  +------------------------------------------------------------------+
        |                                   ^
        v                                   | operator: reply, gate-resolve,
  orchestrate.sh status <dir>               | retry (Orca Mobile or CLI)
  (the conductor's only read)       Orca workers (claude, own worktree)
```

## Design

### Approaches considered + chosen
See `## Solution`.

### Diagram
State of one sub-goal, derived at read time, never stored. First matching rule wins. A rule that needs a field that is absent or reads `unverifiable` yields INDETERMINATE and stops there; it never falls through to the next rule.

```
 1  ROADMAP box checked AND the SG branch exists on origin ............ DONE
 2  no map row, Orca call failed, or a needed field missing ........... INDETERMINATE
 3  gate SG whose accept Task has a pending gate ...................... HELD
 4  Task completed, no `shipped` event for the SG ..................... DONE-UNSEEN
 5  Task failed (worker_done --outcome failed) ........................ FAILED
 6  Task dispatched AND any of:
      liveness exited, dispatch stopped, agentWait present,
      unanswered question or escalation in the Run inbox,
      board work row: `flags` holds `PARKED` .......................... PARKED (reason)
 7  Task dispatched AND liveness live ................................. RUNNING
 8  Task ready AND ROADMAP deps boxes all checked ..................... READY
 9  Task pending or deps boxes open ................................... WAITING
10  a worker_done was consumed but the box stayed open, or
    the gate resolved `rework` ........................................ BLOCKED (reason)
```

PARKED reasons: `exited`, `stopped`, `agent-wait`, `question`, `escalation`, `idle` (from `board work`). HELD applies to `gate` and `gate!` sub-goals only; a `gate!` hold also stops every new `worker-start` in the run.

Rule 10 is checked by the event log (`blocked "box not flipped (no self-claim)"`), the same halt the default path uses (`lib/queue/orchestrate.sh:2760-2764`).

### ADR link(s)
None. The switch is opt-in and reversible; no lasting decision is made until the trial reports. If the trial says adopt, the follow-up that changes the default writes the ADR.

### Boundaries & failure modes
Orca is an external provider. The backend never infers a fact Orca did not report: absence authorizes nothing (skill line 609-613). See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

**CLI surface (new):**

| Command | Effect | Exit |
|---|---|---|
| `orchestrate.sh run <dir> --backend orca [--dry-run]` | plan, then tick until all boxes are checked, a `gate!` holds, or nothing is runnable and nothing is running | 0 done or held; 1 halted with a named reason; 64 bad args |
| `orchestrate.sh run <dir> --backend claude` or no flag | today's path, byte for byte | unchanged |
| `orchestrate.sh status <dir>` | print the derived view as TSV: `sg`, `state`, `reason`, `task`, `dispatch`, `rung` | 0; 3 when `<dir>` has no Orca run |
| `orchestrate.sh orca-reset <dir>` | for each Dispatch in this run's map: `worker-stop` if live, then `worker-release`; move the map aside | 0; 1 with the Dispatches it could not settle |

`MEGA_BACKEND` env gives the same switch as the flag; the flag wins. Allowed values: `claude` (default), `orca`. Anything else is rejected at pre-flight with exit 64, the same way `WAVE_CAP` is (`lib/queue/orchestrate.sh:2434-2437`). There is deliberately no `kit.toml` key: a committed project file must not be able to switch a run onto another runtime (the same reasoning as `commands/mega.md:402-409`).

**Seams (mock points, same pattern as `CLAUDE_CMD`, `GH_CMD`, `TMUX_CMD` at `lib/queue/orchestrate.sh:83`, `:274`, `:219`):**

- `ORCA_CMD` (default `orca`). Every Orca call goes through it.
- `BOARD_WORK_CMD` (default `<kit root>/bin/board work`). See "Consumed from SPEC-366". The backend calls it with `ORCA_BIN="$ORCA_CMD"`, SPEC-366's own seam, so one stub serves both.
- `ORCA_POLL_SECS` (default 30), `ORCA_IDLE_MIN` (default 20, passed as `--idle-min`), `ORCA_AGENT` (default and only allowed value in the trial: `claude`).

**Orca calls used, all with `--run <R> --json` except where the verb has no `--run`:**

| Step | Call | Why this verb |
|---|---|---|
| plan | `run-create --objective "mega:<dir basename>"` once; id saved to `<dir>/.orchestrate/orca/run` | a Run is a namespace and inbox, it never schedules (agent-context notes) |
| plan | `task-create --spec <pointer> --task-title <SG-NN title> --deps <json of dep task ids> --retry-request mega-<slug>-<SG-NN>` per sub-goal, ROADMAP order | `--retry-request` makes a lost response safe to replay (skill line 627-641) |
| plan | for each `gate` or `gate!` sub-goal, one extra Task `SG-NN:accept` (`--deps` = that sub-goal's Task); its dependents' `--deps` name the accept Task instead. Never dispatched | gives the operator's decision a not-yet-started Task to gate |
| tick read | `task-list`, `worker-list`, `gate-list`, `inbox --json` | read-only |
| tick read | `check --run R --json` (consuming, no `--ack`) | returns the oldest unacknowledged Delivery and replays it until acked (`check --help` notes) |
| tick act | `check --run R --ack <delivery_id>` only after every message in that Delivery is acted on (table below) | operator decision: mark read only after acting |
| tick act | `worker-start --task T --agent claude --worktree new-top-level --name <branch slug> --repo path:<repo root> [--model M [--effort E]]` | supervised start; exit 0 only for `ready` (agent-context notes) |
| tick act | `worker-release --dispatch D` after grounded completion | completion accounting (skill line 159-174) |
| tick act | when a gate sub-goal's Task is `completed`: `gate-create --task <SG-NN:accept> --question "Accept SG-NN: branch <b> at <sha>?" --options '["accept","rework"]'` | operator call on a coordinator-owned DAG decision (skill line 444-455); no PR involved |
| tick act | when that gate is resolved `accept`: `orchestrate.sh flip <dir> SG-NN` (`lib/queue/orchestrate.sh:926`), event `shipped "gate <id> accept"`, then `task-update --id <SG-NN:accept> --status completed` | the box flip rests on a human decision, not on the worker's word |
| reset | `worker-stop --dispatch D`, `worker-release --dispatch D` | never deletes worktrees (agent-context notes) |

Never called: `orchestration reset`, `worker-abandon`, `dispatch --inject`, `reply`, `gate-resolve`, any retry. Those are operator decisions.

**When a message counts as acted on.** A Delivery is acked only when every message in it qualifies. Orca offers no per-message read mark, only a whole-batch ack (`check --help` notes).

| Message type | Acted on when |
|---|---|
| `worker_done` | the tick has run grounded completion for that Task (DONE recorded, or BLOCKED recorded) |
| `heartbeat` | on read; nothing to do |
| `question` | an operator `reply` to its message id shows in `inbox --json`; until then the SG shows PARKED `question` |
| `escalation` | an operator reply exists, or the Task has left `dispatched` |
| any other type | never by the backend; `status` names it so the operator acts |

An unacked Delivery replays and holds later mail behind it. Completion does not wait on mail (Task status comes from `task-list`), so a held batch delays only the ack.

**The Task spec is a pointer, never the prompt body.** The runner writes `_build_prompt` output (`lib/queue/orchestrate.sh:841`) to `<dir>/.orchestrate/orca/<SG-NN>.prompt.md`, which is gitignored (`.gitignore:41`). The Task spec carries Orca's five required fields (skill line 149-157): Target (the goal file path), Change (its `Done =` line), Constraints and Ownership (its `## Touches`), Observable acceptance (push the branch to `origin`, then run `bash <kit>/lib/queue/orchestrate.sh flip <absolute dir> SG-NN`; a gate sub-goal pushes and does NOT flip), then "Read and follow <absolute prompt path>". This keeps handoff text out of argv, the same bug class the default path avoids with a stdin temp file (`lib/queue/orchestrate.sh:2682-2686`).

**Consumed from SPEC-366** (`docs/specs/SPEC-366-execution-view.md`, `### Interfaces (I/O contract)`, "`--json` contract (schema 1)"; flag meaning from `### Flag rules`). One read-only call per tick:

`ORCA_BIN="$ORCA_CMD" $BOARD_WORK_CMD --json --megagoals-root <parent of dir> --code-root <repo root> --idle-min $ORCA_IDLE_MIN`

| Key read | Type and enum (SPEC-366) | Use here |
|---|---|---|
| `schema` | integer, `1` | any other value: treat the whole view as missing |
| `orca` | `ok`, `absent`, `error` | not `ok`: the `idle` signal is unavailable this tick |
| `items[].origin` | `board`, `mega` | only `mega` rows are read |
| `items[].item` | `<mega-slug>/SG-NN` | joined to the SG; `<mega-slug>` is the basename of `<dir>` |
| `items[].flags` | subset of `PARKED`, `DONE-UNSEEN`, `INDETERMINATE` | `PARKED` feeds rule 6 with reason `idle` |
| `items[].agent.state`, `items[].agent.idle_s` | `working`, `idle`, `unknown`; integer or null | shown in the `reason` column beside `idle` |
| `items[].rung` | `none`, `validated`, `built`, `reviewed`, `shipped` | the `rung` column |
| `items[].reasons` | subset of `no-draft`, `no-branch`, `ambiguous`, `no-worktree`, `no-orca`, `not-in-orca`, `no-terminal`, `duplicate-id` | shown only; never changes a state |

SPEC-366's `DONE-UNSEEN` means shipped but never tidied (`### Flag rules`). That is a different fact from this spec's DONE-UNSEEN (worker finished, runner has not consumed it), so the backend does not read it. `PARKED` is the one signal Orca liveness cannot give: a live terminal idle past the threshold. If the call fails, the schema differs, or the row is missing, `rung` prints `?` and rule 6 uses the Orca signals only; nothing becomes idle or done on a missing view. This spec does not edit `lib/board/**`; SPEC-366's note that 370 might swap its `src_orca` (`## Siblings`) is not taken up here.

**Outputs and invariants:**

- `<dir>/.orchestrate/orca/map.tsv`: `SG-NN<TAB>task_id<TAB>dispatch_id` (dispatch empty until started). The only new stored fact. States are never stored.
- `<dir>/.orchestrate/events.log`: the existing append-only log (`lib/queue/orchestrate.sh:460-470`) gains state-change events only; no new file format.
- ROADMAP.md stays the only source of done. A `worker_done` never advances a sub-goal. An `auto` sub-goal is done when its box is checked and `git ls-remote origin refs/heads/<branch>` finds its branch. A `gate` sub-goal is done only through the operator's `accept`.
- Stacking: a sub-goal with one SG dependency starts with `--base-branch <that dependency's branch>`; with none, from the default branch. A sub-goal with two or more SG dependencies is rejected at pre-flight in the trial (no merge step exists without PRs). The final branch of the chain holds all work; merging it is the operator's act, outside both arms.
- Admission reuses `_wave_gate` (`lib/queue/orchestrate.sh:602`) and `WAVE_CAP`: at most `WAVE_CAP` RUNNING workers, and two run together only when their `## Touches` are provably disjoint. A `gate!` sub-goal halts new dispatch for the whole run, as today.
- `Model:` and `Effort:` come from `_route` (`lib/queue/orchestrate.sh:721`). Orca needs `--model` for `--effort` (agent-context notes), so an `Effort:` with no `Model:` is dropped with a warning. A `Harness:` other than `claude` is rejected at pre-flight under this backend.

### Data model changes
`map.tsv` and `run` under `<dir>/.orchestrate/orca/`, both gitignored. No schema change elsewhere.

### Infrastructure changes
None. Orca is already installed; no daemon, no listener. The tick loop is the runner's own process.

## Task Breakdown

Build starts only after SPEC-366 is SHIPPED.

### Phase 1: Foundation
- [ ] T1: `tests/fixtures/orca-stub/orca`, a bash stub backed by `$ORCA_STUB_STATE` that implements the verbs in the Orca calls table (including `check` with Delivery replay until `--ack`, `inbox`, `task-update`, `worktree ps` for `board work`) plus a test-only `_set` verb (set a Task status, a dispatch liveness, an `agentWait`, a pending question, an operator reply, a gate resolution). Its field names start from the documented ones and are replaced by the T6 capture. Any other verb exits 99 and logs. Every call appends argv to `calls.log`. Acceptance: `bash tests/test-orchestrate-orca.sh` case `stub-contract` passes.
- [ ] T2: `lib/queue/orca-backend.sh` `plan` and `derive`, sourced only under `--backend orca`. Acceptance: AC2, AC4, AC5, AC6 (derive half), AC7.

### Phase 2: Core
- [ ] T3: `tick` (admission, stacking base, worker-start, consume, release, accept-gate create and resolve, inbox ack) and `orca-reset`. Acceptance: AC3, AC6, AC7, AC8, AC9, AC13.
- [ ] T4: `orchestrate.sh` flag parsing, `MEGA_BACKEND`, the `status` and `orca-reset` verbs, the usage line (`:2851`). Acceptance: AC1, AC10.

### Phase 3: Docs and trial
- [ ] T5: `commands/mega.md` Step 5 run mode: one paragraph naming `--backend orca` as an opt-in trial and `status` as the conductor's read. Regenerate `docs/FEATURES.md` with `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md`. Acceptance: AC11.
- [ ] T6: the trial (see `## Trial plan`), recorded at `docs/verification/orca-trial/<date>-trial.md`. It starts with trial step 0 (the live capture) and updates the stub from that capture before any measured run. Acceptance: AC12, AC14.

## After state

- [ ] `orchestrate.sh run <dir> --backend orca` drives a 3-sub-goal mega through Orca Tasks and supervised workers. (Today: no kit code calls `orca orchestration`.)
- [ ] `orchestrate.sh status <dir>` prints one row per sub-goal with a derived state from the rule table, checkable by `bash tests/test-orchestrate-orca.sh`.
- [ ] A worker stopped mid-task shows PARKED on the first `status` after the stop. (Today: the default path learns only when the process exits.)
- [ ] Without the flag, the runner never invokes `$ORCA_CMD`, checkable by the poison-stub case in AC1.
- [ ] A trial record compares both backends on the three measures.

## Acceptance Criteria (global)

Every AC below runs against the stub. No test touches the live Orca runtime.

- AC1 default path unchanged: with `ORCA_CMD` set to a poison stub that writes a sentinel file, `orchestrate.sh run <fixture>` with no flag and with `--backend claude` leaves no sentinel, and the existing suites pass. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC1' && bash tests/test-orchestrate.sh && bash tests/test-orchestrate-gate-dispatch.sh && bash tests/test-orchestrate-hardening.sh`
- AC2 plan: one `run-create`, then four `task-create` calls in ROADMAP order (SG-01, SG-02, SG-03, `SG-03:accept`); SG-02's `--deps` holds SG-01's task id; SG-03's holds SG-02's; `SG-03:accept`'s holds SG-03's; each carries a `--retry-request`; a second `run` on the same dir creates nothing new. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC2'`
- AC3 dispatch: `worker-start --task` runs only for a Task that Orca reports `ready` AND whose ROADMAP deps are checked; a Task that is Orca-ready but whose dep box is open is not started. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC3'`
- AC4 negative control, stop mid-task: SG-02 RUNNING; the stub flips its dispatch to `exited` with the Task still `dispatched`; the next `orchestrate.sh status` prints SG-02 as `PARKED` with reason `exited`. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC4'`
- AC5 unknown stays unknown: liveness `unverifiable`, or no map row, or `ORCA_CMD` exiting nonzero, each prints `INDETERMINATE`, never `RUNNING`, `PARKED` or `DONE`. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC5'`
- AC6 DONE-UNSEEN then DONE: Task `completed`, box open, no `shipped` event prints `DONE-UNSEEN`; after the worker flips the box and one tick runs, it prints `DONE`, `events.log` has `shipped`, and `calls.log` has `worker-release` for that dispatch. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC6'`
- AC7 HELD and accept: plan creates `SG-03:accept`; when SG-03's Task completes, `gate-create --task <SG-03:accept>` is issued once and `status` prints SG-03 `HELD`; SG-03's box stays open; after the stub resolves the gate `accept`, one tick flips the box, records `shipped "gate <id> accept"` and completes the accept Task; resolved `rework` prints `BLOCKED rework`. No `gh` call is made. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC7'`
- AC8 no self-claim: Task `completed` with the box still open after one tick prints `BLOCKED` with reason `no self-claim`; its dependents are not started. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC8'`
- AC9 rollback: `orchestrate.sh orca-reset <dir>` calls `worker-stop` and `worker-release` only for dispatch ids in this dir's map, never `reset`, and leaves `map.tsv` moved aside. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC9'`
- AC10 pre-flight: `--backend foo` and `MEGA_BACKEND=foo` exit 64; a goal file with `Harness: codex` under `--backend orca` stops before any Orca call. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC10'`
- AC11 docs: Verify: `grep -q -- '--backend orca' commands/mega.md && bash tests/test-meta.sh`
- AC13 inbox ack after acting: a Delivery holding a `worker_done` and an unanswered `question` is not acked; after the stub records an operator reply and the tick has consumed the `worker_done`, exactly one `check --ack <delivery_id>` is issued. Verify: `bash tests/test-orchestrate-orca.sh 2>&1 | grep -q '^PASS AC13'`
- AC14 live capture recorded: the trial record holds real Task, worker, gate and Delivery rows and the branch name Orca created, and the stub commit that follows them. Verify: `f=$(ls docs/verification/orca-trial/*-trial.md | tail -1) && grep -q '^## Capture' "$f" && grep -q 'branch created by Orca' "$f"`
- AC12 trial record exists with all three measures filled for both arms. Verify: `f=$(ls docs/verification/orca-trial/*-trial.md | tail -1) && grep -q '^| stranded work caught' "$f" && grep -q '^| orchestrator context' "$f" && grep -q '^| operator interventions' "$f"`

## Verification

```
bash tests/test-orchestrate-orca.sh &&
bash tests/test-orchestrate.sh &&
bash tests/test-orchestrate-gate-dispatch.sh &&
bash tests/test-orchestrate-hardening.sh &&
bash tests/test-meta.sh
```

AC12 is checked after T6, not in the build's verification run.

## Test plan

One new file, `tests/test-orchestrate-orca.sh`, following the fixture pattern of `tests/test-orchestrate-gate-dispatch.sh:1-40` (a mega dir, fake binaries on seams). `ORCA_CMD` points at `tests/fixtures/orca-stub/orca`; `CLAUDE_CMD` points at a fake and `GH_CMD` at a poison fake (the Orca backend makes no `gh` call); `BOARD_WORK_CMD` points at a fake printing schema-1 JSON; each fixture has a local bare `origin`; `ORCA_POLL_SECS=0` and a tick bound keep it fast. The fixture mega: SG-01 `auto`; SG-02 `auto, depends SG-01`; SG-03 `gate, depends SG-02`.

| Case | Setup | Expect |
|---|---|---|
| stub-contract | call each supported verb; call `orchestration reset` | valid JSON per verb; `reset` exits 99 |
| AC1 | poison `ORCA_CMD`; run without flag | no sentinel; existing suites green |
| AC2 | run `--backend orca` with a tick bound of 0 | calls.log shows 1 run-create, 4 task-create with deps; re-run adds none |
| AC3 | stub marks SG-02 ready, SG-01 box open | no worker-start for SG-02 |
| AC4 (negative control) | SG-02 running; `_set` dispatch exited | first `status` after the flip: `SG-02 PARKED exited` |
| AC5 | liveness unverifiable; delete map row; `ORCA_CMD` exits 1 | INDETERMINATE in all three |
| AC6 | Task completed, box open, then box flipped, one tick | DONE-UNSEEN, then DONE plus release |
| AC7 | SG-03 Task completed; then gate resolved `accept`; separately `rework` | gate-create on the accept Task; HELD; then box flipped and accept Task completed; `rework` gives BLOCKED |
| AC13 | one Delivery: `worker_done` + `question`; then operator reply | no ack before the reply; one ack after |
| view fallback | `BOARD_WORK_CMD` prints `schema: 2`, then exits 1 | `rung` is `?`; no `idle` PARKED; other states unchanged |
| AC8 | Task completed, box never flipped, one tick | BLOCKED no self-claim; no dependent start |
| AC9 | map with two dispatches, one live | stop plus release for those two only |
| AC10 | bad backend; `Harness: codex` | exit 64; zero Orca calls |
| mutation check | remove the `exited` branch from rule 6 in a temp copy of `orca-backend.sh`, re-run AC4 | AC4 goes red. Proves the control can fail |

The mutation check runs inside the test file on a temp copy, so the shipped file is never edited.

## Trial plan

**Fixture, not client data.** No real upcoming mega fits (Premise check). The trial uses a synthesized public mega committed at `docs/verification/orca-trial/fixture/`, run against a local scratch repo whose `origin` is a local bare git repo (operator decision). No GitHub, no PR.

- SG-01 `auto`: add `bin/wordcount` (count words in stdin) plus one test.
- SG-02 `auto, depends SG-01`: add a `--lines` flag. Its goal file says the flag name is undecided between `--lines` and `-l`, and the worker must ask before writing. This is the fault that strands work: a headless `claude -p` cannot ask; an Orca worker can `ask` and wait.
- SG-03 `gate, depends SG-02`: README usage section. In Arm B it ends at an Orca decision gate on `SG-03:accept`. In Arm A today's runner dispatches it, finds no PR (`lib/queue/orchestrate.sh:2713-2718`) and halts; the operator reviews the branch and runs `orchestrate.sh flip`. Both arms spend one human decision here.

**Step 0, live capture (before any measured run).** On a separate throwaway copy of the fixture, run Arm B for SG-01 only and capture, into the trial record's `## Capture` section: one real row each from `task-list`, `worker-list`, `worker-show`, `gate-list` (after a `gate-create` on a pending Task, which also shows whether `task-list --ready` still lists a gated Task), one `check` Delivery, and the branch created by Orca for `worktree new-top-level --name <slug>` with `--base-branch`. Update the stub's field names and the backend's reads to match, commit that, and re-run `bash tests/test-orchestrate-orca.sh` green before step 1. Then `orchestrate.sh orca-reset` the capture copy.

**Arms.** Two only. Two fresh copies of the fixture, same model tier (`Model: sonnet` in each goal file), same `WAVE_CAP`.

- Arm A (baseline, today's runner): a conductor Claude session runs `orchestrate.sh run <copyA>` and reports.
- Arm B: a conductor Claude session runs `orchestrate.sh run <copyB> --backend orca` in the background and reads only `orchestrate.sh status <copyB>` until done.

**Injected faults, same in both arms.** F1: SG-02's clarification question (above). F2: kill SG-01's worker once its first commit lands (Arm A: kill the `claude -p` pid; Arm B: `orca orchestration worker-stop --dispatch <id>`); the operator then restarts it.

**Measures (the table AC12 checks):**

| Measure | How it is counted | Source |
|---|---|---|
| stranded work caught | for F1 and F2: detected by the runner or view (yes/no), and minutes from the fault to the first signal | Arm A: runner stdout and `events.log`; Arm B: `status` output and `events.log` timestamps |
| orchestrator context | conductor session tokens at the end (input + cache read + cache creation of its last turn) | the conductor's transcript jsonl `usage` block |
| operator interventions | every human action needed to reach all-DONE: answers, restarts, gate resolutions or manual flips, transcript reads to find out why | operator tally cross-checked with `events.log` and `orca orchestration inbox --json` |

**Decision rule, written down before the run.** Adopt for a second trial on a real mega only if Arm B catches F1 at or before Arm A, catches F2 within one poll, and its conductor context is not larger than Arm A's. Otherwise record the result and stop; the backend stays opt-in or is removed.

## Edge Cases

1. The runner is started twice on the same dir: the second finds `run` and `map.tsv`, reuses them, and creates no Tasks (AC2). Two live tick loops on one dir are prevented with the existing flip lock (`lib/queue/orchestrate.sh:321`).
2. `worker-start` exits 1 with `outcome_unknown`: record `blocked` with the receipt's stage, show INDETERMINATE, never relaunch (skill line 106-108).
3. A worker parks on a permission or trust prompt: `agentWait` is present, so PARKED with reason `agent-wait`. A waiting worker is healthy, not failed (`worker-show --help` notes).
4. A worker asks a question: the unacked Delivery holds a `question` for its Task, so PARKED with reason `question` until an operator reply shows in `inbox`. The Delivery is acked only after that (AC13).
5. The runner itself runs inside an Orca-dispatched worker: Orca's nested depth limit applies and a new Run does not reset it (skill line 111-113). `worker-start` refuses; the runner halts with that code.
6. The ROADMAP is edited mid-run (a sub-goal added): the next tick creates its Task; a removed sub-goal's Task is left alone and shown in `status` as `INDETERMINATE (not in ROADMAP)`.
7. `task-list --ready` may still list a gated Task (step 0 finds out). The accept Task is never dispatched, and its dependents wait on it through `--deps` and through the ROADMAP box check, so a gate holds either way.
9. The same Delivery replays across ticks: acting is idempotent (a consumed `worker_done` is recognised by its `shipped` or `blocked` event), so replay never double-flips or double-releases.
8. All boxes checked: the backend returns to the existing TIER-4 close (`lib/queue/orchestrate.sh:2339`) unchanged.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Orca not running or CLI missing | `ORCA_CMD` exits nonzero on the first read | pre-flight halt, exit 1, message names the call; default path unaffected |
| Orca field names differ from the stub | T6 live-row diff | fix stub and backend before measured runs; derive treats unknown fields as absent, so the failure is INDETERMINATE, never a false DONE |
| Lost mutation response | `task-create` or `worker-start` returns no receipt | replay with the same `--retry-request`; `request-show` before any second attempt (skill line 627-641) |
| Worker finished but box never flipped | rule 10 | halt that chain, same as today's no-self-claim guard |
| Orphan terminals after abort | `worker-list --run R --terminal-state reclaimable` | `orchestrate.sh orca-reset <dir>` |
| SPEC-366 view missing or changed | `board work` exits nonzero, `schema` is not 1, or top-level `orca` is not `ok` | `rung` shows `?`; PARKED uses Orca signals only |
| Unacked Delivery grows | `status` footer shows the oldest unacked Delivery age | the operator replies; the backend never acks early |

## Out of Scope

- Devin, Codex or any non-Claude Orca worker. Devin has no supervised path; Codex waits for the trial result.
- Automatic retry, stop or abandon. Orca allows those only on positive proof, and the trial counts them as operator interventions.
- Changing the default backend, the `/kit:mega` default run mode, or `commands/execute.md` (SPEC-369 owns it).
- A `kit.toml` key for the backend, a TUI, a daemon, or remote Orca servers (`--on`).
- `orca orchestration reset` in any code path.
- D8 roles or seats (`docs/research/2026-09-29-openrig-absorption.md:206-213`).

## Rollback

- Switch off: omit `--backend orca` (or unset `MEGA_BACKEND`). The default path never sources `orca-backend.sh` and never invokes `$ORCA_CMD` (AC1).
- Orca state for one mega: `bash lib/queue/orchestrate.sh orca-reset <dir>`. It stops live Dispatches from this run's map, releases them, and moves `map.tsv` aside. Worktrees and branches stay (Orca never deletes them on stop).
- Full removal: revert the change; `.orchestrate/orca/` is gitignored scratch. The global `orca orchestration reset --tasks` is a last resort only the operator runs, and only when no other Run is live.

## Touches

This spec runs after SPEC-366, not in a concurrent fan-out. The two flat files below cannot be written as directory prefixes, so the dispatch gate would serialize this spec anyway.

- lib/queue/**
- tests/fixtures/orca-stub/**
- docs/verification/orca-trial/**
- docs/implementation-notes/**
- tests/test-orchestrate-orca.sh
- commands/mega.md

## Siblings

| Spec | Relation | Files this spec avoids |
|---|---|---|
| SPEC-366 execution-view | hard dependency; consumes `board work --json` schema 1 (`### Interfaces (I/O contract)`) through `BOARD_WORK_CMD`; does not take up its suggested `src_orca` swap | `lib/board/**`, `tests/fixtures/board-work/**`, `tests/test-board-work.sh` |
| SPEC-367 ceremony-lens | none; its dispatch counts could later measure this trial | its files |
| SPEC-368 lanes-as-data | none; D8 step two (roles) waits for this trial's result | `kit.toml`, lane data |
| SPEC-369 whole-spec-dispatch | none | `commands/execute.md` |
| SPEC-371 adopt-pointer-onboarding | none | `commands/adopt.md`, onboarding files |

## Grounding

Read-only samples from Orca 1.4.209 on this host. No Run, Task or worker was created.

- `orca orchestration run-list --json` returned one Run: `{"id":"run_legacy_local","objective":"Legacy orchestration state (inspect only)","legacy":1,...}`.
- `orca orchestration task-list --run run_legacy_local --json` returned `{"runId":"run_legacy_local","legacyReadOnly":true,"tasks":[],"count":0}`. **Task row fields are unsampled**: no Task exists and creating one is forbidden while researching. Status values come from `task-update` notes: `pending, ready, dispatched, completed, failed, blocked`. T6 captures a real row.
- `orca orchestration worker-list --limit 2 --json` returned `{"workers":[],"counts":{},"page":{"limit":2,"total":0,"hasMore":false,"nextCursor":null},"scope":{"source":"all"}}`. **Row fields are unsampled**; `projection.liveness` (`live | unverifiable | exited`), `projection.attention` and `projection.nextAction` come from skill line 57-59 and 576-580.
- `orca orchestration gate-list --run run_legacy_local --json` returned `{"runId":"run_legacy_local","gates":[],"count":0}`. Gate row fields unsampled.
- `orca repo list --json` includes `{"id":"4f2645e1-...","path":"/Users/tieubao/workspace/dwarvesf/dwarves-kit","displayName":"dwarves-kit"}`; `orca repo show --help` confirms selector form `path:<path>`.
- `worker-show` `observation.agentWait` semantics (present, null, absent) come from its `--help` notes, unsampled.

**Negative control dry trace (AC4).** Mutation: delete the `exited` alternative from rule 6 in `derive`. Fixture reads: stub state has SG-02's Task `dispatched`, its dispatch liveness `exited`, no gate, no question, and `BOARD_WORK_CMD` returns SG-02's row with `flags: []`. Code path: `orchestrate.sh status` -> `derive` -> rules 1 to 5 miss -> rule 6 no longer matches `exited` -> rule 7 needs `live`, gets `exited`, so no match -> falls to rule 9 or INDETERMINATE. Red test: `tests/test-orchestrate-orca.sh` case AC4 expects `PARKED exited` and fails; the in-file mutation check asserts that failure.

## Decision Log

- DEC-A: a non-LLM backend inside `orchestrate.sh`, not a harness and not an LLM coordinator. Reason: keep liveness and keep the conductor small. Rejected: approaches 1 and 2.
- DEC-B: supervised `worker-start --agent claude`, not `worker-launch` profiles. Reason: only a supervised Dispatch carries liveness and `agentWait`. Rejected: Devin via `dispatch --inject` (unsupervised).
- DEC-C: ROADMAP box stays the only proof of done; Orca `completed` only raises DONE-UNSEEN. Reason: no self-claim, as today.
- DEC-D: flag and env only, no config key. Reason: a committed file must not switch the runtime.
- DEC-E: rollback is per-Dispatch stop and release, never `orchestration reset`. Reason: reset is global.
- DEC-F: a synthesized public fixture for the trial. Reason: both open real megas touch holder data or a live deploy.
- DEC-G (operator): SPEC-366 is consumed as `board work --json` schema 1 with its real keys, not guessed fields.
- DEC-H (operator): Orca row field names and the branch Orca creates are captured in trial step 0; the stub is updated from that capture.
- DEC-I (operator): local bare git remote, no GitHub; the gate sub-goal ends at an Orca decision gate, no PR.
- DEC-J (operator): two arms only, default runner versus the Orca backend.
- DEC-K (operator): an inbox Delivery is acked only after every message in it has been acted on.

## Open questions

(none open; the six earlier questions were answered by the operator, see DEC-G to DEC-K. Step 0 of the trial settles the Orca field names and branch naming.)
