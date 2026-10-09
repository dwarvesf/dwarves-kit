# Proof of done: the landed proof survives the bash locale crash

## What changed

`_absorbed` in `lib/wrap/wrap-apply.sh` set `local LC_ALL=C`. Homebrew bash 5.3 on macOS SIGSEGVs (rc 139) in `setlocale` when a function exit restores `LC_ALL`, about 1 call in 20 under load. The crash killed the `$(_merge_proof ...)` subshell in `wrap land`, so the "already landed" proof read as empty and land went down the push, PR and merge path. That was the intermittent red `test-wrap-land` in the nightly regression (TE1, TF1, TH1 on 2026-10-10).

`LC_ALL=C` now reaches git through `env` and is never a bash variable.

## Gate table

| Claim | Evidence |
|---|---|
| root cause is the bash crash, not wrap logic | logging showed `PROOF rc=139 []` on every failing case and `rc=0` on passing ones; bash crash reports end in `pop_var_context -> sv_locale -> libintl_setlocale` |
| fixed tree is green under load | green run |
| the fix is load-bearing | negative control |
| nightly-style env, sequential full suite | green run |

## Green run

```
Command: LAND_CACHE=0 LAND_ONLY=SPEC-376 bash tests/test-wrap-land.sh   (8 in parallel x 4 rounds, env -i with the nightly PATH and placeholder tokens)
Exit: 0 for 32 of 32
test-wrap-land: all 93 passed   (32 runs)
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only test-wrap-land   (10 sequential runs, nightly-style scrubbed env, KIT_RUN_ALL=1)
Exit: 0 for 10 of 10
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only test-wrap-apply
Exit: 0
test-wrap-apply                                ok
run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

With `lib/wrap/wrap-apply.sh` restored to its previous `local LC_ALL=C` form, the same parallel command goes red in 16 of 32 runs:

```
Command: LAND_CACHE=0 LAND_ONLY=SPEC-376 bash tests/test-wrap-land.sh   (fix reverted, 8 in parallel x 4 rounds)
Exit: 1 for 16 of 32
test-wrap-land: 84 passed, 9 FAILED of 93   (1 run)
test-wrap-land: 88 passed, 5 FAILED of 93   (3 runs)
FAIL TD1: still reports already landed
FAIL TF1: reports already landed
FAIL TH3: the branch reads as gone from origin
Verdict: RED as expected; restored, then green as above
```
