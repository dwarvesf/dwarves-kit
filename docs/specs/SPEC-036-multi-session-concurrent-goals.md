# Spec: Multi-session concurrent goals (the cross-session running-goal registry) (ID-040)
Generated: 2026-05-23
Status: VALIDATED

> Extends SPEC-032 (concurrent goal dispatch) from the **single-lead in-session** case
> to the **multi-session** case. SPEC-032 / ADR-0019 / ADR-0020 gave the kit one lead
> session fanning out N background worktree workers, the lead holding disjointness in
> its head. This spec covers what the goal calls "not just one lead fanning out workers
> in a single chat": several independent Claude sessions, one goal each, with no shared
> lead. It reuses the SPEC-032 disjointness moat (`lib/dispatch-gate.sh`) rather than
> reimplementing it, and confronts the remaining boundary the C1 ADR left standing: the
> L5 / multi-session line PHILOSOPHY punted to Nimbalyst.

## Problem

`/kit:dispatch` (SPEC-032) runs **one lead session** that launches N background workers.
The disjointness gate, the drift guard, and the convergence all live inside that one
session's context; the lead is the single coordinator.

The maintainer also works the other shape: open several Claude sessions (one terminal /
tab per goal), set a `/goal` in each, and walk away. Here there is **no shared lead**.
Nothing stops two sessions from each picking a goal that writes the same files; nothing
gives a human one place to see "which goals are running, in what lane, and what each has
tried." The single-session moat does not reach across sessions because it is held in one
session's head, not on disk.

Two boundaries forbid the capability today (conflict **C4**, the multi-session twin of
SPEC-032's C1):

1. `docs/PHILOSOPHY.md` target-user note (~line 121): **"someone who needs multi-session
   orchestration across machines or 3+ live operators (that's L5, use
   Nimbalyst/Conductor)."**
2. `docs/PHILOSOPHY.md` "What the kit does NOT cover" (~line 151): **"multi-session
   coordination across machines or live operators stays L5."**

These were written before the single-operator multi-window workflow was a real use. ADR-0019
already settled the *in-session* fan-out; this is the *cross-session* collision, and per
PHILOSOPHY line 11 (a principle that cannot bend when the tradeoff shifts is not a real
principle) it must be bent **deliberately, by ADR**, for exactly the case that shifted, and
no wider.

## Solution

<!-- Depth pattern forked from superpowers:brainstorming. See docs/specs/SPEC-008. -->

### Approaches considered

1. **A shared file registry under the git common dir + a cross-session claim gate
   (chosen).** Each session that starts a goal writes ONE file describing its claim
   (slug, lane, declared globs, branch, worktree, status) to a directory under
   `$(git rev-parse --git-common-dir)`; before it starts, it gates its declared globs
   against every active registered goal, reusing `lib/dispatch-gate.sh`. The same
   directory is the monitor (one read lists every running goal) and the home of each
   goal's running attempt log. Pure bash + files; no daemon, no lock server, no
   scheduler. Tradeoff: coordination is advisory at claim time, not a kernel lock; two
   sessions that claim in the same millisecond could both pass (mitigated by a
   last-writer-loud re-read, the same pattern `/kit:assign` uses for ID allocation).
2. **A coordinating daemon / lock server (rejected).** A long-lived process that hands
   out leases. That is a runtime: it breaks "bash over binaries", adds a process to
   supervise, and is exactly the L5 orchestration (Nimbalyst) the kit hands off. The
   registry needs to *record and compare*, not to *schedule or execute*.
3. **Commit the registry into the repo (rejected).** A tracked `running-goals.md` that
   sessions append to. Churns the repo with ephemeral state, and a shared tracked file
   is a write-collision magnet across worktrees (the very thing the disjoint-file rule
   forbids). The git common dir is the natural location: per-machine, per-repo, shared
   by every worktree of that repo, and never committed (it lives inside `.git`).

### Chosen approach + why

Approach 1. The git common dir (`git rev-parse --git-common-dir`) is shared by every
worktree of one repo on one machine and is inherently untracked, so it is the exact
scope of the bend: same machine, same repo, one operator's several sessions. It cannot
reach across machines (a different machine has a different `.git`), which keeps the L5
fence (across-machines / 3+ live operators) standing for free, by construction.

The registry is **one file per goal, single-writer** (only that goal's session writes
its own file), the identical ownership model as the hands-off shared-surface list: no
file has two writers, so there is no shared-state parallelism. The cross-session gate is
not a second moat: it sources `lib/dispatch-gate.sh` and reuses `prefix_overlap` +
`is_handsoff`, so the disjointness rule has exactly one implementation. Monitoring is a
`list` over the directory; it complements (does not replace) the native agent view,
which can only show the subagents inside one session, not goals across sessions.

### Extensibility & boundaries

- **Load-bearing dimension = number of concurrent same-machine sessions for one
  operator.** Adding a session is one more file + one more pairwise gate sweep (cheap,
  glob comparison). The model has no scheduler to grow.
- **The tripwire to hand off (unchanged from SPEC-032, restated for the multi-session
  axis):** the moment goals need ordering (B must wait for A to merge) or a *second
  human operator* needs a shared view, that is L5 (GSD v2 / Nimbalyst), not a feature to
  add here. The registry deliberately records and compares; it never sequences.
- **Five units, each testable alone:** the C4 un-nerf (ADR + doc rewords), the registry
  store (`claim` / `list` / `log` / `status` / `release`), the cross-session gate (a
  reuse of dispatch-gate), the monitor surface (`/kit:start`), the attempt-log
  convention (helper-backed, detect-don't-dictate).

### Architecture

```
ONE MACHINE, ONE REPO (worktrees share .git, so they share .git/kit-goals/)

 session 1 ── /kit:assign ID-A ── lane=full ── declares Touches: src-a/**
   │   goal-registry claim A:  gate src-a/** vs active{}  → OK
   │     → write  .git/kit-goals/A.goal {lane=full,branch=goal/A,worktree,status=running}
   │   /goal loop builds A in its worktree
   │   each round →  goal-registry log A "<one line of what it tried>"  → A.attempts
   ▼
 session 2 ── /kit:assign ID-B ── lane=normal ── declares Touches: src-b/**
   │   goal-registry claim B:  gate src-b/** vs active{A}  (disjoint, hands-off excluded) → OK
   │     → write  B.goal {…status=running}
   │   ( if B had declared src-a/** →  REFUSED: "overlaps running goal A; serialize or repick" )
   ▼
 human ── /kit:start ──  goal-registry list  → one table, every running goal + lane + status
   │                     + native agent view shows each session's own workers
   ▼
 on done in each session ──  goal-registry release <slug>  → A.goal / A.attempts removed
```

The registry **records and compares**; it never launches a session, sequences goals, or
merges. A human opens each session; convergence stays per-session (each goal ships its
own branch via `/kit:ship`, the SPEC-031 lead-owned convergence applied within a session).

## Technical Design

### Interfaces (I/O contract)

- **Consumes:**
  - A goal's `<slug>` + `lane` (from `/kit:assign` + `lib/lane-classify.sh`).
  - The goal's declared write-set: either a spec's `## Touches` globs or globs passed on
    the command line (same prefix-glob form as SPEC-032).
  - The hands-off shared-surface list (from `WORKFLOW.md`, via `dispatch-gate.sh`; never
    re-enumerated).
  - `git rev-parse --git-common-dir` (the registry root).
- **Produces:**
  - `lib/goal-registry.sh` (claim / list / log / status / release).
  - Per-goal files under `$(git rev-parse --git-common-dir)/kit-goals/`: `<slug>.goal`
    (key=value claim record) and `<slug>.attempts` (append-only attempt log).
  - A claim step in `commands/assign.md` and a monitor section in `commands/start.md`.
  - `docs/decisions/0022-multi-session-boundary.md` (C4).
  - PHILOSOPHY (lines 121 + 151 reworded) + `commands/kit-health.md` carve-out.
- **Invariants:**
  - One writer per registry file: a session writes only its own goal's `<slug>.goal` /
    `<slug>.attempts`. No file has two writers (no shared-state parallelism).
  - A claim is admitted only if its globs are disjoint from EVERY active registered
    goal, by the reused `dispatch-gate.sh` rule (conservative prove-or-serialize); an
    overlap is REFUSED with the colliding goal named, never silently allowed.
  - The registry lives inside `.git` and is never committed.
  - No scheduler, no DAG, no durability state machine, no daemon. The kit never launches
    a session; the human opens each.
  - Cross-machine coordination, a 3+-live-operator shared pool, and goal ordering chains
    stay L5 (GSD v2 / Nimbalyst), unchanged.

### Data model changes

`<slug>.goal` is key=value lines (`slug=`, `lane=`, `status=`, `branch=`, `worktree=`,
`touches=`, `started=`, `updated=`). Key=value, not JSON, deliberately: a human reads it
with `cat`, the tooling parses it with `grep`/`awk`, and it adds no `jq` dependency for a
file whose whole point is legibility. `<slug>.attempts` is append-only timestamped lines.
No database, no runtime state store; the registry is a directory of small flat files.

### API changes

New `lib/goal-registry.sh` (a `lib/` helper, like `dispatch-gate.sh` /
`lane-classify.sh`, NOT a slash command, so it adds no V-phase-inventory row). `claim`
step added to `/kit:assign`; `list` surfaced in `/kit:start`. `/kit:dispatch` is
unchanged: the single-lead fan-out stays the in-session surface; this spec is the
cross-session complement.

### UI changes

None (CLI/bash only). The monitor is a text table from `goal-registry list`.

### Infrastructure changes

Reads/writes a directory under the existing `.git`. No new binaries, no daemon, no
network. The only filesystem lifecycle is per-goal claim files, removed on `release`.

## Task Breakdown

### Phase 1: Un-nerf the multi-session boundary (C4)
- [ ] TASK-001: Write `docs/decisions/0022-multi-session-boundary.md`. Supersede the two
  C4 boundaries (PHILOSOPHY ~121 + ~151) for exactly the **one-operator / N same-machine
  sessions / disjoint goals** case; UPHOLD the L5 fence for across-machines, 3+ live
  operators, and ordering chains. Disambiguate from ADR-0011 (the goal-**draft** store)
  by naming this the **running-goal registry**. Cross-reference SPEC-036 + ADR-0019.
  AC: ADR exists, 0001-0021 format, records the reworded boundary + what stays upheld;
  cross-referenced in `docs/architecture.md`.
- [ ] TASK-002: Apply the C4 rewords to the live docs in sync: PHILOSOPHY lines ~121 +
  ~151 (carve in one-operator multi-session, keep across-machines / 3+ operators L5);
  `commands/kit-health.md` reject-list carve-out (the running-goal registry is in-scope
  per ADR-0022, not flagged as runtime duplication); `_meta/BACKLOG.md` line ~120 (the
  parked "L5 not needed until 3+ concurrent sessions" entry, now re-scoped to the
  ADR-0022 boundary). AC: each boundary string matches the ADR's reworded form; a
  meta-test guards the absence of the old "stays L5" multi-session strings in PHILOSOPHY.

### Phase 2: The registry store
- [ ] TASK-003: Build `lib/goal-registry.sh`, sourcing `lib/dispatch-gate.sh` for the
  overlap + hands-off logic (no second copy of the moat). Subcommands: `claim <slug>
  <lane> <glob...>` (gate vs active goals; on clear, write `<slug>.goal`, exit 0; on
  overlap, name the colliding goal, exit 1); `list` (table of active goals); `log <slug>
  <msg>` (append to `<slug>.attempts`); `status <slug> <state>` (update the record);
  `release <slug>` (remove the goal's files). Registry root = `$(git rev-parse
  --git-common-dir)/kit-goals/`. Pure bash; executable. AC: `claim` of two disjoint
  goals both succeed; a second `claim` overlapping an active goal is refused with the
  colliding slug; `list` shows both; `log` appends; `release` removes.

### Phase 3: Wire claim, monitor, and attempt-log into the commands
- [ ] TASK-004: `commands/assign.md`: after the lane is picked (Step 5), add a
  cross-session **claim** step that runs `goal-registry claim` with the slug + lane +
  the goal's declared globs, and refuses to route the goal into a lane if it overlaps an
  active goal (name the collision; the operator serializes or repicks). AC: assign.md
  documents the claim step and the refuse-on-overlap behavior; a meta-test pins it.
- [ ] TASK-005: `commands/start.md`: add a **"Running goals (cross-session)"** section
  that calls `goal-registry list` so the human (in any session) sees every running goal
  + lane + status, alongside the native agent view. AC: start.md documents the monitor
  section and calls `goal-registry list`; a meta-test pins it.
- [ ] TASK-006: Document the attempt-log convention (detect-don't-dictate, helper-backed,
  no hook): the `/kit:assign` directive and the `/kit:dispatch` worker prompt each tell
  the goal/worker to append one `goal-registry log` line per attempt. AC: both surfaces
  mention the attempt-log line; a meta-test pins the convention's presence.

### Phase 4: Reconcile docs + guards
- [ ] TASK-007: Reconcile the surrounding docs: `WORKFLOW.md` multi-session subsection
  (the cross-session complement to the existing worktree-per-spec / `/kit:dispatch`
  section); `docs/architecture.md` concurrency boundary + the `lib/goal-registry.sh`
  note; `MANUAL.md` registry/monitor usage; `README.md` if it lists the concurrency
  surface; `CHANGELOG.md` `[Unreleased]`; `_meta/BACKLOG.md` ID-040 row. AC: no doc
  claims multi-session "stays L5" unconditionally; the architecture concurrency boundary
  names both the in-session (ADR-0019) and cross-session (ADR-0022) cases; inventory
  parity holds (no new command ⇒ no new inventory row).
- [ ] TASK-008: Tests. `tests/test-meta.sh`: ADR-0022 exists; PHILOSOPHY multi-session
  strings reworded; `lib/goal-registry.sh` exists + executable; assign/start wiring +
  attempt-log convention present; kit-health carve-out present. `tests/test-hooks.sh`:
  the registry round-trips (claim disjoint → both admitted; claim overlapping → second
  refused; list shows entries; log appends; release cleans up). AC: `bash
  tests/test-meta.sh && bash tests/test-hooks.sh` pass with the new assertions green.

## After state
- [ ] One operator can open N Claude sessions on one machine, set a `/goal` per session,
  and the sessions will not pick colliding file-sets (the claim gate refuses an overlap).
  (Today: nothing coordinates across sessions.)
- [ ] `goal-registry list` shows every running goal + lane + status in one table, from
  any session. (Today: no cross-session view; the agent view sees only one session's
  workers.)
- [ ] Each goal leaves a `<slug>.attempts` running log of what it tried. (Today: no
  per-goal attempt log across sessions.)
- [ ] `docs/decisions/0022-multi-session-boundary.md` exists and the two C4 PHILOSOPHY
  strings are superseded for the one-operator multi-session case. (Today: multi-session
  is forbidden as L5.)
- [ ] `/kit:dispatch` (single-lead fan-out) and `/kit:execute` are unchanged. (Verifiable
  by `git diff commands/dispatch.md commands/execute.md` showing no behavior change.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `bash tests/test-meta.sh && bash tests/test-hooks.sh` pass
- [ ] A claim overlapping an active goal is refused (not silently allowed)
- [ ] No daemon / scheduler / DAG / durability store introduced (relabel-into-runtime guard)
- [ ] The disjointness rule is reused from `dispatch-gate.sh`, not re-implemented
- [ ] The registry lives in `.git` and is never committed

## Verification
```bash
bash tests/test-meta.sh && bash tests/test-hooks.sh \
  && test -f docs/decisions/0022-multi-session-boundary.md \
  && test -x lib/goal-registry.sh \
  && grep -q 'goal-registry' commands/assign.md \
  && grep -q 'goal-registry' commands/start.md \
  && ! grep -q 'multi-session coordination across machines or live operators stays L5' docs/PHILOSOPHY.md
```

## Edge Cases
1. **Two sessions claim in the same instant.** Both may pass the gate (advisory, not a
   kernel lock). Mitigation: `claim` re-reads the registry after writing and, if a
   conflicting active goal now exists, fails loud (same last-writer-loud pattern as
   `/kit:assign`'s ID allocation). Residual race window is sub-second and the human owns
   both sessions; a missed overlap costs a manual merge conflict, not corruption (merges
   are human-gated, as in SPEC-032 DEC-008).
2. **A session crashes leaving a stale `<slug>.goal`.** `list` shows it as `running`
   with no live worker. The operator runs `goal-registry release <slug>` (or `status`
   it). No durability/GC daemon by design; stale entries are visible and one command to
   clear, mirroring the SPEC-032 worktree-GC stance.
3. **A goal declares no globs.** `claim` rejects it (cannot prove disjoint from an
   undeclared file-set), the same "gate lies" default as the dispatch gate.
4. **Across machines.** A second machine has a different `.git`, so it sees an empty
   registry. This is correct: cross-machine coordination is L5 (Nimbalyst), explicitly
   out of scope, and the registry location enforces the fence by construction.
5. **The repo is not a git worktree at all.** `git rev-parse --git-common-dir` fails;
   `goal-registry` reports it needs a git repo and exits non-zero (the kit is git-bound
   already: dispatch, ship, drift guard all assume git).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Two goals collide on a file | claim gate: declared globs overlap an active goal | claim REFUSED, colliding slug named; operator serializes or repicks |
| Stale registry entry (crashed session) | `list` shows `running` with no live work | `goal-registry release <slug>`; no GC daemon by design |
| Claim race (same-instant) | post-write re-read finds a new conflicting active goal | fail loud (last-writer-loud), operator re-runs; human owns both sessions |
| Drift into a runtime | a daemon / lease server / scheduler appears in review | the no-runtime invariant + ADR-0022; a 2nd operator or ordering chain is the L5 handoff tripwire, not a build signal |
| Registry committed by accident | a `kit-goals/` path shows in `git status` | impossible: the dir lives under `.git`, which git never tracks |

## Out of Scope
- **Cross-machine coordination / a multi-operator shared pool.** Stays L5 (Nimbalyst).
  The `.git`-local registry location enforces this.
- **Goal ordering / sequencing across sessions** (B waits for A). That is `/kit:mega`
  (in-session, sequential) or GSD v2 (a real DAG); the registry never sequences.
- **A coordinating daemon, lease server, or crash-recovery durability.** The registry
  records and compares; it does not schedule or supervise.
- **Auto-launching sessions.** The human opens each session; the kit never spawns one.
- **Changing `/kit:dispatch` or `/kit:execute`.** The single-lead fan-out and the
  sequential intra-spec executor are unchanged; this is the cross-session complement.

## Touches
This spec touches shared root docs (`WORKFLOW.md`, `README.md`, `MANUAL.md`, the
hands-off `CHANGELOG.md` / `_meta/BACKLOG.md` / `tests/`), so it is a **lead-owned
change, NOT dispatch-eligible** for concurrent fan-out: it must run as one lead session,
not as a worker behind the gate. The clean directory-prefix globs it writes (the part the
gate could express) are:
- lib/**
- commands/**
- docs/**

## Decision Log
- DEC-001: **Registry lives under `$(git rev-parse --git-common-dir)/kit-goals/`, not in
  the working tree and not committed.** Rationale: the git common dir is shared by every
  worktree of one repo on one machine and is inherently untracked. A working-tree file is
  invisible to other worktrees; a committed file is a shared-write collision magnet. The
  location *is* the boundary: it cannot reach across machines, so the L5 fence stands by
  construction.
- DEC-002: **Reuse `dispatch-gate.sh` for the cross-session gate; do not re-implement
  disjointness.** Rationale: the kit's no-premature-duplication rule and a single source
  for the one safety-critical comparison. `goal-registry.sh` sources it.
- DEC-003: **Key=value flat files, not JSON.** Rationale: the registry's purpose is human
  legibility (`cat` it, `grep` it); JSON would add a `jq` parse step for a file a human
  is meant to read, against "bash over binaries" minimalism.
- DEC-004: **No new slash command; wire the claim into `/kit:assign` and the monitor into
  `/kit:start`.** Rationale: "Reconcile before adding" + minimal surface. The registry is
  a `lib/` substrate (like `dispatch-gate.sh`); the existing intake and render commands
  are the natural homes. A dedicated `/kit:running` was rejected to avoid inventory churn
  and an orphan-command risk; revisit only if the monitor proves undiscoverable.
- DEC-005: **The boundary bends for one operator / N same-machine sessions / disjoint
  goals only.** Across machines, 3+ live operators (multiple humans), and ordering chains
  stay L5 (GSD v2 / Nimbalyst), unchanged. "Several sessions" in the goal means one human
  running several; it does not mean a team. This is the precise, minimal bend ADR-0022
  records.
- DEC-006: **Coordination is advisory at claim time, not a kernel lock.** Rationale: a
  real lock needs a daemon (a runtime, the L5 handoff). The advisory gate + last-writer-
  loud re-read + human-gated merge is the same safety posture as SPEC-032's gate; a missed
  same-instant overlap costs a manual merge, not corruption.

## Open questions
(none; DEC-004 and DEC-005 are the two judgment calls and both have a recorded default.)
