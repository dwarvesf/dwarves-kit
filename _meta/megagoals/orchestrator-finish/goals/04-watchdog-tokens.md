# Sub-goal 04: watchdog-tokens (ID-097)

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table showing the watchdog-stall branch writing tokens to `$slog`, with a negative control (a simulated stall that previously dropped the token line now records it). Rung 2.
**Design:** obvious
**Depends on:** 03 (stacked for orchestrate.sh merge hygiene, no logical dep)
Model: sonnet
**Branch:** fix/orchfin-04-watchdog
**PR base:** fix/orchfin-03-wave-tokens

## Outcome

When a worker stalls and the `WATCHDOG_STALL_SECS` branch fires, it STILL captures the worker's tokens to `$slog` before killing/hopping. The stall path no longer silently drops token accounting, so an overnight run's totals include the work that stalled, not just the work that finished cleanly.

## Quality bar

A stall is an event, not an accounting black hole. The ledger's totals are honest even on the runs that went sideways.

## How to close the loop

- Find the `WATCHDOG_STALL_SECS` branch in `orchestrate.sh` and confirm it exits without writing to `$slog` (the current bug).
- Route the token capture through the stall branch too (mirror the happy-path capture).
- Test: simulate a stall (stub the watchdog trigger) and assert a token line lands in `$slog`.
- Capture the run-table (the stall case + the token line it now writes).

**Done =** the `WATCHDOG_STALL_SECS` branch writes the worker's tokens to `$slog` (verified by a captured stall-simulation run-table); the negative control confirms the pre-fix path dropped it.

**Kit-adopted repo? Record the gates** (from dwarves-kit cwd, `lane-classify` → `normal`).

## Handoff on completion

1. ROADMAP `[x]` + PR #. 2. `HANDOFF.md` → 05. 3. `DECISIONS.md`. 4. Report, EXIT.

## Scope edges

**In:** the watchdog/stall branch in `orchestrate.sh` and its token capture.
**Out:** the watchdog's stall DETECTION logic, `WATCHDOG_STALL_SECS`'s value.
**Not:** changing when the watchdog fires, adding new stall handling, reworking `$slog`'s format.

## Where to look

The watchdog / stall branch in `lib/queue/orchestrate.sh` (`WATCHDOG_STALL_SECS`), the happy-path token-capture it should mirror, `$slog`.

## PR body

Captures tokens to `$slog` on the watchdog-stall branch (ID-097), closing the accounting hole where a stalled worker's tokens were dropped. Verify: the stall-simulation token run-table. Stacked on #<03 PR>; review after it. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes
