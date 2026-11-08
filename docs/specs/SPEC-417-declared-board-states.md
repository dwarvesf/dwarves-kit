# Spec: declare the board row machine once, derive every reader from it

Status: APPROVED
Lane: normal
Brief: docs/briefs/DECISION-BRIEF-declared-state-machines.md

## Problem

The board row status is the kit's most-written state: seven writers across bash and Python. Its vocabulary is hardcoded in six code files (`backlog.sh`, `board-writeback.sh`, `sync_core.py`, `sources/github.py`, `sources/hermes.py`, `sweep/board-health`), and nothing checks the copies agree. `board-writeback.sh` says in a comment that its copy "must be kept in sync" by hand. `backlog.sh set` accepts any state from any state, so a `shipped -> queued` flip is silent. An agent that asks "where can this row go next" must read WORKFLOW.md, SYSTEM-DESIGN.md and command prose.

## Solution

### Approaches considered

| Approach | Verdict |
|---|---|
| A. A `states.tsv` beside the writer; readers derive; a test fails on a new copy; `set` prints a notice on a reopen | chosen |
| B. A generic `lib/fsm/` engine that refuses undeclared moves | rejected: blocks sync, reconcile and hand repairs; breaks PHILOSOPHY "Detect, don't dictate" |
| C. Fix the six copies by hand | rejected: the next added state re-creates the drift |

### Chosen approach + why

A. It is additive: every derived set equals the old literal, so no caller sees a different value. The brief carries the full reasoning and the inventory of the other machines.

## Technical Design

### Interfaces (I/O contract)

- `lib/board/states.tsv`: TAB-separated `state class next`, `#` comments. Classes `active`, `hold`, `terminal`. `next` is the advisory forward path, `-` for none. File order is render order.
- `backlog.sh states` (unchanged output), `backlog.sh states --class active|hold|terminal` (new), `backlog.sh machine` (new: a `state class next` header, then the rows). A bad class exits 64. Neither verb needs a BACKLOG file.
- `backlog.sh set`: unchanged stdout and exit codes. A move out of a `terminal` state to a different state prints `board set: <ID> reopens from terminal '<from>' to '<to>'` on stderr and still writes.
- The terminal-note rule (a terminal state's note supersedes) reads the `terminal` class, not a literal.
- A missing or unreadable `states.tsv` is fatal in `backlog.sh` and `board-writeback.sh`, and raises in Python.
- `sync_core.py` gains `BOARD_MACHINE_FILE` and `load_board_machine()`; `BOARD_STATES`, `ACTIVE_STATUSES`, `TERMINAL_STATUSES` keep their names, types and values. `github.py` and `hermes.py` import `ACTIVE_STATUSES` (the import `reminders.py` and `notion.py` already use). `board-health` derives its ordered `ACTIVE` tuple through `sync_core`.

### Data model changes

New file `lib/board/states.tsv`. No stored state changes.

## Task Breakdown

1. Add `states.tsv`; derive `backlog.sh` and `board-writeback.sh` from it; add `states --class`, `machine`, the reopen notice.
2. Derive `sync_core.py`, `github.py`, `hermes.py`, `board-health`.
3. Add `tests/test-board-states.sh`.
4. Docs: WORKFLOW.md and SYSTEM-DESIGN.md point at the table; the brief.

## After state

`grep` finds the full board vocabulary only in `lib/board/states.tsv` among code files. Adding a state is one line there. `backlog.sh machine` prints the machine.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 every reader yields the old sets | `tests/test-board-states.sh` case 2 |
| AC2 an added row reaches bash and Python readers with no other edit | case 3 |
| AC3 a missing table is fatal | case 4 |
| AC4 a re-introduced copy fails the suite | case 5 + a negative control on the real tree |
| AC5 reopen notice; quiet otherwise; terminal note rule kept | case 6 |
| AC6 existing board and sync suites stay green | `bash tests/run-all.sh --changed` |

## Verification

```bash
bash tests/test-board-states.sh
bash tests/run-all.sh --changed
```
