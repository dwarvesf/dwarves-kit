# Proof of done: refresh stale command-emit-sweep pins (ID-475)

## What changed

`tests/test-command-emit-sweep.sh` had two stale manual tripwire pins: the
command-count (32) and the exemption-table expected set (10, missing
`feature-map`). The repo had drifted to 36 commands and an 11-entry table, so
the test was RED on master. Updated both pins plus the AC2 header comment.
Test-only change; no production/library code touched.

## Recorded run

```
Command: bash tests/test-command-emit-sweep.sh
Exit: 0
Passed: 19 / 19
```

## Confirmation + negative control

| Run | Command | Result |
|---|---|---|
| green | `bash tests/test-command-emit-sweep.sh` | 19/19, Exit 0 |
| independent count | `ls commands/*.md \| wc -l` | 36 (matches the new pin) |
| NEGATIVE CONTROL | revert the count pin to `32` | AC1 fails (expected 32, got 36); restore -> 19/19 green |

Verdict: PASS (claim: the pins match the live repo and the tripwire still
fires; metric: the test suite; threshold: 19/19 with the reverted pin flipping
RED).

## Rollback

Test-only, no state. `git revert` the branch commits to restore the old pins
(the test goes RED again against the current repo, which is the pre-fix state).
No cleanup.

## Reproduce

```
bash tests/test-command-emit-sweep.sh   # 19/19
ls commands/*.md | wc -l                # 36, must equal the count pin
```
