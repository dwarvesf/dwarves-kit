# Proof of done: `board promote <n>` honours the shim's `--backlog-file`

2026-09-16. Acceptance: `board promote <n>` run through a consumer shim (`<repo>/_meta/board`, which appends `--backlog-file <path>` to every subcommand) promotes the candidate onto the board the flag names, with the staging file resolved beside it. Env overrides (`BACKLOG_STAGE_BACKLOG`, `BACKLOG_STAGE_STAGING`) still win. A dangling flag is a usage error. Lane: fix. Files: `lib/board/bin/add-backlog`, `tests/test-board-promote.sh`.

## The failure this replaces

`board.sh promote` forwards its argv verbatim to `lib/board/bin/add-backlog`, whose selector parser runs `int()` over every token. The shim's appended `--backlog-file <path>` hit that `int()`, so every `promote <n>` through a shim printed the usage line and exited 2. `promote list` and `promote all` never reached the parser and kept working, which hid the break. Surfaced on ops-toolkit while promoting a staged candidate; the workaround was a direct call with both env vars set.

## Green run

Command: `bash tests/test-board-promote.sh`
Exit: 0
Output: `== 34 run, 34 passed, 0 failed ==`
Verdict: PASS. 29 assertions before the change, 34 after; the five new ones cover list and promote through the flag with both env vars unset, no usage line on the promote path, the row landing on the flag-named board, and the dangling-flag usage error.

Command: `DWARVES_KIT=<this worktree> ops-toolkit/_meta/board promote 99` (the real shim, an index that matches nothing)
Exit: 1
Output: `no matching staged candidates.`
Verdict: PASS. The index reached the selector. The installed kit on the same command prints `usage: board promote [list | <n>... | all | reject <n>...]`.

Command: `bash tests/run-all.sh`
Exit: see the table
Verdict: RUN-ALL-PENDING

## Negative control

Command: `git show origin/master:lib/board/bin/add-backlog >| lib/board/bin/add-backlog && bash tests/test-board-promote.sh`
Exit: 1
Output: `== 34 run, 31 passed, 3 failed ==` with `FAIL shim list: shows the staged block`, `FAIL shim promote: board named by the flag gained the row`, `FAIL shim promote: dangling flag is a usage error`
Verdict: RED as expected. Patch restored, suite back to 34 of 34.

## Reproduce

```
git worktree add /tmp/kit-probe origin/master
cd /tmp/kit-probe && bash tests/test-board-promote.sh   # 3 shim cases red
git checkout fix/promote-backlog-file -- lib/board/bin/add-backlog
bash tests/test-board-promote.sh                       # 34 of 34 green
```
