# Proof of done: board work (SPEC-366)

Branch `feat/execution-view`. All runs from the worktree root, fixtures and stub orca only (live orca never called).

## Green

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-board-work.sh` | 0 | `== board work: 78 passed, 0 failed ==` |
| `bash tests/test-board.sh` | 0 | `TOTAL: 58   PASS: 57   FAIL: 0   SKIP: 1` |
| `bash tests/test-bin-forwarders.sh` | 0 | `test-bin-forwarders: all 48 passed, 0 skipped` |
| `bash tests/test-meta.sh` | see report | census and wiring checks, run last |

## Negative controls

Work committed first (`1df62cc4`), each mutation applied with `sed -i`, the suite run, then `git checkout -- lib/board/work.sh` and the suite re-run.

| # | Mutation in `lib/board/work.sh` | Suite while broken | Failing case | Suite after restore |
|---|---|---|---|---|
| 1 | zero-terminal / no-`lastOutputAt` branch returns `idle` instead of `unknown` | `76 passed, 2 failed` | `not_in_orca_no_terminal` (no-terminal, never idle) | `78 passed, 0 failed` |
| 2 | PARKED drops the `idle_s >= idle_min * 60` comparison | `75 passed, 3 failed` | `not_parked_under_threshold` (young terminal, `--idle-min 60`, future clock) | `78 passed, 0 failed` |
| 3 | ledger reader counts `skipped` as a rung | `77 passed, 1 failed` | `rung_ladder` | `78 passed, 0 failed` |
| 4 | shipped rows with no branch are listed instead of dropped | `74 passed, 4 failed` | `done_unseen`, `shipped_unchecked_footer` | `78 passed, 0 failed` |

## Reproduce

`bash tests/test-board-work.sh`, then apply any mutation above and re-run.
