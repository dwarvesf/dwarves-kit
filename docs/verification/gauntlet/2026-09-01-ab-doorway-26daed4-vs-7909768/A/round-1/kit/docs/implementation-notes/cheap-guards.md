# Implementation notes: SPEC-224 cheap guardrails

Delta from the spec only. Where the build matched the spec verbatim, nothing is written here.

## 2026-08-01 claim-lease scoped out from the merged SPEC-221 code

Context: board row ID-461 named three ideas (draft PR, spend ceiling, claim-lease). The spec had to decide the claim-lease from the ACTUAL merged SPEC-221, not the survey's guess.

Decision: scoped OUT. Verified in `lib/queue/queue.sh`: the header states `<slug>.beat` "its PRESENCE is the in-flight claim", `_beat`/`_beat_clear` maintain it, and `_launch_once` clears a stale status + beats every poll. `watch-board.sh` is the reaper (SPEC-221 DEC-003 chose beat-presence AS the claim to avoid a second lock). A `claimed_at` lease would be the exact redundant lock DEC-003 rejected.

Why: no deviation from the spec; recorded here because it is the load-bearing scope call the caller asked to justify from real code.

Impact: 461 shipped only the two cheap wins.

## 2026-08-01 the spend proxy is self-reported tool-calls, not pane-scraped or token-fed

Context: the spec's DEC-002 picks tool-call count. The build had to choose the READ mechanism.

Decision: the run self-reports `TOOL_CALLS: <n>` into the SPEC-221 `<slug>.status` file, read by a new `_status_num` (MAX across lines). Not pane-scraped.

Why: verified `_mux_capture` is `tmux capture-pane -p`, a fixed viewport that loses scrolled-off turns, so a cumulative count off the pane is unreliable. There is no token/cost feed at the bash layer. The status file is a channel the conductor already opens every poll.

Alternatives: pane scraping (rejected, viewport); a real token feed (does not exist here).

Impact: the ceiling is a guardrail an under-reporting run can evade; the wall-clock `QUEUE_TIMEOUT_SECS` is the non-gameable backstop, composed OR-style. Named in the spec's `## Design` and DEC-002.

## 2026-08-01 spend stop reuses the stalled verdict + a new reason value

Context: the caller asked to EXTEND SPEC-221's stop-reason field, not add a second.

Decision: a per-row ceiling trip returns `stalled:spend_ceiling`. `stalled` is the existing verdict; `spend_ceiling` is a new value of SPEC-221's journal `reason` column.

Why: the journal is a four-column TSV several readers parse by column. A new verdict word would touch every reader; a new reason value touches none. The reason survives `_breaker_apply` because a `stalled` verdict with no repo delta prints an empty reason, which `cmd_run` does not overwrite.

Impact: `mega runs` / any journal reader sees `spend_ceiling` distinct from a clean `done` with zero new parsing.

## 2026-08-01 draft default lives only in _goal_line, so the interactive path is untouched by construction

Context: the spec requires interactive `/kit:ship` to stay a normal PR.

Decision: the draft clause is appended in `_goal_line`, which only the autonomous queue calls. `commands/ship.md` Step 8 documents the split; it does not add a draft branch to the interactive flow.

Why: the queue never runs `gh`. The only channel to the run is the typed prompt (SPEC-221 precedent). So "autonomous path only" is a structural fact, not a runtime flag the interactive path must check.

Impact: no interactive code changed; the test asserts the doc contract (A3) plus the two `_goal_line` branches (A1 draft default, A2 --ready).

## 2026-08-01 security review: clamp the self-reported count at the source

Context: the security reviewer found the untrusted self-reported `TOOL_CALLS` was read unclamped.

Decision: `_status_num` clamps to 9 digits (`if (length(v) > 9) v="999999999"`) before any compare.

Why: on the `--from-boards` untrusted path a run could write a 30-digit number that (a) errors the `-ge` compare with "integer expected" and silently DISABLES the per-row ceiling, and (b) overflows the 64-bit queue-wide accumulator and spuriously aborts the whole batch. The clamp is at the one source both call sites go through, so it is a single-line root-cause fix, not a per-caller guard.

Impact: the ceiling is robust to a hostile self-report; the wall-clock remains the non-gameable backstop. Test B3 asserts an oversized report still trips; its revert-to-RED confirms the clamp binds. Also footered the journal BASENAME (not the home path) to stop a username leak into the PR body. The stall-ladder design question is answered in SPEC-224 DEC-006, no code change.
