# ADR-0019: Parallel-execution boundary (bounded cross-goal fan-out, not a runtime)

## Status: accepted (2026-05-23). Implements SPEC-032 conflict C1. Supersedes four standing boundaries that forbade any concurrency.

## Context

The kit was specified to run **one goal at a time, attended**. Four boundaries in the
live policy docs forbade any concurrency outright (conflict **C1**, `_meta/BACKLOG.md`
ID-035 row):

1. `docs/PHILOSOPHY.md` "What the kit does NOT cover": **"Parallel execution: /execute
   dispatches tasks sequentially ... not competing with agent runtimes."**
2. `docs/PHILOSOPHY.md`: **"one agent session at a time, with subagents dispatched
   within that session."**
3. `docs/PHILOSOPHY.md` target-user note: **"someone who needs multi-agent
   orchestration across parallel sessions (that's L5)."**
4. `docs/PHILOSOPHY.md` **"Shallow and wide beats deep and narrow"** read as a ban on
   any fan-out.

These were written before the 2026-05-22 harness-engineering pivot, in which the
maintainer committed to firing several independent specs, tabbing away, and collecting
several finished branches (ID-035 / SPEC-032). PHILOSOPHY line 11 is explicit: a
principle that cannot be violated when the tradeoff shifts is not a real principle.
The tradeoff shifted; the boundary must be superseded **deliberately, by ADR**, before
the capability is built. SPEC-033 / ADR-0020 already proved the dispatch primitive
(in-session `Agent(run_in_background, isolation:worktree)` workers, Path A) runs on
today's harness. What remained was the policy un-nerf. This ADR is it.

## Decision

**Bounded cross-goal fan-out is in-scope. A DAG / scheduler / runtime is not.**

The kit's parallel boundary is redrawn, not erased. The permitted model:

- **One LEAD session orchestrates N isolated worktree workers**, one per independent
  `Status: VALIDATED` spec, via the SPEC-033 / ADR-0020 primitive.
- **A disjointness gate is the moat**: two goals run concurrently only when their
  declared `## Touches` file globs are disjoint after excluding the lead-owned
  shared-surface list; any pair the gate cannot PROVE disjoint is serialized (a
  wait-queue), never parallelized. Conservative by construction (SPEC-032 DEC-008).
- **A post-task drift guard** asserts each worker's real diff stays within its declared
  globs and never touches a hands-off surface.
- **Convergence is lead-owned** (SPEC-031): workers never write the shared surfaces; the
  lead integrates them once at `/kit:ship`. No auto-merge; the human merges.
- **No cross-session durability**: in-flight workers are tied to the lead session;
  committed work survives as `goal/*` branches.

### The four boundary rewords

| # | Old (forbids) | New (permits the bounded model) |
|---|---|---|
| 1 | "Parallel execution: /execute dispatches tasks sequentially ... not competing with agent runtimes" | "Cross-goal parallel fan-out (N disjoint specs in isolated worktrees, behind the disjointness gate, lead-owned convergence) is in-scope. `/kit:execute` itself stays sequential intra-spec; a DAG / wave scheduler / crash-recovery runtime stays out (GSD v2)." |
| 2 | "one agent session at a time" | "one LEAD session orchestrating N isolated worktree workers" |
| 3 | "multi-agent orchestration across parallel sessions (that's L5)" | "bounded cross-goal fan-out is in-kit; multi-session orchestration across machines / 3+ live operators stays L5 (Nimbalyst / Conductor)" |
| 4 | "Shallow and wide" read as a fan-out ban | **UPHELD.** Fan-out IS width, not depth: N goals at 70% lifecycle depth each, not one goal at runtime depth. The principle stands; it never forbade width. |

### What stays UPHELD (explicitly not loosened)

- **"Shallow and wide"** (reword #4): the model is width, not a deeper runtime.
- **The runtime-integration boundary**: when goals develop real ordering chains
  (C needs A+B merged, then D needs C), that is the **tripwire to hand execution to
  GSD v2**, not to grow a scheduler in-kit.
- **The no-DAG line**: flat set + pairwise gate + wait-queue only. No topological
  sort, no wave execution, no dependency resolver.
- **Bash over binaries**: the gate and drift guard are pure bash/glob; no new binary.
- **The safety subset**: safety-gate, push-to-main blocker, anti-rationalization, and
  the verification pipeline are NOT loosened for unattended workers. Worker isolation
  rides on the git worktree + the gate + the drift guard + human-gated merge.
- **Intra-spec sequential**: `/kit:execute` is unchanged; one spec's tasks still run
  one at a time. This ADR is cross-goal only.

## Alternatives considered

- **Keep the ban; route all concurrency to GSD v2.** Rejected: the maintainer's
  fire-and-walk-away workflow needs only disjoint-file fan-out, which the harness
  already supports natively (ADR-0020); deferring it entirely to an external runtime
  imposes a heavyweight dependency for a lightweight need.
- **Permit a full in-kit DAG runtime.** Rejected: that is GSD v2's job; rebuilding it
  breaks "Shallow and wide", the runtime-integration boundary, and bash-over-binaries.
  The parking-lot "In-kit DAG executor" entry stays parked; this ADR does not unpark it.
- **Loosen the safety hooks for unattended workers.** Rejected: the worktree + gate +
  drift guard + human-gated merge are the safety net; the hard hooks stay hard. Workers
  inherit `bypassPermissions` for prompts only (SPEC-032 DEC-009), not a hook bypass.

## Consequences

- `docs/PHILOSOPHY.md` reframes the four boundaries above from a ban to the bounded
  model; "Shallow and wide" gains a one-line note that fan-out is width. The change is
  a **boundary/policy restatement**, correct independent of build status, not a feature
  inventory claim.
- `commands/kit-health.md` Step 4 gains a recorded carve-out (alongside the visual-team
  exception) so the self-assessment does not flag `/kit:dispatch` as "duplicates an
  external tool (GSD)" or "competes with agent runtimes": bounded cross-goal fan-out is
  in-scope per this ADR; only a DAG/scheduler/durability runtime is a REJECT.
- The implementing surface is **SPEC-032** (`/kit:dispatch` + `## Touches` + the gate +
  the drift guard); the primitive is locked by **ADR-0020**; the convergence contract is
  **SPEC-031**. This ADR carries only the policy decision.
- `docs/architecture.md` and `README.md` cross-reference this ADR (per the WORKFLOW
  doc-impact map "a new docs/decisions ADR" row).
- `tests/test-meta.sh` asserts this ADR exists, is cross-referenced from PHILOSOPHY and
  architecture.md, and that the bald "competing with agent runtimes" ban no longer
  survives as a live PHILOSOPHY claim.

Source: SPEC-032 (conflict C1, TASK-001/002), SPEC-031 (lead-owned convergence),
ADR-0020 (dispatch primitive lock), `_meta/BACKLOG.md` 2026-05-22 re-evaluation
(initiative I2). Relates to ADR-0018 (V-model phase frame) which carries the C2 reword.
