# Verification: two brief lede phrases join with "and"

## Result

| Check | Command | Exit | Result |
|---|---|---|---|
| Brief suite, fix | `bash tests/test-board-brief.sh` | 0 | 241 passed, 0 failed |
| Negative control | `lib/sync/sweep/board-brief` from `HEAD~1`, then the suite | 1 | 240 passed, 1 failed |
| Restore | `git checkout -- lib/sync/sweep/board-brief`, then the suite | 0 | 241 passed, 0 failed |

## Change

`lede_of` joined two phrases with a comma: "a memo draft that parks tomorrow, 2 cards to triage". Two phrases now join with "and". Three or more items keep "A, B and N more".

## Green run

- Command: `bash tests/test-board-brief.sh`
- Exit: 0
- Output:
  ```
  board-brief: 241 passed, 0 failed
  ```
- Verdict: PASS

## Negative control

- Command: the previous renderer, then `bash tests/test-board-brief.sh`
- Exit: 1
- Output:
  ```
  board-brief: 240 passed, 1 failed
  ```
- Verdict: PASS (red as required)
