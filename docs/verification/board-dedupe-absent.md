# Verification -- board-dedupe-absent

`lib/board/backlog.sh` `dedupe` died silently on an absent id: the row count ran `printf '%s\n' "$rows" | grep -c .` before any emptiness check, and `grep -c` exits 1 on zero matches, so `set -e` killed the script with exit 1 and no output. `get` already guards the same shape with `[ -z "$rows" ]`; `dedupe` now does the same and reports `no Active-queue row for <id>` on stderr with exit 1.

## Change

- `dedupe` tests `$rows` for emptiness before counting, matching `get`'s guard verbatim. Absent id: `no Active-queue row for <id>` on stderr, exit 1. Unique id: still `nothing to dedupe`, exit 0, file untouched. Duplicate id: unchanged collapse.
- `tests/test-board-set-note.sh` gains case 17: absent id exits nonzero, names the id on stderr, writes nothing.
- Same-file audit for the `grep -c` under `set -e` shape: `get`'s count (line ~102) is guarded by its `[ -z "$rows" ]` check; `set_state`'s `match_count` (line ~140) is guarded by the `grep -qE` existence check above it, so `match_lines` is never empty there. `dedupe` was the only unguarded copy.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `BACKLOG_FILE=<1-row fixture> backlog.sh dedupe ID-999` | 1, stderr `no Active-queue row for ID-999` | PASS: reports instead of dying silently |
| `BACKLOG_FILE=<1-row fixture> backlog.sh dedupe ID-001` | 0, stdout `nothing to dedupe` | PASS: unique id stays a no-op |
| `BACKLOG_FILE=<dup fixture> backlog.sh dedupe ID-871` | 0, `kept line 6, dropped lines 5`, one row left | PASS: collapse unchanged |
| `BACKLOG_FILE=<fixture> backlog.sh get ID-999` | 1, `no Active-queue row for ID-999` | PASS: `get` unaffected |
| `BACKLOG_FILE=<fixture> backlog.sh next` / `set ID-001 claimed` | 0 | PASS: `next`/`set` unaffected |
| `bash tests/test-board-set-note.sh` | 0 (`ALL PASS`, 21 cases) | PASS |
| `bash tests/test-board-dedupe-all.sh` | 0 (`ALL PASS`) | PASS |
| `bash tests/test-board.sh` | 0 (`TOTAL: 51 PASS: 50 FAIL: 0 SKIP: 1`) | PASS (skip is NC-e, needs sibling ops-toolkit checkout) |
| `bash tests/test-hooks.sh` | 0 (`Passed: 498 / 498`) | PASS |

## Negative control

Revert -> RED -> restore, run inside the worktree against the new test case:

| Step | Command | Exit | Verdict |
|---|---|---|---|
| Baseline (fixed) | `bash tests/test-board-set-note.sh` | 0, `ALL PASS` | green before revert |
| Revert | `git show master:lib/board/backlog.sh > lib/board/backlog.sh` | - | master's unguarded `grep -c` restored |
| RED | `bash tests/test-board-set-note.sh` | 1, `FAIL dedupe's absent-id message is wrong (silent death?): ''` | case 17 goes red: empty output, the silent death |
| Restore | `cp <saved fixed file> lib/board/backlog.sh` | - | - |
| Green again | `bash tests/test-board-set-note.sh` | 0, `ALL PASS` | PASS |

Direct side-by-side on a 1-row fixture, `dedupe ID-999` (absent):

| Version | Output | Exit |
|---|---|---|
| master checkout (`/Users/tieubao/workspace/dwarvesf/dwarves-kit/lib/board/backlog.sh`) | `''` (nothing on stdout or stderr) | 1 |
| branch | `no Active-queue row for ID-999` on stderr | 1 |

Both exit nonzero; master gives the caller nothing to diagnose, the branch names the id.

## Reproduce

```bash
printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-001 | a row | src | queued |\n' > /tmp/board.md
BACKLOG_FILE=/tmp/board.md bash lib/board/backlog.sh dedupe ID-999
bash tests/test-board-set-note.sh
```

## Not proven

- `dedupe-all` is untouched; it only sweeps ids found in the file, so it never sees an absent id.
- No coverage of callers outside the test suite that might have depended on the old silent exit-1 (none found in `lib/`; `wrap.sh` calls `dedupe-all`, not `dedupe`).
