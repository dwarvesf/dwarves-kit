# Verification: brief keeps Discord channel links out of the secret mask

## Result

| Check | Command | Exit | Result |
|---|---|---|---|
| Brief suite, fix | `bash tests/test-board-brief.sh` | 0 | 243 passed, 0 failed |
| Negative control | `lib/sync/sweep/board-brief` from `HEAD~1`, then the suite | 1 | 242 passed, 1 failed |
| Restore | `git checkout -- lib/sync/sweep/board-brief`, then the suite | 0 | 243 passed, 0 failed |

## Cause

The live df brief printed its Handled link as `https://discord.[redacted]`. `_text` and `_rich` mask any 40+ run of base64 characters. A Discord channel link (`discord.com/channels/<guild>/<thread>`) is only numeric ids, but its digits and slashes form such a run.

## Change

`_mask_runs` sets Discord channel and message links aside, masks the long runs, then puts the links back. Webhook URLs, `op://` references, hex runs and other base64 runs stay masked. The new test also checks that a base64 token beside a kept link is still masked.

## Green run

- Command: `bash tests/test-board-brief.sh`
- Exit: 0
- Output:
  ```
  board-brief: 243 passed, 0 failed
  ```
- Verdict: PASS

## Negative control

- Command: the previous renderer, then `bash tests/test-board-brief.sh`
- Exit: 1
- Output:
  ```
  board-brief: 242 passed, 1 failed
  ```
- Verdict: PASS (red as required)
