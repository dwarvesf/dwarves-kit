# Verification: observe timing view

| Check | Command | Result |
|---|---|---|
| Red before implementation | `bash lib/session/observe/tests/smoke.sh` | `[112]` aborts: `argument cmd: invalid choice: 'timing'` |
| Green after | `bash lib/session/observe/tests/smoke.sh` | `smoke: all 113 passed` |
| Negative control | set `SLEEP_POLL_MIN = 100`, rerun smoke | `smoke: 112 passed, 1 FAILED` (sleep-poll 60s becomes 0) |
| Restored | revert the mutation, rerun smoke | `smoke: all 113 passed` |
| Neighbour suite | `bash lib/session/observe/tests/test-vps-report.sh` | `vps-report: all 6 passed` |
| Real flow | `session-observe timing --file <real 1037-call transcript>` | table printed: 8 sleep-polls, 493.5s, top-5 slowest listed |

## Run

Fixture `lib/session/observe/tests/fixtures/timing-sample.jsonl` holds 3 tool calls: a Read (2s), a `sleep 30; sleep 30` Bash call (60s) and a `sleep 5 && ls` Bash call (6s).

Asserted values: wall 81s, tool 68s, model 12s, 3 calls, sleep-poll 1 call and 60s. The 5s sleep stays under the 10s floor.

## Negative control

Raised the sleep-poll floor to 100s in `bin/session-observe`. The `[112]` assertion failed (sleep-poll calls 0, not 1). Restored the original file and the suite returned to green.

## Not proven

- Parallel tool calls in one assistant message share a start time; their durations overlap and sum above wall time.
- Sleeps inside `bash -c '...'` or a script file are not detected.
- `--project` and `--days` reuse the existing file walker and were not exercised for this view.
