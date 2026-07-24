# Decision Brief: DAG wavefront scheduling in the orchestrator

Date: 2026-07-02 · Source: operator ask ("run independent sub-goals concurrently in the background"), verified against `lib/queue/orchestrate.sh` + ADR-0019/0020/0027/0028. Status: DRAFT (proposal for Han; needs a mini-ADR before build , it re-opens ADR-0028's DAG deferral, narrowly).

## Verified current state

- `lib/queue/orchestrate.sh` runs a mega-goal STRICTLY SERIALLY: `_next()` picks the first unchecked sub-goal; the loop waits for its grounded box-flip before the next. `WATCHDOG_STALL_SECS>0` backgrounds each `claude -p` session, but only to poll for stalls , robustness, not parallelism.
- **The DAG is already declared AND parsed, but unused for scheduling.** `_sg_deps_blocked()` (line ~133) extracts `depends SG-NN` tokens from ROADMAP lines; today it feeds only the board view (ready/blocked prose). The scheduler ignores it.
- The SG-10 event log is append-only by design with the stated property "a crashed/CONCURRENT session cannot corrupt a checkbox" , the completion plumbing already anticipates concurrency.
- Disjointness machinery exists at another layer: `lib/gate/dispatch-gate.sh` (ADR-0019, DEC-008 prove-or-serialize over `## Touches` directory-prefix globs, + drift guard), used by `/kit:dispatch` for disjoint VALIDATED specs in worktrees.
- ADR-0028 explicitly deferred "an ORDERED dependency graph + scheduler + crash-recovery + parallel-writer locks" as the GSD-v2 successor. (It claims the deferral is "tracked in the kit-hardening mega-goal NOTES" , it never was; this brief closes that dangling reference.)

## Verdict: BUILD-SMALL , a wavefront extension, NOT the GSD-v2 engine

The operator's ask (run dep-independent sub-goals concurrently) does not need the deferred engine. A wavefront scheduler falls out of five shipped pieces: the `depends` parser, the grounded box-flip completion signal, the watchdog's session backgrounding, `dispatch-gate.sh`'s prove-or-serialize, and the repo's worktree discipline. Estimated ~150-200 lines in `orchestrate.sh` + a flock helper + tests.

## Design

```
READY SET = unchecked AND every `depends SG-NN` checked        (parser exists)
  -> dispatch-gate over the wave's pairs: prove-disjoint or serialize (DEC-008)
  -> spawn each ready sub-goal as `claude -p` in ITS OWN WORKTREE, cap N (default 2)
  -> on each grounded box-flip (flock-guarded), recompute READY SET, launch next wave
  -> crash/restart: recompute from ROADMAP boxes + PR states (idempotent resume, no state store)
```

Collision points -> resolutions:

| Collision | Resolution |
|---|---|
| Parallel writers on one checkout (`.git/index.lock`) | one worktree per concurrent session (existing discipline; worktree at `<repo>/.claude/worktrees/<sg-id>`) |
| Dep-independent but FILE-overlapping sub-goals | run `dispatch-gate.sh` across wave pairs before spawn; unprovable = serialize (conservative); drift guard after |
| `HANDOFF.md` is one HOT file; parallel sessions clobber it | per-edge handoffs: each sub-goal writes `HANDOFF-<id>.md`; a child's prompt injects its dep-parents' handoffs. Linear chain = degenerate single-parent case (backward compatible) |
| Concurrent ROADMAP box flips (read-modify-write) | tiny `orchestrate flip <id>` helper wrapped in `flock`; event log already append-only-safe |

Gate semantics change: a `gate` sub-goal pauses only ITS dependent chain; independent branches continue; the loop stops when every branch is done or gate-held. `--step`/`--stream`/board modes unchanged (board already renders ready/blocked).

Concurrency cap default 2 (configurable): these are full sessions, not cheap dispatches; the 2026-07-02 token audit showed the cost center is long-session cache-read, so small waves.

## Explicitly NOT built (the GSD-v2 boundary stands)

Priority scheduling · cross-machine execution · new retry policies · a separate crash-recovery store · speculative execution · DAG visualization beyond the existing board. If any of these becomes a real need, that is GSD-v2 and re-opens ADR-0017/0019 properly.

## Exit criteria (negative controls first)

1. Two dep-independent, Touches-disjoint sub-goals run concurrently in separate worktrees; both land with green proofs.
2. A dep-independent but Touches-OVERLAPPING pair is SERIALIZED by the gate (never concurrent).
3. Kill the orchestrator mid-wave; restart recomputes the ready set and resumes without duplicating a completed sub-goal (idempotent).
4. A `gate` sub-goal holds only its chain; an independent branch completes meanwhile.
5. A linear-chain mega-goal (no deps declared beyond order) behaves EXACTLY as today (regression control).

## Sequencing

After kit-telemetry ships (no new sub-goals mid-mega-goal). Order: (1) mini-ADR amending ADR-0028's deferral scope (wavefront in, GSD-v2 still out), (2) `/spec` + `/spec-validate`, (3) build in the full lane. Board row: ID-084.

## 2026-07-25 addendum (operator direction, row ID-394)

The wavefront half of this brief SHIPPED as ADR-0030. Han's direction 2026-07-25 supersedes the
"GSD-v2 still out" boundary: the kit owns its ordering graph outright; the handoff tripwire
language (5 mentions in commands/dispatch.md + commands/mega.md) is retired. Scope now: explicit
`depends_on` + a DYNAMIC ready-queue with auto-unblock (not static waves), sequential merge in
deterministic ID order under parallel execution, file-footprint as a concurrency constraint,
task-state-transition hooks, and bisect-on-red as the follow-up failure semantics. Prior-art
grounding + ranked pickups/avoids: `docs/research/2026-07-25-dag-orchestration-prior-art-refresh.md`.
The "Explicitly NOT built" list above stands MINUS the graph itself (still no priority scheduling,
no cross-machine, no speculative execution, no CP-SAT before the ready-queue ships). The mini-ADR
in Sequencing step (1) now amends ADR-0028 to retire the boundary entirely rather than narrow it.
