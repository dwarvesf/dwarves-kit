# Proof of done: C12 report byte-identity no longer flakes on the clock

## What changed

Nightly regression 2026-10-11 failed `test-gate-validate-round` at `C12 report --period month byte-identical`. The `gate-ledger.sh report` header prints `since <now-30d>` with one-second resolution. The test runs the two reports back to back, so a second boundary between them changes the header. Measured: 26 mismatches in 300 paired calls (about 9 percent). C12 never failed in earlier nightly logs, which fits that rate.

It is not the bash setlocale crash class: no `bash-*.ips` exists for 2026-10-11, and the only `LC_ALL` use in `lib/gate/gate-ledger.sh` is a `LC_ALL=C tr` command prefix.

The test now masks the `since` stamp before comparing. Rows and totals stay byte-compared. No product code changed.

## Gate table

| Claim | Evidence |
|---|---|
| root cause is the one-second header stamp | 26/300 paired-call mismatches, run table below |
| the fix removes the flake | forced-tick shim: master fails, branch passes |
| the suite stays green in a nightly-like env | six scrubbed-env runs, run table below |

## Run table

```
Command: PATH="$SHIM:$PATH" bash tests/test-gate-validate-round.sh   (master checkout, date shim forces a tick between the two reports)
Exit: 1
Output: FAIL C12 report --period month byte-identical
=== results: 195/196 pass, 1 fail ===
Verdict: FAIL (negative control: the unfixed test fails when the clock ticks between the calls)
```

```
Command: PATH="$SHIM:$PATH" bash tests/test-gate-validate-round.sh   (this branch, same shim)
Exit: 0
Output: === results: 196/196 pass, 0 fail ===
Verdict: PASS
```

```
Command: env -i HOME=$HOME PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin KIT_RUN_ALL=1 bash tests/run-all.sh --only test-gate-validate-round </dev/null   (6 runs)
Exit: 0
Output: test-gate-validate-round                       ok   (x6)
Verdict: PASS
```
