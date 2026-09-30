# Proof of done: the harvest sweep holds on a weekly usage limit

Verdict: PASS

The scheduled `mini.harvest-sweep` run on 2026-09-30 exited rc 1 and paged a CRIT. The report showed `INCIDENT extractor: probe failed: You've hit your weekly limit · resets 8am (Asia/Saigon)`. `LIMIT_RE` matched the 5-hour and generic limit shapes but not the weekly one, so the first failure went to the auth probe, the probe hit the same limit, and the run stopped as auth-shaped. DEC-80 says a limit-shaped failure is a hold: rc 0, cursor held, no fail count. The pattern now also matches `weekly limit` and `hit your <window> limit`.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-harvest-sweep.sh` (before the fix) | 1 | 597/598, `ExtractFailure.limit catches the weekly-limit shape (live Mini run)` failed |
| `bash tests/test-harvest-sweep.sh` (after the fix) | 0 | 598/598 |

## Run detail

```
Command: bash tests/test-harvest-sweep.sh
Exit: 0
Verdict: Passed: 598 / 598
```

NEGATIVE CONTROL: the new test ran red on the old pattern and green on the new one.

## Rollback

Revert this commit; a weekly-limit failure then pages as auth again.
