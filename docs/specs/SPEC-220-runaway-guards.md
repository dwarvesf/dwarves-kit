# SPEC-220: runaway guards for the autonomous run queue

Status: Draft · 2026-07-31 · Owner: Han
Lane: full (`lane-classify.sh classify` said `full`)
Relates-to: SPEC-217 (`queue watch`, the watcher this extends), SPEC-148
(`queue run`, the conductor and the journal), SPEC-146 (`board queue` +
parse-board allow-list), board row ID-460,
`docs/research/2026-07-31-orchestrator-loop-prior-art.md` (the survey the row
came from)

References:
- `lee-to/aif-handoff` `src/watchdog/taskWatchdog.ts`: the two-threshold
  heartbeat reaper. Imitate the SHAPE, a stale run is force-moved to a parked
  state carrying a jittered `retryAfter`, and a null alarm is the quarantine.
  Do not imitate its status vocabulary; this kit has journal verdicts.
- `frankbria/ralph-claude-code` `lib/circuit_breaker.sh` (`check_no_progress`):
  the four no-progress escape hatches and the consecutive-counter reset rule.
  Imitate the hatch set exactly; an agent asking a question freezes the counter
  rather than counting as stagnation.
- `frankbria/ralph-claude-code` `lib/response_analyzer.sh` (the dual-condition
  block): explicit machine-readable exit always precedes prose heuristics, and
  a malformed structured response is never a completion signal.

## Problem

`queue watch` re-plans any row whose last journal verdict is not `done` or
`gated`. That is the right default, `error` and `stalled` are retryable, but it
is unbounded in two directions.

First, there is no backoff and no ceiling. A row that fails the same way every
time is re-planned on every tick, forever, each time opening a fresh
`--dangerously-skip-permissions` session. From an hourly cron that is a session
per hour on work that cannot progress.

Second, a run can end with no verdict at all. The row's own framing says a dead
WINDOW is unhandled; reading the code, that case is handled (`_mux_capture`
exits nonzero, `_launch_once` returns 2, one retry, then `error`). The genuinely
unhandled case is a dead CONDUCTOR: if the `queue.sh` process itself dies (the
host sleeps, the terminal closes, a SIGKILL), the journal never gets a row for
that slug. The watcher then sees an unrun slug and plans it again on every tick,
with the previous window possibly still alive. Two windows can end up driving
one row.

Third, and independent of both, completion is inferred from prose on a terminal
pane. The marker scan is hardened against soft-wrap, but its channel is still
rendered text. A run has no way to say "I am NOT done" in a form that outranks
what the pane happens to show.

## Solution

### Approaches considered

1. **A reaper daemon that watches beat files.** Rejected: it adds a process to
   supervise, and the kit already has a tick the operator runs, `queue watch`.
   A guard that needs its own daemon to stay alive is a new runaway surface.
2. **A wider journal schema (extra columns for attempt counts and timers).**
   Rejected: the journal is append-only TSV that several readers parse by
   column. Widening it breaks every reader for state that is per-slug and
   mutable, which is the opposite of what an append-only log is good at.
3. **Per-slug sidecar files plus a gate at the single re-pick point.** Chosen.

### Chosen approach + why

All three guards hang off one idea: a per-slug sidecar directory under the
resolved log dir, and one gate in `watch-board.sh` that reads it before a row
can be planned. Nothing new runs on a schedule. The reaper IS the watcher tick.

Three files per slug, each with exactly one writer:

| File | Writer | Meaning |
|---|---|---|
| `<slug>.beat` | the conductor, every poll | mtime = liveness of the process driving this row |
| `<slug>.status` | the RUN itself | the explicit `EXIT_SIGNAL:` line and its progress self-report |
| `<slug>.guard` | the conductor and the reaper | counters and timers (`stalls`, `retry_after`, `noprogress`, `sameerror`, `cooldown_until`) |

The rejected alternatives traded away, in order: a daemon traded a supervision
problem for a scheduling one; a wider journal traded reader stability for
convenience.

### Extensibility & boundaries

The load-bearing dimension is SLUGS, and it is bounded by reads, not by scale:
the watcher reads only the sidecars of the slugs it is already considering plus
the beat files that exist, never a full scan of history. Every threshold is an
environment variable with a default, so tuning is operator config and not a code
change.

Out of bounds by construction: nothing here writes to a board, kills a live
conductor, or merges anything. The guards can refuse to start work and can write
a verdict for work that already stopped. They cannot stop work in flight.

### Architecture

See `## Picture` and `## Design`.

## Picture

```
                      _meta/BACKLOG.md   (queued rows tagged #auto)
                                |
                                v
 +--------------------------------------------------------------------+
 | lib/queue/watch-board.sh          THE TICK (operator or cron)       |
 |                                                                     |
 |  [1] REAP, per <slug>.beat found under <log-dir>/queue-runs/        |
 |        age <  STALE (600s)   -> in flight    -> refuse to plan      |
 |        age >= STALE, < DEAD  -> orphan warn  -> refuse to plan      |
 |        age >= DEAD (3600s)   -> conductor is gone:                  |
 |              read <slug>.status                                     |
 |                 EXIT_SIGNAL: true  -> journal `done` / `gated`      |
 |                 anything else      -> journal `stalled`             |
 |              no progress evidence  -> stalls++                      |
 |              stalls <  MAX (3)     -> retry_after = now + 5..15min  |
 |              stalls >= MAX         -> retry_after empty = QUARANTINE|
 |              clear the beat, kill any orphan window                 |
 |                                                                     |
 |  [2] RE-PICK GATE, per candidate row                                |
 |        last verdict done | gated   -> skip   (shipped rule)         |
 |        beat file present           -> skip   (in flight)            |
 |        quarantined                 -> skip   (human clears it)      |
 |        now < retry_after           -> skip   (backing off)          |
 |        now < cooldown_until        -> skip   (breaker open)         |
 |        otherwise                   -> PLAN                          |
 +--------------------------------------------------------------------+
                                |
                                |   slug <TAB> repo <TAB> pointer
                                v
 +--------------------------------------------------------------------+
 | lib/queue/queue.sh run            THE CONDUCTOR (one row at a time) |
 |                                                                     |
 |   _launch_once, every QUEUE_POLL_SECS and during the retry sleep:   |
 |        touch <slug>.beat                    <-- the heartbeat       |
 |                                                                     |
 |   EXIT GATE, read <slug>.status before the pane is ever consulted:  |
 |        EXIT_SIGNAL: true      -> done, or gated when REASON is set  |
 |        EXIT_SIGNAL: false     -> keep polling, the pane is ignored  |
 |        present but unparsable -> never done, run out to the timeout |
 |        absent                 -> scan the pane   (shipped path)     |
 |        timeout reached        -> stalled                            |
 |                                                                     |
 |   BREAKER, after the verdict, against <slug>.guard:                 |
 |        progress? HEAD moved | FILES_CHANGED > 0 | EXIT_SIGNAL true  |
 |                       -> reset every counter                        |
 |        QUESTION: true -> freeze every counter                       |
 |        else, non-terminal verdict -> noprogress++, stalls++,        |
 |                                      sameerror++ on `error`         |
 |        noprogress >= 3 or sameerror >= 5                            |
 |                -> rewrite the verdict to `error`,                   |
 |                   reason stagnation_detected,                       |
 |                   cooldown_until = now + 1800                       |
 +--------------------------------------------------------------------+
              |                                    |
              v                                    v
     queue-journal.tsv                  <log-dir>/queue-runs/
     ts  slug  verdict  reason            <slug>.beat    conductor touches
     (append-only, unchanged shape)       <slug>.status  the RUN writes
                                          <slug>.guard   counters + timers
```

## Design

### Approaches considered + chosen

Point at `## Solution`. The design view adds one tradeoff the solution view did
not: the beat file doubles as the in-flight claim, which is why the re-pick gate
checks for its mere presence and not only for its age.

### The two thresholds, and why these numbers

The donor uses 5 minutes to free a claim and 90 minutes to declare a stage dead,
against a 30-second heartbeat. This kit's beat interval is `QUEUE_POLL_SECS`,
default 15 seconds, and its per-row wall-clock ceiling is `QUEUE_TIMEOUT_SECS`,
default 2 hours. The numbers are re-derived, not copied.

| Threshold | Value | Why this number |
|---|---|---|
| `QUEUE_BEAT_STALE_SECS` | 600 (10 min) | 40x the default beat interval, and longer than every legitimate conductor pause put together: startup wait (20s), submit settle (up to 10s), one poll (15s). Below this, a missing beat is noise. Above it, the conductor is presumed gone and the operator gets told. |
| `QUEUE_BEAT_DEAD_SECS` | 3600 (60 min) | Six times the stale threshold, so a host that sleeps and wakes inside an hour resumes with no verdict written and no work lost. Deliberately BELOW the donor's 90 minutes: their stage budget is hours, this kit caps a row at 2 hours, so an hour of silence is already half the row's entire life. |
| `QUEUE_COOLDOWN_SECS` | 1800 (30 min) | Matches `QUEUE_RETRY_SLEEP_SECS`, the launch-retry backoff this launcher already ships. The kit's existing instinct for "back off and try later" is half an hour; a second, different number would be arbitrary. |

Retry backoff after a stall is `now + 5..15 minutes`, jittered per stall. The
jitter is the point: several rows stalled by one host sleeping must not all
become re-pickable on the same tick.

`QUEUE_MAX_STALLS` is 3. On the third stall `retry_after` is written EMPTY,
which no comparison can ever satisfy, so the row is skipped until a human
deletes the sidecar. Quarantine is that empty field, not a new state.

### The exit gate's precedence rule

The rule is one sentence: an explicit signal always outranks prose, and the
absence of a parsable signal is never a completion.

`EXIT_SIGNAL: false` is respected as "keep working" even when the pane shows a
marker. That is the anti-false-completion property, and it is why the status
file is read BEFORE the pane on every poll rather than after.

A status file that exists but carries no parsable `EXIT_SIGNAL:` line is treated
as `false` for the completion question and remembered, so the eventual `stalled`
verdict names `malformed_exit_signal` as its reason. It never degrades into
"well, the pane looked done".

With no status file at all, behavior is byte-identical to today: the pane scan,
line-anchored and blank-line-guarded. That path already carries both halves the
donor requires of a text-mode fallback, a completion marker plus a structural
guard, so it is kept rather than re-derived.

### The four no-progress escape hatches

Ported unchanged in spirit, because git-diff-only stall detection produces false
stalls and that is the failure this guard must not have:

1. the repo's HEAD moved, or its tree is dirty, since the run started
2. the run self-reported `FILES_CHANGED: <n>` with n greater than zero
3. the run emitted `EXIT_SIGNAL: true` (a completion signal is progress)
4. the run reported `QUESTION: true`, which FREEZES the counters, neither
   progress nor stagnation

Hatch 4 is the one worth naming: an agent that stops to ask something has not
stagnated, and counting it as stagnation would quarantine exactly the rows most
worth a human's attention.

### Verified evidence versus self-reported evidence

Hatch 1 is checked against the repo. Hatches 2, 3, and 4 read `<slug>.status`,
which the RUN writes about itself. Those are different kinds of fact and the
guard treats them differently:

| Evidence | May reset the breaker counters | May reset the stall ladder |
|---|---|---|
| `verified` (hatch 1, a real repo delta) | yes | yes, and it clears the backoff alarm |
| `reported` (hatches 2 and 3, self-attested) | yes | NO |
| `freeze` (hatch 4, a question) | no, it freezes them | NO |
| none | no, they increment | no, it climbs |

The split is the whole reason quarantine survives contact with an agent. If a
self-report could clear the stall ladder, any run that writes `FILES_CHANGED: 1`
on every attempt would never accrue a stall, never back off, and never
quarantine. The guard's one promise would be opt-out, and the population most
likely to opt out is the one it exists to catch: a hostile Notes cell (still
unsanitized, board row ID-459) or an agent that simply over-reports itself.

So self-report may calm the breaker, and only the repo may clear the ladder. A
run that keeps claiming progress still reaches a human on the third stall.

`CB_OUTPUT_DECLINE_THRESHOLD` is deliberately NOT ported. The deep read confirms
it is defined and documented upstream but never read by any code path.

### Why the breaker does not duplicate the stall counter

They cooperate rather than overlap. The stall counter quarantines a row that
keeps ending without a verdict. The escape hatches are what keep that counter
from firing on a row that IS progressing across retries, a row that commits real
work each night and then hits the 2-hour cap. Without the hatches, the stall
counter alone would quarantine the most productive long-running row in the
queue.

### ADR link(s)

No new ADR. Every decision here is reversible: delete the sidecar directory and
the guards degrade to the shipped behavior exactly. The thresholds are env vars.
Nothing is written that another tool depends on.

### Boundaries & failure modes

See `## Failure modes`. The guards never kill a conductor, never edit a board,
and never write a verdict for a run whose beat is still fresh.

## Technical Design

### Interfaces (I/O contract)

- **Inputs**: the queue journal (unchanged read shape); `<log-dir>/queue-runs/<slug>.{beat,status,guard}`.
- **Outputs**: journal rows (unchanged four-column TSV shape); the sidecar files above; stderr warnings for orphan windows.
- **Invariants**:
  - the journal's column shape and verdict vocabulary do not change; `stalled` and `error` keep their existing meanings and gain timers, not new spellings
  - a slug whose beat file exists is never planned, whatever its journal says
  - a run with no status file behaves exactly as it does today
  - quarantine is only ever cleared by a human deleting the sidecar

### The status-file contract

The run writes `<log-dir>/queue-runs/<slug>.status`, a plain-text file read
line-wise. Recognized keys, all optional except the first:

```
EXIT_SIGNAL: true|false
REASON: <free text, turns a `true` into a `gated` verdict>
FILES_CHANGED: <integer>
QUESTION: true
```

The conductor tells the run this path by appending one clause to the typed
`/goal` line. That is the same channel the `RUNNER_DONE` marker already travels
on, so it needs no environment plumbing and no tmux version floor.

### Data model changes

None to the journal. One new directory, `<log-dir>/queue-runs/`, alongside the
existing `<log-dir>/watch-board-plans/`.

### Infrastructure changes

None. No daemon, no launchd job, no new dependency. Bash only, and bash 3.2
compatible (no associative arrays, no `mapfile`), because CI runs macOS.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: sidecar helpers in `lib/queue/queue.sh` (run dir, portable mtime, guard read/write, `_slug_ok` tightened to reject `/`). AC: a guard value round-trips; a slug containing `/` is refused before any file is written.

### Phase 2: Core
- [ ] TASK-002: heartbeat. The conductor touches `<slug>.beat` every poll AND during the launch-retry sleep, and clears it on a terminal verdict. AC: a completed run leaves no beat file behind.
- [ ] TASK-003: the exit gate in `_launch_once`. AC: explicit `true` wins over an empty pane; explicit `false` beats a `RUNNER_DONE` pane; a malformed file yields `stalled`, never `done`.
- [ ] TASK-004: the breaker in `cmd_run`, counters plus the four hatches. AC: three no-progress runs trip to `error` with reason `stagnation_detected`; one progressing run resets to zero.
- [ ] TASK-005: the reaper and the re-pick gate in `lib/queue/watch-board.sh`. AC: a dead beat writes `stalled` with a `retry_after` in the 5..15 minute window; the third stall writes an empty `retry_after`; a quarantined row is never planned.

### Phase 3: Polish
- [ ] TASK-006: `tests/test-runaway-guards.sh`, each mechanism with its negative control. AC: green, and green from a clean sidecar dir.

## After state

- [ ] A run whose conductor is killed gets a journal verdict on the next watcher tick. (Today: no verdict, ever.)
- [ ] A stalled row is not re-planned before its `retry_after`. (Today: re-planned on every tick with no backoff.)
- [ ] A row that stalls three times is never planned again without a human. (Today: retried forever.)
- [ ] A run that writes `EXIT_SIGNAL: false` is not marked done even if its pane shows `RUNNER_DONE`. (Today: the pane is the only channel.)
- [ ] A row a WATCHER-planned run is already driving is never given a second window. (Today: nothing prevents it.) Scoped honestly: the check lives in the watcher's re-pick gate, so a direct `queue run <tsv>` on an in-flight slug still bypasses it. That path is operator-authored, which SPEC-148 already treats as the trust boundary.
- [ ] A run that claims progress on every attempt is still quarantined on the third stall. (Today: nothing bounds it at all.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Every mechanism has a negative control: a healthy run does not trip anything
- [ ] No regressions: `bash tests/test-self-grill-watcher.sh`, `bash tests/test-meta.sh`, `bash tests/test-docs-wiring.sh`

## Verification

- `bash tests/test-runaway-guards.sh` (exit 0 = all checks green).
- `bash tests/test-self-grill-watcher.sh` stays green: the watcher's shipped plan/skip behavior is unchanged when no sidecar exists.
- `bash lib/queue/watch-board.sh` over this repo's real board still prints an empty plan and exits 0 (the real board carries no `#auto` rows).
- `bash tests/test-meta.sh && bash tests/test-docs-wiring.sh` show no NEW failures versus master.
- Negative controls, one per mechanism, asserted in the test and shown in `docs/verification/`:
  - watchdog: a run with a FRESH beat gets no verdict written and is not planned
  - breaker: a run with progress evidence resets its counters and never trips
  - exit gate: a malformed `EXIT_SIGNAL` never yields `done`
- Live revert-to-RED on the exit gate: invert the precedence so the pane is read first, watch the malformed-signal case go RED, restore, watch it go GREEN.

## Test plan

| Case | Tier | Why |
|---|---|---|
| conductor touches the beat every poll | script | real bash logic |
| a terminal verdict clears the beat | script | leak check on the in-flight claim |
| a slug with a fresh beat is refused a plan (NEGATIVE CONTROL) | script | the in-flight claim |
| a beat past DEAD writes `stalled` plus a jittered `retry_after` | script | the watchdog's core write |
| that `retry_after` lands inside now+300 .. now+900 | script | the jitter window, asserted as a range not a value |
| a dead beat whose status says `EXIT_SIGNAL: true` writes `done`, not `stalled` | script | a finished run must not be called stalled |
| the third stall writes an EMPTY `retry_after` | script | quarantine |
| a quarantined slug is never planned | script | quarantine is terminal without a human |
| a slug inside its `retry_after` is not planned | script | backoff |
| explicit `EXIT_SIGNAL: true` yields `done` with an empty pane | script | explicit beats absent prose |
| explicit `EXIT_SIGNAL: false` yields `stalled` against a `RUNNER_DONE` pane | script | explicit beats present prose, the anti-false-completion rule |
| a malformed status file never yields `done` (NEGATIVE CONTROL) | script | the never-guess rule |
| no status file at all behaves exactly as today | script | backward compatibility |
| three no-progress runs trip to `error` reason `stagnation_detected` | script | the breaker |
| a run with `FILES_CHANGED: 3` resets the counters (NEGATIVE CONTROL) | script | hatch 2 |
| a run with `QUESTION: true` freezes the counters | script | hatch 4, the one that must not quarantine a question |
| a slug inside its breaker cooldown is not planned | script | cooldown |
| a slug containing `/` is refused | script | sidecar path traversal |
| the operator's real tuning of these thresholds on a live host | NOT TESTED | wall-clock behavior over hours; the test asserts the arithmetic, the operator observes the fit |

## Edge Cases

1. Clock jumps backward (an NTP correction): elapsed times are clamped at zero, so a backward jump delays a reap rather than firing one early. `retry_after` is an absolute epoch, so a backward jump extends the backoff, which is the safe direction.
2. The sidecar directory does not exist: every read returns empty and every guard is inert. The kit behaves exactly as it does today.
3. A slug's status file is written by a run that then dies before its conductor: the reaper reads it and honors `EXIT_SIGNAL: true`, so real work is not relabeled `stalled`.
4. Two watcher ticks overlap: the reap is per-slug and idempotent. The second tick finds the beat already cleared and the verdict already written, and plans nothing new.
5. A row runs to `done`: every counter is reset and the sidecar is cleared, so a future re-queue of the same slug starts clean.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A dead conductor leaves a row unrun forever | the slug has a beat file and no journal row | the reaper writes `stalled` past the DEAD threshold and schedules a jittered retry |
| A row fails identically on every tick | the same slug re-enters the plan every run | `retry_after` after each stall, quarantine on the third |
| A quarantined row is silently forgotten | the watcher prints a `quarantined` skip line naming the slug on every tick | it is loud by design; a human deletes the sidecar to clear it |
| Two windows drive one row | a second `new-window` for a slug that already has one | the re-pick gate refuses any slug with a beat file present |
| A run's prose falsely reads as completion | the pane shows a marker the run did not intend | an explicit `EXIT_SIGNAL: false` outranks the pane; with no status file the shipped structural guard still applies |
| A malformed status file is guessed at | a status file with no parsable signal | never a completion; the run goes to `stalled` with reason `malformed_exit_signal` |
| A progressing row is quarantined for being slow | a row that commits real work but hits the 2h cap | the four escape hatches reset the counters, so only rows producing nothing accumulate stalls |
| A slug escapes the sidecar directory | a slug containing `/` or a path separator | `_slug_ok` refuses it before any file is opened |
| A run buys itself an exemption from quarantine | a slug that stalls repeatedly but never accrues stalls | a self-report may reset only the breaker counters; the stall ladder moves on verified repo deltas alone |
| Guards misfire and block real work | rows skipped that should run | delete `<log-dir>/queue-runs/`; every guard is inert without it |
| One run sabotages a SIBLING row's sidecar | a row stuck `in flight` or `quarantined` with no matching activity | NOT DEFENDED, and named honestly: sidecar names are derived from the board and nothing authenticates a write, so any process running as the same user can plant one. This is inside the existing trust boundary (the launched sessions already run `--dangerously-skip-permissions` as that user), but the sidecars do make sibling sabotage cheaper than it was. Recovery is deleting the sidecar. |
| Two concurrent watcher ticks plan the same slug | two windows for one row | NOT DEFENDED. The re-pick gate and the beat write are two moments with no atomic reservation between them, a deliberate consequence of the no-daemon, no-lock design. Operational constraint: do not run two `queue watch --apply` invocations against one board concurrently. |
| Two repos share a directory basename | one repo's row locks or quarantines another's | pre-existing (the slug has always been `<basename>__<id>`), but the blast radius grew from a shared journal verdict to shared in-flight and quarantine state; pin `--repo-name` explicitly in cron wiring |

## Out of Scope

- **Convergence detection.** Scoped out deliberately, see DEC-004. The kit HAS per-finding identity (`review-team.md` Step 3a's `<defect-slug>:<file-path>` finding-key), so the primitive exists, but the review loop runs INSIDE the `/goal` session and never persists a per-iteration blocking set. The queue conductor sees a tmux pane, not findings. Wiring convergence would mean inventing a review-iteration ledger and a cross-subsystem contract to carry it, which is a review-subsystem feature, not a queue guard.
- **A state-machine transition table.** Scoped out, see DEC-005.
- **`lib/queue/orchestrate.sh`.** It already ships an advisory stall watchdog for the sub-goal sessions inside one mega-goal, and it is not the surface that re-picks work. The runaway named on the row is the watcher's re-pick loop.
- Per-row token or dollar ceilings. That is board row ID-461.
- Notes-cell sanitization. That is board row ID-459.
- Any cron, launchd, or daemon wiring. The guards run on the tick the operator already runs.

## Decision Log

- DEC-001: the two stale thresholds are 10 minutes and 60 minutes, not the donor's 5 and 90. Rationale: the donor heartbeats every 30s against an hours-long stage budget; this kit beats every 15s against a 2-hour row cap, so the short threshold can be tighter in beat-multiples while the long one must be shorter in absolute terms. Derivation is in `## Design`. Rejected: copying 5/90 unexamined, which would have declared a row dead at 5 minutes of a legitimate 20-second startup wait plus a slow poll.
- DEC-002: the short threshold does NOT free a slot, because this kit has no slot registry to free. The donor's cheap reversible action was releasing a claim; here the equivalent cheap action is to WARN about the orphan and keep refusing to plan the slug. Rejected: killing the orphan window at 10 minutes, which destroys a run whose conductor may simply be paused. The window is killed only at the DEAD threshold, together with the verdict write.
- DEC-003: the in-flight claim is the mere PRESENCE of a beat file, not a separate lock. Rationale: one file already carries both facts (someone is driving this slug, and how recently), and a second lock file would be a second thing to leak. Rejected: reusing `orchestrate.sh`'s mkdir-lock, which is built for concurrent writers inside one mega-goal and would have to be taught the reaper's thresholds anyway.
- DEC-004: convergence detection is OUT of scope. Rationale: the queue conductor's entire view of a run is a tmux pane plus, now, a status file. Review findings never cross that boundary. Implementing convergence honestly needs a per-iteration blocking-set ledger inside the review loop, which is a review-subsystem change with its own spec. Recorded rather than half-built: a convergence check reading a set that nothing populates would be a guard that never fires. Also noted from the deep read: the donor's own `new_blockers_after_rework` escape only fires under its non-default `closure_first` strategy, so even upstream this is an opt-in path, not the shipped default.
- DEC-005: no state-machine transition table. Rationale: the legal moves for these three guards all converge on ONE place, the re-pick gate in `watch-board.sh`, and that gate reads top to bottom in a dozen lines. A `case` table restating it would be a second copy that can disagree with the first. The kit's own rule applies: write a spec, or a table, only when a gate is behind it.
- DEC-006: `CB_OUTPUT_DECLINE_THRESHOLD` is not ported. Rationale: the deep read confirms it is dead config upstream, defined and documented but read by nothing.
- DEC-007: the run learns its status-file path from one clause appended to the typed `/goal` line, not from an environment variable. Rationale: `tmux new-window -e` needs tmux 3.0 and would need a fallback path for older hosts; the typed prompt is the channel the `RUNNER_DONE` contract already uses, is argv-safe, and adds no version floor. Cost, accepted: every run's typed line grows by one sentence.
- DEC-008: `_slug_ok` is tightened to reject `/` as well as `:` and `.`. Rationale: the slug now names a file path under the sidecar directory, so a slug carrying a separator is a traversal. It was already meant to be a simple identifier and the watcher only ever builds `<repo>__<id>`. Rejected: sanitizing the slug into a safe filename, which makes two different slugs collide on one sidecar.
- DEC-009: the breaker rewrites a NON-TERMINAL verdict only. A `done` or `gated` run resets the counters and is never converted. Rationale: a legitimate investigate-and-report row changes no files and must not be called stagnation for it.

## Open questions

(none)
