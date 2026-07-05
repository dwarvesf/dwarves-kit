# Sub-goal 05: conductor-rid-check (ID-099)

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table + named negative control (a sub-goal dispatched with no rid is caught, not silently run). Rung 2.
**Design:** obvious
**Depends on:** 04 (stacked for orchestrate.sh merge hygiene, no logical dep)
Model: sonnet
**Branch:** fix/orchfin-05-rid-check
**PR base:** fix/orchfin-04-watchdog

## Outcome

The conductor refuses to proceed with a sub-goal that has no run-id (`rid`), or flags it loudly, so gate coverage is always auditable. Today a missing rid means the run's gates cannot be traced to a ledger record, an unauditable pass. After this, an rid-less dispatch is a caught error, not a silent gap.

## Quality bar

No run is unauditable. If the conductor can't tie a sub-goal to an rid, it stops and says so, it never quietly lets gate coverage go dark.

## How to close the loop

- Find where the conductor dispatches a sub-goal and where the rid is (or isn't) required in `orchestrate.sh`.
- Add a pre-dispatch guard: missing rid → hard error (or explicit blocked-with-reason), never a silent proceed.
- Test (the negative control): dispatch a sub-goal with an empty/absent rid; assert the conductor errors/flags and does NOT run it as if covered.
- Capture the run-table (the rid-less case being rejected).

**Done =** the conductor rejects (or explicitly flags blocked) a missing-rid dispatch, verified by a captured negative-control run-table where an rid-less sub-goal is caught, not silently passed.

**Kit-adopted repo? Record the gates** (from dwarves-kit cwd, `lane-classify` → `normal`).

## Handoff on completion

1. ROADMAP `[x]` + PR #. 2. `HANDOFF.md` → 06. 3. `DECISIONS.md`. 4. Report, EXIT.

## Scope edges

**In:** the conductor's pre-dispatch rid check in `orchestrate.sh`.
**Out:** how rids are GENERATED, the gate-ledger's rid format.
**Not:** adding rid to other tools, reworking the ledger, changing dispatch semantics beyond the guard.

## Where to look

The conductor dispatch path in `lib/queue/orchestrate.sh`, the rid handling, `lib/gate/gate-ledger.sh rid`.

## PR body

Adds a conductor-side missing-rid guard (ID-099) so gate coverage is always auditable, an rid-less dispatch is caught, not silently run. Verify: the rid-less negative-control run-table. Stacked on #<04 PR>; review after it. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes
