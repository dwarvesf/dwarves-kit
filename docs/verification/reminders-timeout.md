# Proof of done: Reminders transport fails fast when the app never answers

Change under proof: `lib/sync/sources/reminders.py` `_osascript` probes Reminders once per process with a 30s deadline. A probe or bulk call that times out drops `~/.cache/backlog-sync/reminders-unresponsive`. Every later process within 30 minutes skips the reminders leg at once. Motivation: on 2026-10-02 a wedged LaunchServices on the Mini stopped every app launch. Each board waited the full 600s timeout, so the hourly sweep over 13 boards ran about 2h15m and failed every tick.

## Green run

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | New cases + whole sync suite | `bash tests/test-sync.sh` | 294 passed in 1.03s | PASS |
| 2 | Live, wedged Mini, first board | `python3 lib/sync/backlog_sync.py --apps reminders --list "Backlog · books" --backlog <books-backlog>/BACKLOG.md --state-root <tmp> --dry-run` | `did not answer a 30s probe; skipping reminders for 30 min`, rc=1, 30s | PASS |
| 3 | Live, same command again | same | `skipped, Reminders.app did not answer 0 min ago`, rc=1, 0s | PASS |

Before the fix the same call blocked 600s per board (sweep log `board-sync-all.log`, 48 `TimeoutExpired` tracebacks since the 00:11 tick).

## Negative controls

| # | Control | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Revert `reminders.py` to the parent commit, keep the tests | `git show HEAD~1:lib/sync/sources/reminders.py >\| lib/sync/sources/reminders.py; pytest lib/sync/tests/test_reminders.py` | 6 passed, 4 errors | RED as expected |
| 2 | Restore | `git checkout -- lib/sync/sources/reminders.py; bash tests/test-sync.sh` | 294 passed | PASS |

## Reproduce

```
bash tests/test-sync.sh
uv run --no-project --with pytest -- pytest lib/sync/tests/test_reminders.py -q
```
