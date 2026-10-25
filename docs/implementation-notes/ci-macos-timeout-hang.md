# ci-macos-timeout-hang: implementation notes

Run 40230793961 on master 0c0af2ea: ubuntu green; macOS `TIMED OUT at 300s -> test-bin-forwarders test-stats-no-persist`. Both take about 2.4 s on a Mac and both passed on macos-latest in run 40213719424, before `tests/lib/timeout.sh` existed. Proof: `docs/verification/ci-macos-timeout-hang.md`.

## What the log says

- The hung step is the same in both: `bin/stats` through `uv run --project lib/stats` (the last line before the timeout in test-bin-forwarders is the `== stats:` header). test-stats-no-persist runs the same project. Other uv suites (`test-sync`, `test-webcheck`) finished.
- The other 258 suites ran fine under the same perl wrapper, so the wrapper works in general. It is uv plus the wrapper, or uv alone.
- The macOS job has no `timeout` and no `gtimeout`, so before this change the runner started each suite as a bare `bash suite`. The only difference the wrapper adds is a perl parent and, in the old version, a new process group (`setpgrp`) with TERM sent to the group.

## What I tried on the Mac (no hang in any of it)

`timeout` and `gtimeout` hidden from PATH; the suites through `run-all.sh` and through `kit_timeout` directly; `</dev/null`; stdin an open pipe; a pty (`script`); SIGCHLD ignored; a cold uv cache and cold `lib/stats/.venv`; the two suites started at the same time with a cold cache (three trials, 8 to 12 s each). I cannot reproduce a loaded GitHub Mac, so the root cause is not proven.

## Change

| Part | Before | After |
|---|---|---|
| Process group | `setpgrp(0,0)` in the child; TERM to `-pgid` | the command stays in the caller's group, exactly as when no limit existed |
| At the limit | TERM, then KILL | print the live process tree under the command (pid, state, elapsed, command) to stderr, TERM to that tree, KILL five seconds later |
| Test seam | none | `KIT_TIMEOUT_FORCE_PERL=1` runs the fallback even where GNU timeout exists |
| `test-run-all-timeout` | `requires: timeout`, so it was skipped on the macOS job | `requires: perl`, runs there through the fallback; case 11 pins the fallback |

Case 11 checks: same process group as the caller (the regression), stdin passes through, exit 7 stays 7 and a SIGKILL death is 137, a timeout is 124 with the process tree printed and no descendant left, a TERM-ignoring command is killed after the grace period.

## What this does and does not claim

- It removes the one environmental difference the wrapper introduced and keeps the limit real (a hang still ends at the ceiling, with a tree dump).
- If macOS still times out, the TIMEOUT tail now contains `timeout: 300s reached; still running under pid N:` and one line per live process. That names the stuck command (uv waiting on a lock, a download, a read), which is the evidence this round could not get.
- It does not make `uv run` faster. If the dump shows uv itself stalled, the next fix is in the suites or the workflow (sync the stats venv once before `run-all`, or pass `UV_*` settings through `env -i` in test-stats-no-persist), not in the timeout helper.

## Rollback

Revert `fix/ci-macos-timeout-hang`. It touches `tests/lib/timeout.sh` and `tests/test-run-all-timeout.sh` only. Nothing is deployed.
