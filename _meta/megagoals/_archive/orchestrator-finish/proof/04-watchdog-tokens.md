# Proof of done: orchfin-04-watchdog-tokens (ID-097)

## Acceptance criteria

| # | Criterion | Met | Evidence |
|---|---|---|---|
| 1 | A stalled-then-shipped session (watchdog fires) still gets its tokens captured to `$slog` when capture was requested | yes | Run-table: TOKENS line lands after a real stall WARN fires (mock sleeps 3s under `WATCHDOG_STALL_SECS=1`) |
| 2 | Watchdog path reuses the SAME `_record_tokens` extraction + stream-json format + deterministic filename (no new format/path invented) | yes | `_run_session_watchdog` writes `${id}.stream.jsonl` in the identical `--output-format stream-json` shape the non-watchdog capture path already uses; downstream `_record_tokens` call sites needed zero changes |
| 3 | Negative control: the SAME stall scenario with capture OFF still drops the token line (proves capture-gated, not unconditional) | yes | Same mock/env, no `--capture-tokens`: no `stream.jsonl`, zero TOKENS lines |
| 4 | Default watchdog behavior (no capture) byte-identical to before | yes | `tests/test-orchestrate.sh` watchdog scenarios (12a-12d) unmodified, all still PASS |
| 5 | Stall detection logic + `WATCHDOG_STALL_SECS` untouched | yes | `while kill -0 ...` poll loop, `stalled` event, WARN-once logic: zero lines changed |
| 6 | Green under macOS bash 3.2 (CI) and bash 5 | yes | Both suites run under `/bin/bash` and `bash`, both green |

## Implementation

`lib/queue/orchestrate.sh`:
- `_run_session_watchdog` gains a 5th param `capture` (0/1, default 0). `capture=1`: writes to
  `$logdir/${id}.stream.jsonl` (the SAME deterministic filename the non-watchdog capture path and
  the wave reap loop's recompute already use) using `--output-format stream-json --verbose` (same
  format used elsewhere for capture); `capture=0` (default): unchanged, plain `.session.log`,
  plain `-p`. Result exposed via new global `_WD_SLOG` (bash 3.2 has no other way to return a
  string across a job-controlled background call).
- `_run_one_session`'s watchdog branch computes `wd_capture` with the SAME gate the non-watchdog
  elif already uses (`stream=1 || DETERMINISTIC_HANDOFF=1 || CAPTURE_TOKENS=1`), passes it through,
  and sets `slog="$_WD_SLOG"` before the existing `_ROS_SLOG="$slog"` line.
- **Zero changes needed downstream**: the serial path's `_record_tokens "$dir" "$id" "$slog"` (03's
  helper) and the wave reap loop's recomputed `.stream.jsonl` path (03's fix) both already work,
  because filename + format now match what those call sites expect.
- New test: `tests/test-watchdog-token-capture.sh` (positive stall-then-ship + capture ON, negative
  control same scenario + capture OFF).

## Run detail (watchdog-stall token run-table)

```
$ bash tests/test-watchdog-token-capture.sh
PASS positive fixture: the run actually stalled (watchdog WARN fired) before finishing
PASS watchdog-stall TOKENS recorded despite the stall (in=1200 out=80 cache_read=8000 cache_create=0)
PASS watchdog-stall capture-from-file: recorded usage == sum-usage(SG-01.stream.jsonl) (in=1200 out=80 cache_read=8000 cache_create=0)
RUN-TABLE (watchdog-stall token capture, positive):
  stall WARN seen: 1
  SG-01 rid=kit-wdtok-c1: 2026-07-05T21:05:58Z | TOKENS | in=1200 out=80 cache_read=8000 cache_create=0
PASS negative-control fixture: this run also stalled (same scenario as the positive arm)
PASS watchdog-stall NEGATIVE CONTROL: default (no capture requested) drops the token line -- the pre-fix black hole, still true when capture is OFF
RUN-TABLE (watchdog-stall token capture, negative control -- capture OFF):
  stall WARN seen: 1
  stream.jsonl present: no
  TOKENS line: (none)
----
ALL PASS
```

Byte-identical result (modulo timestamp) under `/bin/bash` (macOS system bash 3.2.57).

## Regression sweep

| Test | bash 5 | bash 3.2 |
|---|---|---|
| `tests/test-token-capture.sh` (serial path) | 9/9 PASS | 9/9 PASS |
| `tests/test-wave-token-capture.sh` (wave path) | 4/4 PASS | 4/4 PASS |
| `tests/test-orchestrate.sh` (full suite, incl. watchdog scenarios 12a-12d) | ALL PASS | ALL PASS |
| `shellcheck -x lib/queue/orchestrate.sh` | clean | n/a |

## Reproduce

```bash
bash tests/test-watchdog-token-capture.sh
/bin/bash tests/test-watchdog-token-capture.sh
bash tests/test-token-capture.sh
bash tests/test-wave-token-capture.sh
bash tests/test-orchestrate.sh
```
