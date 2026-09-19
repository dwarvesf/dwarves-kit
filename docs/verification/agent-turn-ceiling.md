# Proof of done: per-agent turn ceiling with deterministic segment handoff

2026-09-19. Acceptance: a claude sub-goal dispatched under `TURN_CAP>0` runs with
`--max-turns N` + a forced stream-json capture; a segment ending on
`subtype:error_max_turns` gets a deterministic handoff and re-dispatches the
SAME sub-goal; below the ceiling nothing changes; a lapsed lease alerts and
never stops; `TURN_CAP=0` restores the pre-ceiling dispatch byte-for-byte.

## Green run

Command: `bash tests/test-turn-cap.sh`
Exit: 0
Output: 28/28 PASS. Includes: ceiling re-dispatched exactly once (2 segments),
HANDOFF-SG-01.seg.md written with "Next sub-goal: SG-01", segment-2 prompt
carries the TURN-CEILING CONTINUATION block pointing at the per-id handoff and
DECISIONS.md by absolute path, segment-1 prompt unmodified, `handoff` event in
.orchestrate/events.log, capped transcript archived to SG-01.seg1.stream.jsonl,
both segments' TOKENS recorded, `--max-turns 7` present on the mock's argv.
Verdict: PASS

Command: `bash tests/run-all.sh --changed`
Exit: 0
Output: 50/50 suites ok (test-turn-cap, test-orchestrate, test-token-capture,
test-watchdog-token-capture, test-wave-token-capture, test-wave-rid-check,
test-multiplexer, test-orchestrate-gate-dispatch, test-orchestrate-hardening,
test-harness-dispatch, test-model-routing, test-meta, test-no-scattered-ids,
plus the always-on lints).
Verdict: PASS

## Negative controls (run and observed)

Command: below-ceiling arm inside `bash tests/test-turn-cap.sh`
Output: mock emitting `subtype:success` + box flip on invocation 1 dispatches
exactly once; no HANDOFF-SG-01.seg.md, no .seg*.stream.jsonl, no continuation.
Verdict: PASS

Command: lease arm inside `bash tests/test-turn-cap.sh`
(`WATCHDOG_STALL_SECS=2 WATCHDOG_POLL_SECS=1`, mock sleeps 4s then flips)
Output: `[watchdog] WARN: SG-01 stalled` + `stalled` event in events.log;
exactly 1 dispatch; box flipped; rc 0. The lapsed lease ALERTED and did not
stop the session; the ceiling did not fire.
Verdict: PASS

Command: exhaustion arm (`TURN_CAP=2 TURN_CAP_SEGMENTS=2`, mock always caps)
Output: exactly 2 dispatches, `blocked` event "turn-cap: exhausted 2 segments",
box stays unchecked, run halts.
Verdict: PASS

Command: disable arm (`TURN_CAP=0`)
Output: no `--max-turns` on argv, no .orchestrate/*.stream.jsonl written; the
default invocation is the pre-ceiling byte-identical shape.
Verdict: PASS

Command: `bash tests/test-orchestrate.sh` (pre-existing controls)
Output: ALL PASS. The two controls that pin the OLD default no-capture path
(13g, and the no-TOKENS-line control) now run under `TURN_CAP=0` so they keep
asserting the off-path rather than silently retargeting.
Verdict: PASS

## Config surface

| Knob | Env | kit.toml | Default |
|---|---|---|---|
| turns per segment | `TURN_CAP` | `[mega].turn_cap` | `100` (`0` disables) |
| max segments per sub-goal | `TURN_CAP_SEGMENTS` | `[mega].turn_cap_segments` | `10` |

`kit_config_get mega.turn_cap` resolves 300 and `mega.turn_cap_segments`
resolves 10 from the shipped kit.toml; env overrides land in the dry-run plan
line; `TURN_CAP=abc` and `TURN_CAP_SEGMENTS=0` reject rc 64.

## Not covered here

- Real `claude --max-turns` end-to-end: the suite mocks the CLI. The result
  subtype `error_max_turns` was verified against the documented CLI result
  shape (exit 1, is_error true); the mock emits that shape.
- Agent-tool subagent dispatch (`/kit:mega` conductor-spawned workers): no
  `claude -p` argv exists there; the ceiling covers the headless dispatch path
  only. Documented boundary in the spec.
- Non-claude harnesses: no `--max-turns` equivalent; they WARN and run the
  plain path (advisory, not a wall). Pinned by test-harness-dispatch.
