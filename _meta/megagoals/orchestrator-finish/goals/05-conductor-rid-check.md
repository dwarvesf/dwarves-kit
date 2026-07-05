# Sub-goal 05: conductor-rid-check (ID-099)

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table showing a WAVE dispatch now emits a START/rid record (it previously emitted none) + a negative control (a dispatch with no derivable rid is caught, not silently untracked). Rung 2.
**Design:** obvious
**Depends on:** 04 (stacked for orchestrate.sh merge hygiene, no logical dep)
Model: sonnet
**Branch:** fix/orchfin-05-rid-check
**PR base:** fix/orchfin-04-watchdog

## Outcome

Every dispatch , serial AND wave , emits a START/rid record so gate coverage is always auditable.

Verified reality (2026-07-06): the described "conductor does not guard at all" is STALE. The serial path DOES derive a rid via `_emit_start` and, when the goal file has no `**Branch:**`, WARNS and skips it ("run will be '?' in lane-telemetry") , advisory, not a block. The real gap is the WAVE path: `_wave_run`'s spawn loop emits only an `executing` event and NEVER calls `_emit_start`, so wave dispatches produce no START/rid at all , they are invisible to lane-telemetry. Rescoped fix: (1) emit a START (`_emit_start`) on the wave dispatch path so wave runs are tracked like serial ones; (2) decide whether the serial advisory warn on a missing rid should become a hard block or stay advisory (pin: keep advisory + loud, since a `?`-rid run is degraded-but-runnable, not corrupt).

## Quality bar

No dispatch is invisible. A wave of five sub-goals leaves five START records, not zero. If a rid genuinely can't be derived, the run is loudly flagged, never silently untracked.

## How to close the loop

- Confirm the gap: `_emit_start` is called on the serial path but NOT in `_wave_run`'s spawn loop (which emits only `executing`).
- Add the START/rid emission to the wave dispatch path, mirroring the serial `_emit_start`.
- Test (negative control): run a 2-sub-goal wave; assert TWO START/rid records land (previously zero); assert a dispatch with no derivable rid is loudly flagged.
- Capture the run-table (the wave now emitting START records).

**Done =** the wave dispatch path emits a START/rid per sub-goal (verified by a captured 2-sub-goal-wave run-table showing two START records where there were zero), AND a no-rid dispatch is loudly flagged, not silently untracked.

**Kit-adopted repo? Record the gates** (from dwarves-kit cwd, `lane-classify` → `normal`).

## Handoff on completion

1. ROADMAP `[x]` + PR #. 2. `HANDOFF.md` → 06. 3. `DECISIONS.md`. 4. Report, EXIT.

## Scope edges

**In:** the wave dispatch path in `orchestrate.sh` (`_wave_run` spawn loop) and its missing START emission; the serial `_emit_start` advisory.
**Out:** how rids are GENERATED, the gate-ledger's rid format, the serial path's existing START (already works).
**Not:** adding rid to other tools, reworking the ledger, turning the advisory warn into a hard abort (pinned: keep advisory).

## Where to look

`lib/queue/orchestrate.sh`: `_emit_start` (serial), `_wave_run`'s spawn loop (emits only `executing`, no START), the rid derivation, `lib/gate/gate-ledger.sh rid`.

## PR body

Emits a START/rid on the WAVE dispatch path (ID-099, rescoped): the wave spawn loop previously emitted only `executing` and no START, so wave dispatches were invisible to lane-telemetry (the serial path already warns-but-runs on a missing rid; that stays advisory). Verify: a 2-sub-goal-wave run-table showing two START records where there were zero. Stacked on #<04 PR>; review after it. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes
