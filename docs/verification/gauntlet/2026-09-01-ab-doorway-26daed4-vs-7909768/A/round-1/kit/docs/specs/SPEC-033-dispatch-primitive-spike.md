# Spec: Dispatch-primitive bakeoff (spike, de-risks SPEC-032)
Generated: 2026-05-22
Status: APPROVED

> **Throwaway spike, not a feature.** Its only product that survives is a verdict
> table + one ADR that LOCKS SPEC-032's dispatch primitive with evidence instead of
> assumption. The harness itself is deleted after the ADR is written. Build/run this
> BEFORE `/kit:spec-validate` on SPEC-032. Sources of record:
> `docs/specs/DECISION-BRIEF.md`, `docs/specs/SPEC-032-concurrent-goal-dispatch.md`,
> `docs/specs/SPEC-031-v-model-and-convergence.md`,
> `docs/research/2026-05-22-concurrent-goal-dispatch.md`,
> `docs/research/2026-05-22-claude-code-agent-views.md`.

## Problem

SPEC-032 commits to a specific dispatch primitive, **Path A**: in-session
`Agent(run_in_background: true, isolation: "worktree")` workers polled via the `Task*`
tools. That choice is **assumed, never executed.** Two unverified claims sit under the
whole spec: (1) the harness actually fans out N isolated worktree workers the lead can
poll without blocking, and (2) N `goal/<slug>` branches come back collectable for the
SPEC-031 lead-owned convergence.

Separately, the maintainer's literal question was "can I use **the agent view** to
manage the session lifecycle?" The agent view is a **different** primitive, **Path B**:
`claude --bg` background sessions polled via `claude agents --json`, hosted by the
supervisor daemon (see the agent-views research note). SPEC-032 does not use it at all.

So before validating SPEC-032 we have an unproven assumption AND an unanswered maintainer
question, and they happen to be the two sides of the same fork. A spike resolves both at
once: run the same toy workload through both primitives, let evidence pick the one
`/kit:dispatch` will be built on.

## Solution

<!-- Depth pattern forked from superpowers:brainstorming. See docs/specs/SPEC-008. -->

### Approaches considered

1. **Head-to-head bakeoff of Path A vs Path B (chosen).** Two toy disjoint specs, run
   through each primitive, observations recorded on fixed axes, verdict locks the
   primitive via ADR. Tradeoff: ~2x the run cost of testing one path; throwaway code to
   write and then delete.
2. **Build `/kit:dispatch` directly on Path A (rejected).** Trust SPEC-032's assumption,
   skip the spike. Tradeoff: ships the kit's first concurrency surface on an unverified
   primitive and never answers the agent-view question the maintainer actually asked.
   The exact "no phantom features / verify at every level" violation the kit forbids.
3. **Spike Path B only, since that is what was asked (rejected).** Tradeoff: proves the
   agent view works but cannot say whether it beats SPEC-032's existing choice, so it
   does not de-risk SPEC-032; you would still be assuming on the A side.

### Chosen approach + why

Approach 1. It is the only one that produces a *comparison*, and the maintainer
explicitly chose "compare both" when shown the fork. The rejected alternatives each
leave one side of the fork unmeasured. The cost (2x runs + throwaway harness) is the
price of turning an architectural assumption into an architectural decision, which is
cheap relative to building `/kit:dispatch` on the wrong primitive.

### Extensibility & boundaries

- **Load-bearing dimension = number of dispatch primitives compared.** Today two (A, B).
  If a Path C emerges (e.g. the Agent SDK managed-agents API, currently out for
  bash-over-binaries reasons), it is one more runner + one more column in the verdict
  table; the fixtures, gate/guard smoke, and axes are reused unchanged. There is no
  scheduler here to grow, by construction; this is a measurement rig, not a runtime.
- **Unit boundaries.** Six independent units, each runnable/checkable alone: (a) toy
  fixtures, (b) the gate+guard bash functions lifted from SPEC-032's design, (c) the
  Path A runner, (d) the Path B runner, (e) the verdict recorder, (f) the
  primitive-locking ADR. The two runners share only the fixtures and the axes; neither
  depends on the other's result.

### Architecture

```
_meta/spikes/dispatch-primitive/            (throwaway scratch; deleted after ADR)
  fixtures/
    spec-x.md   (## Touches: a/**  → worker creates a/hello.txt, commits goal/spec-x)
    spec-y.md   (## Touches: b/**  → worker creates b/hello.txt, commits goal/spec-y)
  gate.sh       (pairwise glob disjointness + drift guard, lifted from SPEC-032 design)
  run-path-b.sh (claude --bg fan-out + `claude agents --json` poll + branch collect)
  observe.md    (filled by hand from both runs)

  PATH A (in-session, lead = me):                 PATH B (shell, daemon-hosted):
   Agent(run_in_background, isolation:worktree)     claude --bg --name goal-spec-x ...
     x2 on spec-x / spec-y                          claude --bg --name goal-spec-y ...
   poll: TaskList / TaskGet / TaskOutput            poll: claude agents --json | jq
   collect: goal/spec-x, goal/spec-y branches       collect: claude logs <id> + branches
                       │                                          │
                       └──────────► VERDICT TABLE ◄───────────────┘
                                  (same axes, both columns)
                                          │
                                          ▼
                         ADR: lock SPEC-032's primitive
                  (+ note SPEC-032 Solution reconciliation if B wins)
```

## Technical Design

### Interfaces (I/O contract)

- **Consumes:**
  - Harness primitives under test: the Agent tool (`run_in_background`, `isolation:
    "worktree"`) + `Task*` tools (Path A); the `claude` CLI (`--bg`, `agents --json`,
    `logs`, `rm`) + the supervisor daemon (Path B); `git worktree`; `bash`/`jq`.
  - The disjointness-gate + drift-guard *design* from SPEC-032 TASK-004/005 (globs in,
    parallel-safe set / pass-fail out). The spike lifts the logic to smoke it early; it
    does not own the final implementation (SPEC-032 does).
  - Two toy fixture specs with a `## Touches` glob block each.
- **Produces:**
  - A throwaway harness under `_meta/spikes/dispatch-primitive/`.
  - A filled verdict table (in `observe.md` and copied into the ADR).
  - One ADR `docs/decisions/NNNN-dispatch-primitive-lock.md` that records the winner and,
    if Path B wins, the exact SPEC-032 `## Solution` reconciliation delta (worded, not
    applied).
  - Gate/guard smoke results (pass/fail against the toy specs).
- **Invariants:**
  - The spike writes nothing under `commands/`, `agents/`, `hooks/`, or any SPEC-031/032
    hands-off shared surface. Its only durable output is the ADR (+ this spec).
  - If a primitive is unavailable on the running CC version, the runner records
    "unavailable + version" as the honest result; it never fakes a pass (verify-at-every-
    level).
  - SPEC-032 and SPEC-031 are not edited by this spike; a needed change to either is
    recorded as a delta in the ADR for those specs to absorb.

### Data model changes
None. The toy git branches and scratch files ARE the state, and all of it is deleted
after the ADR. No store, no runtime structure.

### API changes
None. No `/kit:` command, no agent, no hook. (`/kit:dispatch` is SPEC-032's, explicitly
out of scope here.)

### UI changes
None.

### Infrastructure changes
Throwaway: a scratch dir `_meta/spikes/dispatch-primitive/` and up to four temporary git
worktrees/branches (`goal/spec-x`, `goal/spec-y`, one pair per path). All removed at the
end (TASK-007). No new binaries.

## Task Breakdown

### Phase 1: Fixtures + the bash gate (no agents yet)
- [ ] TASK-001: Create `_meta/spikes/dispatch-primitive/fixtures/spec-x.md` and
  `spec-y.md`: each a minimal spec with a `## Touches` block (`a/**` and `b/**`
  respectively) and a one-line task ("create `a/hello.txt` containing `x`, commit on
  branch `goal/spec-x`"; mirror for y)., AC: both files exist; their `## Touches`
  globs are provably disjoint; each names a distinct `goal/<slug>` branch.
- [ ] TASK-002: Lift the disjointness gate + drift guard into
  `_meta/spikes/dispatch-primitive/gate.sh` (pure bash/glob, no agent): `gate.sh
  disjoint <specA> <specB>` → exit 0 if `## Touches` globs are disjoint else 1;
  `gate.sh drift <branch> <spec>` → exit 0 if `git diff --name-only base..<branch>` ⊆
  the spec's globs AND ∩ hands-off = ∅ else 1. Smoke it against the toy specs., AC:
  spec-x vs spec-y → disjoint (0); spec-x vs spec-x → overlap (1); a branch writing
  outside its glob → drift caught (1); a clean branch → pass (0).

### Phase 2: The two runners (the actual bakeoff)
- [ ] TASK-003: **Path A run.** From the lead session, dispatch two
  `Agent(run_in_background: true, isolation: "worktree")` workers on spec-x and spec-y;
  poll with `TaskList`/`TaskGet`/`TaskOutput`; collect both `goal/*` branches; then test
  durability behavior (note what the docs/harness say happens to a `run_in_background`
  worker if the lead session ends, do not actually kill the session if it is unsafe,
  record the documented/observed behavior). Record every axis in `observe.md`., AC:
  `observe.md` Path-A column filled for all axes; both toy branches collected OR the
  precise failure recorded; the poll calls are noted as blocking or non-blocking from
  observation.
- [ ] TASK-004: **Path B run.** Write `run-path-b.sh`: guard on `claude --version` ≥
  v2.1.139 (else record "unavailable" and exit cleanly); `claude --bg --name goal-spec-x
  '<spec-x task>'` + same for y; poll `claude agents --json | jq` until both leave
  Working; `claude logs <id>` to confirm; collect branches; `claude rm <id>` cleanup.
  Record every axis., AC: `observe.md` Path-B column filled for all axes (or a clean
  "unavailable on vX.Y.Z" row); script is idempotent and cleans up its sessions; no
  faked pass.

### Phase 3: Verdict + the decision
- [ ] TASK-005: Build the verdict table from `observe.md` across the fixed axes:
  fan-out works? · poll non-blocking? · N branches collectable? · durability on lead
  exit · convergence ergonomics (fit to SPEC-031 lead-owned convergence) · cost/complexity
  to the kit (bash-over-binaries) · answers "use the agent view?"., AC: table has both
  columns and a one-line winner-per-axis; no axis left blank (an honest "n/a, unavailable"
  counts as filled).
- [ ] TASK-006: Write `docs/decisions/NNNN-dispatch-primitive-lock.md` (Context /
  Decision / Consequences, the 0001-0016 format) recording the chosen primitive and the
  verdict table. If Path B wins, include the exact reworded SPEC-032 `## Solution` +
  `## Technical Design` delta (so SPEC-032 can absorb it), do NOT edit SPEC-032 here.
  Resolve the ADR number against the live `docs/decisions/` list (see Open questions:
  0017 is already taken by `0017-mega-decomposition-lane.md`)., AC: ADR exists with a
  non-colliding number; states the winner + why in one sentence up top; embeds the
  verdict table; cross-referenced from SPEC-032 and this spec.
- [ ] TASK-007: Tear down. Remove the toy worktrees/branches (`goal/spec-x`,
  `goal/spec-y` for both paths) and delete `_meta/spikes/dispatch-primitive/`. The ADR
  is the durable record; the harness is throwaway., AC: `git worktree list` shows no
  `goal/spec-*` worktrees; `git branch --list 'goal/spec-*'` is empty;
  `_meta/spikes/dispatch-primitive/` is gone; the ADR remains.

## After state
- [ ] A verdict table compares Path A vs Path B on every axis, backed by an actual run
  (not a doc claim). (Today: SPEC-032 asserts Path A with no run behind it.)
- [ ] `docs/decisions/NNNN-dispatch-primitive-lock.md` exists and names the primitive
  `/kit:dispatch` will use. Checkable by `test -f docs/decisions/*dispatch-primitive-lock.md`.
  (Today: no such ADR; the choice is implicit in SPEC-032's prose.)
- [ ] The SPEC-032 disjointness gate + drift guard are proven runnable as pure bash
  against real fixtures. Checkable by `bash _meta/spikes/dispatch-primitive/gate.sh`
  exit codes (before teardown). (Today: gate/guard exist only as task descriptions.)
- [ ] The maintainer's "can I use the agent view to manage session lifecycle?" question
  has a one-word evidence-backed answer in the verdict table. (Today: open.)
- [ ] The spike harness is deleted; only the ADR (+ this spec) survives. Checkable by
  `! test -d _meta/spikes/dispatch-primitive`. (Today: n/a.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] The verdict table has both columns filled and a winner-per-axis
- [ ] The ADR exists, has a non-colliding number, and embeds the verdict table
- [ ] No edits to SPEC-031, SPEC-032, `commands/`, `agents/`, `hooks/`, or any hands-off surface
- [ ] The throwaway harness and toy branches/worktrees are removed at the end

## Verification
```bash
# before teardown (TASK-007), the gate/guard smoke must pass:
bash _meta/spikes/dispatch-primitive/gate.sh disjoint \
  _meta/spikes/dispatch-primitive/fixtures/spec-x.md \
  _meta/spikes/dispatch-primitive/fixtures/spec-y.md
# after teardown, the durable record must exist and the scratch must be gone:
test -f docs/decisions/*-dispatch-primitive-lock.md \
  && ! test -d _meta/spikes/dispatch-primitive
```

## Edge Cases
1. **`claude --bg` unavailable** (CC < v2.1.139 or feature-flagged off). Path B runner
   records "unavailable on vX.Y.Z" as the verdict for every Path-B axis; Path A still
   gets a full column; the ADR locks Path A by default-on-availability and notes Path B
   was untestable here. No faked pass.
2. **A `run_in_background` worker (Path A) cannot be safely orphaned** to test
   lead-exit durability. Record the documented behavior from the agent-views note rather
   than killing a live session; mark that axis "documented, not observed."
3. **`isolation: "worktree"` does not actually isolate** (both workers write the same
   tree). That is itself a finding: it would invalidate SPEC-032's safety model; record
   it loudly, do not work around it.
4. **A toy worker blocks / asks a question** instead of finishing. Record it as a
   convergence-ergonomics data point (how does the lead see the block on each path) and
   move on; the toy task is trivial enough that a block is itself signal.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Spike scope-creeps into building `/kit:dispatch` | a `commands/dispatch.md` appears | hard out-of-scope line + the no-new-surface acceptance criterion; the spike writes only fixtures + gate.sh + an ADR |
| Throwaway harness left behind | `_meta/spikes/dispatch-primitive/` survives | TASK-007 teardown + the `! test -d` verification line |
| ADR number collides | two ADRs share `NNNN` | resolve against the live `docs/decisions/` list at TASK-006 (Open questions records the known 0017 clash) |
| Path B pollutes the real agent view with stray sessions | `claude agents` shows leftover `goal-spec-*` | `run-path-b.sh` is idempotent and `claude rm`s its sessions in a trap |
| Verdict is ambiguous (A and B tie) | no clear winner-per-axis majority | the ADR defaults to Path A (SPEC-032's existing choice + bash-over-binaries tiebreak) and records the tie |

## Out of Scope
- **Building `/kit:dispatch`** (SPEC-032's job). The spike proves the primitive; it does
  not ship the command.
- **The C1 ADR (parallel-execution boundary) and C2 ADR (V-model frame).** Those belong
  to SPEC-032 / SPEC-031. This spike's ADR is only the primitive lock.
- **The `## Touches` spec-format change** (SPEC-032 TASK-003). The spike hand-writes
  `## Touches` into its toy fixtures to exercise the gate, but does not change the real
  spec template.
- **Editing SPEC-031 / SPEC-032.** Any needed change is recorded as a delta in the ADR.
- **Re-running the 4 research agents.** The area is already covered by the two dated
  research notes + `CONTEXT.md`; re-research would be waste.

## Decision Log
- DEC-001: **Compare both primitives, not one.** Rationale: maintainer chose "compare
  both" when shown the Path A / Path B fork (2026-05-22); it is the only option that
  both de-risks SPEC-032 and answers the agent-view question. Rejected: build on Path A
  blind (Approach 2); spike Path B alone (Approach 3).
- DEC-002: **The spike is throwaway; only the ADR survives.** Rationale: a measurement
  rig has no standing reason to live in the repo once it has produced its decision
  ("every file justifies its existence"). The verdict table is preserved inside the ADR.
- DEC-003: **Do not clobber SPEC-031's `CONTEXT.md`.** Rationale: it is scoped to
  SPEC-031; the spike references the research notes directly. Skipping the kit:spec
  CONTEXT.md regen is deliberate, not an omission.
- DEC-004: **Skip the 4 research agents.** Rationale: brownfield research already exists
  (`docs/research/2026-05-22-concurrent-goal-dispatch.md` +
  `docs/research/2026-05-22-claude-code-agent-views.md` + `CONTEXT.md`); re-running is
  waste.
- DEC-005: **The spike's ADR is primitive-lock only**, separate from SPEC-032's
  ADR-for-C1. It MAY later be folded into SPEC-032's parallel-execution-boundary ADR if
  the maintainer prefers one ADR; recorded as a fold option, not done here.

## Open questions
- **ADR numbering. RESOLVED 2026-05-22.** Linearized by logical dependency order:
  0017 mega-decomposition-lane / 0018 v-model-phase-frame (SPEC-031) / 0019
  parallel-execution-boundary (SPEC-032) / 0020 dispatch-primitive-lock (this spike).
  SPEC-031 and SPEC-032 task text updated to match; this spike's ADR is 0020.
- **Keep or delete the toy fixtures?** TASK-007 deletes everything; if the gate/guard
  fixtures prove reusable as SPEC-032 test fixtures, the maintainer may instead promote
  them into `tests/`. Default: delete.
