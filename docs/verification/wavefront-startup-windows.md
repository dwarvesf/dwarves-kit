# Verification: wavefront suite startup windows

`tests/test-orchestrate-wavefront.sh` has three fixed windows that bound how far apart two mock wave sessions may start: the fifo barrier at block (g), the same barrier reused at block (k), and the marker-file poll at block (h2). Each one flaked under load on a dev Mac. The 2026-09-10 handoff read the suite as Air-local; it is timing-dependent.

None of the three windows is the proof. The proof is that a serial implementation cannot pass. That holds at any value: the lone reader always times out and exits without flipping. A larger window only makes that failure slower.

## Change

| Block | Window | Before | After |
|---|---|---|---|
| (g) concurrency proof | `BARRIER_T` on the fifo `read -t` | 4s | 20s |
| (k) full-wire dispatch | `BARRIER_T` on the same mock | 6s | 20s |
| (h2) abort path | poll for both `.pid` markers | 40 x 0.25s = 10s | 120 x 0.25s = 30s |

The (h2) mock sleeps 30s AFTER writing its pid, so a slow start never shortens the time it stays alive for the SIGTERM.

## Before (kit 4261e2b, the Air, 2026-09-11)

| Block | Runs | Failures | Failing line |
|---|---|---|---|
| (g) | 3 | 1 | `wave_run g: concurrency NOT proven (rc=1 b1='- [ ] SG-01 ...' b2='- [ ] SG-02 ...')` |
| (h2) | 5 | 2 | `wave_run h2: both mock sessions never started (marker files missing)` |

## Green run (kit 504f516, the Air, 2026-09-11)

Five consecutive standalone runs, machine under normal load for runs 1 to 4.

```
Command: for i in 1 2 3 4 5; do bash tests/test-orchestrate-wavefront.sh; done
run 1: ALL PASS (103s)
run 2: ALL PASS (135s)
run 3: ALL PASS (123s)
run 4: ALL PASS (132s)
run 5: 1 FAILED (243s)   dispatch k: wave not taken/failed (rc=1 b1='- [ ] SG-01 ...' b2='- [ ] SG-02 ...')
Exit: 0 (runs 1 to 4), 1 (run 5)
Verdict: PASS for (g) and (h2), 0 failures in 5 against 1 in 3 and 2 in 5 before. (k) NOT proven.
```

Run 5 took twice as long as the others, so the machine was under heavy load during it. (k) drives the whole `orchestrate.sh run` wire, not just `_wave_run`, and its rc=1 can come from the barrier or from anything else on that path. The loop kept only the FAIL line; `dispatch-wave.out` is gone with the temp dir. The next measurement must keep it:

```bash
# reproduce (k): loop until it fails, keep the driver output
for i in $(seq 1 10); do
  out=$(bash tests/test-orchestrate-wavefront.sh 2>&1)
  printf '%s' "$out" | grep -q '^FAIL dispatch k' && { printf '%s' "$out" > /tmp/wavefront-k-fail.txt; break; }
done
```

The suite `cat`s `dispatch-wave.out` right after the FAIL line, so the saved file carries the driver log.

## Negative control

A revert-to-red is probabilistic for a widened window, so the control is the before table above plus the serial-impl argument: the value never changes which implementations pass, only how long a failing one takes. Both (g) and (h2) reproduced their old failure rate at the old values in the same session, on the same machine, and stopped failing at the new values.

## Not touched

The lock-acquire poll at line 209 (10 x 0.5s) and the post-SIGTERM settle at line 571 (`sleep 0.5`) have the same shape and have not flaked. Left alone.
