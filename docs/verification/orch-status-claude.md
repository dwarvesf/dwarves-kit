# Verification -- orch-status-claude

`orchestrate.sh status <dir>` on a dir with no Orca run now prints a compact, read-only claude-backend report instead of "no Orca run" (exit 3).

## Green run
```
Command: bash tests/test-orchestrate.sh
Exit: 0
Output:
  PASS status (claude backend): exit 0, roadmap counts + open ids, no 'no Orca run'
  PASS status: running SG-03 listed with start time, stream size, age, STALE past WATCHDOG_STALL_SECS
  PASS status: shipped SG-01/SG-02 are not running
  PASS status: prints 'no driver' when no driver runs
  PASS status: read-only (no file written or changed)
  PASS status: prints the last 5 events
  PASS status: live session pid + state found via the stream file
  PASS status: driver pid alive with WAVE_CAP/WAVE_ROLLING
  PASS status: a stopped (T) session is flagged STOPPED
  PASS status: an Orca run still takes the Orca status path
  ALL PASS
Verdict: PASS
```

Sample report from a fake mega-goal dir (one done box, one open box executing, no driver):

```
claude backend status: /tmp/mg
roadmap: done 1 / 2; open: SG-02
running:
  SG-02  since 2026-01-01T00:00:00Z  stream 3B age 0s
last events:
  2026-01-01T00:00:00Z  SG-02  executing  model=x
driver: no driver
```

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0
Output:
  test-orchestrate                               ok (70s)
  test-orchestrate-orca                          ok (112s)
  test-wave-rolling                              ok (82s)
  run-all: all 39 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

`tests/test-orchestrate-orca.sh` changed one assertion: `status` with no Orca run used to exit 3 and now exits 0 with the claude report. A dir WITH an Orca run still goes to the unchanged Orca `cmd_status` (pinned by the last new case).

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate.sh" "git show origin/master:lib/queue/orchestrate.sh >| lib/queue/orchestrate.sh"
Exit: 1 under the mutation (RED expected), 0 after restore
Output:
  no Orca run for '<fixture dir>'
  FAIL status: session pid/state missing
  FAIL status: driver line wrong
  FAIL status: STOPPED flag missing
  7 FAILED
Verdict: PASS
```
The mutation is the pre-change driver: it prints "no Orca run" and fails the new assertions (7 of them); only the Orca-path case stays green.

## Not proven
- No live mega-goal run and no real `claude -p`: sessions and the driver are fake `sleep` processes holding the stream file open or running as a script named `orchestrate.sh`.
- Session state comes from `lsof -t <stream>`: a session started without stream capture (no `.stream.jsonl`) shows size/age only, or "stream none". The live-process cases skip where `lsof` is absent.
- Driver WAVE_CAP/WAVE_ROLLING are read from the process environment (`/proc` or `ps eww`); a driver that took them from `kit.toml` rather than the environment prints no values.
- STALE only fires when `WATCHDOG_STALL_SECS` is above 0 (its default 0 means the watchdog is off).

## Rollback
Revert the commit; `status` returns to "no Orca run" for claude-backend dirs. The report writes nothing and takes no lock.
