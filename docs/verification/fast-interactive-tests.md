# Proof of done: interactive test runs stay under 15 minutes

## What changed

Sessions ran `tests/run-all.sh --all` mid-work. The host-wide test lock (`tests/lib/run-lock.sh`) then queued every other session behind that run, so a 3-minute `--changed` run waited 30 to 60 minutes.

1. `tests/run-all.sh --all` exits 64 outside CI unless `KIT_RUN_ALL=1`. The check runs before the lock, so a refused run never waits on it. The nightly job in ops-toolkit sets the variable (tieubao/ops-toolkit#3963, merged first).
2. `bin/test-affected` picks `test-meta.sh` only when the diff touches its inputs (`meta_input` rule). It was always selected and took 197s of a 253s `--changed` run.

## Gate table

| Claim | Evidence |
|---|---|
| `--all` refuses locally, runs under `CI` or `KIT_RUN_ALL=1` | case [8] in `test-run-all-changed.sh`, run table |
| the guard is load-bearing | negative control |
| `test-meta` selection follows its inputs | `test-test-affected.sh`, run table |
| `--time` still works for the full glob | `test-run-all-time.sh` (exports `KIT_RUN_ALL=1`) |
| a typical `--changed` run is faster | timing below |

## Run table

```
Command: bash tests/test-run-all-changed.sh
Exit: 0
Output:
  ok: CI=true runs the full glob
  ok: KIT_RUN_ALL=1 runs the full glob
test-run-all-changed: all 12 passed
Verdict: PASS
```

```
Command: bash tests/test-test-affected.sh
Exit: 0
Output:
test-test-affected: 35 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-run-all-time.sh
Exit: 0
Output:
test-run-all-time: all 4 passed
Verdict: PASS
```

## Negative control

```
Command: bash lib/gate/negctl.sh . "bash tests/test-run-all-changed.sh" "<line 36: match --never instead of --all>"
Output:
  test-run-all-changed: 10 passed, 2 FAILED
Restore: git checkout HEAD -- tests/run-all.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation makes the guard never match `--all`, so the refusal cases go red.

## Timing

Same 22-suite `--changed` selection, same host, measured with `--time`:

| Run | Wall time |
|---|---|
| before (`test-meta` always on) | 244.41s |
| after (`test-meta` only on its inputs) | 145.64s |

Known ceiling: any `*.md` change is a `test-meta` input, so a docs-touching diff still pays its cost.
