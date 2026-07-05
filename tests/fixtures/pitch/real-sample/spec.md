# Spec: Command emit sweep -- close the RUN_REPORT under-count (kit-run-integrity sub-goal 05)

Generated: 2026-07-04
Status: VALIDATED
Lane: full (touches the operate-contract's own gate-recording convention across 9 command
files plus a new invariant test that must hold forever; treated as full per the mega-goal's
own framing, not because any single edit is architecturally deep).

## Problem

`RUN_REPORT.md` (`/kit:mega`'s per-sub-goal gate matrix, `commands/mega.md` "Close the run
visibly") can only show a phase as covered if SOME command actually calls `gate-ledger.sh`
for it. A 2026-07-04 audit found 11 of 29 commands emit directly, 18 are dark, with no
distinction anywhere between "this phase genuinely has no ledger concern" and "nobody wired
it yet."

## Solution

Two-part close-out, plus the forever-invariant test the mega-goal's over-test framing demands:

1. **Wire the 9 phase-owning dark commands.** Each gains ONE line, at its natural hand-off
   point, in the SAME single-line convention `test-plan.md` / `review.md` / `devs-team.md`
   already use (`bash lib/gate/gate-ledger.sh record <rid> <Phase> ran "<summary>"`).

## Out of Scope

- `execute.md`'s pre-existing `Build`/`design-record` gap: named honestly, not fixed.
- No new gate, no lane-matrix cell, no new required phase.

## Acceptance criteria

| # | Criterion | Evidence |
|---|---|---|
| AC1 | Frozen snapshot, fixture-only (tests/test-pitch.sh AC1) | this file |
