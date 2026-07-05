# 0030. DAG-wavefront scheduling in the orchestrator (narrow amendment to ADR-0028's DAG deferral)

Date: 2026-07-02
Status: Accepted (2026-07-03, Han , blessed via explicit authorization in the DAG-wavefront goal loop; the narrow amendment scope confirmed: wavefront in, GSD-v2 still out)
Relates-to: ADR-0028 (autonomous-loop hardening , this narrowly re-opens its DAG deferral), ADR-0017 (mega-decomposition lane , the linear-chain run this extends), ADR-0019 (parallel-execution boundary / `## Touches` disjointness), ADR-0020 (dispatch-primitive lock), ADR-0027 (context hygiene / per-edge handoff), DECISION-BRIEF-dag-wavefront (board ID-084 , the design + exit criteria this ADR authorizes)

## Context

ADR-0028 (Accepted 2026-07-01, team-blessed) deferred, in two places, an ordered dependency-graph orchestrator:

- line 42: "Decomposition stays planning-only (SPEC-034); the run is the existing bounded in-session loop (ADR-0017), not a new scheduler. No DAG / cross-machine (GSD v2)."
- line 94: "A DAG / dependency-graph orchestrator ... An ORDERED dependency graph + scheduler + crash-recovery + parallel-writer locks is the deferred GSD-v2 successor , a separate effort that re-opens ADR-0017/0019, NOT this wave. Tracked as a future option in the kit-hardening mega-goal NOTES."

That deferral bundled two very different scopes under one "no":

1. **GSD-v2**: a general ordered-graph engine , priority scheduling, cross-machine execution, a separate crash-recovery state store, speculative execution, new retry policies, DAG visualization. Genuinely a separate effort.
2. **Wavefront**: run the sub-goals that are *already dep-independent* concurrently instead of strictly serially. This needs none of the GSD-v2 machinery , it falls out of five pieces the kit already shipped.

DECISION-BRIEF-dag-wavefront (ID-084) verified this against the code. The relevant findings:

- `lib/queue/orchestrate.sh` runs a mega-goal strictly serially; `_next()` picks the first unchecked sub-goal and the loop waits for its grounded box-flip before the next.
- **The dependency graph is already declared and parsed** , `_sg_deps_blocked()` extracts `depends SG-NN` tokens from ROADMAP lines, but today only the board view consumes them; the scheduler ignores them.
- The SG-10 event log is append-only by design, explicitly so that "a crashed/CONCURRENT session cannot corrupt a checkbox" , the completion plumbing already anticipates concurrency.
- `lib/gate/dispatch-gate.sh` (ADR-0019, DEC-008) already does prove-or-serialize over `## Touches` directory-prefix globs plus a drift guard.
- Worktree discipline (one worktree per concurrent writer) is already the repo norm.

## Motivation (measured, from the kit-telemetry run 2026-07-02)

The kit-telemetry mega-goal (5 sub-goals, dwarves-kit PRs #112/#113/#114/#115/#117) is the concrete serial-cost evidence:

- Its auto-bottom-up merge posture "worked cleanly" **precisely because it ran serially** , "since I merged each sub-goal before creating the next, no child-retarget dance was needed (each branched off the updated master)." The serial order is what avoided the retarget-child-before-delete dance the NOTES flagged as the hazard to watch. Wavefront must preserve that safety while relaxing the ordering only where deps allow.
- That run's TIER-4 advisor (P6 over-suggest) explicitly listed ID-084 (DAG-wavefront) as "now unblocked" and paired it with the stack-base verification item (SPEC-100 pattern).
- Per-sub-goal token/turn ledgers from that run are the cost basis for the concurrency cap: the cost center is long-session cache-read, so waves stay small (cap default 2), not cheap dispatches.

## Decision

Amend ADR-0028's DAG deferral **narrowly**: authorize the wavefront extension (ID-084) as scoped in the brief. GSD-v2 stays deferred, unchanged.

**In scope (this amendment authorizes):**

- `lib/queue/orchestrate.sh` computes a READY SET each cycle = unchecked sub-goals whose every `depends SG-NN` is checked, and runs the ready wave concurrently (cap default 2, configurable), one worktree per session.
- `dispatch-gate.sh` reused across each wave's pairs: prove-disjoint-or-serialize; unprovable disjointness = serialize (conservative).
- Per-edge `HANDOFF-<id>.md` injection , a child reads its dep-parents' handoffs; the linear chain is the degenerate single-parent case (byte-identical behavior).
- A small `flock`-guarded box-flip helper (the event log is already append-only-safe).
- `gate` semantics narrow: a `gate` sub-goal holds only its own dependent chain; independent branches continue.
- Crash/restart recomputes the ready set from ROADMAP boxes + PR states (idempotent resume, **no new state store**).

**Out of scope (ADR-0028's GSD-v2 boundary stands, unchanged):**

Priority scheduling · cross-machine execution · new retry policies · a separate crash-recovery state store · speculative execution · DAG visualization beyond the existing board. Any of these re-opens ADR-0017/0019 properly and is a separate effort.

**Invariant (non-negotiable):** a mega-goal with no declared deps behaves byte-identically to today's serial run. The linear chain is sacred; any regression on it fails the goal, it is not a trade-off.

## Consequences

- The kit gains concurrency for dep-independent work without a new engine, ~150-200 lines in `orchestrate.sh` plus a flock helper plus tests, all resting on shipped primitives.
- The disjointness guarantee is only as strong as `dispatch-gate.sh`'s `## Touches` prove-or-serialize; conservative-by-default (serialize on doubt) keeps the parallel-writer risk bounded.
- The GSD-v2 line is now explicit rather than bundled: a future ordered-graph engine is a clean re-open of this ADR + ADR-0017/0019, not a surprise.
- This ADR also closes ADR-0028's dangling "tracked in the kit-hardening mega-goal NOTES" reference (the brief notes that tracking never actually landed there).

### Reconciliation with the 2026-05-22 concurrent-goal-dispatch note (status: active)

`docs/research/2026-05-22-concurrent-goal-dispatch.md` §5 set the rule: *"'we need a DAG' is the
tripwire that says you have outgrown the native model. When that day comes, hand execution to
gsd-2; do not build a scheduler inside the kit."* That note also fenced "rich goal ordering chains
(C needs A+B merged, D needs C...)" as genuine DAG scheduling = a runtime = hand to gsd-2.

This ADR **narrows that rule, it does not discard it.** The note conflates two things the brief
separates: (a) *wave scheduling over an already-parsed dependency edge set*, and (b) *a runtime*
(scheduler + separate state store + crash-recovery engine + per-provider retry + auto-advance). The
note's "hand to gsd-2" verdict is correct for (b). Wavefront is (a): it needs none of the runtime
machinery , no state store (resume recomputes from ROADMAP boxes), no crash-recovery engine
(idempotent re-run), no provider retry , and it reuses the shipped `depends` parser + grounded
box-flip + watchdog backgrounding + `dispatch-gate.sh`. So the tripwire now reads: **a wave
scheduler over declared `depends` edges WITHIN a mega-goal stays in-kit (this ADR); a true runtime
(cross-machine, durable state store, priority, provider-retry, auto-recovery) is still the gsd-2
handoff.** The 2026-05-22 note gets a supersession pointer to this ADR.

## Verification (exit criteria the build must satisfy , from the brief)

1. Two dep-independent, Touches-disjoint sub-goals run concurrently in separate worktrees; both land with green proofs.
2. A dep-independent but Touches-OVERLAPPING pair is SERIALIZED by the gate (negative control).
3. Kill the orchestrator mid-wave; restart recomputes the ready set and resumes without re-running a completed sub-goal (idempotent).
4. A `gate` sub-goal holds only its chain; an independent branch completes meanwhile.
5. A linear-chain mega-goal behaves exactly as today (golden regression control).

Proof lands at `docs/verification/orchestrate-wavefront.md` with all five rows; 2 and 5 are the explicit negative controls.
