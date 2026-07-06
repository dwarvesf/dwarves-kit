# Spec: DAG-wavefront scheduling in the orchestrator
Generated: 2026-07-03
Status: SHIPPED-PENDING (PR #125). Shipped as Q1 Option B (opt-in), then ACTIVATED in the same PR per
Han "do it all now": ID-090 (a generator + b flip-injection + c merge arity + d dep-aware halt) done
and `WAVE_CAP` default flipped 1->2 (waves ON by default; `WAVE_CAP=1` forces serial). The Option-B
framing below is the spec's shipped-design history; the default flip is the ID-090 amendment on top
(DEC-002 recorded default 1 at design time). See `docs/verification/orchestrate-wavefront.md`.
Lane: full
Authorizes: ADR-0030 (Accepted) · Source brief: docs/specs/DECISION-BRIEF-dag-wavefront.md (board ID-084)

## Problem

`lib/queue/orchestrate.sh` runs a mega-goal strictly serially: `_next()` picks the first unchecked
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
  Bounded deliberately by the concurrency cap `WAVE_CAP` (default 1 = off, opt-in to `>=2`); the design does NOT try to
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
  for sg in WAVE[:CAP]:  spawn `claude -p` in worktree .claude/worktrees/<sg-id>   # WAVE_CAP, default 1 (off)
  on each grounded box-flip (flock-guarded):  recompute READY, launch next wave
  crash/restart:  recompute READY from ROADMAP boxes + PR states (idempotent, no state store)
  gate sub-goal:  holds only its dependent chain; independent branches continue
```

Backward-compat invariant: a mega-goal with NO declared deps yields a ready set of exactly one
sub-goal per cycle, so behavior is byte-identical to today's serial loop.

## Technical Design

Grounded in `lib/queue/orchestrate.sh` (500 lines) as it stands on `master`. Anchors:

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
  with the empty-guard `${arr[@]+"${arr[@]}"}` , the in-repo pattern at `lib/goal/mega-merge.sh:224`
  and `lib/goal/stack-merge.sh:127`. Copy it; do not `declare -A` (bash 4+).
- **No `flock`.** It is not on macOS by default and has zero repo usage. The lock primitive is
  `mkdir <lockdir>` (atomic on POSIX) with a stale-lock timeout , a new shared helper, since none
  exists today. All "flock-guarded" language in the brief means this mkdir-lock.
- Wave-completion wait = `kill -0` poll loop (as `_run_session_watchdog` L320), never `wait -n`.

### Structural design (from spec-validate; the byte-identical invariant rides on THIS)

The invariant "no-deps mega-goal == today, byte-identical" is guaranteed STRUCTURALLY, not by a
golden test alone:

1. **Extract `_run_one_session()` FIRST** (surgical refactor, zero behavior change) , lift the
   three run-paths (watchdog / `--stream` / plain, L418-439) out of `cmd_run` into one helper keyed
   on `dir id pfile route_flags`. Serial and wave both call it, so all three paths are preserved for
   both and never forked. This is TASK-000, lands + tests green before any wave code.
2. **Dispatch on ADMITTED size, not raw ready size.** `_ready_set` returns ALL unchecked sub-goals
   with no blocking deps , for a no-deps mega-goal that is every unchecked sub-goal (size N), NOT 1
   (nothing blocks them). So raw size cannot gate the serial path. Instead: run `_wave_gate` first,
   then if `admitted <= 1` OR `WAVE_CAP == 1`, run the EXISTING serial body unchanged
   (`_run_one_session` on the FIRST ready sub-goal , exactly `_next`'s pick). Only `admitted >= 2`
   routes to `_wave_run`. A Touches-less mega-goal (every real one today) admits 0 -> serial fallback
   on the first ready pick -> byte-identical. `WAVE_CAP` defaults to **1** (see DEC-002), so waves are
   opt-in and default behavior is byte-identical.
3. **Greedy-in-ROADMAP-order admission** (`_wave_gate`) , a ready sub-goal is admitted iff (a) it
   declares its OWN `## Touches` section AND (b) it proves disjoint (`dispatch-gate.sh gate_disjoint`)
   against EVERY already-admitted wave member; stop at `WAVE_CAP`; defer the rest. Self-Touches is the
   real opt-in gate: `gate_plan` admits the first member vacuously, so without the self-Touches
   requirement a Touches-less sub-goal would be wrongly admitted. Deterministic (ROADMAP order); the
   no-deps / Touches-less / CAP=1 cases all fall through to the serial body.

### Completion + convergence (from spec-validate)

- **Flip targets the SHARED mega-goal-dir ROADMAP via absolute path**, outside any worktree. Sessions
  run in per-sub-goal worktrees (separate checkouts), so a box flip must NOT go to the worktree's own
  ROADMAP copy (the driver would never see it). `cmd_flip <megadir> <id>` writes `$megadir/ROADMAP.md`
  (absolute), and the session's contract calls `cmd_flip`, not a local `sed`. The event log
  (`$megadir/.orchestrate/`) is likewise shared. **Deferral (Option-B):** injecting the `cmd_flip
  <abs-megadir> <id>` instruction into a real wave session's PROMPT is authoring-adjacent (it changes
  what sessions are told), so it bundles with real-wave activation in ID-090. Until then the
  `cmd_flip` helper exists + is unit-tested and the mock-barrier tests script it, but real wave
  sessions are not yet wired (waves are `WAVE_CAP`-opt-in and Touches-gated, so none run by default).
- **Wave convergence:** after a wave's sessions land on their worktree branches, the lead merges them
  **one-at-a-time under the flip lock** (reusing `lib/goal/mega-merge.sh` one-at-a-time; its SEMANTICS are
  untouched per scope , this only sequences existing merges). Concurrent same-base merges never race.

### Locking (from spec-validate)

- `_lock`/`_unlock` = `mkdir "$megadir/.orchestrate/flip.lock"` (atomic; NOT `/tmp`, same trust
  domain as the ROADMAP it guards). Holder writes its PID to `flip.lock/pid`.
- **Stale reclaim = PID-liveness, not bare mtime:** reclaim only when `[ -n "$lockdir" ]` AND the
  recorded PID fails `kill -0` (crashed holder) OR age exceeds `FLIP_LOCK_STALE_SECS` (default 120)
  AND PID dead. Reclaim with `rmdir` (refuses non-empty/odd paths), never `rm -rf`.
- The **reader takes the same lock** for ready-set recompute, OR flips are write-temp-then-`mv`
  (atomic rename) so a reader never sees a torn ROADMAP.
- The **recompute-and-launch decision is serialized under the lock** so two near-simultaneous
  completions cannot both launch and overshoot `WAVE_CAP` / double-launch a now-ready sub-goal.

### Interfaces (I/O contract)

- **Consumes:** ROADMAP.md sub-goal lines (`- [ ] SG-NN ... , auto|gate|gate! [depends SG-MM]`);
  sub-goal files; each sub-goal's OWN `## Touches` section IF PRESENT (opt-in, per Q1/Option-B ,
  absent => never wave-admitted, runs serial); dep-parents' `HANDOFF-<id>.md` (falls back to plain
  `HANDOFF.md` if absent); env `WAVE_CAP` (**default 1** = waves off, byte-identical; integer
  `>=1`, parsed like `WATCHDOG_STALL_SECS`; `<1`/non-numeric rejected), `FLIP_LOCK_STALE_SECS`
  (default 120).
- **Produces:** up to `WAVE_CAP` concurrent `claude -p` sessions in per-sub-goal worktrees
  (`.claude/worktrees/<id>`); lock-guarded box flips in the SHARED `$megadir/ROADMAP.md`; append-only
  event-log entries (`note` field truncated `< PIPE_BUF` = 512B so concurrent appends stay atomic);
  `HANDOFF-<own-id>.md` iff the sub-goal HAS DEPENDENTS (something `depends` on it), else plain
  `HANDOFF.md` (a leaf / linear-tail stays byte-identical).
- **Helper wire formats** (bash-3.2: no assoc-arrays/namerefs; stdout lines are the contract):
  `_ready_set` -> `id<TAB>policy` lines (like `_subgoals`); `_wave_gate` -> `run<TAB>id` /
  `defer<TAB>id` lines; `_wave_run` consumes the `run` lines and maintains an in-band `pid<TAB>id`
  reap map (poll-all `kill -0`, map each dead PID back to its sub-goal for the grounded check).
- **Invariants:** (1) a checked box is never re-run (idempotent resume); (2) an unprovably-disjoint
  OR Touches-less pair is serialized, never concurrent; (3) no-deps mega-goal == today,
  byte-identical (guaranteed by the size-dispatch above, verified by the golden); (4) box flips +
  the launch decision are atomic under the flip lock; (5) a sibling's nonzero exit lets in-flight
  siblings DRAIN to completion in their isolated worktrees, then the run is marked failed (a `trap`
  reaps/kills the wave's PID set on abort , no orphaned `claude -p` children).

## Task Breakdown

Grounded in the real function structure. Wavefront logic lands in NEW `_wave_*` helpers, never inlined
into `cmd_run` (already 154 lines, L335-489). `depends` edges declared per task (this is a
wavefront spec; it eats its own dogfood).

### Phase 0: Surgical refactor (zero behavior change; unblocks byte-identity)
- [x] TASK-000: Extract `_run_one_session()` , lift the three run-paths (watchdog / `--stream` /
  plain, L418-439) out of `cmd_run` into one helper. Acceptance: `bash tests/test-orchestrate.sh`
  stays fully green (byte-identical serial behavior); `cmd_run` shrinks; no wave code yet.
  DONE (commit b5d4d17, verified: task-verifier PASS 4/4, test-orchestrate 59/59).

### Phase 1: Foundation primitives (no scheduling change yet)
- [x] TASK-001: `_ready_set()` , emit every sub-goal with checked==0 AND `_sg_deps_blocked` empty
  (reuses L133), stdout `id<TAB>policy`. Acceptance: unit test over fixtures (linear, diamond, gated)
  returns the correct ready set; on a no-deps ROADMAP it returns exactly `_next`'s first pick
  (size-1 superset invariant). depends: none.
  DONE (commit 01544a0, verified: task-verifier PASS 4/4; wavefront 16/16, orchestrate 59/59). Added
  the house source-guard so the file is unit-test-sourceable (behavior-preserving).
- [x] TASK-002: `_lock`/`_unlock` (mkdir at `$megadir/.orchestrate/flip.lock` + PID file;
  PID-liveness stale reclaim via `rmdir`, `[ -n ]` guarded, `FLIP_LOCK_STALE_SECS` default 120) +
  `cmd_flip <megadir> <id>` flipping the SHARED absolute-path ROADMAP under the lock (write-temp-then
  -`mv`). Acceptance: N parallel `flip` on distinct boxes -> ROADMAP well-formed, no torn lines; a
  test that kills a flip mid-lock -> next flip reclaims (PID dead). depends: none.
  DONE (commit 21cceb0 + fix 73e342c, verified: task-verifier PASS 4/4 with adversarial live-holder +
  6-way parallel hammer; wavefront 29/29, orchestrate 59/59). 3-state PID staleness; `FLIP_LOCK_POLL_SECS`=0.1.

### Phase 2: Core wave loop
- [x] TASK-003: `_wave_gate()` , greedy-in-ROADMAP-order admission: admit a ready sub-goal iff (a)
  it declares its OWN `## Touches` AND (b) it proves disjoint (`dispatch-gate.sh gate_disjoint`)
  against every already-admitted member; stop at `WAVE_CAP`; stdout `run<TAB>id` / `defer<TAB>id`.
  Self-Touches is required because `gate_plan` admits the first member vacuously , without it a
  Touches-less sub-goal would be wrongly admitted. Acceptance: (i) exit-criterion 2 (Touches-declaring
  but OVERLAPPING pair -> second deferred, negative control); (ii) a Touches-LESS ready set ->
  all-`defer` (opt-in gate holds). depends: TASK-001.
  DONE (commit b3793bd, verified: task-verifier PASS 6/6 with independent adversarial fixture + `$-`
  no-`set -e`-leak probe; wavefront 35/35). Reuses dispatch-gate via SUBPROCESS to contain its `set -e`.
- [x] TASK-004a: `_wave_run()` primitive , spawn the `run` set (each in `.claude/worktrees/<id>`,
  reuse-or-recreate on a stale worktree: reuse only if clean + branch/box matches the resume, else
  recreate; never blind `git worktree add`), background via `_run_one_session`, maintain a
  `pid<TAB>id` reap map, poll-all `kill -0`, on each dead PID do the grounded box-flip check for THAT
  id; a sibling nonzero-exit lets in-flight siblings DRAIN then marks the run failed; `trap` reaps/
  kills all wave PIDs on abort. Acceptance: standalone test , two mock sessions run with proven
  temporal overlap (mock-barrier fifo: session A's mock blocks until B's mock signals; timeout =
  not-concurrent = FAIL), both land; a sibling-fail case drains + reports failed, no orphans.
  depends: TASK-000, TASK-001, TASK-002.
  DONE (commit d028331, verified: task-verifier PASS, 9 flake-free runs, EMPIRICALLY reproduced
  serial-fails-the-mock-barrier; the test caught+fixed a live awk+mv flip race, now flips via the
  locked CLI). Coverage follow-up for TASK-009: add isolated tests for the "exits 0 but box unflipped"
  branch and the internal `checked=1` skip.
- [x] TASK-004b: Wire `_wave_run` into `cmd_run` , size-dispatch on ADMITTED count: run
  `_wave_gate` first; if `admitted<=1` OR `WAVE_CAP==1` -> the UNTOUCHED serial body on the first
  ready pick (`_next`'s pick); else -> `_wave_run` on the admitted set. Recompute-and-launch
  serialized under the flip lock. Acceptance: exit-criterion 1 (two Touches-disjoint independents run
  concurrently at `WAVE_CAP=2`) AND a no-deps/Touches-less mega-goal takes the serial body
  (admitted==0). depends: TASK-003, TASK-004a.
  DONE (commit 5ebdcfa, verified: task-verifier PASS 4/4; byte-identity diff +39/-0 serial body
  untouched, guard short-circuits at default; WAVE_CAP=0/abc/-1 exit 64; wave path reachable via
  barrier test; test-orchestrate 59/59, wavefront 53/53 x3 no flake).
- [x] TASK-004c: Wave convergence SEQUENCER , `_wave_converge` merges landed wave sub-goals
  one-at-a-time in ROADMAP order under the flip lock via a MOCKABLE merge hook (real `gh pr merge`
  through `lib/goal/mega-merge.sh` rides with ID-090, same deferral as the flip-contract , waves
  are off at default WAVE_CAP=1, and real merge needs `gh`/real PRs). `mega-merge.sh` semantics
  untouched (only sequenced). Acceptance: a mock-merge test asserts two landed sub-goals merge
  strictly one-at-a-time (never concurrently) in ROADMAP order under the lock; a same-file cross-wave
  edit is flagged, not silently clean-merged. depends: TASK-004b.
  DONE (commit 44f36d8, verified: task-verifier , serialization proven by interleave assertion,
  same-file flagged, `mega-merge.sh` untouched, byte-identical serial; test-orchestrate 59/59,
  wavefront 61/61). `WAVE_MERGE_CMD` mockable; real gh merge deferred to ID-090.
- [x] TASK-005: Per-edge HANDOFF (read AND write, keyed on DEPENDENTS) , a sub-goal writes
  `HANDOFF-<own-id>.md` iff some sub-goal `depends` on it (has dependents); the session-write
  instruction (L282) and `handoff-gen` (L471) target that file, else plain `HANDOFF.md`.
  `_build_prompt` (new signature, reads `depends`) injects each dep-parent's `HANDOFF-<parent>.md`,
  FALLING BACK to plain `HANDOFF.md` if the per-edge file is absent (so a chain root that wrote plain
  HANDOFF still feeds its child). Reconcile the `DETERMINISTIC_HANDOFF` gen path (L465-478) under
  CAP>1. Acceptance: a diamond child prompt contains both parents' handoffs; the LINEAR/no-dependents
  fixture writes+reads plain `HANDOFF.md` byte-for-byte (tests/test-orchestrate.sh
  L42,80,93,157,179,408-485 green). depends: TASK-004b.
  DONE (commit 089ea23, verified: task-verifier PASS 5/5; write keyed on DEPENDENTS , V-CRIT-6 root
  case passes; read-side additive `elif`, fallback + diamond tested; test-orchestrate 59/59 zero-diff,
  wavefront 67/67).

### Phase 3: Resilience, gate semantics, regression
- [x] TASK-006: Idempotent resume + wait-vs-complete termination , `cmd_run` recomputes ready from
  ROADMAP each cycle; when ready==empty AND unchecked>0 it WAITS (does not false-complete); done only
  when unchecked==0. Acceptance: exit-criterion 3 (kill mid-wave, restart, no checked sub-goal
  re-runs) + a test that ready-empty+unchecked-remain waits. depends: TASK-004b.
  DONE (commit c3bebaa, verified: task-verifier; resume already correct , proven by runlog test;
  found+fixed a REAL wave-path bug , dep-blocked fallthrough to `_next` false-completed; guard halts
  with nonzero; byte-identical serial; test-orchestrate 59/59, wavefront 72/72). Deferred to
  ID-090: dep-aware serial-fallback pick when ready is non-empty.
  UPDATE (review-team fixes, 2026-07-03): ID-090 item (d) is now DONE, not deferred , the WAVE_CAP>=2
  fallthrough verifies `_next`'s pick is a member of `_ready_set` before running it, halting with a
  "dep-blocked (not in ready set)" message otherwise. See `docs/implementation-notes/dag-wavefront.md`
  "2026-07-03 review-team fixes" and `_meta/BACKLOG.md` ID-090.
- [x] TASK-007: `gate` = chain-stop (holds only its dependent chain; independent branches keep
  running) + NEW `gate!` = stop-all (preserves today's global human-stop, L382-387, for operators who
  want quiesce-everything). Acceptance: exit-criterion 4 (a `gate` holds its chain while an
  independent branch completes) + a `gate!` test that halts the whole loop. depends: TASK-004b.
  DONE (commit 4521d39, verified: task-verifier; policy parse `auto|gate|gate!`; `_wave_gate` defers
  gate sub-goals so chain-hold + independent-branch-runs proven end-to-end (exit-crit 4); `gate!`
  global-stop both paths; serial `gate` byte-identical; test-orchestrate 59/59, wavefront 80/80).
- [x] TASK-008: `.gitignore` add `_meta/megagoals/**/{HANDOFF*.md,.orchestrate/}`, `*.session.log`,
  `*.stream.jsonl` (session logs can carry resolved `op://` values; per-edge handoffs multiply the
  surface). Acceptance: `git status` on a mega-goal mid-run shows none of these as tracked/eligible.
  depends: none.
  DONE (commit 9e55427, done inline + verified: `git check-ignore` confirms all 3 artifact types
  ignored; also `__pycache__/*.pyc` + untracked the one stray tracked `.pyc`; suites green).
- [x] TASK-009: `tests/test-orchestrate-wavefront.sh` , the five controls (mock-`CLAUDE_CMD`, no real
  sessions) + golden linear-chain capture + **an Option-B honesty control: a real Touches-less
  mega-goal's `goals/` dir gates to all-`defer` (serializes), asserting the inert-until-Touches
  behavior is visible, not hidden**. Acceptance: exit-criterion 5 (no-deps byte-identical) + all five
  green + the Touches-less-serializes assertion. depends: TASK-004b, TASK-004c, TASK-005, TASK-006, TASK-007.
  DONE (commit 4854ba9; all 5 EXIT-CRITERION markers labeled + grep-able, 2 & 5 negative controls,
  Option-B honesty control, exits-0-unflipped coverage; wavefront 89/89 no-flake x3, orchestrate 59/59;
  test-only, no lib change).

## After state

- [ ] `orchestrate.sh run` computes a ready set each cycle and runs dep-independent, disjoint,
  Touches-declaring sub-goals concurrently when `WAVE_CAP>=2` (default 1 = off), each in its own
  worktree, merging landed branches back one-at-a-time. (Today: strictly serial, one at a time.)
- [ ] A sub-goal WITHOUT a `## Touches` section serializes (Option-B opt-in), and TASK-009 asserts
  this visibly. (Today: N/A , no wave path.)
- [ ] `_run_one_session` extracted; a no-deps mega-goal takes the untouched serial path and is
  byte-identical to current master (golden capture + `bash tests/test-orchestrate.sh` green).
- [ ] `tests/test-orchestrate-wavefront.sh` exists and is green on all five controls (+ the
  Touches-less-serializes control), checkable by `bash tests/test-orchestrate-wavefront.sh`.
- [ ] `docs/verification/orchestrate-wavefront.md` has a five-row run-table, rows 2 and 5 marked as
  negative controls.
- [ ] `gate!` global-stop exists alongside `gate` chain-stop; `.gitignore` covers the new
  handoff/session-log surface.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] `bash tests/test-orchestrate-wavefront.sh` green on all five controls.
- [ ] No regression on the existing orchestrate test suite.
- [ ] Diff contains none of the Out-of-Scope items (scope-fail check).

## Verification

`bash tests/test-orchestrate-wavefront.sh` (all five controls green) AND the pre-existing
`bash tests/test-orchestrate.sh` (regression, confirmed present) green.

## Edge Cases
1. Ready set empty but unchecked sub-goals remain (blocked on an unfinished gate) , loop WAITS, does
   not spin or false-complete (TASK-006).
2. A ready sub-goal has no `## Touches` , `gate_disjoint` exit-2 => quiet `defer` => serialize
   (Option-B opt-in). With ALL sub-goals Touches-less, the whole run serializes (TASK-009 asserts it).
3. `WAVE_CAP=1` , size-dispatch takes the untouched serial body (byte-identical).
4. `WAVE_CAP` = 0 / non-numeric , rejected at parse with a clear error (never no-spawn / infinite
   wait).
5. A worktree for a sub-goal id exists from a prior crashed run , reuse only if clean AND branch/box
   matches the resume, else recreate; never blind `git worktree add`.
6. Two boxes flip within the same lock window , second waits on the mkdir-lock, both land, event log
   intact.
7. Two sessions complete near-simultaneously , the recompute-and-launch decision is serialized under
   the flip lock, so `WAVE_CAP` is never overshot and no sub-goal double-launches.
8. A `gate!` sub-goal is reached , the whole loop halts for a human (preserves today's global stop),
   distinct from `gate` which holds only its chain.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Parallel writers corrupt shared ROADMAP.md | garbled boxes / lost flip | `mkdir`-lock `cmd_flip` on the absolute-path shared ROADMAP + write-temp-then-`mv`; append-only event log is the replay source of truth |
| Lock holder crashes holding `flip.lock` | next flip blocks; lock age + `kill -0` PID fails | PID-liveness stale reclaim via `rmdir` (never `rm -rf`), `FLIP_LOCK_STALE_SECS` default 120 |
| Box flip written to a worktree's own ROADMAP copy (invisible to driver) | driver never sees the flip; session loops | flip helper targets `$megadir/ROADMAP.md` (absolute, outside worktrees); session contract calls `cmd_flip`, never a local `sed` |
| Disjointness gate false-negative (serializes safe pair) OR no `## Touches` | slower than ideal, never unsafe | acceptable by design (Q1/Option-B conservative); TASK-009 asserts the serialize-everything outcome is visible |
| Disjointness gate false-positive (parallel unsafe pair) | `.git/index.lock` avoided by worktrees; risk is a clean-but-wrong merge | one worktree per session; convergence detects same-file edits across the wave, not just git conflicts |
| Sibling session exits nonzero mid-wave | reap map sees dead PID + unchecked box | in-flight siblings DRAIN in isolated worktrees, run marked failed after drain; `trap` reaps/kills the wave PID set (no orphaned `claude -p`) |
| Crash mid-wave leaves a half-done sub-goal | box unchecked, worktree present | idempotent resume recomputes ready set; stale worktree reused only if clean+matching, else recreated |
| Event-log line exceeds PIPE_BUF (concurrent appends interleave) | garbled event line | `note` field truncated `< 512B` so O_APPEND stays atomic |

## Out of Scope
- Priority scheduling · cross-machine execution · new retry policies · a separate crash-recovery
  state store · speculative execution · DAG visualization beyond the existing board. (ADR-0030's
  GSD-v2 boundary; any of these in the diff = scope failure.)
- `/kit:dispatch` (untouched), `lib/goal/mega-merge.sh` semantics (convergence only SEQUENCES its
  existing merges under the lock; it does not change how a merge works), the ops-toolkit skill.
- **The `## Touches` schema for sub-goals + the sub-goal generator (`commands/mega.md`) change**
  , deferred to follow-up **ID-090** per Q1/Option-B. Without it, wave-eligibility is
  opt-in and real mega-goals serialize until their sub-goals declare Touches. (Han can pull this in
  by choosing Option A.)

## Touches
<!-- This spec is NOT run via /kit:dispatch (it is a single-writer full-lane build), so Touches is
     informational, not gate-required. Primary write surfaces: -->
- lib/**
- tests/**
- docs/verification/**

## Decision Log
- DEC-001: Reuse `dispatch-gate.sh` for wave-pair disjointness rather than a new gate , ONE
  disjointness authority; rejected building a parallel primitive.
- DEC-002: Concurrency cap `WAVE_CAP` default **1** (waves OFF by default; opt-in to `>=2`). This
  DEVIATES from the brief's "default 2" , spec-validate showed default 2 silently migrates existing
  `gate` (global-stop) to chain-stop, a linear-chain regression the goal forbids. Default 1 => serial
  path always, gate stays global, byte-identical. Waves cap small when enabled (cost center is
  long-session cache-read, 2026-07-02 audit). Rejected unbounded frontier scheduling.
- DEC-003: No separate state store; resume recomputes from ROADMAP boxes + PR state , stays inside
  ADR-0030's boundary (a state store is GSD-v2).
- DEC-004: Reconcile the 2026-05-22 concurrent-goal-dispatch note's "wave = tripwire to gsd-2" rule
  , wavefront over declared `depends` edges is in-kit (needs no runtime machinery); a true durable
  runtime still routes to gsd-2. Recorded in ADR-0030 "Reconciliation" + a supersession pointer on
  the note. (Surfaced by architecture research; flagged to Han in the loop report.)
- DEC-005: Lock primitive is `mkdir <lockdir>` + stale-timeout, NOT `flock` (absent on macOS CI).
  New shared helper; wave-completion wait is a `kill -0` poll (as `_run_session_watchdog`), not
  `wait -n` (bash 4.3+). Arrays empty-guarded `${arr[@]+"${arr[@]}"}` per `lib/goal/mega-merge.sh:224`.
- DEC-006 (spec-validate): the byte-identical serial invariant is STRUCTURAL, not test-only ,
  extract `_run_one_session` first (TASK-000), then size-dispatch on ADMITTED count (admitted<=1 or
  CAP=1 -> untouched serial body). A golden test alone was rejected as insufficient.
- DEC-007 (spec-validate): `_wave_gate` is greedy-in-ROADMAP-order (admit vs every admitted member,
  stop at CAP), because pairwise disjointness does not compose. Deterministic; no-deps identical.
- DEC-008 (spec-validate): flip targets the SHARED absolute-path `$megadir/ROADMAP.md` (outside
  worktrees); convergence merges wave branches one-at-a-time under the flip lock reusing
  `mega-merge.sh` (its semantics untouched , only sequenced).
- DEC-009 (spec-validate): lock at `$megadir/.orchestrate/flip.lock` (not `/tmp`), PID-liveness
  stale reclaim via `rmdir` + `[ -n ]` guard; `WAVE_CAP` env (default 1 = off, see DEC-002; integer
  `>=1`), `FLIP_LOCK_STALE_SECS` (default 120); event `note` truncated `< PIPE_BUF`.
- DEC-010 (spec-validate): `gate` narrows to chain-stop; NEW `gate!` preserves today's global
  human-stop (autonomy gate not weakened , the operator opts into whichever).
- DEC-011 (Q1, provisional , Han away): Option B , concurrency is opt-in (a sub-goal declares
  `## Touches` to be wave-eligible; absent it serializes). Ship machinery + fixtures + TASK-009
  honesty control; the generator/schema retrofit is follow-up ID-090. A = B + generator
  change (no rework). Han override: "do Option A".
- DEC-012 (delta re-validation): three fixes to the first revision , (a) size-dispatch keys on
  ADMITTED (post-gate) count, not raw ready size (a no-deps mega-goal has ready size N, not 1);
  (b) `_wave_gate` requires the candidate's OWN `## Touches` to admit (`gate_plan` admits the first
  vacuously); (c) `HANDOFF-<id>.md` keyed on having DEPENDENTS with a plain-`HANDOFF.md` read
  fallback (keying on deps loses feed-forward at every chain root). `WAVE_CAP` default 1 (DEC-002);
  flip-contract prompt injection deferred to ID-090; convergence is its own TASK-004c.

## Review

### Verdict: RE-VALIDATED (2026-07-03) after two revision passes

5-lens adversarial spec-validate -> first revision (~19 fixes) -> fresh-context delta re-validation
found 3 new bugs the first revision introduced (byte-identity premise false; HANDOFF keyed on wrong
edge end; `_wave_gate` all-defer vs `gate_plan` vacuous-first) -> second revision (DEC-012) closed
them. The re-validator's remaining items (WAVE_CAP default, convergence-as-own-task, flip-contract
deferral) are all applied. Design is implementable; proceeding to `/kit:execute`. History below.

### Prior verdict: NEEDS REVISION (spec-validate, 2026-07-03, 5-lens adversarial)

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
  - **Loop recommended A; RESOLVED provisionally as B** (2026-07-03, Han away >60s on the ask).
    Rationale for taking B autonomously: B is the scope-faithful reading of the brief ("EXECUTES that
    brief, does not re-design"; the brief's own "unprovable = serialize" IS B's behavior), it is fully
    reversible, and **A = B + an additive generator/schema change**, so B is a strict subset , zero
    rework if Han upgrades to A. A expands scope into `commands/mega.md`, which the loop will not
    self-approve while Han is away. B is honest, not a silent no-op: TASK-009 asserts a real
    Touches-less mega-goal serializes, the opt-in is documented, and the generator/schema retrofit is
    filed as follow-up **ID-090 (Touches-on-sub-goals)** for Han to pick up if he wants A.
    **Han override path:** to switch to A, say "do Option A" , the loop adds the generator + schema
    tasks on top of the shipped B machinery (no rebuild).
