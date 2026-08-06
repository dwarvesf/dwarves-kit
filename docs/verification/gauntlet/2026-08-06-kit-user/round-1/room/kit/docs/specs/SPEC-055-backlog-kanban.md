# SPEC-055: The Active queue as a kanban board (pull mode)

Status: SHIPPED ([Unreleased])
Lane: normal
Backlog: ID-045
Branch: feat/north-star-03-kanban
Relates-to: PHILOSOPHY §6 N2 (the criterion this realizes), SPEC-005 (the queue schema this extends), ADR-0022 (goal-registry claims), SPEC-054 (type routing applies to pulled items)

## Problem

The BACKLOG had a status lifecycle (SPEC-005) but every dispatch was operator-push: a human
reads the file, picks an item, names it to `/kit:assign`. Nothing could render "what is queued /
moving / stuck" at a glance, nothing could take the next item, and status flips were hand-edits
(so they drifted: two rows sat `queued` whose implementations had shipped, one row carried an
illegal `P1` status , all found by this spec's own board on first run).

## Solution shape

The BACKLOG stays the one source of truth (no parallel database, per §6 N2's reject list).

1. **`lib/board/backlog.sh`**: `board` (kanban columns from the file; unrecognized statuses surface
   loudly), `next` (first `queued` row; file order = priority), `set <ID> <state> [note]`
   (mechanical flip of the LEADING status keyword, annotation prose preserved), `states`.
   `BACKLOG_FILE` env override for tests.
2. **`claimed` state** added to the SPEC-005 vocabulary between `queued` and `speccing`: a
   pulled item; the cross-session claim itself stays in `lib/goal/goal-registry.sh`.
3. **Pull mode**: `/kit:assign --next` = `backlog.sh next` -> goal-registry claim -> `backlog.sh
   set <ID> claimed` -> the normal assign flow (SPEC-054 type routing included). One explicit
   invocation; no daemon, no auto-trigger. `/kit:start` mentions the board when items are queued.

## Acceptance criteria

- AC1: `board` renders the real BACKLOG grouped by state; section headers skipped; illegal
  statuses surface as UNRECOGNIZED instead of vanishing.
- AC2: `next` returns the first queued ID (exit 1 when none); `set` flips only the leading
  keyword, preserves annotations, rejects unknown states (64) and unknown IDs (1).
- AC3: vocabulary documents `claimed`; assign documents `--next`; start nudges the board.
- AC4: real rows migrated to honest states via `set` (dogfood): ID-020/021 -> shipped (their
  implementations verified on master), ID-012 -> parked (P1 shipped, P2 held under ID-036).
- AC5: 10 behavior tests on a fixture copy + meta pins; both suites green.

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | board/next/set behavior | the 10 fixture tests in `tests/test-hooks.sh` (render, priority order, flip, prose preserved, unknown state/ID rejected) |
| 2 | real-file render | `bash lib/board/backlog.sh board` exit 0 with zero UNRECOGNIZED rows |
| 3 | wiring pins | meta pins: backlog.sh exists+executable, assign documents `--next`, vocabulary contains `claimed` |
| 4 | negative control | delete the `--next` bullet from assign.md -> pin RED (recorded during build) |

## Rollback

`git revert`. One new lib helper + doc prose + three row-state corrections; no daemon, no
external state.
