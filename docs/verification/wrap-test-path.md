# Proof of done: wrap suites stay green on the nightly job's trimmed PATH

## What changed

The nightly job (`mini.kit-nightly-regression`) pins `PATH` to `~/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`. macOS keeps `lsof` in `/usr/sbin`, so under that `PATH` `wrap` prints `NOTE: busy check unavailable (no lsof)` and skips the busy-holder check. Every busy assert in `test-wrap-apply` (9) and `test-wrap-land` (5) then read red, while the same suites passed from an interactive shell.

`tests/lib/wrap-stub.sh` now appends `/usr/sbin:/sbin` to the harness `PATH`. The no-lsof case still strips every `PATH` directory that holds `lsof`, so it is unchanged.

Separately, `test-wrap-deploy` was red on master since the `land --no-pull` change: that change rewrote three sentences in `commands/wrap.md` and the test still asserted the old wording. The three asserts now match the new text.

Rollback: revert the two test commits. No runtime code, no state, no config changed.

## Gate table

| Claim | Evidence |
|---|---|
| the busy cases pass on the nightly's trimmed PATH | run table, apply and land |
| the busy cases were red on that PATH before the fix | negative control below |
| the deploy-doc asserts match the current doc | run table, deploy |
| the touched wrap suites stay green | run table, changed |

## Run table

```
Command: PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin bash tests/test-wrap-apply.sh
Exit: 0
Output: test-wrap-apply: all 309 passed
Verdict: PASS
```

```
Command: PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin bash tests/test-wrap-land.sh
Exit: 0
Output: test-wrap-land: all 615 passed
Verdict: PASS
```

```
Command: bash tests/test-wrap-deploy.sh
Exit: 0
Output: test-wrap-deploy: all 176 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 before the deploy assert commit (test-wrap-deploy only), 0 for every other suite
Output: run-all: 21 suites run, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

```
Command: git revert --no-commit <harness commit>; same PATH; bash tests/test-wrap-apply.sh and tests/test-wrap-land.sh
Exit: 1 and 1 (RED expected)
Output: test-wrap-apply: 300 passed, 9 FAILED of 309
Output: test-wrap-land: 610 passed, 5 FAILED of 615
Restore: git revert --abort
Verdict: PASS (the fix is load-bearing)
```

```
Command: git revert --no-commit <deploy assert commit>; bash tests/test-wrap-deploy.sh
Exit: 1 (RED expected)
Output: test-wrap-deploy: 173 passed, 3 FAILED of 176
Restore: git revert --abort
Verdict: PASS
```
