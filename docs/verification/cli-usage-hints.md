# Verification: cli-usage-hints

Usage refusals in `wrap` and `board` keep their exit code and `usage:` line, then add one hint line that names the right form.

| Check | Result |
|---|---|
| New assertions in `tests/test-wrap-cli.sh` (12) and `tests/test-board-add.sh` (AC11, 5) | pass on this branch |
| Same tests on the old lib files (negctl) | wrap-cli 8 failed, board-add 2 failed |
| Touched suites, uncached: wrap-apply, merge, ship, start, cli, land, ci, board-add, sync-characterize, premerge, meta | all pass (470, 288, 120, 143, 106, 889, 214, 75, 13, 20 checks, meta all) |
| `tests/run-all.sh`, 80 suites, host load over 100 | 76 ok; 3 hit the 300s runner ceiling and pass alone; `test-board-states` fails the same way on origin/master (`wrap-session.sh:29`, untouched here) |
| Transcript replay (ops-toolkit `experiments/cli-entropy/code/replay.sh`) | 30 of 30 cases on this branch, 4 of 30 on origin/master |

## Green run
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-cli.sh && bash tests/test-board-add.sh" "git checkout 266c9ec4 -- <the eight lib files>"
Exit: 0 (green before mutation)
Output:
  test-wrap-cli: all 106 passed
  == 75 run, 75 passed, 0 failed ==
Verdict: PASS
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "<same tests>" "git checkout 266c9ec4 -- lib/wrap/wrap-common.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-ship.sh lib/board/backlog.sh lib/board/board_add.py"
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-cli: 98 passed, 8 FAILED of 106
Restore: git checkout HEAD -- <the eight lib files>
Exit: 0 (green after restore)
Verdict: PASS
```

A second control on the board files alone: `tests/test-board-add.sh` went 75 to 73 passed under the old `backlog.sh` and `board_add.py` (`add --help exits 0`, `an unknown verb is named`), then green after restore.

## Not proven
- That agents retry less in practice: ops-toolkit re-measures from transcripts on 2026-12-28.
