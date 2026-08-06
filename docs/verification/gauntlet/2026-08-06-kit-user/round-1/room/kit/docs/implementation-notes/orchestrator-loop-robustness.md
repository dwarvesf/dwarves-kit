# Implementation notes: orchestrator loop-robustness (SG-11)

Delta from goal file `goals/11-loop-robustness.md` (token-optim-v2). Branched off master AFTER
SG-01 (#86) + SG-10 (#87) merged, so it reuses SG-10's event log directly.

## 2026-06-29 watchdog is opt-in (default = unchanged synchronous path)
- The session call is synchronous (`claude -p ... < pfile`, blocks). A true stall-watchdog needs
  the session backgrounded + a poll loop, which is a real execution-model change.
- Decision: gate it behind `WATCHDOG_STALL_SECS` (default 0 = OFF -> the existing synchronous
  path runs verbatim, incl. the SG-01 `--stream` tee). Only `>0` switches to the bg + poll path.
- Why: keeps the common interactive run byte-identical; the watchdog is for unattended runs.

## 2026-06-29 progress signal = the session's output file mtime (not SG-10's event log)
- SG-10's `events.log` only updates on TRANSITIONS (executing/shipped), not DURING a session, so
  it can't detect a mid-session stall. The finer signal is the session's own output activity.
- Decision: in watchdog mode the session writes to `<dir>/.orchestrate/<id>.session.log` and the
  poll loop watches THAT file's mtime. No new bytes for `WATCHDOG_STALL_SECS` while the process is
  still alive => `stalled`. (SG-10's event log still gets a `stalled` event appended, which is the
  "reuse SG-10's event log" the goal asks for -- as the durable record, not the live signal.)
- Tradeoff: watchdog mode redirects output to the session log instead of the SG-01 live tee
  (getting claude's PID out of a `| tee` pipeline is not portable). The operator tails the file;
  the path is printed. Watchdog is the unattended-robustness mode, where the file record matters
  more than a live terminal tail. If both `--stream` and watchdog are set, watchdog's file path
  wins (documented in the README line).

## 2026-06-29 liveness = `kill -0` on the backgrounded subshell (no daemon)
- The session runs as `{ claude ...; } &`; `$!` is the subshell pid. `kill -0 $spid` is the
  liveness probe (pi-swarm `isAgentActive`, no heartbeat daemon). On exit, `wait $spid` yields rc.
- Dead-session reconciliation: a session that died (rc!=0) OR exited without flipping its box does
  NOT advance -- this is the EXISTING grounded-completion halt; SG-11 makes it explicit by
  emitting a `blocked` event (SG-10) and a `[guardrail]` line. Advisory: the watchdog never kills
  a stalled-but-alive session (goal: "flag, do not silently kill").

## 2026-06-29 guardrails (the testable one)
- The two examples in Done= (advancing past an unflipped box; running a gate in auto context)
  already HALT/STOP today. SG-11 adds the explicit, greppable `[guardrail]` label to the
  box-not-flipped halt, plus one NEW pre-launch guardrail: WARN when the next sub-goal has no
  goal file (a re-discovery hazard the loop would otherwise hit silently). The new one is what the
  test asserts ("at least one guardrail").
