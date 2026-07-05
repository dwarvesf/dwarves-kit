# Proof of done: capture worker tokens on the watchdog-stall branch (ID-097)

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | A session that trips `WATCHDOG_STALL_SECS` (stalls, then recovers/ships) still has its tokens captured to `$slog` and recorded to the `\| TOKENS \|` ledger, when a capture was requested | MET |
| 2 | The watchdog path reuses the EXISTING `_record_tokens` extraction + stream-json format + deterministic filename (`$dir/.orchestrate/<id>.stream.jsonl`) -- no new format, no new ledger path | MET |
| 3 | Negative control: the SAME stall scenario with capture OFF (the pre-fix-equivalent default posture) still drops the token line -- proves the fix is capture-gated, not unconditional | MET |
| 4 | Default watchdog behavior (no capture requested) is byte-identical to before: plain `.session.log`, no `stream.jsonl`, no `_ROS_SLOG` exposure | MET |
| 5 | Watchdog stall DETECTION logic and `WATCHDOG_STALL_SECS`'s value are untouched (out of scope) | MET |
| 6 | Green under macOS system bash 3.2 (CI-equivalent) AND modern bash 5 | MET |

## Implementation

`lib/queue/orchestrate.sh`:

- **The bug.** `_run_session_watchdog` always wrote plain text to `$logdir/${id}.session.log` and
  never exposed that path to its caller. `_run_one_session`'s watchdog branch left its local `slog`
  variable empty, so `_ROS_SLOG=""` on every watchdog run. The serial path's existing
  `_record_tokens "$dir" "$id" "$slog"` call (added in ID-094/03) always no-op'd on `[ -s "$slog" ]`
  for a watchdog run -- a stall was an accounting black hole even when `--capture-tokens` or
  `DETERMINISTIC_HANDOFF=1` was set.
- **The fix.** `_run_session_watchdog` gains a 5th param `capture` (0/1). When `capture=1` it:
  - writes to `$logdir/${id}.stream.jsonl` (the SAME deterministic filename the non-watchdog
    capture path and the wave reap loop's recompute already use) instead of `${id}.session.log`;
  - invokes `claude` with `--output-format stream-json --verbose` (the SAME format the non-watchdog
    elif branch already uses for capture) instead of plain `-p`;
  - exposes the path via the new global `_WD_SLOG` (bash 3.2 has no other clean way to return a
    string from a function that backgrounds a job).
  When `capture=0` (the default), behavior is byte-identical to before: plain `.session.log`, `cat`
  at the end, `_WD_SLOG=""`.
- `_run_one_session`'s watchdog branch now computes `wd_capture` with the SAME gate the non-watchdog
  elif already uses (`stream=1 || DETERMINISTIC_HANDOFF=1 || CAPTURE_TOKENS=1`), passes it to
  `_run_session_watchdog`, and sets `slog="$_WD_SLOG"` before falling through to the existing
  `_ROS_SLOG="$slog"` line. **No changes needed downstream**: the serial path's
  `_record_tokens "$dir" "$id" "$slog"` (line ~1855) and the wave reap loop's recomputed
  `$megadir/.orchestrate/${id}.stream.jsonl` path (line ~1247) both already pick this up, since the
  filename and format now match exactly what those call sites already expect.
- Stall DETECTION (the `while kill -0 ...` poll loop, the `stalled` event, the WARN-once logic) and
  `WATCHDOG_STALL_SECS` are unchanged -- the mtime-based stall check works identically on a jsonl
  file (any write advances mtime) as it did on plain text.

New test: `tests/test-watchdog-token-capture.sh`.

## Confirmation run-table

| Check | Command | bash 5 | bash 3.2 (macOS system) |
|---|---|---|---|
| New watchdog-token test | `bash tests/test-watchdog-token-capture.sh` | ALL PASS (5/5) | ALL PASS (5/5) |
| Serial token capture (regression) | `bash tests/test-token-capture.sh` | ALL PASS (9/9) | ALL PASS (9/9) |
| Wave token capture (regression) | `bash tests/test-wave-token-capture.sh` | ALL PASS (4/4) | ALL PASS (4/4) |
| Full orchestrate suite incl. watchdog scenarios (regression) | `bash tests/test-orchestrate.sh` | ALL PASS | ALL PASS |
| Syntax + lint | `bash -n` / `/bin/bash -n lib/queue/orchestrate.sh`; `shellcheck -x` | OK, clean | OK, clean |

## Run detail

### Positive: watchdog fires (real stall), `--capture-tokens` on -> TOKENS still lands

Mock `claude` sleeps 3s (tripping `WATCHDOG_STALL_SECS=1`/`WATCHDOG_POLL_SECS=1` at least once,
pid still alive) before emitting the stream-json transcript and flipping its box -- so this
exercises the actual stall-then-recover branch, not a watchdog pass-through.

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

Identical output (modulo timestamp) under `/bin/bash` (macOS system bash 3.2.57).

### Negative control: same stall scenario, capture OFF (the pre-fix-equivalent default posture)

Same mock, same `WATCHDOG_STALL_SECS=1`/`WATCHDOG_POLL_SECS=1`, same stall-then-ship path, but the
run is invoked with NO `--capture-tokens` / `DETERMINISTIC_HANDOFF` / `--stream` flag -- i.e. the
posture every pre-fix watchdog run always had. Confirms:

- `SG-01.stream.jsonl` is NOT created (watchdog falls back to plain `.session.log`, as before);
- `SG-01.session.log` IS written (stall detection still works);
- the ledger has ZERO `| TOKENS |` lines.

This is the actual "current bug" the sub-goal asked to confirm still exists in the un-captured
default case (dropping tokens there is CORRECT/honest -- no capture was requested, matching the
existing `CAPTURE-GATED` contract everywhere else in the file), and proves the positive result above
is caused by the capture gate, not some unconditional side effect.

```
RUN-TABLE (watchdog-stall token capture, negative control -- capture OFF):
  stall WARN seen: 1
  stream.jsonl present: no
  TOKENS line: (none)
```

### Regression: serial + wave token capture, full orchestrate suite

```
$ bash tests/test-token-capture.sh        # bash 5 and /bin/bash (3.2): ALL PASS (9/9) both
$ bash tests/test-wave-token-capture.sh   # bash 5 and /bin/bash (3.2): ALL PASS (4/4) both
$ bash tests/test-orchestrate.sh          # bash 5 and /bin/bash (3.2): ALL PASS, incl.
                                           #   "watchdog flags a stalled session (event + WARN)",
                                           #   "watchdog is advisory: ... recovers + ships",
                                           #   "watchdog dead-session: halts ...",
                                           #   "watchdog off by default: no bg path, chain unchanged"
```

## Reproduce

```bash
bash tests/test-watchdog-token-capture.sh          # modern bash
/bin/bash tests/test-watchdog-token-capture.sh     # macOS system bash 3.2 (CI-equivalent)
bash tests/test-token-capture.sh                   # serial-path regression, both bash versions
bash tests/test-wave-token-capture.sh              # wave-path regression, both bash versions
bash tests/test-orchestrate.sh                     # full suite regression, both bash versions
```
