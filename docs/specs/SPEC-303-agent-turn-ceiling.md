# SPEC-303: per-agent turn ceiling with deterministic segment handoff

**Status**: VALIDATED
Lane: full
**Owner module**: `lib/queue/orchestrate.sh` (+ `lib/goal/handoff-gen`)
**Source**: backlog row ID-902; measurement in `ops-toolkit/research/2026-09-13-token-burn-optimization.md`

## Problem

A dispatched builder agent ran 352 turns in one `claude -p` session: context grew
95,641 -> 436,862 tokens, 99.6M cache-read tokens, 549 tokens re-read per output
token. Cost grows roughly quadratically with turn count because every turn
re-reads accumulated context. Nothing in the dispatch path bounds how long one
agent runs; a stuck or over-scoped sub-goal burns until it finishes or dies.

Splitting one long agent into ~100-turn segments cuts cache-read ~46 percent for
the same work. The handoff mechanism a successor resumes from already exists
(`lib/goal/handoff-gen`, deterministic two-tier handoff from the transcript). The
missing piece is the ceiling that triggers it mid-sub-goal.

## Design

Two independent numbers, never conflated (the VoiceStudio control-plane lens):

- **Ceiling** = turns per dispatched segment. When a session reaches it, the
  segment stops, a handoff is generated, and a successor segment is dispatched
  for the SAME sub-goal.
- **Lease** = age of the session's last output. The existing stall watchdog
  (`WATCHDOG_STALL_SECS`) already owns this: it ALERTS on a lapsed lease and
  never kills. Unchanged.

The ceiling lives at the dispatch boundary, not in agent prose: `--max-turns N`
on the `claude -p` argv inside `_run_one_session`, the one choke point the
serial loop, the wave subshell, and the tmux-pane re-entry all dispatch
through.

### Mechanism

`TURN_CAP > 0` (claude harness only) does three things in `_run_one_session`:

1. Appends `--max-turns $TURN_CAP` to the `claude -p` argv.
2. Forces the silent stream-json capture path (the same `> slog` branch
   `DETERMINISTIC_HANDOFF` / `CAPTURE_TOKENS` already use). The transcript is
   required twice: to detect the cap (the result event's
   `subtype == "error_max_turns"`, verified against CLI 2.1.277: exit 1,
   `is_error: true`, `terminal_reason: "max_turns"`) and to feed handoff-gen.
3. After each session, runs the segment gate:

```
session exits
  |-> not capped (result subtype != error_max_turns)  -> done, return rc
  |-> capped AND ROADMAP box already flipped          -> done (finished at the ceiling)
  |-> capped AND seg == TURN_CAP_SEGMENTS             -> blocked event, halt sub-goal
  |-> else: handoff-gen transcript -> HANDOFF-<id>.seg.md (+ DECISIONS.md append)
            record the segment's token usage, archive its transcript to
            <id>.seg<N>.stream.jsonl, re-dispatch with the ORIGINAL prompt
            plus a TURN-CEILING CONTINUATION block, seg++
```

The continuation block points the successor at `HANDOFF-<id>.seg.md` and
`DECISIONS.md` by absolute path and says "continue the SAME sub-goal; do not
redo completed work". It is appended to a COPY of the caller's prompt file, so
the serial prompt, the wave flip-contract prompt, and the gate held-PR prompt
all carry forward unchanged; no caller signature changes.

`HANDOFF-<id>.seg.md` is a per-sub-goal file (overwritten per segment), never
the shared `HANDOFF.md`, so concurrent wave siblings that both cap cannot
clobber each other's continuation. handoff-gen gains a `--handoff-name` option
(basename-validated, default `HANDOFF.md`) for this.

Segment exhaustion is a halt, not a silent spin: a `blocked` event is emitted
and the sub-goal is left for a human. Re-running `orchestrate.sh run` resumes
it (the records are on disk and the box is still unchecked). A bound exists
because an agent that never converges is exactly the quadratic-cost failure the
ceiling exists to bound; without it the cap would only delay the burn.

Per-segment token usage is recorded through the existing `_record_tokens`
ledger stream before the segment transcript is archived, so the cost evidence
this feature exists for stays measurable per segment. The wave reap-loop's
token gate is widened to include `TURN_CAP > 0` so the final segment is recorded
there exactly as `CAPTURE_TOKENS`/`DETERMINISTIC_HANDOFF` already do.

### Config

| Knob | Env | kit.toml | Default | Meaning |
|---|---|---|---|---|
| turns per segment | `TURN_CAP` | `[mega].turn_cap` | `100` | the ceiling; `0` disables (byte-identical pre-feature behavior) |
| max segments per sub-goal | `TURN_CAP_SEGMENTS` | `[mega].turn_cap_segments` | `10` | stuck-loop bound per run invocation |

Resolution follows the existing `[mega]` convention: env wins, else project
`.kit.toml` > kit-root `kit.toml` > default. Both are validated at `cmd_run`
entry (non-negative integer for `turn_cap`, positive integer for
`turn_cap_segments`), rejected with rc 64 like `WAVE_CAP`.

A muxed wave session (`MULTIPLEXER=1`) re-execs the driver via `tmux
new-window`, which does not inherit the orchestrator's env, so `_pane_spawn`
hands the pane `env TURN_CAP=.. TURN_CAP_SEGMENTS=..` as leading argv (the
multi-arg exec-direct form, mock-compatible).

### Boundaries

- **Non-claude harnesses**: no `--max-turns` equivalent. Same degrade posture
  as the other stream-json features: WARN once, run the plain path, no ceiling
  for that sub-goal. The vendor-caveat doc gains the turn ceiling in its list.
- **Agent-tool subagent dispatch** (`/kit:mega` default run mode,
  `/kit:dispatch` workers, `/kit:execute` workers): those are spawned by the
  conductor's Agent tool, not a `claude -p` argv this driver controls. There is
  no argv boundary to hang the ceiling on; this spec covers the headless
  dispatch path only and says so.
- **The lease stays advisory**: the watchdog still never kills. A lapsed lease
  alerts; only the ceiling stops a segment.

## Non-goals

- No turn cap on interactive `/goal` sessions (`lib/queue/queue.sh` drives the
  operator's live session via tmux send-keys; no argv boundary).
- No mid-wave re-dispatch from the reap loop: the segment loop lives inside
  `_run_one_session`, which the wave spawns per sub-goal, so waves get the
  ceiling for free without a second implementation.
- No per-agent ceiling inside one session beyond segments: subagents a worker
  spawns itself are that worker's own context budget.

## Test plan

New suite `tests/test-turn-cap.sh` (mock `CLAUDE_CMD`, fixture mega-goal dirs,
same shape as `tests/test-orchestrate.sh`):

1. Ceiling triggers handoff + re-dispatch: a mock that emits an
   `error_max_turns` result on invocation 1 and `success` + box-flip on
   invocation 2 produces exactly 2 dispatches, a `HANDOFF-SG-01.seg.md`, a
   `turn-cap` handoff event, a continuation block in the segment-2 prompt, and
   a flipped box (run rc 0).
2. Negative control, below the ceiling: a mock that emits `success` + flips on
   invocation 1 dispatches exactly once; no `.seg` handoff file, no
   continuation block.
3. Lease/ceiling distinction: `WATCHDOG_STALL_SECS` lapsed (mock stalls) still
   alerts and never kills; the run completes in ONE segment with a `stalled`
   event and no re-dispatch.
4. Segments bound: a mock that always caps and never flips dispatches exactly
   `TURN_CAP_SEGMENTS` times, emits a `blocked` event, and halts the run.
5. `--max-turns N` reaches the argv; `TURN_CAP=0` removes it and produces no
   forced capture (the disable knob is byte-identical).
6. Config resolution: `[mega].turn_cap` reads from kit.toml with env override;
   non-numeric values reject rc 64.
7. handoff-gen `--handoff-name` writes the named hot file (+ DECISIONS.md) and
   rejects a non-basename.

Existing negative controls that pin the pre-feature default path
(`tests/test-orchestrate.sh` 13g "no forced capture" and the SPEC-110
no-TOKENS-line control) pin `TURN_CAP=0` so they keep testing the off-path.

## Verification

```bash
bash tests/test-turn-cap.sh
bash tests/test-orchestrate.sh
bash tests/run-all.sh --changed
```

## After state

- `orchestrate.sh run` dispatches every claude sub-goal with `--max-turns 100`
  (default) and a silent stream-json capture; a capped sub-goal resumes in
  ~100-turn segments through deterministic handoffs until it flips its box or
  exhausts `TURN_CAP_SEGMENTS`.
- `kit.toml [mega]` documents both knobs; `commands/mega.md` and
  `docs/architecture.md` name the ceiling/lease split and the vendor boundary.
- `docs/verification/` proof: green `test-turn-cap.sh` run + negative controls.
