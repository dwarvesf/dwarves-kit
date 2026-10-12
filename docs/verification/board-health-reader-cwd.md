# Verification -- board-health-reader-cwd

`kanban_json` in `lib/sync/sweep/board-health` now runs the kanban reader with `cwd="/"`. A user-switching reader (sudo -u server) no longer inherits a job cwd it cannot read, so the brief stops posting "kanban unreadable ... getcwd". The `--line` hook and poster calls are not user-switching readers and are unchanged.

## Green run
```
Command: bash tests/test-board-health.sh
Exit: 0
Output:
  ok   the kanban reader runs from / , not the job cwd
board-health: 97 passed, 0 failed
Verdict: PASS
```

## Negative control
```
Command: bash tests/test-board-health.sh   (with , cwd="/" removed from kanban_json)
Exit: 1
Output:
  FAIL reader ran from the job cwd: kanban unreadable for alpha: shell-init: error retrieving current directory: getcwd: cannot access parent directories: Permission
board-health: 96 passed, 1 failed
Verdict: RED (expected)
```
The arg was restored afterwards; the green run above is the restored state.

## Not proven
- A real sudo -u reader on the Mini; the fake reader models the failure by checking pwd.
