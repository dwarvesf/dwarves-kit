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

- **PR base is `master`, not `fix/orchfin-03-wave-tokens`.** The dispatch brief said 03 was already
  merged to `master` (stack collapsed) before this worktree was created; confirmed via
  `git log --oneline -5` showing 03's commit already on `origin/master`. Following the dispatch
  brief over this goal file's stale `**PR base:**` field.
- **`$slog`'s format DOES change, but only in the capture-requested case, and only by reusing the
  EXISTING stream-json convention.** Read "Not: reworking `$slog`'s format" as "don't invent a
  THIRD extraction format/convention" rather than "the watchdog's own log must always stay plain
  text": token extraction (`handoff_gen.py sum-usage`) hard-requires `--output-format stream-json`
  JSONL input, so SOME format change was unavoidable to satisfy the Outcome/Done criteria at all.
  The fix scopes that change tightly: it only fires when a capture was actually requested
  (`stream=1 || DETERMINISTIC_HANDOFF=1 || CAPTURE_TOKENS=1`, the SAME gate the non-watchdog path
  already uses), writes to the SAME deterministic filename (`${id}.stream.jsonl`) the wave reap
  loop already recomputes, and in the same shape the non-watchdog capture path already produces.
  The DEFAULT (no capture requested) watchdog path is untouched: plain `.session.log`, plain `-p`,
  `cat` at the end, byte-identical to pre-fix. Precedent: the pre-existing `--stream` path already
  tees raw stream-json straight to the operator's terminal for the analogous non-watchdog case, so
  a human-facing raw-jsonl surface under capture is already an accepted shape in this codebase, not
  a new one.
