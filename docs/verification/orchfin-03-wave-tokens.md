# Proof of done: capture per-sub-goal TOKENS on the wave reap path (ID-094)

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | Every sub-goal in a wave (parallel) run gets its own TOKENS ledger line, same as the serial path | MET |
| 2 | The two paths write via the identical extraction (no drift risk between serial/wave) | MET |
| 3 | Negative control: pre-fix-equivalent code produces ZERO wave TOKENS lines under the same scenario (causal effect, not just post-fix presence) | MET |
| 4 | No behavior change to the serial path's existing token capture | MET |
| 5 | Green under macOS system bash 3.2 (CI-equivalent) AND modern bash 5 | MET |

## Implementation

`lib/queue/orchestrate.sh`:
- New shared helper `_record_tokens <dir> <id> <slog>` (next to `_rid_for`): extracts usage via
  `handoff_gen.py sum-usage` and records it via `gate-ledger.sh tokens`. The serial per-sub-goal
  loop's inline block was replaced with a call to this helper (behavior-preserving refactor).
- `_wave_run`'s reap loop success branch (`box` flipped, sub-goal shipped) now calls
  `_record_tokens "$megadir" "$id" "$megadir/.orchestrate/${id}.stream.jsonl"`, gated on
  `CAPTURE_TOKENS=1 || DETERMINISTIC_HANDOFF=1` (mirrors `_run_one_session`'s own capture gate).
  The slog path is RECOMPUTED (deterministic, `$dir/.orchestrate/<id>.stream.jsonl` with
  `dir == megadir` on the wave call) rather than threaded back from the forked subshell that runs
  `_run_one_session`, since that subshell's `_ROS_SLOG` global cannot cross back to the caller.
- Test-only `NC_SKIP_WAVE_TOKENS=1` escape hatch on the same call site, for the negative control.
- Stale "WAVE_CAP default 1" comment fixed in the `_wave_gate` docstring and the `CAPTURE_TOKENS`
  header block (optional trivial cleanup; the live default was already `WAVE_CAP=2`, unchanged).

New test: `tests/test-wave-token-capture.sh`.

## Confirmation run-table

| Check | Command | bash 5 | bash 3.2 (macOS system) |
|---|---|---|---|
| New wave-token test | `bash tests/test-wave-token-capture.sh` | ALL PASS (4/4) | ALL PASS (4/4) |
| Serial token capture (regression) | `bash tests/test-token-capture.sh` | ALL PASS (9/9) | ALL PASS (9/9) |
| Wave scheduling suite (regression) | `bash tests/test-orchestrate-wavefront.sh` | 104 PASS (0 fail, idle host) | 101 PASS (0 fail, idle host)* |
| Syntax | `bash -n` / `/bin/bash -n lib/queue/orchestrate.sh` | OK | OK |

\* `tests/test-orchestrate-wavefront.sh` has a PRE-EXISTING host-load-sensitive flake in its
FIFO-barrier concurrency cases (`wave_run g`, `wave_run h2`, `BARRIER_T=4`), reproduced identically
on unmodified `origin/master` (see Run detail). Not introduced by this change; out of scope for
ID-094.

## Run detail

### Positive: 2-sub-goal wave, `CAPTURE_TOKENS=1` -> both TOKENS lines land

```
$ bash tests/test-wave-token-capture.sh
PASS wave-token-capture POSITIVE: both wave sub-goals' TOKENS lines recorded (SG-01='in=1200 out=80 cache_read=8000 cache_create=0' SG-02='in=1200 out=80 cache_read=8000 cache_create=0')
RUN-TABLE (wave token capture, positive):
  SG-01 rid=wave-tok-sg-01: 2026-07-05T20:33:04Z | TOKENS | in=1200 out=80 cache_read=8000 cache_create=0
  SG-02 rid=wave-tok-sg-02: 2026-07-05T20:33:04Z | TOKENS | in=1200 out=80 cache_read=8000 cache_create=0
PASS wave-token-capture: each sub-goal's ledger usage == sum-usage of ITS OWN child.jsonl (no cross-sub-goal mixup)
PASS wave-token-capture NEGATIVE CONTROL: pre-fix-equivalent code (extraction stubbed) writes the SAME child.jsonl files but ZERO wave TOKENS lines -- causal effect demonstrated
----
ALL PASS
```

Same output (modulo timestamp) under `/bin/bash` (macOS system bash 3.2.57), confirmed 3x repeat
runs each on both bash versions with no flake.

### Negative control: same wave scenario, extraction disabled (`NC_SKIP_WAVE_TOKENS=1`)

Demonstrates the fix's CAUSAL effect: the exact same 2-sub-goal wave, same mock, same captured
`child.jsonl` files (still written, since `CAPTURE_TOKENS` still streams to file independent of the
ledger-write step) -- but with the new extraction call skipped, ZERO TOKENS lines land in either
sub-goal's ledger:

```
tok_lines=0  slog_present=1  rc=0
PASS wave-token-capture NEGATIVE CONTROL: pre-fix-equivalent code (extraction stubbed) writes the
SAME child.jsonl files but ZERO wave TOKENS lines -- causal effect demonstrated
```

This directly operationalizes the sub-goal's stated Proof ("Rung 2: negative control ... a wave
sub-goal whose token line is missing is caught" / "run the SAME wave scenario against the pre-fix
code (or the fix stubbed out) and assert ZERO token lines land").

### Serial path unaffected (regression)

```
$ bash tests/test-token-capture.sh   # bash 5
... 9/9 PASS, ALL PASS
$ /bin/bash tests/test-token-capture.sh   # bash 3.2
... 9/9 PASS, ALL PASS
```

### Pre-existing flake, reproduced on unmodified master (not this change)

```
$ cd <repo root, unmodified origin/master checkout>
$ bash tests/test-orchestrate-wavefront.sh
FAIL wave_run g: concurrency NOT proven (rc=1 ...)
[orchestrate] [wave] SG-01 session exited nonzero (7); draining siblings, then failing.
[orchestrate] [wave] SG-02 session exited nonzero (7); draining siblings, then failing.
1 FAILED
```
Reproduced twice on plain `origin/master` (zero diff), same `BARRIER_T=4` FIFO-timeout signature.
When the host is idle (no concurrent test runs contending for CPU), the same suite is stably
`ALL PASS` (104/104), both on `master` and on this branch -- confirming the flake is host-load
timing sensitivity in that one pre-existing test, not a regression from this sub-goal's diff.

## Reproduce

```bash
bash tests/test-wave-token-capture.sh          # modern bash
/bin/bash tests/test-wave-token-capture.sh     # macOS system bash 3.2 (CI-equivalent)
bash tests/test-token-capture.sh               # serial-path regression, both bash versions
```
