# Proof of done: test-queue.bats state sandbox (ID-468, the NC2/NC6/NC7 "failures")

Profile: fix   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | NC2, NC6, NC7 pass again on this machine (the suite is fully green) | PASS | R1 |
| 2 | Run files (beat/status/guard) resolve inside the test sandbox, never the operator's real state dir (tripwire T13) | PASS | R1 |
| 3 | Removing only the sandbox export turns T13 red (negative control, read-only, no re-pollution) | PASS | R2 |
| 4 | The leaked guard files in the real state dir are cleaned (trash, recoverable) | PASS | R3 |

## 2. Root cause

The three "pre-existing NC failures on master" were not product regressions and not test-logic
rot. `setup()` sandboxed `QUEUE_JOURNAL` but NOT the run-file root: beat/status/guard files
resolve through `kit_resolve_log_dir`, which fell through to the real
`~/.local/state/dwarves-kit/logs/queue-runs/`. Every local suite run appended to the same guard
counters (e.g. `prose1.guard` had reached `noprogress=16`); once `noprogress` crossed the
SPEC-221 breaker's trip (3), `_breaker_apply` rewrote the NCs' expected `stalled` verdict into
`error stagnation_detected`, failing them forever on that machine while staying green on any
fresh checkout. The ID-463 class of bug (a suite writing outside its sandbox), state-dir
edition. Fix: `setup()` exports `KIT_LEDGER_DIR="$WORK/logs"`, the resolver's canonical knob,
so the whole ledger root lands in the per-test mktemp sandbox; T13 pins it.

## 3. Confirmation (runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| R1 | `bats tests/test-queue.bats` | 0 | PASS (19/19, NC2/NC6/NC7 included) |
| R2 | strip the `KIT_LEDGER_DIR` export, `bats -f "T13"` | 1 | RED-as-expected; restored green |
| R3 | `trash` the 7 leaked `*.guard` files (big11, err1, err2, prose1, s1n, s2n, wrap1); recount | 0 | 0 non-`dwarves-kit__*` files remain |

## 4. Run detail

### R1 GREEN
Full suite 19/19 (`bats tests/test-queue.bats`), including the three NCs that failed before the
fix and the T13 tripwire. Diagnostic that started it, reproduced by hand before the fix:

```
[queue] prose1: error (stagnation_detected).      # expected: stalled
$ cat ~/.local/state/dwarves-kit/logs/queue-runs/prose1.guard
noprogress=16
stalls=16
```

### R2 NEGATIVE CONTROL
```
not ok 1 T13 state-sandbox tripwire: run files resolve under KIT_LEDGER_DIR
#   `[ "$(_run_dir)" = "$KIT_LEDGER_DIR/queue-runs" ]' failed
```
T13 is resolver-only (sources queue.sh, calls `_run_dir`, writes nothing), so the control run
could not re-pollute the real state dir.

### R3 CLEANUP
The 7 leaked guard files moved to the Trash (recoverable); `ls | grep -cv '^dwarves-kit__'`
returns 0. Real run files for the `#auto` pilot rows were untouched.

## 5. Reproduce

```
bats tests/test-queue.bats
```
