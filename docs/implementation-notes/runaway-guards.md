# Implementation notes: runaway guards

The DELTA from `docs/specs/SPEC-220-runaway-guards.md`, not a mirror of it. Entries are appended
as decisions land.

## 2026-08-01 09:10 The spec number moved from 218 to 220

Context: the task reserved SPEC-218. By the time the branch was cut, `SPEC-218-feature-map-skill`
and `SPEC-219-feature-registry` had both merged to master, and `lib/spec/spec-next.sh next`
returned 220.

Decision: renumber to SPEC-220. Every reference in the spec, the two libs, and the test moved
with it.

Why: `tests/test-meta.sh` carries a hard duplicate-SPEC-number guard, and it went RED on the
collision. The reservation was made against a stale view of the specs directory, so honoring it
would have shipped a known-broken test. Master already carries a commit named "renumber registry
spec to SPEC-219 after collision", so this is a recurring hazard the guard exists to catch.

Alternatives: keep 218 and override the guard (rejected: the guard is correct and the collision
is real); pick 221 to leave room (rejected: `spec-next` said 220, and second-guessing it is how
the next collision happens).

Impact: the reserved number in the task description is stale. Nothing else changes.

## 2026-08-01 09:15 The problem statement is narrower than the board row claimed

Context: board row ID-460 says "a row whose window dies mid-run is an unhandled state".

Decision: the guards target a different, verified pair of states, and the spec says so in
`## Problem`.

Why: reading `_launch_once`, a dead WINDOW is already handled. `_mux_capture` exits nonzero, the
function returns 2, `_run_row` retries once, and a second failure journals `error`. The genuinely
unhandled states are (a) a dead CONDUCTOR process, which leaves no journal row at all, and (b)
`error` and `stalled` being re-picked by the watcher on every tick with no backoff and no
ceiling. Building against the row's framing would have added a guard for a case that already
works while leaving both real ones open.

Impact: the stale-window watchdog is specified against conductor liveness (the beat file), not
window liveness. The re-pick gate is where the unbounded-retry half is fixed.

## 2026-08-01 09:40 The short stale threshold does not free a slot

Context: the donor's two-threshold design frees a CLAIM at the short threshold and force-parks the
task at the long one. The feed's MAP line proposed "reclaim slot on short staleness".

Decision: the short threshold warns about the orphan and keeps refusing to plan the slug. It frees
nothing and kills nothing. Recorded as spec DEC-002.

Why: this kit has no slot registry, so "reclaim a slot" has no referent. The nearest real action
was killing the orphan tmux window, and doing that at 10 minutes would destroy a run whose
conductor is merely paused. The window is killed only at the DEAD threshold, together with the
verdict write, where the conductor is confirmed gone.

Impact: a deviation from the feed's MAP line, deliberate. The two thresholds still do different
work: one reports, one decides.

## 2026-08-01 10:05 `git -C ""` reads the operator's current directory

Context: the reaper calls `_progress_evidence` without knowing which repo the slug ran against, so
it passes an empty repo path.

Decision: `_progress_evidence` returns early unless the repo argument is a real directory.

Why: `git -C ""` does not fail. It silently falls back to the current directory. Unguarded, the
reaper ran `git -C "" status --porcelain` against whatever directory the operator invoked the
watcher from, and a dirty checkout there counted as THIS row's progress, which reset the stall
counter and defeated quarantine entirely.

How it was found: the A4 assertion `the stall counter incremented` went RED with the counter at 0
while the verdict itself was correct. The test caught it; reading the code alone had not.

Impact: in the reaper, only the run's own self-report (the status file) can supply progress
evidence. That is honest, and the spec's edge-case 3 already depended on it.

## 2026-08-01 10:20 The run learns its status path from the typed prompt

Context: the run has to be told where to write `EXIT_SIGNAL`, or the whole exit-gate contract is
dead code nothing ever populates.

Decision: `_goal_line` appends one clause naming the path. Recorded as spec DEC-007.

Why: `tmux new-window -e` is the obvious alternative and it needs tmux 3.0, so it would need a
fallback path for older hosts, in the one launcher that runs unattended overnight. The typed
prompt is the channel the `RUNNER_DONE` contract already travels on, is argv-safe, and adds no
version floor.

Alternatives: an env var via `-e` (rejected, above); deriving the path in the session from a
convention (rejected: the session does not know its own slug).

Impact: every run's typed `/goal` line grows by one sentence. No existing test pinned that line
exactly, and the shipped bats suite stayed green.

## 2026-08-01 10:30 Scope-outs that were judgment calls, not omissions

**Convergence detection.** Out. The kit DOES have per-finding identity: `commands/review-team.md`
Step 3a computes a `<defect-slug>:<file-path>` finding-key, which is the same primitive the donor
content-addresses. What it does not have is a per-iteration blocking-set ledger, and more
decisively, the queue conductor cannot observe review findings at all. Its entire view of a run is
a tmux pane plus the new status file. A convergence check reading a set that nothing populates
would be a guard that never fires. Spec DEC-004 records both halves, including that the donor's
own `new_blockers_after_rework` escape fires only under its non-default strategy.

**The state-machine transition table.** Out. Every legal move for these three guards converges on
one function, `_guard_skip_reason`, which reads top to bottom in about a dozen lines. A `case`
table restating it would be a second copy that can disagree with the first. Spec DEC-005.

**`lib/queue/orchestrate.sh`.** Untouched. It already ships an advisory stall watchdog for
sub-goal sessions inside one mega-goal, and it is not the surface that re-picks work.

## 2026-08-01 11:30 Self-reported progress may not clear the stall ladder

Context: a security lens and an architecture lens, dispatched independently on the finished diff,
both landed on the same HIGH finding. `_progress_evidence` returned a single `yes` for all four
hatches, and `_breaker_apply` let any `yes` zero every counter including `stalls`.

Decision: split the return into `verified` (hatch 1, a real repo delta), `reported` (hatches 2 and
3, self-attested), and `freeze` (hatch 4). Only `verified` clears the stall ladder and the backoff
alarm. `reported` calms the breaker counters only. `freeze` calms nothing but accuses of nothing.
The reaper, which has no repo context and therefore can never obtain `verified`, now always climbs
the ladder.

Why: the hatches read `<slug>.status`, which the RUN writes about itself. Under the old code a run
emitting `FILES_CHANGED: 1` on every attempt reset `stalls` every time, so it never backed off and
never quarantined. That is the guard's central promise, made opt-out by the exact population it
exists to catch. The spec's own "After state" claimed the opposite, so the spec was wrong too, not
just the code.

Alternatives: cap how many consecutive self-report-only resets are allowed (rejected: the
verified/reported split makes a cap unnecessary, since the ladder now climbs regardless); drop
hatches 2 and 3 entirely (rejected: they are what stop a false stall on a row whose work the git
check cannot see).

Impact: `_stall_bump` extracted, because the ladder is now climbed from three branches and a third
copy of the read-increment-schedule sequence was where the counter and its alarm would eventually
disagree. Two new tests (B7, B8) pin both halves, and B7 was proven by a live revert-to-RED.

## 2026-08-01 11:40 Two review findings accepted as documented boundaries, not fixed

Both reviews flagged the same two gaps. Neither is fixed in code, and both are now named in the
spec's failure-modes table instead.

**A direct `queue run <tsv>` bypasses the in-flight check.** The re-pick gate lives in
`watch-board.sh`, so `queue.sh run` invoked straight on a TSV never consults a beat file, and
`_mux_open` kills any existing window for the slug before opening its own. Not fixed: the plain
TSV path is operator-authored, which SPEC-148 already establishes as the trust boundary for that
path, and pushing the check down into `_launch_once` would make the launcher consult guard state
it otherwise has no part in. The spec's "After state" line was narrowed to claim only what the
code delivers, rather than left overclaiming.

**Sidecar writes are unauthenticated.** Slug names are derivable from the board and nothing proves
a `.beat` or `.guard` write came from that slug's own conductor, so any process running as the
same user can pin a sibling row `in flight` or `quarantined`. Not fixed: every launched session
already runs `--dangerously-skip-permissions` as that user, so this is inside the existing trust
boundary rather than a new hole. It is still a cheaper sabotage primitive than existed before, so
it is stated in the table rather than left implied.

## 2026-08-01 10:45 No deviations beyond the entries above

Everything else matches the spec verbatim: three sidecar files with one writer each, the two
thresholds at 600 and 3600 seconds, quarantine as an empty `retry_after` on the third stall, the
four escape hatches with the question-freeze, and the exit-gate precedence with a malformed signal
never yielding `done`.
