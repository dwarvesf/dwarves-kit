# Implementation notes: orchestrator board-sync (SG-10)

Delta from goal file `goals/10-board-sync.md` (token-optim-v2). Stacked on SG-01
(`feat/orchestrator-run-modes`) because both edit `lib/queue/orchestrate.sh`.

## 2026-06-29 state-vocabulary mapping (the one real deviation)
- Spec wants the board to extend the kanban with `ready` / `blocked(reason)` / `stalled`.
- `lib/board/backlog.sh` (the reuse target) has a FIXED, non-env-overridable `STATES` vocabulary
  (`queued claimed speccing validated executing shipped parked dropped`). Editing backlog.sh is
  out of scope (scope = orchestrate.sh + its test + reuse backlog.sh).
- Decision: map the orchestrator's derived lifecycle onto backlog.sh's standard keywords and
  carry the extended nuance as STATUS PROSE (backlog.sh explicitly supports "prose after the
  keyword"):
  - box checked            -> `shipped`
  - event log = executing  -> `executing`
  - event log = stalled    -> `executing [stalled: <note>]`  (SG-11 emits this; SG-10 renders it)
  - unchecked, deps met    -> `queued [ready]`                ("ready" = workable now)
  - unchecked, deps NOT met -> `parked [blocked: needs <SG-..>]`
- Why: keeps ONE renderer (backlog.sh) + the cockpit row format, no vocab fork. ready/blocked/
  stalled stay visible (queued vs parked columns + the prose), which is the spec's intent
  (distinguish workable-now from dep-blocked), just without forking backlog.sh's STATES.

## 2026-06-29 dependency analysis source
- "ready vs blocked" needs to know a sub-goal's deps. Read them from the ROADMAP line's
  `depends ...` tail (e.g. `depends SG-02+SG-03`), NOT the goal file, so derivation needs only
  the ROADMAP already in hand. A dep is blocking iff it names an UNCHECKED `SG-NN`. Non-SG deps
  (`#81` = a prerequisite PR) are treated satisfied -- out of board scope, can't be read here.

## 2026-06-29 event log = the progress signal SG-11 reuses
- Event log at `<dir>/.orchestrate/events.log`, append-only `ISO\tSG\tstatus\tnote`. Emitted on
  each transition in cmd_run (executing on launch, shipped on box-flip, blocked on gate-stop).
- Board state is DERIVED by replay (last event per sub-goal wins); never mutated in place. A
  crashed/concurrent session can't corrupt a checkbox. SG-11's stalled-watchdog reuses this
  file's mtime + last-status as its progress signal (goal 11 "reuse SG-10's event log").

## 2026-06-29 --board default = detect
- Default (no `--board`): `both` when `lib/board/backlog.sh` resolves next to orchestrate.sh, else
  `roadmap`. Fail-safe to `roadmap` so a kit without backlog.sh still runs. Never writes to the
  repo-wide BACKLOG.md; the per-mega-goal board is `<dir>/BOARD.md` only.
