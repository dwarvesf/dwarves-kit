# SG-01: orchestrator run-modes (--step pause + live stream)

Merge policy: gate
Time budget: ~1 session
Depends on: #81 (orchestrate.sh phase 1)
Model: sonnet
Effort: medium

## Directional outcome
The orchestrator becomes observable and interruptible mid-run, so a human can watch each
sub-goal and step in between them. Solves the "background black box" concern without giving up
the per-sub-goal context isolation.

## Done =
`lib/orchestrate.sh` gains `--step` (pause after each sub-goal, resume on a flag/keypress) and
streams each sub-goal session's output live (e.g. `--output-format stream-json | tee`). The
in-session `/goal` loop is untouched. `tests/test-orchestrate.sh` covers step-pause-then-resume
and that non-step (default) mode is unchanged. PR opened.

## Close the loop (verification)
```
# in the dwarves-kit checkout
bash tests/test-orchestrate.sh         # new --step + stream assertions green; old ones unchanged
bash lib/orchestrate.sh run <fixture> --step --dry-run   # plan shows the pause points
```

## Scope edges
Only `lib/orchestrate.sh` + its test (+ a doc line). Do NOT touch the in-session `/goal` loop or
the Stop hook. `--step` is opt-in; default behavior must not change.

## Where to look
`lib/orchestrate.sh` (#81), SPEC-087 Mechanism A, the 2026-06-29 design discussion (stream +
pause-gate are the two observability mechanisms).

## Proof expectation
A run-table (test output) showing `--step` pauses then resumes, plus a captured terminal slice
of streamed sub-goal output. Scale: this is behavioral, so the full reviewable proof.

## PR body
feat(kit): orchestrator --step pause + live stream for observability. Implements SPEC-087
Mechanism A observability. Gated for team review.

## Borrowed from pi-swarm (2026-06-29)
Reuse the overlay primitives (see `research/2026-06-29-pi-swarm-comparison.md`):
- step/pause gate <- `overlay/actions.ts` `confirmAction` y/n + `inputMode` state machine.
- live stream without a busy-loop <- `live-progress.ts` push (100ms throttle) + 1s interval fallback + 50ms render cache.
- per-unit live tail <- `render-detail.ts` auto-scroll of the running session's output.
