# Spec: Concurrent goal dispatch (ID-035)
Generated: 2026-05-22
Status: VALIDATED

> Implements backlog **ID-035** (I2 initiative). The value-bearing half of the
> `docs/specs/DECISION-BRIEF.md` pair. Build order was reversed from the brief
> (ID-035 before ID-034) on a maintainer call: design the consumer (the disjointness
> gate) first so ID-034's contract is concrete, and confront the C1 boundaries (the
> real nerf) up front. Source of record: that brief +
> `docs/research/2026-05-22-concurrent-goal-dispatch.md`. Imports the **hands-off
> shared-surface list** and **lead-owned convergence contract** from SPEC-031
> (ID-034); co-defined here, owned there.

## Problem

The kit runs **one goal at a time, attended**. The maintainer wants to fire several
independent specs, tab away, and come back to several finished branches, getting
pulled in only on a real blocker. Today that is impossible: `/kit:execute` drives a
single spec's tasks sequentially in the main session; there is no cross-goal fan-out,
no safety check that two concurrent goals will not collide, and no contract for what a
worker does when it hits a decision it should not make alone.

Four standing boundaries actively forbid the capability (conflict **C1**): the
operating-layer-vision says the kit "does NOT cover parallel execution"; PHILOSOPHY
says "one agent session at a time" and "Shallow and wide"; the v2 note says
"sequential by design." These were written before the 2026-05-22 harness-engineering
pivot. They are the nerf. They must be superseded, deliberately, by ADR, before the
capability can be built, because PHILOSOPHY itself (line 11) says a principle that
cannot be violated when the tradeoff shifts is not a real principle.

## Solution

<!-- Depth pattern forked from superpowers:brainstorming. See docs/specs/SPEC-008. -->

### Approaches considered

1. **Native single-lead fan-out (chosen).** One lead session launches N background
   worktree subagents (one per independent spec), a plan-layer disjointness gate
   decides which may run concurrently, workers escalate only on blockers, the lead
   converges shared surfaces once at the end. Runs on primitives that exist today
   (`run_in_background` + `isolation: worktree` + `AskUserQuestion`). Tradeoff: no
   crash durability (lead dies → restart picks up branches); merge safety rides
   entirely on the disjointness gate being correct.
2. **In-kit DAG runtime (rejected).** A scheduler that owns topological ordering, wave
   execution, crash recovery. Tradeoff: this is gsd-2's job; rebuilding it breaks
   "Shallow and wide" + the runtime-integration boundary + bash-over-binaries. The
   brief's hard NO. The tripwire to *hand off* to gsd-2, not to build.
3. **Extend /kit:execute to N specs (rejected as the primary surface).** Overload the
   existing intra-spec orchestrator to also do cross-goal fan-out. Tradeoff: conflates
   two units (one spec's tasks vs N specs), two modes (attended vs tab-away), two
   lifecycles (phase-checkpoint vs convergence). Rejected in favor of a dedicated
   command; see DEC-001.

### Chosen approach + why

Approach 1. It delivers fire-and-walk-away multi-goal autonomy with no scheduler and
no state machine, preserving the kit's "glue, not runtime" thesis. The three thin
build items from the brief: **(1) fan-out dispatch, (2) the file-disjointness gate
(the moat), (3) the blocker-escalation contract.** Plus the C1 un-nerf (the ADR + doc
rewords) as the prerequisite, and the post-task **drift guard** that closes the "gate
lies" risk the maintainer flagged: the gate's promise is checked twice, once at plan
(pairwise glob disjointness) and once against the real diff (actual writes ⊆ declared
globs).

### Extensibility & boundaries

- **Load-bearing dimension = number of concurrent goals.** Adding goals stays a flat
  set + pairwise gate + wait-queue; cost grows quadratically in the *gate check*
  (cheap, glob comparison), not in any scheduler. The moment goals develop real
  ordering chains (C needs A+B merged, then D needs C) the flat model cannot express
  it: that is the **tripwire to hand execution to gsd-2**, not to add a DAG here.
- **Unit boundaries.** Five independent units: the C1 un-nerf (docs), the `## Touches`
  declaration (spec-format change), the pre-dispatch gate (plan logic), the post-task
  drift guard (verification), the dispatcher + blocker contract (execution). Each
  testable alone; the gate and drift guard are pure functions of (declared globs, real
  diff, hands-off list).

### Architecture

```
LEAD SESSION (you, tab away)
  │
  │ 1. collect N dispatch-eligible specs (each has a ## Touches glob list)
  │ 2. DISJOINTNESS GATE (plan layer, the moat):
  │      pairwise glob overlap, EXCLUDING the ID-034 hands-off list
  │      → parallel-safe set  +  wait-queue (overlapping pairs serialize)
  ▼
  ├─ worker A ─ isolation:worktree + run_in_background ─ branch goal/A ─┐
  ├─ worker B ─ isolation:worktree + run_in_background ─ branch goal/B ─┤  each runs the
  └─ worker C (waits: overlaps A) ──────────── starts when A done ──────┘  kit lifecycle,
  │                                                                          commits often
  │  each worker on a blocker: commit WIP + blocker note + signal BLOCKED (no silent guess)
  ▼
  4. DRIFT GUARD (post-task): actual `git diff --name-only` ⊆ declared globs
     AND ∩ hands-off = ∅   → else flag, do NOT converge, escalate
  ▼
  5. CONVERGENCE (lead-owned, SPEC-031 contract): collate ready/blocked signals;
     integrate hands-off surfaces ONCE via /kit:ship; remove worktrees; restart
     picks up branches (no durability state). NO auto-merge.
```

## Technical Design

### Interfaces (I/O contract)

- **Consumes:**
  - N specs with `Status: VALIDATED` + a `## Touches` glob list (new, TASK-003).
  - The **hands-off shared-surface list** from SPEC-031/ID-034 (always excluded from
    the gate; never written by a worker).
  - Harness primitives: Agent tool `run_in_background: true` + `isolation: "worktree"`
    under **bypassPermissions** (DEC-009), `AskUserQuestion`.
- **Produces:**
  - `docs/decisions/0019-parallel-execution-boundary.md` (C1).
  - A `## Touches` section in the spec format (`commands/spec.md` template).
  - A new `/kit:dispatch` command (the cross-goal fan-out + gate + drift guard).
  - One branch per dispatched goal (`goal/<slug>`), each with the worker's commits.
  - A worker signal protocol the lead reads via the worker's final-message status line
    (spike-proven channel): `STATUS: READY` | `STATUS: BLOCKED — <note>` | (no line /
    error / timeout) ⇒ `FAILED`.
- **Invariants:**
  - Two goals run concurrently **only if** their declared globs are disjoint after
    excluding the hands-off list. Overlap → serialize (wait-queue), never parallelize.
  - A worker never writes a hands-off shared surface. The lead integrates those once
    at convergence via `/kit:ship`.
  - No worker's actual diff exceeds its declared `## Touches` globs (drift guard).
  - No DAG, no wave scheduler, no cross-session durability state. The dispatcher
    launches and returns; the wait-queue is pairwise serialize only.
  - Intra-spec task parallelism is NOT introduced; `/kit:execute` stays sequential.

### Data model changes
A new `## Touches` section in the spec format: a list of file globs the spec will
write. No runtime state store; the branch commits ARE the state.

### API changes
New command `/kit:dispatch` (see DEC-001). No change to `/kit:execute`'s intra-spec
behavior. The worker prompt (inside dispatch) extends the existing execute worker
prompt with the blocker contract (TASK-007).

### UI changes
None (CLI/bash only).

### Infrastructure changes
Uses git worktrees via the Agent tool's `isolation: worktree`. No new binaries.
Worktree creation/removal is the only filesystem lifecycle; it is bounded (per goal,
removed at convergence), not a managed pool.

## Task Breakdown

### Phase 1: Un-nerf the boundaries (C1)
- [x] TASK-001: Write `docs/decisions/0019-parallel-execution-boundary.md`. Supersede
  the four C1 boundaries with reworded forms: operating-layer-vision "does NOT cover
  parallel execution" → "covers bounded cross-goal fan-out of disjoint specs, NOT a
  DAG runtime"; "one agent session at a time" → "one LEAD session orchestrating N
  isolated worktree workers"; "sequential by design" → "cross-goal concurrent behind
  the disjointness gate; intra-spec sequential (deferred)"; "Shallow and wide" →
  UPHELD (fan-out is width, not a runtime). Explicitly UPHOLD the
  runtime-integration boundary + the no-DAG line., AC: ADR exists, 0001-0016 format,
  records all four reworded boundaries + what stays upheld; cross-referenced in README
  + `docs/architecture.md`.
- [x] TASK-002: Apply the C1 rewords to the live docs in sync: `docs/operating-layer-
  vision.md` (the "does NOT cover parallel execution" clause), `docs/PHILOSOPHY.md`
  ("Shallow and wide" principle note + the "one agent session at a time" line ~149/151
  + the v2 "Agent Teams parallel execution" line ~278), `commands/kit-health.md`
  reject-list., AC: each boundary string matches the ADR's reworded form; no
  surviving "sequential by design" / "does NOT cover parallel execution" claim
  contradicts the ADR; test-meta guards the absence of the old strings.

### Phase 2: The disjointness gate (the moat)
- [x] TASK-003: Add a required `## Touches` section to the spec format for
  dispatch-eligible specs (a list of file globs the spec will write). **Constrain the
  form to directory-prefix globs** (`dir/**`, `dir/sub/**`); fancier patterns (`*.md`,
  `**/x`, `a/*.ext`, brace globs) are not accepted and force a conservative "overlap"
  (DEC-008). Document it in `commands/spec.md` (template + one line of guidance) and add
  it to this spec and SPEC-031 as the worked example. The ID-034 hands-off list is
  always implicitly excluded and must not be listed., AC: `commands/spec.md` documents
  `## Touches` + the prefix-glob constraint; a dispatch-eligible spec lacking it is
  rejected by the gate (TASK-004) with a clear message; the section is prefix globs, not
  prose.
- [x] TASK-004: Build the pre-dispatch disjointness gate inside `/kit:dispatch`
  (depends: TASK-003): given N specs, compute pairwise prefix-glob overlap after
  removing the hands-off list; output the parallel-safe set + a wait-queue (each
  overlapping pair serialized, later goal waits for the earlier). **Conservative rule
  (DEC-008): if the gate cannot PROVE two specs disjoint, it serializes them.** Pure
  bash/glob; no runtime. Merge stays human-gated at `/kit:ship`, so over-serializing is
  safe-but-slower while under-serializing is the only real danger, which prove-or-
  serialize structurally prevents., AC: two disjoint specs → both parallel; two
  overlapping specs → serialized; overlap only on a hands-off surface → still parallel
  (excluded); a spec with no `## Touches` → rejected, not assumed-empty; a glob the gate
  cannot prove disjoint → serialized (not assumed parallel).
- [x] TASK-005: Build the post-task drift guard (depends: TASK-003): after a worker
  finishes, assert `git diff --name-only <base>..<branch>` ⊆ the spec's declared globs
  AND ∩ hands-off = ∅. On drift: flag the goal, do NOT include it in convergence,
  escalate to the lead. **Known limit (W1):** this sees only in-repo committed writes;
  out-of-worktree side effects (`$HOME`, network, uncommitted files) are invisible, and
  under bypassPermissions workers (DEC-009) the worker prompt is the only control
  there., AC: a worker writing outside its declared globs is caught before convergence;
  a worker touching a hands-off surface is caught; a clean worker passes.

### Phase 3: Fan-out dispatch, blocker contract, convergence
- [x] TASK-006a: Implement `/kit:dispatch` fan-out (depends: TASK-004). Take the
  parallel-safe set; for each spec launch one background worktree worker (Agent tool:
  `run_in_background: true`, `isolation: "worktree"`) under **bypassPermissions
  (DEC-009)**, on branch `goal/<slug>` where **`<slug>` = the spec filename minus the
  `SPEC-NNN-` prefix and `.md`** (e.g. `SPEC-040-foo-bar.md` → `goal/foo-bar`); refuse
  any spec not `Status: VALIDATED`. Return control to the lead immediately (tab-away).
  Register `/kit:dispatch` in `.claude-plugin/plugin.json` (`marketplace.json`
  inherits), the README command table, and `MANUAL.md`. **Build-note (SPEC-033 /
  ADR-0020):** `isolation: "worktree"` starts the worktree on an auto-named branch
  (`worktree-agent-<id>`), so the worker prompt MUST `git switch -c goal/<slug>` before
  its first commit; worker commit subjects MUST be Conventional Commits (the
  commit-format hook blocks workers too)., AC: N parallel-safe VALIDATED specs launch N
  workers, each on its own `goal/<slug>` branch (not the auto-name); a non-VALIDATED
  spec is refused; the lead is not blocked; single-spec input degenerates to one worker
  (no gate needed); `/kit:dispatch` is registered in plugin.json + README + MANUAL.
- [x] TASK-006b: Wait-queue serialization (depends: TASK-006a). A goal in the
  wait-queue starts only after the conflicting peer it overlaps has completed; cap
  concurrent workers at a maintainer-tunable max (default small, e.g. 4) and queue the
  rest (W2)., AC: a wait-queued goal starts only after its conflicting peer's worker
  completes; with more than `max` eligible goals, at most `max` run at once and the
  remainder queue; an all-overlapping set degenerates to fully sequential.
- [x] TASK-007: The worker contract + signal protocol in the worker prompt (depends:
  TASK-006a). Port the CLAUDE.md Vibe-Coding rubric + `AGENTS.md` zone 4 "Pause if"
  (already referenced in `commands/assign.md:51`). **Signal protocol (C2):** the worker
  ends with one status line in its final message, which returns to the lead via the
  completion notification (spike-proven channel, SPEC-033): `STATUS: READY` (branch
  done) or `STATUS: BLOCKED — <one-line note>`. On irreversible / ambiguous / Pause-if
  conditions → commit WIP (Conventional subject, e.g. `chore: WIP goal/<slug> blocked`),
  signal `BLOCKED`; on reversible decisions → proceed + log (the collaborative-design
  protocol already in `execute.md`). **FAILED terminal (C3):** a worker that returns no
  `STATUS:` line, errors, or exceeds a per-worker timeout is classified `FAILED`
  (distinct from BLOCKED): excluded from convergence + escalated; the lead must never
  read a missing signal as READY. The lead collates READY / BLOCKED / FAILED and
  surfaces BLOCKED + FAILED via `AskUserQuestion`., AC: the worker prompt contains the
  rubric + the exact STATUS-line format; a Pause-if condition yields `STATUS: BLOCKED` +
  WIP commit, never a silent default; a reversible decision proceeds and is logged; a
  worker that returns no STATUS line or times out is classified FAILED, not READY.
- [x] TASK-008: Convergence + worktree GC (lead side), per the SPEC-031 contract
  (depends: TASK-005, TASK-007). After workers finish: collate `READY`/`BLOCKED`/`FAILED`
  signals (only READY goals are eligible to converge); the lead integrates the
  hands-off surfaces ONCE via `/kit:ship` (workers never wrote them); GC each worktree
  after its branch is PR'd/merged via `git worktree unlock <path>` → `git worktree
  remove --force <path>` → `git branch -D goal/<slug>` (proven by SPEC-033 / ADR-0020:
  the harness LOCKS agent worktrees, so a bare `remove --force` fails with "cannot
  remove a locked working tree"); on lead restart, pick up existing
  `goal/*` branches (no durability state). No auto-merge: the human merges at ship., AC: shared surfaces written once by the lead, not by any worker; 0 orphan worktrees
  after a clean run; a crashed worker's branch commits survive a lead restart;
  convergence does not re-run integration-checker's cross-task wiring check (that
  stayed per-spec inside each worker).

### Phase 4: Guards
- [x] TASK-009: Tests. `tests/test-meta.sh`: `/kit:dispatch` exists + registered in
  `.claude-plugin/plugin.json`, `marketplace.json` (inherits), README command table,
  `MANUAL.md`; old C1 strings absent. `tests/test-hooks.sh` or a new gate unit test:
  the disjointness gate serializes overlapping specs and parallelizes disjoint ones;
  the drift guard catches out-of-glob and hands-off writes., AC: `bash
  tests/test-meta.sh && bash tests/test-hooks.sh` pass with the new assertions green.

## After state
- [ ] The maintainer can fire N independent validated specs and tab away; each builds
  in its own worktree+branch. (Today: `/kit:execute` drives one spec, attended, in the
  main session.)
- [ ] Two goals run concurrently only when their `## Touches` globs are disjoint;
  overlapping goals serialize. Checkable by the gate unit test. (Today: no gate.)
- [ ] A worker that writes outside its declared globs or into a hands-off surface is
  caught before convergence. Checkable by the drift-guard test. (Today: no such check.)
- [ ] `docs/decisions/0019-parallel-execution-boundary.md` exists and the four C1
  strings are superseded in the live docs. Checkable by `! grep -rn "does NOT cover
  parallel\|sequential by design" docs/ commands/`. (Today: 4 boundaries forbid it.)
- [ ] `/kit:dispatch` exists, registered in plugin.json + README + MANUAL. (Today: no
  cross-goal command.)
- [ ] `/kit:execute` is unchanged (intra-spec, sequential). (Verifiable by `git diff
  commands/execute.md` showing no behavior change.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `bash tests/test-meta.sh && bash tests/test-hooks.sh` pass
- [ ] A deliberately-overlapping pair of specs is correctly serialized, not parallelized
- [ ] No DAG / scheduler / cross-session durability introduced (relabel-into-runtime guard)
- [ ] The hands-off list + convergence are imported from SPEC-031, not re-implemented
- [ ] A worker that returns no signal / times out is classified FAILED and excluded from convergence (never read as READY)

## Verification
```bash
# CORRECTED at build (2026-05-23): commands are auto-discovered from commands/*.md;
# plugin.json / marketplace.json carry NO command list, so the original
# `grep kit:dispatch .claude-plugin/plugin.json` premise was false. The C1-absence
# grep is scoped to the LIVE policy doc (PHILOSOPHY); specs/ADRs that QUOTE the old
# wording to document the supersession are exempt. See Decision Log DEC-010.
bash tests/test-meta.sh && bash tests/test-hooks.sh \
  && ! grep -q "not competing with agent runtimes" docs/PHILOSOPHY.md \
  && test -f commands/dispatch.md \
  && grep -q 'kit:dispatch' README.md && grep -q 'kit:dispatch' MANUAL.md \
  && grep -q 'kit:dispatch' docs/architecture.md
```

## Edge Cases
1. **A spec has no `## Touches`.** The gate rejects it (does NOT assume empty/safe),
   because an undeclared file-set is the "gate lies" failure by default.
2. **All N specs overlap pairwise.** The wait-queue degenerates to fully sequential;
   that is correct (safety over speed), and the lead is told why.
3. **A worker blocks immediately.** It commits nothing-or-WIP, signals BLOCKED; its
   goal is excluded from convergence; other disjoint workers continue.
4. **Lead dies mid-run.** Worktree branches retain commits; on restart the lead finds
   `goal/*` branches and resumes convergence. No orchestration state was persisted by
   design.
5. **Two workers both legitimately need a hands-off surface (e.g. both add a
   CHANGELOG line).** Neither writes it; both succeed on their feature files; the lead
   writes both CHANGELOG lines once at convergence. This is the whole point of the
   hands-off list.
6. **A worker dies mid-run** (API 5xx, rate-limit, hang). It returns no `STATUS:` line
   or trips the timeout; the lead classifies it FAILED, excludes it from convergence,
   preserves any branch commits, and escalates. Distinct from BLOCKED (a deliberate
   pause); the lead must never read silence as READY.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Gate lies (worker drifts past declared globs) | drift guard: real diff ⊄ declared globs | goal excluded from convergence; escalate; declared globs corrected or work re-run serially |
| Worktree sprawl (crash leaves worktrees) | `git worktree list` shows orphans after a run | convergence removes worktrees on merge; lead-restart GC removes stale ones; branches preserved |
| Silent merge collision | two goals' diffs touch the same file | impossible if the gate is correct (disjoint globs); the drift guard is the backstop if a glob was under-declared |
| Escalation storm (too many blockers) | lead pulled in on >1 per goal | tune the Pause-if rubric; >80%-genuine escalation is the brief's exit bar, not raw count |
| Drift into a runtime | a "wave scheduler" or durability store appears in review | the no-DAG invariant + DEC-002; the ordering-chain need is the gsd-2 handoff tripwire, not a build signal |
| Worker crash / hang (API 5xx, rate-limit, timeout) | no `STATUS:` line returned, or per-worker timeout exceeded | classified FAILED (not READY/BLOCKED); goal excluded from convergence + escalated; branch commits (if any) preserved |
| API rate-limit / quota exhaustion at high N | many workers stall or 429 at once | concurrency cap (TASK-006b, default ~4) bounds simultaneous workers; excess queue; lead escalates persistent throttling |
| Out-of-worktree side effect (bypassPermissions worker) | NOT caught by the drift guard (in-repo only) | accepted risk per DEC-009; worker prompt is the only control; OS sandbox (agentkernel) is the deferred boundary |

## Out of Scope
- **Intra-spec task parallelism** (running one spec's tasks concurrently). Deferred
  per the brief's refined NO-list; `/kit:execute` stays sequential. This spec is
  cross-goal only.
- **A DAG / topological scheduler / wave execution / crash-recovery durability.** The
  gsd-2 handoff territory; the no-DAG invariant holds.
- **Auto-merge of worktree branches.** Merge stays human, at `/kit:ship`.
- **OS-level worker sandboxing.** v1 workers run under bypassPermissions in a git
  worktree, which is NOT an OS sandbox (DEC-009). A true blast-radius boundary
  (agentkernel / container per worker) is deferred.
- **The C2 "8 phases" reword + the V-model lens**, that is SPEC-031 (ID-034). This
  spec only does C1.
- **Full ID-024** (the cross-spec context-switch affordance + ABANDONED terminal).
  ID-035 defines only the minimal worktree-per-goal lifecycle it needs (branch +
  isolation primitive + GC). See Decision Log DEC-004.

## Touches
Worked example of the `## Touches` section this spec introduces (directory-prefix globs
only; lead-owned hands-off surfaces like CHANGELOG / VERSION / plugin.json / tests are
excluded automatically and never listed):
- commands/**
- lib/**

## Decision Log
- DEC-001: **New `/kit:dispatch` command, not an extension of `/kit:execute`.**
  Rationale: different unit (N specs vs one spec's tasks), mode (tab-away background vs
  attended), and lifecycle (convergence vs phase-checkpoint). Overloading execute
  muddies both. Cost: one new command, justified by a named consumer (the tab-away
  workflow) and the Build phase of the multi-goal lane (clears the 2+-phase bar).
  Rejected: extend execute (Approach 3). **Confirmed by maintainer 2026-05-22.**
- DEC-002: **No DAG, no scheduler, no durability.** Flat set + pairwise gate +
  wait-queue. Rationale: the brief's hard line; anything more is gsd-2's job. The
  ordering-chain need is the handoff tripwire.
- DEC-003: **The disjointness gate needs a declared file-set, so `## Touches` becomes
  required for dispatch-eligible specs.** Rationale: specs declare no file-set today;
  an undeclared set defaults to the "gate lies" failure. The gate is checked twice
  (plan-time globs + post-task real-diff drift guard). **Confirmed by maintainer
  2026-05-22** (required for dispatch-eligible specs only; ordinary specs unaffected).
- DEC-004: **ID-024 is a soft dependency.** ID-035 defines the minimal
  worktree-per-goal lifecycle inline (branch + `isolation: worktree` + bounded GC);
  ID-024's broader context-switch affordance + ABANDONED terminal is separable and not
  required for v1. Rejected: block ID-035 on ID-024 (the raw primitives suffice).
- DEC-005: **The hands-off list is a view over WORKFLOW.md's existing doc-impact map
  (the shared-surface rows), not a new artifact owned by either spec.** Rationale:
  the order-reversal (ID-035 first) means ID-035 cannot import a list from an
  unbuilt ID-034; but it does not need to, because the source already exists in
  WORKFLOW.md. This spec's gate EXCLUDES those rows; SPEC-031's convergence CONTRACT
  governs them (workers don't write them, the lead integrates once). Both reference
  the doc-impact map; neither re-enumerates it as a second source. Resolves the
  gate-ownership question (Option 2: gate here, coupled to the convergence contract)
  without a build-order dependency.
- DEC-006: **Exit metric is autonomy + safety, not wall-clock** (per the committed
  brief): N clean PRs, overlapping pair correctly serialized, >80% genuine
  escalations. The maintainer's earlier "speedup ≥40%" applies to the *deferred*
  intra-spec initiative, not this cross-goal one.
- DEC-007: **Dispatch primitive locked to in-session `Agent(run_in_background,
  isolation:worktree)` + `Task*` polling (Path A), not the `claude agents` agent view
  (Path B).** Rationale: the SPEC-033 bakeoff proved the agent view is monitor-only (no
  CLI verb to create a background session; `claude --bg` does not exist; in-session
  subagents are invisible to it), while Path A fanned out, polled non-blocking, and let
  the lead collect `goal/*` branches in one session. See `docs/decisions/0020-dispatch-
  primitive-lock.md` for the verdict table. The TASK-006a/007/008 build-notes above
  (worker `git switch -c goal/<slug>`, Conventional-Commit worker subjects, unlock-then-
  remove worktree GC) are the spike's concrete findings folded in.
  Rejected: Path B as the dispatch surface.
- DEC-008: **The disjointness gate is conservative, not rigorous.** `## Touches` is
  constrained to directory-prefix globs; the gate serializes any pair it cannot PROVE
  disjoint. Rationale (spec-validate 2026-05-22): merges are human-gated (`/kit:ship`,
  no auto-merge), so a missed overlap costs a manual merge conflict, not silent
  corruption; over-serializing is safe-but-slower, under-serializing is the only real
  danger, and prove-or-serialize structurally prevents it. Rejected: a full bash
  glob-intersection engine (more surface on the one safety control, against
  bash-over-binaries).
- DEC-009: **Unattended workers inherit bypassPermissions.** Rationale (maintainer,
  spec-validate 2026-05-22): tab-away autonomy needs no prompts; worktree isolation +
  the disjointness gate + drift guard + human-gated merge are the in-repo safety net.
  Accepted caveat: a git worktree is not an OS sandbox, so out-of-worktree side effects
  (`$HOME`, network, push) are uncontrolled and invisible to the drift guard; OS-level
  sandboxing is deferred (Out of Scope). Rejected: a scoped allowlist (unattended
  workers can't answer prompts anyway; maintainer chose throughput).

- DEC-010 (added at build 2026-05-23): **Command registration is via `commands/*.md`
  auto-discovery + the README / MANUAL / architecture-inventory surfaces, NOT a
  `plugin.json` command list.** Rationale: reading the live `.claude-plugin/plugin.json`
  and `marketplace.json` showed neither lists commands (they carry name/version/
  description only); the original TASK-006a "register in plugin.json" clause and the
  `grep kit:dispatch plugin.json` verification were based on a false premise. Corrected
  the Verification block + TASK-006a accordingly; the parity is enforced by
  `tests/test-meta.sh` (architecture inventory rows == live `commands/`+`agents/` files)
  plus the README/MANUAL registration checks. Adjacent finding (flagged, not fixed
  here): the WORKFLOW doc-impact map "commands/* (new)" row still lists plugin.json +
  marketplace.json; that is vestigial (only the version bump touches them, covered by
  the "any shipped change" row).

## Open questions
(none; DEC-001 and DEC-003 are flagged for confirmation but have a recommended default)
