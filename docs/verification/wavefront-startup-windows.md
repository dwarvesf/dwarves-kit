# Verification: wavefront suite startup windows

`tests/test-orchestrate-wavefront.sh` has three fixed windows that bound how far apart two mock wave sessions may start: the fifo barrier at block (g), the same barrier reused at block (k), and the marker-file poll at block (h2). All three flaked on a dev Mac. The 2026-09-10 handoff read the suite as Air-local; it is load-dependent.

## Mechanism

`_wave_run`'s spawn loop does real per-sub-goal work BEFORE backgrounding each session (`lib/queue/orchestrate.sh`): `_wave_worktree` (a `git worktree add`) at :1754, `_route` at :1769, `mktemp` + `_build_prompt` at :1781, and `_wave_reserve_spec`, which takes a LOCK, at :1804. Only then does :1864 background the session. Session 2 therefore starts that whole gap after session 1, and under load that gap is unbounded.

Every one of the three windows must exceed that skew. None of them is the proof. The proof is that a serial implementation cannot pass, and that holds at any value: the lone reader always times out and exits without flipping. The window only decides how slowly a true regression fails.

## Change

| Block | Window | Before | After |
|---|---|---|---|
| (g) concurrency proof | `BARRIER_T` on the fifo `read -t` | 20s | 120s |
| (k) full-wire dispatch | `BARRIER_T` on the same mock | 20s | 120s |
| (h2) abort path | poll for both `.pid` markers | 120 x 0.25s = 30s | 480 x 0.25s = 120s |
| (h2) abort path | mock lifetime after writing its pid | 30s | 300s |

The mock lifetime moves with the poll deliberately. The two must stay consistent: a mock that expires before the SIGTERM lands dies of old age, and the both-mocks-dead assertion then passes without exercising the process-group kill. At the previous values the poll equalled the mock lifetime, which left no margin; 120s against 300s leaves 180s.

The soft-barrier negative control at :448 and :460 keeps `BARRIER_T=1` on purpose and is untouched.

## Green run (this branch, the Air, 2026-09-11)

Three runs under load induced by 8 spin-loop burners.

```
Command: bash measure-loaded.sh 3 8
run 1: ALL PASS (319s) load=90.66 50.83 27.32
run 2: ALL PASS (338s) load=81.47 73.23 46.11
run 3: ALL PASS (489s) load=31.69 51.44 48.62
RESULT: 0 failure(s) in 3 run(s) under induced load
Exit: 0
Verdict: PASS
```

Idle wall time is roughly 130s, so these ran at up to 3.7x slowdown.

## Negative control (matched load)

Restore the four previous values, hold the load comparable, run three times.

```
Command: bash negctl-matched.sh 3 16
OLD values in place: 2 barrier sites, poll=seq 1 120, mock=1
negctl run 1: 1 FAILED (347s) load=42.61 32.34 27.12
  FAIL wave_run h2: both mock sessions never started (marker files missing)
negctl run 2: 1 FAILED (369s) load=44.45 39.21 32.31
  FAIL wave_run h2: both mock sessions never started (marker files missing)
negctl run 3: 2 FAILED (401s) load=47.72 45.00 37.49
  FAIL wave_run h2: both mock sessions never started (marker files missing)
  FAIL dispatch k: wave not taken/failed (rc=1 b1='- [ ] SG-01 ...' b2='- [ ] SG-02 ...')
NEGCTL RESULT: 3 failure(s) in 3 run(s) at OLD values under matched load
restored: 0 dirty
Exit: 0
Verdict: RED as expected, then restored clean
```

The control bites: 3 of 3 fail at the old values where 3 of 3 pass at the new ones.

A FIRST attempt at this control did NOT reproduce (`ALL PASS`, 286s). It is recorded here because it is the reason the matched version exists: its burners only drove the 1-minute average to 11.4, while the green measurement ran at 31 to 91, so it compared two different conditions and proved nothing. The matched version uses 16 burners and a 60s ramp.

## What this settles about block (k)

(k) was the open question on ID-834. Run 3 of the control reproduced it, and its driver log names the mechanism:

```
[orchestrate] [wave] spawned SG-01 (pid 17063) in .../worktrees/SG-01
[orchestrate] [wave] SG-02 reserved SPEC-452
[orchestrate] [wave] spawned SG-02 (pid 27068) in .../worktrees/SG-02
[orchestrate] [wave] SG-01 session exited nonzero (7); draining siblings, then failing.
[orchestrate] [wave] SG-02 session exited nonzero (7); draining siblings, then failing.
```

Exit 7 is the barrier mock's own timeout branch (`exit 7  # timed out: sibling never overlapped`). Both sessions timed out on each other. In the same run `dispatch k: wave-path marker present ([wave] spawned)` and `dispatch k: no orphaned mock processes remain` both PASSED, so `cmd_run` routed to the wave path correctly and reaped correctly. (k) is the same start-skew mechanism as (g) and (h2), not a fault on the dispatch wire. It shows the widest skew because it drives the whole `cmd_run` wire rather than calling `_wave_run` directly.

## Reproduce

```bash
bash docs/verification/wavefront-startup-windows-measure.sh 3 8    # green under load
bash docs/verification/wavefront-startup-windows-negctl.sh 3 16    # old values, expect RED
```

Both scripts kill their burners on every exit path and the control restores the file with `git checkout --`.

## Not touched

The lock-acquire poll at line 209 (10 x 0.5s) and the post-SIGTERM settle at line 576 (`sleep 0.5`) have the same shape and have not flaked.
