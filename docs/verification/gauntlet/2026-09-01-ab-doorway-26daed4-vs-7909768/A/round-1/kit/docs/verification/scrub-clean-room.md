# Proof of done: clean-room scrub no-match fix

Date: 2026-09-01. Branch: fix/scrub-clean-room.

## Recorded run

- Command: `bash tests/gauntlet/cleanroom/persist-check.sh`
- Exit: 0
- Output: `PASS leg A` / `PASS leg B` / `PASS leg C (key scrubbed to <REDACTED-KEY>)` / `PASS leg D (clean room persists with key set)` / `PERSIST-CHECK: GREEN`
- Verdict: PASS

## Negative control

The red arm is the live 2026-09-01 campaign log (`bg-runs/gauntlet-campaign/run.log`, ticks 1-2): with the key set and a clean room, the scrub's `grep | while` pipeline exited 1 under `pipefail`, run.sh died before the persist, the row record never landed, and the campaign re-ran J1 on every tick. Leg D reproduces that condition (`ANTHROPIC_API_KEY` set, `PROBE_CMD='exit 0'`, nothing to redact) and fails against the pre-fix runner, passes post-fix.

## Rollback

Single-hunk revert; no state.
