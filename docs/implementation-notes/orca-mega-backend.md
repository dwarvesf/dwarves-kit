# Implementation notes: Orca mega backend

Delta from `docs/specs/SPEC-370-orca-mega-backend.md`. The spec is the contract; this file lists only where the build differs from it, narrows it, or leaves a gap.

| # | Item | Spec says | Build does | Why |
|---|---|---|---|---|
| 1 | Orca row field names | unsampled until trial step 0 | Stub and backend assume: Task `{id, title, status, deps, runId}`; worker row `{dispatchId, taskId, dispatchStatus, terminalState, projection.liveness, observation.agentWait}`; gate `{id, taskId, status, resolution}`; inbox `{messages[{id, type, taskId, dispatchId, replyTo, createdAt}]}`; check `{delivery{id, messages[]}}`; run-create `{id}` | the documented names only start the list; step 0 replaces them. Unknown fields read as absent, so a wrong name yields INDETERMINATE, never a false DONE |
| 2 | Admission | reuse `_wave_gate` | uses `dispatch-gate.sh disjoint` (the authority `_wave_gate` calls) and `WAVE_CAP` directly | `_wave_gate` never admits a `gate` sub-goal and demands `## Touches` from the first member; both would stop a serial Orca run. Slots count RUNNING and PARKED workers |
| 3 | Pre-flight order | `--version`, then lock, then Harness checks | Harness, Model tier and SG fan-in checks first, then `--version`, then the lock | AC10 wants zero Orca calls on a `Harness: codex` goal, and `--version` is an Orca call |
| 4 | Test seams | not named | `ORCA_MAX_TICKS` (unset = unbounded, 0 = plan only) and `ORCA_BACKEND_LIB` (load a mutated copy) | the suite needs a tick bound and the in-file mutation check needs a swap point |
| 5 | `status` reads | four reads plus `check` per poll | `status` never calls the consuming `check`; only a tick does. The footer uses `check --peek` | a read verb must not mark mail read. An earlier draft consumed a Delivery from `status` and split one batch into two acks |
| 6 | Gate creation | on a completed gate Task | also needs the branch on origin, else a `blocked` event | the question carries the branch sha, and a gate over an unpushed branch has nothing to accept |
| 7 | Events | `shipped`, `blocked` | adds status `held` (gate opened). Notes read `dispatch=<id> task=<id>: <reason>`. The gate accept note is exactly `gate <id> accept` | rule 4 and DONE-UNSEEN key on the Dispatch; `held` marks the `worker_done` as acted on without reading BLOCKED |
| 8 | Failed `worker_done` | acted on when DONE or BLOCKED is recorded | also acted on when the Task is `failed` | otherwise a failed worker holds the Delivery and all later mail forever |
| 9 | `worker-start` failure | record `blocked`, show INDETERMINATE | same, via a `dispatch=-` blocked event whose note holds `worker-start exit N`; the prior-Dispatch guard reads it, so the backend never relaunches. `request-show` is not called | the operator inspects and retries by hand |
| 10 | `orca-reset` | stop, release, block, move map | also refuses with exit 75 while a live runner holds `run.lock`, and moves the `run` file aside with the map | a live runner would re-plan into the moved map. A new run after reset must create a new Run |
| 11 | Plan | a Task per sub-goal | a Task per UNCHECKED sub-goal; dependencies on checked sub-goals are dropped | a checked sub-goal has no worker to wait for |
| 12 | Gate ledger START | not mentioned | not emitted under this backend | keeps the backend to the spec's scope; the default path still emits it |
| 13 | View fallback | `board work` flags feed rule 7 | `PARKED` counts only when top-level `orca` is `ok`; the `files-idle` advisory is not read separately | the spec says a non-ok view means no idle signal |

## Gaps left for the trial (PARTIAL)

| Gap | Where | Closed by |
|---|---|---|
| Live Orca row shapes and the Task id on `worker-list` rows unverified | `lib/queue/orca-backend.sh` `_orca_sg_state`, `_orca_latest_disp`; `tests/fixtures/orca-stub/orca` | trial step 0 (`docs/verification/orca-trial/RUNBOOK.md`) |
| Branch Orca creates for `--worktree new-top-level --name` unverified | `_orca_dispatch` | step 0 |
| Nested-depth refusal (Edge 5): `worker-start` failure becomes a `blocked` event, not a run halt | `_orca_dispatch` | step 0 records the refusal text; then a halt can match it |
| Stop-then-retry behavior of a live Dispatch unverified | operator path only, no backend code | step 0 |
| Trial arms, AC12, AC14 | not built | lead |

## Zero-deviation check

Rules 1 to 10 of the state table, the CLI surface, the run lock, the ack rule and the rollback verb follow the spec. Every AC that runs against the stub (AC1 to AC10, AC13, AC15, AC16) is covered by `tests/test-orchestrate-orca.sh`.
