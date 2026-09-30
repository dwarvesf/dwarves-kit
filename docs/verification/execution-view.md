# Proof of done: board work (SPEC-366)

Branch `feat/execution-view`. All runs from the worktree root, fixtures and stub orca only (live orca never called).

## Green

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-board-work.sh` (BSD pass, then GNU-tools pass) | 0 | `== board work: 112 passed, 0 failed ==` (BSD pass), then `ok: GNU-tools pass is green` and `== board work: 113 passed, 0 failed ==` |
| `bash tests/test-board.sh` | 0 | `TOTAL: 58   PASS: 57   FAIL: 0   SKIP: 1` |
| `bash tests/test-bin-forwarders.sh` | 0 | `test-bin-forwarders: all 48 passed, 0 skipped` |
| `bash tests/test-meta.sh` | 0 | `Passed: 887 / 887`, `All meta tests passed.` (FEATURES.md regenerated) |

## Negative controls

Work committed first (`1df62cc4`), each mutation applied with `sed -i`, the suite run, then `git checkout -- lib/board/work.sh` and the suite re-run.

| # | Mutation in `lib/board/work.sh` | Suite while broken | Failing case | Suite after restore |
|---|---|---|---|---|
| 1 | zero-terminal / no-`lastOutputAt` branch returns `idle` instead of `unknown` | `76 passed, 2 failed` | `not_in_orca_no_terminal` (no-terminal, never idle) | `78 passed, 0 failed` |
| 2 | PARKED drops the `idle_s >= idle_min * 60` comparison | `75 passed, 3 failed` | `not_parked_under_threshold` (young terminal, `--idle-min 60`, future clock) | `78 passed, 0 failed` |
| 3 | ledger reader counts `skipped` as a rung | `77 passed, 1 failed` | `rung_ladder` | `78 passed, 0 failed` |
| 4 | shipped rows with no branch are listed instead of dropped | `74 passed, 4 failed` | `done_unseen`, `shipped_unchecked_footer` | `78 passed, 0 failed` |

## Review-round negative controls

Fix committed first (`17953c8d`), then each mutation, run, `git checkout -- lib/board/work.sh`, re-run (94 passed, 0 failed each time). N1 runs with the coreutils gnubin first on PATH.

| # | Mutation in `lib/board/work.sh` | Suite while broken | Failing case |
|---|---|---|---|
| N1 | `tr` set back to the reversed `'[:alnum:]._-\n'` | GNU pass red | `runid_parity` (1 of 9 names), then every joined row `unknown` |
| N2 | branch fallback borrows any repo's orca row | `93 passed, 1 failed` | cross-repo branch fallback (`not-in-orca` expected) |
| N3 | finished shipped rows counted unchecked | `92 passed, 2 failed` | `done_unseen` unchecked-count assertions |
| N4 | claims with no worktree not listed | `93 passed, 1 failed` | claimed slug with no worktree is `INDETERMINATE(no-worktree)` |

## Final-round negative controls (file activity, window)

Committed first (`39b45d8a`), mutation, run, `git checkout -- lib/board/work.sh`, re-run (112 passed, 0 failed each). F4 runs with the GNU tools first on PATH, so it also proves the GNU `stat -c` branch is exercised.

| # | Mutation in `lib/board/work.sh` | Suite while broken | Failing cases |
|---|---|---|---|
| F1 | no activity is guessed idle instead of unknown | red, 5+ failures | `not_in_orca` rows, cross-repo fallback, truncated page, worktree item |
| F2 | age comparison inverted | red, 5+ failures | fresh file working, old file PARKED, table source cell, `--idle-min` boundary, HEAD commit time |
| F3 | `--since` window ignored | `108 passed, 4 failed` | done_unseen unchecked counts, 0 day window, 40 day old record |
| F4 | GNU `mtime` returns 0 | red, 5+ failures | file-activity cases (fresh, old, boundary, table) |

## Live smoke (read-only, dwarves-kit checkout, after the final round)

`bash bin/board work --repo-root <dwarves-kit> --json`: 24 items. By origin: `board` 9, `worktree` 15, `mega` 0. By `agent.source`: `files` 15, `none` 9, `orca` 0. By state: `working` 8, `idle` 7, `unknown` 9. Flags: PARKED 7, INDETERMINATE 9 (the board rows, `no-draft`). `unchecked_shipped` 0, `undated_shipped` 206, window 14 days. The checkout's `git status --porcelain` is unchanged (0 lines before and after).

## Reproduce

`bash tests/test-board-work.sh`, then apply any mutation above and re-run.
