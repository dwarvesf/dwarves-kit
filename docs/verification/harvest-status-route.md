# Proof of done: harvest.py --status routes to the sweep

Verdict: PASS

The first hand dry run on the Mini showed `python3 hooks/harvest.py --status` exiting 0 with no output. `_dispatch` routed only `--sweep` and `--dry-run` to the sweep, so `--status` fell through to the per-session hook path. The fix adds `--status` to that route.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-harvest-sweep.sh` (before the fix) | 1 | 593/594, `AC28: harvest.py --status routes to the sweep` failed: got `\|0`, wanted `none\|0` |
| `bash tests/test-harvest-sweep.sh` (after the fix) | 0 | 594/594 |
| `bash tests/test-kit-foldin-hooks.sh` | 0 | 97/97 |

## Run detail

```
Command: bash tests/test-harvest-sweep.sh
Exit: 0
Verdict: Passed: 594 / 594
```

NEGATIVE CONTROL: the new test ran red before the one-line dispatch change and green after it.

## Rollback

Revert this commit; `--status` then works only through `hooks/harvest_sweep.py --status` again.
