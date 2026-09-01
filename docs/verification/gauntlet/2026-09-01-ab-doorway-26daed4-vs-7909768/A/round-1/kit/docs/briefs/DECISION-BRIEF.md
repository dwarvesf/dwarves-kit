# Decision Brief: V-model-gated concurrent goal dispatch (I2 / ID-034 + ID-035)

Produced by `/kit:think` (dogfooded), 2026-05-22. Supersedes the prior brief (SPEC-004 lane B, shipped). Design source of record: `docs/research/2026-05-22-concurrent-goal-dispatch.md`. This brief locks scope and adds one new decision (convergence-owned shared writes) that the research note did not yet have.

## Verdict: BUILD (scope-locked to the native, non-runtime model)

## Core thesis
After requirement clarification, the maintainer fires N independent specs and tabs away; one autonomous worker per goal builds each in its own background worktree under the kit's V-model gates, escalating only on blockers. Safety comes from worktree isolation + a file-disjointness gate + a lead-owned convergence that integrates every shared surface once, after the workers finish.

## Strongest argument for
It delivers fire-and-walk-away multi-goal autonomy on primitives that exist today (`run_in_background` subagents + `isolation: worktree` + `AskUserQuestion`), with no scheduler, no DAG, no runtime. It removes the kit's biggest current limit (one goal at a time, attended) while preserving the bash-and-shallow thesis and the runtime-integration boundary.

## Strongest argument against
The safety gate is file-disjointness: necessary but not sufficient, and a poor fit for the kit's own shared-surface-heavy work (nearly every kit change touches `tests/test-meta.sh` + `CHANGELOG`). So the speedup mostly accrues to downstream projects, not to dogfooding the kit; and the convergence-write design that fixes this adds real lead-side complexity that, if it ever grows into scheduling, is the exact tripwire back toward the runtime the model swears off.

## The two coupled IDs
- **ID-034 (the trust contract, load-bearing, build first).** The per-goal V-model lifecycle each worker follows, and the lead-owned convergence point. NOT a relabeling: it is what makes a tab-away worker trustworthy and where shared state safely merges.
- **ID-035 (the dispatch, rides on ID-034).** The three thin build items: fan-out, the disjointness gate, the blocker contract.

## Recommended scope for v1

**IN:**
- **ID-034 lifecycle + convergence:** left arm (brief -> requirement -> solution/test design) | bottom (build) | right arm (verify -> review -> docs -> converge), with the existing `worker -> task-verifier -> fix-agent (<=2)` running inside each worktree as the per-goal gate. The **lead owns the convergence write**: workers touch only their feature files; `CHANGELOG`, `VERSION`, suite counts, `BACKLOG`, `plugin.json` are integrated once by the lead after all workers finish (the right-arm re-convergence). This is the new decision from this think and the seam between ID-034 and ID-035.
- **ID-035 dispatch:** (1) fan-out dispatch (extend `/kit:execute` or a new `/kit:dispatch`) launching N background worktree subagents from N independent specs; (2) the parallel-safety gate = file-disjointness + dep-tag, with shared surfaces excluded from the disjointness test because the lead owns them at convergence; (3) the blocker-escalation contract in the worker prompt (escalate irreversible/ambiguous, proceed on reversible; port the existing CLAUDE.md Vibe-Coding rubric).
- **The ADRs (required before merge):** C1 (reword "does NOT cover parallel execution" + "one agent session at a time"; supersede "sequential by design"; explicitly UPHOLD the runtime-integration boundary + "Shallow and wide"). C2 (reword the "8 workflow phases" frame + feature-rejection criterion #2 to the V-model phase set). PHILOSOPHY + `commands/kit-health.md` reject-list updates per the WORKFLOW doc-impact map.

**CUT (the no list, from the research note):**
- No DAG / topological scheduler. Across independent goals the structure degenerates to a flat set + pairwise disjointness + wait-queue; build the gate, not a graph.
- No in-kit runtime / state machine (rejected Option 6; that is gsd-2 territory).
- No cross-session durability. Lead dies -> restart; workers commit frequently so progress survives as branch commits.
- No Agent Teams. Deferred, not discarded: that is intra-goal collaboration; reconsider only on the intra-spec task-parallelism tripwire.
- No intra-spec task parallelism **in v1** (deferred, not discarded; refined by a second `/kit:think` pass 2026-05-22). v1's unit is the whole spec: one worker per spec, a spec's own tasks stay sequential. Running one spec's disjoint-file tasks concurrently is a **separate, later initiative**, sequenced after v1's disjointness gate + lead-owned convergence prove out. **Revisit tripwire:** a single spec routinely carries 2+ genuinely disjoint-file tasks AND its serial wall-clock is the felt bottleneck. **Metric for that future initiative:** wall-clock speedup (target ≥40% on a real 2-task spec), with 0 silent merge corruptions as a hard gate; deliberately distinct from this brief's autonomy+safety metric. **Caveat that may sink it:** intra-spec tasks usually share files (test suites, fixtures, `CHANGELOG`), so the disjointness gate will often serialize them anyway, the same shared-surface problem this brief's "strongest argument against" already names for the kit's own work.

## Exit criteria (maintainer-chosen)
- Fire 3 independent specs on a downstream-shaped repo, tab away, get 3 clean PRs: 0 merge conflicts, <=1 blocker-escalation each.
- A deliberately-overlapping pair of goals is correctly **serialized**, not parallelized (the moat holds).
- Across ~10 fired goals, >80% of escalations are genuine (not babysitting, not silent-wrong-default).
- Explicitly NOT judged on wall-clock speed: the win is autonomy + safety, not raw throughput.

## Risk tripwires (when to stop and hand off)
- A real cross-goal ordering chain (C needs A+B merged) -> hand execution to gsd-2; do not build a scheduler.
- A single spec needing its own tasks to cooperate -> reconsider Agent Teams (intra-goal), not this model.
- The convergence logic growing into scheduling/state-tracking -> you have crossed into runtime; stop and integrate, do not rebuild.

## Build order
ID-034 (gate + convergence contract) first, because it is the moat and the trust. ID-035 (fan-out + disjointness gate + blocker contract) rides on it. Both are full lane; both need `/kit:spec-validate` (autonomy-gate lens, ID-027, applies directly).
