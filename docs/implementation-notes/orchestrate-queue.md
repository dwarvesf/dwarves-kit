# Implementation notes: overnight queue launcher (SPEC-146)

Delta from the spec only (not a mirror). Reference SPEC-146 for the design.

## 2026-07-05 12:00 marker anchor relaxed after the live smoke

Context: the spec pinned a STRICT line anchor `^RUNNER_DONE$`.
Decision: relaxed to `^[[:space:]]*RUNNER_DONE[[:space:]]*$` (marker is the only non-space token
on its line).
Why: the live tmux smoke proved the real Claude Code TUI renders the assistant's final line
INDENTED inside its message block, so the strict anchor MISSED the real pane and the launcher
would have stalled every real run. The relaxed anchor still rejects mid-prose (`end with the line
RUNNER_DONE`), so NC2 still holds.
Alternatives: strip pane indentation before matching (more fragile across mux/TUI versions).
Impact: T1/T2 fixtures updated to the indented rendering to lock the regression.

## 2026-07-05 12:10 readiness-wait + verify-and-resubmit added (not in spec)

Context: the spec's state machine went open -> type `/goal` + Enter -> poll.
Decision: inserted `_mux_wait_ready` (poll for the TUI footer/prompt before typing) and split the
Enter into `_mux_submit` (send Enter, verify the prompt actually cleared, re-issue up to 5x).
Why: the first live smoke hung , the `/goal` text was typed but the Enter fired before the TUI was
input-ready and was DROPPED (text sat unsent on the prompt). A manual Enter then submitted it,
confirming the mechanism. This is a real TUI-automation hazard, not covered by the spec.
Alternatives: a fixed startup sleep (pure guess; brittle across machines). The readiness poll +
resubmit is deterministic-ish and self-correcting.
Impact: new CONSUMER config `QUEUE_STARTUP_SECS` (20) + `QUEUE_SUBMIT_SETTLE_SECS` (2); tests set
both to 0. An extra Enter on an empty prompt is a harmless no-op.

## 2026-07-05 12:20 error-twice reconciliation (design-doc ambiguity)

Context: the runner-fastpath design doc says "two consecutive failed/gated megas ... STOPS THE
NIGHT" in one place but its own risks table says a gated mega just "records and moves on", and NC3
tests `error`.
Decision: only `error` accrues toward the night-stop; `gated`/`stalled` are per-pointer stops that
MOVE ON and RESET the counter; a `skipped` row is a pass-through (neither increments nor resets).
Why: matches the rate-limit rationale ("assume account-level rate limit"), the risks table, and
NC3. Documented in SPEC-146 `## Design` and proven fail-closed in the rung-4 red-team (RT-b2: a
skip between two errors still stops).
Impact: the consecutive-error semantics are the counter's whole contract; see NC3 + RT-b1/b2/b3.

## 2026-07-05 12:25 sibling lib, not an orchestrate.sh internal

Context: the sub-goal allowed either an `orchestrate.sh queue` subcommand or a sibling `lib/queue.sh`.
Decision: logic lives in `lib/queue.sh`; `orchestrate.sh` gets a one-line `queue) exec queue.sh
run "$@"` alias.
Why: orchestrate.sh is 1783 lines with 70+ pinned tests driving a DIFFERENT mechanism (headless
`claude -p` per sub-goal). The interactive-`/goal` launcher is a distinct mechanism; a sibling
keeps its tests isolated and orchestrate.sh's suite untouched, while still exposing the documented
`orchestrate.sh queue` entry point.
Impact: `tests/test-queue.bats` is standalone; no orchestrate.sh test changed.

## No further deviations

Everything else matches SPEC-146 verbatim: queue-row contract (`slug<TAB>repo<TAB>pointer`),
journal columns, preflight, `--dry-run`/`--max-megas`/`--from-boards`, CONSUMER config keys.
