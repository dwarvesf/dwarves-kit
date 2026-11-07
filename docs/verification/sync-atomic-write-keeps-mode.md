# Verification: board sync keeps the board's file mode

## Result

| Check | Command | Exit | Result |
|---|---|---|---|
| Sync suite, fix | `bash tests/test-sync.sh` | 0 | 270 passed |
| Negative control | `lib/sync/backlog_sync.py` from `HEAD~1`, then the suite | 1 | 3 failed, 267 passed |
| Restore | `git checkout -- lib/sync/backlog_sync.py`, then the suite | 0 | 270 passed |

## Cause

`atomic_write` in `lib/sync/backlog_sync.py` used `mkstemp` (opens 0600) and `os.replace`, so every board write left BACKLOG.md at 0600. A cron under another account (dfoundation `taskboard-status`, running as `server`) could not read the board and skipped its check. `board_add.py`, `board-normalize` and `staging-format.py` already carry the target's mode over.

## Change

`atomic_write` reads the target's mode and applies it to the temp file before the replace. A new file gets `new_mode`: 0644 for a board, 0600 for the two sync state files (they keep their old mode). Other `os.replace` writers in `lib/` were checked: `board-health` and `board-hermes save_links` are deliberately private state, `board-hermes write` and `board-mirror-cleanup` write a spoke file and a snapshot, not a board.

## Green run

- Command: `bash tests/test-sync.sh`
- Exit: 0
- Output:
  ```
  270 passed in 1.30s
  ```
- Verdict: PASS

## Negative control

- Command: the previous `lib/sync/backlog_sync.py`, then `bash tests/test-sync.sh`
- Exit: 1
- Output:
  ```
  FAILED lib/sync/tests/test_atomic_write_mode.py::test_existing_board_keeps_its_mode
  FAILED lib/sync/tests/test_atomic_write_mode.py::test_a_new_board_is_world_readable
  FAILED lib/sync/tests/test_atomic_write_mode.py::test_a_new_state_file_stays_private
  3 failed, 267 passed in 0.92s
  ```
- Verdict: PASS (red as required)
