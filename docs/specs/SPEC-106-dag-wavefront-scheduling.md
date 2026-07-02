# Spec: DAG-wavefront scheduling in the orchestrator
Generated: 2026-07-03
Status: DRAFT (spec-validate: NEEDS REVISION , blocked on Open-question Q1, a scope decision for Han)
Lane: full
Authorizes: ADR-0030 (Accepted) · Source brief: docs/specs/DECISION-BRIEF-dag-wavefront.md (board ID-084)

## Problem

`lib/orchestrate.sh` runs a mega-goal strictly serially: `_next()` picks the first unchecked
sub-goal and the loop waits for its grounded box-flip before starting the next. But the dependency
graph is already declared (`depends SG-NN` on ROADMAP lines) and already parsed
(`_sg_deps_blocked()`) , it just isn't used for scheduling. Sub-goals that are dep-independent and
touch disjoint files are forced to run one at a time. The 2026-07-02 kit-telemetry run is the
concrete cost: five sub-goals that only ran cleanly bottom-up because seriality avoided the
child-retarget merge dance. Operators want dep-independent sub-goals to run as concurrent waves.

## Solution

<!-- The design is pinned by the brief + ADR-0030; this spec EXECUTES it, it does not re-open it. -->

### Approaches considered

1. **Wavefront extension over shipped primitives (CHOSEN).** Compute a ready set each cycle, run it
   concurrently (small cap), reuse `dispatch-gate.sh` for disjointness, reuse worktree discipline,
   flock-guard the box flips. ~150-200 lines in `orchestrate.sh` + a flock helper. Tradeoff: a
   coarse cap-2 wave, not a true scheduler , accepted, matches the real cost profile (long-session
   cache-read is the cost center, so small waves).
2. **The full GSD-v2 engine** (ordered-graph scheduler + priority + separate crash-recovery store +
   parallel-writer locks). Rejected: ADR-0028/0030 explicitly defer this; the operator ask does not
   need it; it re-opens ADR-0017/0019 as a separate effort.
3. **A new parallel primitive separate from `/kit:dispatch`.** Rejected: `dispatch-gate.sh` already
   does prove-or-serialize; reusing it keeps ONE disjointness authority.

### Chosen approach + why

Wavefront (1). It falls out of five already-shipped pieces , the `depends` parser, the grounded
box-flip completion signal, the watchdog's session backgrounding, `dispatch-gate.sh`'s
prove-or-serialize, and the repo's worktree discipline , so it adds scheduling behavior without a
new engine or a new state store. The rejected alternatives each trade away that reuse (2 builds a
parallel engine; 3 builds a parallel gate).

### Extensibility & boundaries

- **Load-bearing dimension = wave width.** Growth = more dep-independent sub-goals ready at once.
  Bounded deliberately by the concurrency cap (default 2, configurable); the design does NOT try to
  schedule the whole frontier, it caps the wave. Raising the cap is a config change, not a redesign.
- **Unit boundaries:** (a) ready-set computation (pure function of ROADMAP boxes + deps), (b) the
  disjointness gate call over wave pairs (delegated to `dispatch-gate.sh`), (c) concurrent session
  spawn + reap (extends the watchdog backgrounding), (d) the flock-guarded box-flip helper, (e)
  per-edge handoff injection. Each is testable independently.

### Architecture

```
run() loop, per cycle:
  READY = { sg : sg unchecked AND every `depends SG-NN` of sg is checked }   # _sg_deps_blocked, exists
  WAVE  = dispatch-gate over READY pairs -> prove-disjoint keep-parallel, else serialize   # DEC-008
  for sg in WAVE[:CAP]:  spawn `claude -p` in worktree .claude/worktrees/<sg-id>   # cap default 2
  on each grounded box-flip (flock-guarded):  recompute READY, launch next wave
  crash/restart:  recompute READY from ROADMAP boxes + PR states (idempotent, no state store)
  gate sub-goal:  holds only its dependent chain; independent branches continue
```

Backward-compat invariant: a mega-goal with NO declared deps yields a ready set of exactly one
sub-goal per cycle, so behavior is byte-identical to today's serial loop.

## Technical Design

Grounded in `lib/orchestrate.sh` (500 lines) as it stands on `master`. Anchors:

- `_subgoals()` L86 , parses `- [ ] SG-NN ... , auto|gate` ROADMAP lines to `id<TAB>policy<TAB>checked`.
- `_next()` L101 , the serial pick (first unchecked); wavefront REPLACES this with a ready-set.
- `_sg_deps_blocked()` L133 , already returns a sub-goal's unchecked `depends SG-NN` tokens. The
  ready-set primitive already exists: **ready = checked==0 AND `_sg_deps_blocked` empty.**
- Event log L108-121 (`.orchestrate/events.log`, `_emit_event` / `_event_status`) , append-only,
  replay-derived, documented "a crashed/concurrent session cannot corrupt a checkbox". This is the
  concurrency-safe completion substrate.
- `_run_session_watchdog()` L312 , backgrounds `claude -p` with `&` and polls liveness via
  `kill -0` in a loop (L320). The wave spawn/reap loop REUSES this `kill -0` poll pattern (NOT
  `wait -n`, which is bash 4.3+ and absent on macOS 3.2).
- `cmd_run()` main loop L376-488 , the serial driver. Grounded completion check at L449 (re-reads
  the box after the session; advance only if flipped). Per-sub-goal routing L392, prompt build via
  temp file L412, three run paths (watchdog / stream / plain) L418-439.
- HANDOFF.md hot-file logic L267-282 (built into the prompt), overwritten by `handoff-gen` L471.

### Portability constraints (hard , macOS bash 3.2 is CI, `.github/workflows/test.yml`)

- `orchestrate.sh:33` runs `set -uo pipefail`. Every new array (ready ids, wave pids) MUST expand
  with the empty-guard `${arr[@]+"${arr[@]}"}` , the in-repo pattern at `lib/mega-merge.sh:224`
  and `lib/stack-merge.sh:127`. Copy it; do not `declare -A` (bash 4+).
- **No `flock`.** It is not on macOS by default and has zero repo usage. The lock primitive is
  `mkdir <lockdir>` (atomic on POSIX) with a stale-lock timeout , a new shared helper, since none
  exists today. All "flock-guarded" language in the brief means this mkdir-lock.
- Wave-completion wait = `kill -0` poll loop (as `_run_session_watchdog` L320), never `wait -n`.

### Interfaces (I/O contract)

- **Consumes:** ROADMAP.md sub-goal lines (`- [ ] SG-NN ... depends SG-MM`), sub-goal files, each
  sub-goal's `## Touches` section (for the gate), dep-parents' `HANDOFF-<id>.md`.
- **Produces:** concurrent `claude -p` sessions in per-sub-goal worktrees; flock-guarded box flips
  in ROADMAP.md; append-only event-log entries; per-edge `HANDOFF-<id>.md` files.
- **Invariants:** (1) a checked box is never re-run (idempotent resume); (2) an unprovably-disjoint
  pair is serialized, never run concurrently; (3) no-deps mega-goal == today, byte-identical;
  (4) box flips are atomic under concurrency (flock or the repo's lock primitive).

### Infrastructure changes

A small `orchestrate flip <id>` box-flip helper wrapped in a mutual-exclusion lock (flock if
available on the host; otherwise the portable fallback the repo already uses , to be confirmed by
pitfalls research). Per-edge handoff files replace the single hot `HANDOFF.md` (linear chain =
degenerate single-parent case).

## Task Breakdown

Grounded in the real function structure. Wavefront logic lands in NEW `_wave_*` helpers, not inlined
into `cmd_run` (already 154 lines, L335-489, the file's split candidate).

### Phase 1: Foundation (primitives, no behavior change yet)
- [ ] TASK-001: `_ready_set()` helper , emit every sub-goal with checked==0 AND `_sg_deps_blocked`
  empty (reuses L133). Acceptance: unit test over fixture ROADMAPs (linear, diamond, gated) returns
  the correct ready set each cycle; on a no-deps ROADMAP it returns exactly what `_next` would pick
  first (superset invariant).
- [ ] TASK-002: `_lock`/`_unlock` mkdir-based lock helper (stale-timeout) + `cmd_flip <dir> <id>`
  that flips a ROADMAP box under the lock. Acceptance: a test hammering N parallel `flip` calls on
  distinct boxes leaves ROADMAP.md well-formed (all N flipped, no torn lines); `flock` absent is
  fine (no flock used).

### Phase 2: Core wave loop
- [ ] TASK-003: `_wave_gate()` , take the ready set, run `dispatch-gate.sh` over its pairs, return
  the disjoint sub-set to run concurrently + the rest to serialize. Verify the gate's `## Touches`
  parser works on goal files, not just specs (pitfalls caveat). Acceptance: exit-criterion 2
  (overlapping pair serialized , negative control) as a unit test on the gate call.
- [ ] TASK-004: `_wave_run()` , spawn up to CAP (default 2) ready+disjoint sub-goals concurrently,
  each in its own worktree, poll completion via `kill -0` + grounded box-flip (reuse the
  `_run_session_watchdog` background+poll pattern L312), recompute ready set, next wave. Wire into
  `cmd_run` behind the same grounded-completion contract (L448-455). Acceptance: exit-criterion 1
  (two disjoint independents run concurrently, both land).
- [ ] TASK-005: Per-edge `HANDOFF-<id>.md` , `_build_prompt` (L267-282) injects a child's
  dep-parents' handoffs; single-parent/no-dep path keeps writing/reading plain `HANDOFF.md`
  byte-for-byte (tests/test-orchestrate.sh L42,80,93,157,179,408-485 must stay green). Acceptance:
  a diamond fixture's child prompt contains both parents' handoffs; the linear fixture is unchanged.

### Phase 3: Resilience + regression
- [ ] TASK-006: Idempotent resume , `cmd_run` recomputes the ready set from ROADMAP boxes on every
  cycle (already the model); add a test that kills mid-wave and restarts. Acceptance:
  exit-criterion 3 (no checked sub-goal re-runs).
- [ ] TASK-007: `gate`-policy sub-goal holds only its dependent chain , an independent branch's
  ready sub-goals still run while a `gate` blocks its own chain (today a gate stops the whole loop,
  L382-387). Acceptance: exit-criterion 4.
- [ ] TASK-008: `tests/test-orchestrate-wavefront.sh` with all five controls + golden linear-chain
  capture. Acceptance: exit-criterion 5 (no-deps mega-goal byte-identical to current master).

## After state

- [ ] `orchestrate.sh run` computes a ready set each cycle and runs dep-independent, disjoint
  sub-goals concurrently (cap 2). (Today: strictly serial, one sub-goal at a time.)
- [ ] `tests/test-orchestrate-wavefront.sh` exists and is green on all five controls, checkable by
  `bash tests/test-orchestrate-wavefront.sh`.
- [ ] `docs/verification/orchestrate-wavefront.md` has a five-row run-table, rows 2 and 5 marked as
  negative controls.
- [ ] A no-deps mega-goal behaves byte-identically to current master (golden capture in the test).

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] `bash tests/test-orchestrate-wavefront.sh` green on all five controls.
- [ ] No regression on the existing orchestrate test suite.
- [ ] Diff contains none of the Out-of-Scope items (scope-fail check).

## Verification

`bash tests/test-orchestrate-wavefront.sh` (all five controls green) AND the pre-existing
`bash tests/test-orchestrate.sh` (regression, confirmed present) green.

## Edge Cases
1. Ready set is empty but unchecked sub-goals remain (all blocked on an unfinished gate) , loop
   waits, does not spin or falsely complete.
2. A wave pair is dep-independent but `## Touches` is missing on one , gate cannot prove disjoint,
   so serialize (conservative).
3. Cap = 1 (config) , behaves exactly like the serial loop.
4. A worktree for a sub-goal id already exists from a prior crashed run , reuse or clean, never
   collide.
5. Two boxes flip within the same lock window , second waits, both land, event log intact.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Parallel writers corrupt ROADMAP.md | garbled boxes / lost flip | flock-guarded `flip` helper; append-only event log is the source of truth |
| `flock` absent on host (macOS) | helper errors / no mutual exclusion | portable lock fallback (confirm repo's existing primitive in pitfalls research) |
| Disjointness gate false-negative (serializes safe pair) | slower than ideal, never unsafe | acceptable by design (conservative); logged |
| Disjointness gate false-positive (parallel unsafe pair) | `.git/index.lock` / merge conflict | one worktree per session isolates writers; drift guard after |
| Crash mid-wave leaves a half-done sub-goal | box unchecked, worktree present | idempotent resume recomputes ready set; unchecked = re-runnable |

## Out of Scope
- Priority scheduling · cross-machine execution · new retry policies · a separate crash-recovery
  state store · speculative execution · DAG visualization beyond the existing board. (ADR-0030's
  GSD-v2 boundary; any of these in the diff = scope failure.)
- `/kit:dispatch` (untouched), `lib/mega-merge.sh` semantics, the ops-toolkit skill.

## Touches
<!-- This spec is NOT run via /kit:dispatch (it is a single-writer full-lane build), so Touches is
     informational, not gate-required. Primary write surfaces: -->
- lib/**
- tests/**
- docs/verification/**

## Decision Log
- DEC-001: Reuse `dispatch-gate.sh` for wave-pair disjointness rather than a new gate , ONE
  disjointness authority; rejected building a parallel primitive.
- DEC-002: Concurrency cap default 2 (configurable) , the cost center is long-session cache-read
  (2026-07-02 token audit), so small waves; rejected unbounded frontier scheduling.
- DEC-003: No separate state store; resume recomputes from ROADMAP boxes + PR state , stays inside
  ADR-0030's boundary (a state store is GSD-v2).
- DEC-004: Reconcile the 2026-05-22 concurrent-goal-dispatch note's "wave = tripwire to gsd-2" rule
  , wavefront over declared `depends` edges is in-kit (needs no runtime machinery); a true durable
  runtime still routes to gsd-2. Recorded in ADR-0030 "Reconciliation" + a supersession pointer on
  the note. (Surfaced by architecture research; flagged to Han in the loop report.)
- DEC-005: Lock primitive is `mkdir <lockdir>` + stale-timeout, NOT `flock` (absent on macOS CI).
  New shared helper; wave-completion wait is a `kill -0` poll (as `_run_session_watchdog`), not
  `wait -n` (bash 4.3+). Arrays empty-guarded `${arr[@]+"${arr[@]}"}` per `lib/mega-merge.sh:224`.

## Review

### Verdict: NEEDS REVISION (spec-validate, 2026-07-03, 5-lens adversarial)

One scope decision blocks re-validation (see Open questions Q1); the rest are fixes applied in the
revision pass. Findings, deduped across the five lenses:

**Load-bearing (blocks): the `## Touches` reuse assumption is false.**
- V-CRIT-1: 0 of 684 real sub-goal files carry a `## Touches` section; no generator emits one.
  `dispatch-gate.sh gate_disjoint` returns exit-2 REJECT with no Touches, and `gate_plan` maps that
  to "serialize". So on every real mega-goal, every wave pair serializes , concurrency is inert on
  real data; the feature ships as a serial loop unless sub-goals gain Touches. -> Q1 decides scope.

**Critical (fix in revision, fork-independent):**
- V-CRIT-2: ROADMAP.md is per-worktree. A session flipping its box in its own worktree checkout is
  invisible to the driver reading the shared mega-goal-dir copy , grounded completion (L449) never
  sees the flip; the lock is irrelevant (different files). Fix: the `flip` helper targets the
  SHARED mega-goal-dir ROADMAP via absolute path (outside any worktree); completion is read there.
- V-CRIT-3: No wave-convergence step. N green sub-goal branches never merge back to advance the
  mega-goal. Fix: add a convergence task , the lead merges wave branches one-at-a-time under a
  merge lock (reusing `mega-merge.sh` one-at-a-time; its SEMANTICS stay untouched per scope).
- V-CRIT-4: `_wave_gate` partition undefined , pairwise disjointness does not compose (A⊥B, B⊥C,
  A∩C). Fix: greedy-in-ROADMAP-order admission , admit a ready sub-goal iff it proves disjoint
  against every already-admitted wave member, stop at CAP, defer the rest. No-deps falls out
  byte-identical.
- V-CRIT-5: TASK-004 not atomic. Split into 004a (`_wave_run` spawn/reap primitive: worktree-per-sg,
  pid->sg-id map, `kill -0` poll-all, done-vs-died distinction, siblings drain on a sibling's
  failure, trap to reap/kill all wave PIDs) and 004b (wire into `cmd_run` at the grounded-completion
  contract L448-455 + next-wave recompute, serialized under the flip lock to avoid CAP overshoot /
  double-launch).
- V-CRIT-6: Per-edge HANDOFF fixes only the READ side (TASK-005 touches `_build_prompt`); the WRITE
  side still clobbers , the session instruction (L282 "overwrite HANDOFF.md") and `handoff-gen`
  (L471) both write one hot file. Fix: conditional rule , no-deps writes plain `HANDOFF.md`
  (byte-identical, keeps tests/test-orchestrate.sh green); deps write/read `HANDOFF-<id>.md`.
  Reconcile the `DETERMINISTIC_HANDOFF` gen path (L465-478) under CAP>1.
- V-CRIT-7: `gate` human-stop silently narrowed global->chain , an autonomy-gate weakening: the
  scheduler mutates other branches while a human is at a checkpoint. Fix: keep `gate` = chain-stop
  but add `gate!` = stop-all opt-out; state the semantic change explicitly.

**Warnings (fix in revision):** event-log append atomicity only holds under PIPE_BUF (512B) , cap
the `note` field; reader-writer torn read of ROADMAP , reader takes the lock or flips are
write-temp-then-`mv`; `WAVE_CAP` env var (name it, default 2, validate `>=1` numeric, parse like
`WATCHDOG_STALL_SECS`) + add to Interfaces "Consumes"; pin helper stdout wire formats
(`_ready_set` -> `id<TAB>policy`; `_wave_gate` -> `run<TAB>id` / `defer<TAB>id`; `_wave_run` consumes
`run` lines); extract a shared `_run_one_session` helper FIRST so serial stays byte-identical and all
three run-paths (watchdog/--stream/plain) are preserved for both serial and wave; stale-worktree
(edge 4) reuse-or-clean rule pinned into 004a (detect dirty-vs-clean, never blind `git worktree add`);
mkdir-lock at `$dir/.orchestrate/flip.lock` (not `/tmp`), PID-liveness stale reclaim via `rmdir` +
`[ -n "$lockdir" ]` guard (never `rm -rf`), timeout value stated; termination (ready-empty +
unchecked-remain -> wait, not false-complete) owned by a task + acceptance; serialize order
deterministic (ROADMAP order), unprovable-disjoint logged (safe vs corruption, not vs wrong-ordering);
gate exit-2 (undeclared) handled as quiet conservative serialize, distinct from exit-1 (overlap);
inter-task `depends TASK-NN` edges declared; concurrency test needs a mock-barrier fifo to PROVE
temporal overlap (a serial impl must FAIL criterion 1); add a criterion asserting a real
Touches-less mega-goal serializes (makes the V-CRIT-1 gap visible, not hidden); `.gitignore` add
`_meta/megagoals/**/{HANDOFF*.md,.orchestrate/}` + `*.session.log` + `*.stream.jsonl` (session logs
can carry resolved `op://` values). Security surface otherwise minimal; stdin-injection discipline is
preserved by keeping the multi-parent concat inside `_build_prompt`'s stdout.

## Open questions

- **Q1 (BLOCKS re-validation , scope decision for Han).** Sub-goal files carry no `## Touches`
  section (0/684) and no generator emits one, so `dispatch-gate.sh` reuse serializes every real wave
  , the feature is inert on real mega-goals as scoped. Two ways forward:
  - **Option A , make it work now (expands scope):** add a `## Touches` schema for sub-goal files +
    teach the sub-goal generator (`commands/mega.md`) to emit it, as part of THIS goal. Cost: the
    brief's "In" scope did not include the generator; adds an authoring convention others depend on.
    Payoff: concurrency actually runs on real mega-goals; delivers the operator's ask.
  - **Option B , ship opt-in + defer (tight scope):** ship the wavefront machinery + fixtures + a
    documented "concurrency is opt-in: a sub-goal must declare `## Touches` to be wave-eligible;
    absent it, it serializes (safe)"; file the generator/schema retrofit as a follow-up board row.
    Cost: inert on today's mega-goals until the follow-up lands. Payoff: stays inside the brief's
    literal "In" list; smallest diff; fully reversible.
  - **Recommendation: Option A (minimal).** Shipping a concurrency feature that never runs
    concurrently on any real mega-goal defeats the brief's own motivation (the kit-telemetry serial
    cost). The generator change is small (an optional `## Touches` block in the sub-goal template) and
    the retrofit of existing sub-goals can stay lazy (they serialize until edited). But it does widen
    scope past the brief, so it is Han's call, not the loop's.
