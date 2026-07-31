# SPEC-224: two cheap guardrails for the autonomous run queue

Status: DRAFT · 2026-08-01 · Owner: Han
Lane: full (`lane-classify.sh classify` said `full`)
Relates-to: SPEC-221 (runaway guards, the sidecar + reaper this builds beside),
SPEC-148 (`queue run`, the conductor and the journal), SPEC-217 (`queue watch`),
SPEC-223 (untrusted pointer sanitization), board row ID-461,
`docs/research/2026-07-31-orchestrator-loop-prior-art.md` (the survey the row came
from)

References:
- OpenHands `mcp_router.py` `create_pr` tool: `draft: bool = True` is a per-call
  default the model can override with `draft=False`. Imitate the POSTURE, an
  unattended run drafts by default and an explicit override opens a normal PR. Its
  SAAS-only `get_conversation_link()` footer is the model for the provenance line.
- SWE-agent `models.py` `per_instance_call_limit` (unit = API-call count, default 0 =
  disabled) and its two-tier stop: a per-instance limit stops THAT instance after its
  turn (autosubmit the partial patch), the total limit halts the whole batch. Imitate
  the two tiers and the count-not-dollars axis. There is no cost feed here, so the
  count is self-reported, not harness-measured.
- vercel `ralph-loop-agent` `ralph-stop-condition.ts`: `stopWhen` is composed OR
  (`results.some`). Imitate the OR composition with the existing wall-clock timeout,
  and do BETTER than its `completionReason` collapsing every trip to `max-iterations`,
  name the spend stop distinctly in the journal.

## Problem

The autonomous queue opens PRs and burns effort with two unbounded edges that
SPEC-221 did not close.

First, an unattended overnight run opens a NORMAL pull request. A normal PR reads as
review-ready, but no human saw it. There is no signal on the PR that a machine opened
it and nobody has looked.

Second, SPEC-221 bounds a row by WALL-CLOCK only. `QUEUE_TIMEOUT_SECS` caps a single
attempt at two hours, and three stalls quarantine the row. Neither bounds the SPEND
INSIDE one attempt. A row that keeps looking busy for two hours, or that makes real
progress while burning a huge number of tool calls, never trips the wall-clock early
and never stalls. Time is capped; effort is not.

Claim-leases are the third idea the survey raised. They are NOT a problem here, see
the scope decision below.

## Solution

### Approaches considered

1. **A real token or dollar feed at the bash queue layer.** Rejected: none exists.
   The conductor drives a tmux pane, not an API client. There is no per-turn cost to
   read.
2. **Scrape a running counter off the tmux pane.** Rejected: `capture-pane` is a
   fixed viewport. Old turns scroll off, so a cumulative count read from the pane is
   wrong the moment the run is longer than one screen.
3. **A per-slug claim-lease with a `claimed_at` timer.** Rejected: SPEC-221 already
   ships the claim. See the scope decision.
4. **Self-reported effort through the status file SPEC-221 already opened, plus a
   draft-default clause on the typed prompt.** Chosen.

### Chosen approach + why

Both wins ride channels SPEC-221 already built, so the diff is small and adds no new
process.

Draft-default is one clause on the typed `/goal` line. The queue never runs `gh`
itself; the launched run opens its own PR via `/kit:ship`. The only channel from the
conductor to the run is the typed prompt, the same channel SPEC-221 uses to name the
status file. So the conductor appends: open the PR as a draft, and stamp it with a
provenance footer. `QUEUE_PR_READY=1` (the `--ready` flag) drops the clause, which is
OpenHands' model-overridable `draft=False`. Interactive `/kit:ship` never calls this
builder, so it is untouched.

The spend ceiling reads a self-reported counter. The run writes `TOOL_CALLS: <n>` into
the SAME `<slug>.status` file it already writes for the exit signal, and the conductor
reads it on the poll it already does. Two tiers, exactly SWE-agent's split:

| Tier | Trip | Effect |
|---|---|---|
| per-row (`QUEUE_MAX_TOOL_CALLS`) | the run's reported count crosses the ceiling | stop THIS row after the observed turn; whatever draft PR it already opened persists |
| queue-wide (`QUEUE_MAX_TOTAL_TOOL_CALLS`) | the batch total crosses the ceiling | the current row finishes and journals first, then the REMAINING rows are skipped |

Both default 0 (disabled), matching SWE-agent's `per_instance_call_limit=0` default,
so the shipped behavior is byte-identical until an operator sets a ceiling.

### The honest limit of a self-report

Self-report is a GUARDRAIL, not a boundary. SPEC-221 states this verbatim for its
locks: "The protection is intentionally a guardrail rather than a security boundary."
The same holds here. A run that under-reports `TOOL_CALLS` evades the ceiling. Two
things make that acceptable. The wall-clock timeout is the non-gameable backstop and
is composed OR-style beside the ceiling, so a run that lies about its count still dies
at two hours. And the gaming direction is self-limiting: a run under-reports to keep
GOING, and SPEC-221's stall ladder plus wall-clock already bound how long it can.

### Extensibility & boundaries

The load-bearing dimension is the proxy. Today it is tool-call count. If a real token
or cost feed ever reaches the bash layer, it slots into the same two-tier gate and the
same journal reason; the composition (OR with wall-clock, first-to-trip) does not
change. Each piece is one purpose: `_status_num` reads a self-reported counter,
`_goal_line` appends clauses, the poll loop trips the per-row ceiling, `cmd_run` trips
the queue-wide one.

Out of bounds by construction: this never runs `gh`, never merges, never interrupts a
tool call mid-execution. The per-row ceiling stops a row only between observed turns.

### The claim-lease scope decision (the 460 dependency)

SCOPED OUT. SPEC-221 already ships the claim-lease this row's survey imagined, so a
second lease would be a redundant lock over the same fact.

- The survey's lease is a `claimed_at` timestamp with lazy expiry checked when a NEW
  run claims a row. SPEC-221's `<slug>.beat` file IS that claim: its mere presence is
  the in-flight claim (queue.sh header, "its PRESENCE is the in-flight claim"), and
  its mtime is the lazy-expiry clock.
- SPEC-221 DEC-003 chose beat-presence AS the claim precisely so there is no second
  lock to leak: "the in-flight claim is the mere PRESENCE of a beat file, not a
  separate lock." Adding `claimed_at` would be the separate lock DEC-003 rejected.
- The reaper in `watch-board.sh` is the lazy expiry: a beat past `QUEUE_BEAT_DEAD_SECS`
  is reclaimed on the next tick (the tick the operator already runs), not by a
  watchdog. The re-pick gate refuses any slug whose beat is present.
- SPEC-221 `## Out of Scope` names this handoff explicitly: "Per-row token or dollar
  ceilings. That is board row ID-461." The two rows were designed to meet here.

So 461 keeps only the two genuinely-cheap wins. The "guardrail not a boundary" framing
is carried into the ceiling section above, per the survey's instruction.

### Architecture

See `## Picture` and `## Design`.

## Picture

```
                    _meta/BACKLOG.md  (queued rows tagged #auto)
                              |
                              v
 +------------------------------------------------------------------+
 | lib/queue/queue.sh cmd_run          THE CONDUCTOR (one row/turn)  |
 |                                                                   |
 |  _goal_line, the typed /goal prompt:                             |
 |     + status-file clause          (SPEC-221, unchanged)           |
 |     + DRAFT clause  unless QUEUE_PR_READY=1   (SPEC-224)           |
 |         "open the PR as a draft; footer: journal <path> slug <s>" |
 |     + TOOL_CALLS clause  when a ceiling is set (SPEC-224)          |
 |                                                                   |
 |  _launch_once, every QUEUE_POLL_SECS:                            |
 |     read <slug>.status                                            |
 |        EXIT_SIGNAL true/gated -> done   (SPEC-221, wins first)    |
 |        TOOL_CALLS >= QUEUE_MAX_TOOL_CALLS                         |
 |             -> stop the row: stalled, reason spend_ceiling        |
 |        elapsed >= QUEUE_TIMEOUT_SECS   (SPEC-221 wall-clock)      |
 |             -> stalled                                            |
 |     (OR composition: first of the three to trip wins)            |
 |                                                                   |
 |  after the row journals:                                         |
 |     total += this row's reported TOOL_CALLS                       |
 |     total >= QUEUE_MAX_TOTAL_TOOL_CALLS                           |
 |          -> abort the REMAINING rows (this one already shipped)   |
 +------------------------------------------------------------------+
              |                                    |
              v                                    v
     queue-journal.tsv                  the launched /goal run
     ts slug verdict reason               opens its OWN draft PR
     reason gains: spend_ceiling          via /kit:ship (gh pr create
     (SPEC-221 field, EXTENDED)           --draft + provenance footer)
```

## Design

### Approaches considered + chosen

Point at `## Solution`. One tradeoff the design view adds: the per-row ceiling reuses
the `stalled` verdict rather than inventing a new one, so a spend stop flows through
SPEC-221's existing stall ladder (backs off, quarantines on the third). The distinct
signal is the journal REASON (`spend_ceiling`), not a new verdict word. This keeps the
verdict vocabulary and every reader of it unchanged.

### The proxy, and why tool-call count

The axis is SWE-agent's `per_instance_call_limit`: a count of calls, not dollars or
tokens. It is the one effort signal a run can report cheaply and monotonically. Tokens
would need a real usage feed; dollars would need a price table. A call count is a
number the run already knows about itself.

`_status_num` reads the MAX numeric `TOOL_CALLS` value across the status file, so it is
correct whether the run rewrites the line or appends a new one each update. A monotonic
counter's max is its latest value either way.

### Composition

The three stop conditions (exit signal, spend ceiling, wall-clock) are checked in that
order on every poll, OR-style, first-to-trip wins. Exit-signal first is deliberate: a
finished run is never spend-capped. The queue-wide ceiling is a fourth, coarser gate
checked once per row at the batch level, after the row has journaled.

### ADR link(s)

No new ADR. Every decision is reversible: unset the two env vars and the ceiling is
inert; set `QUEUE_PR_READY=1` and the draft clause is gone. Nothing persists that
another tool depends on. The journal shape is unchanged (the reason column gains a
value, not a column).

### Boundaries & failure modes

See `## Failure modes`. This never runs `gh`, never interrupts a tool call, and never
writes a verdict for a run whose beat is still fresh (SPEC-221 owns that).

## Technical Design

### Interfaces (I/O contract)

- **Inputs**: `<log-dir>/queue-runs/<slug>.status` (the run writes `TOOL_CALLS: <n>`,
  optional); the three new env vars.
- **Outputs**: the typed `/goal` line gains up to two clauses; journal rows carry the
  new reason `spend_ceiling`; stderr carries the queue-wide abort line.
- **Invariants**:
  - the journal's four-column shape and verdict vocabulary do not change
  - both ceilings default 0 = disabled; with them unset, behavior is byte-identical to
    SPEC-221
  - `QUEUE_PR_READY=1` removes the draft clause entirely
  - interactive `/kit:ship` never calls `_goal_line`, so it stays a normal PR

### The status-file contract (extended)

SPEC-221's `<slug>.status` gains one optional key, read only when a ceiling is set:

```
TOOL_CALLS: <integer>   the run's cumulative tool-call count, updated as it works
```

The run learns to write it from a clause on the typed `/goal` line, the same channel
SPEC-221 uses for the exit-signal keys. A run that ignores the clause never trips the
ceiling and dies at the wall-clock instead, exactly as before.

### Data model changes

None. No new file, no new journal column. One new optional key in an existing file.

### Infrastructure changes

None. No daemon, no new dependency. Bash 3.2 compatible (CI runs macOS): no
associative arrays, no `mapfile`.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: the three env vars and `_status_num` (max-numeric read of a status
  key). AC: `_status_num` returns the largest `TOOL_CALLS` value across a
  multi-line status file, and 0 when absent.

### Phase 2: Core
- [ ] TASK-002: `_goal_line` appends the draft clause unless `QUEUE_PR_READY=1`, and
  the `TOOL_CALLS` reporting clause when a ceiling is set. AC: the draft clause and
  footer appear by default; `QUEUE_PR_READY=1` removes them.
- [ ] TASK-003: the per-row ceiling in `_launch_once`, checked after the exit gate and
  before the wall-clock. AC: a run whose reported `TOOL_CALLS` crosses the ceiling
  journals `stalled` reason `spend_ceiling`; a run under the ceiling never trips.
- [ ] TASK-004: the queue-wide ceiling in `cmd_run`, accumulated per row. AC: once the
  batch total crosses the ceiling, the current row still journals and later rows are
  skipped.
- [ ] TASK-005: the `--ready` flag. AC: `queue run --ready` sets the ready posture.

### Phase 3: Polish
- [ ] TASK-006: `tests/test-cheap-guards.sh`, each mechanism with its negative control.
  AC: green, and green from a clean sidecar dir.

## After state

- [ ] An unattended run's PR opens as a draft with a provenance footer. (Today: a
  normal PR with no machine marker.)
- [ ] `queue run --ready` opens a normal PR. (Today: no such control; every PR is the
  same.)
- [ ] A row whose reported tool-call count crosses `QUEUE_MAX_TOOL_CALLS` stops with
  reason `spend_ceiling`, readable in the journal. (Today: only wall-clock stops a
  row.)
- [ ] Once the batch tool-call total crosses `QUEUE_MAX_TOTAL_TOOL_CALLS`, remaining
  rows are skipped. (Today: nothing bounds total effort across rows.)
- [ ] With both ceilings unset and `QUEUE_PR_READY` unset, `bash tests/test-runaway-guards.sh`
  still passes unchanged. (Backward compatibility.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Every mechanism has a negative control: a healthy short run is not draft-forced
  to abort and does not trip a ceiling
- [ ] No regressions: `bash tests/test-runaway-guards.sh`, `bash tests/test-meta.sh`,
  `bash tests/test-docs-wiring.sh`

## Verification

- `bash tests/test-cheap-guards.sh` (exit 0 = all checks green).
- `bash tests/test-runaway-guards.sh` stays green: SPEC-221's guards are untouched when
  the new env vars are unset.
- `bash tests/test-meta.sh && bash tests/test-docs-wiring.sh` show no NEW failures
  versus master.
- Negative controls, one per mechanism, asserted in the test:
  - draft-default: `QUEUE_PR_READY=1` produces a `/goal` line with no draft clause
  - per-row ceiling: a run reporting a count UNDER the ceiling reaches `done`, never
    `spend_ceiling`
  - queue-wide ceiling: a batch under the total runs every row
- Live revert-to-RED, shown in `docs/verification/`:
  - draft-default: delete the `QUEUE_PR_READY` guard so the clause is unconditional,
    watch the `--ready` negative control go RED, restore, watch it go GREEN
  - ceiling-trip: invert the per-row comparison to `-lt`, watch the trip case go RED,
    restore, watch it go GREEN

## Test plan

| Case | Tier | Why |
|---|---|---|
| the draft clause + footer appear by default | script | the autonomous default |
| `QUEUE_PR_READY=1` removes the draft clause (NEGATIVE CONTROL) | script | the `--ready` escape hatch |
| `queue run --ready` sets the ready posture | script | the flag wires to the env |
| interactive `/kit:ship` still opens a normal PR | doc | the interactive path is untouched |
| a run reporting TOOL_CALLS at the ceiling stops with reason `spend_ceiling` | script | the per-row trip |
| a run reporting TOOL_CALLS under the ceiling reaches `done` (NEGATIVE CONTROL) | script | a healthy run does not trip |
| the batch total crossing the queue-wide ceiling skips remaining rows | script | the queue-wide trip |
| a batch under the queue-wide ceiling runs every row (NEGATIVE CONTROL) | script | a cheap batch is not aborted |
| both ceilings unset behaves exactly as SPEC-221 | script | backward compatibility |
| `_status_num` returns the MAX across a multi-line status file | script | append-or-rewrite robustness |
| an under-reporting run still dies at the wall-clock | NOT TESTED (asserted by design) | the non-gameable backstop is SPEC-221's timeout, already tested |

## Edge Cases

1. The run never writes `TOOL_CALLS`: `_status_num` returns 0, the ceiling never trips,
   the wall-clock backstop still applies. Byte-identical to SPEC-221.
2. Junk in `QUEUE_MAX_TOOL_CALLS` (non-numeric): coerced to 0 (disabled) at parse time,
   so a bad config never errors a comparison and never blocks a row.
3. The run under-reports to dodge the ceiling: the wall-clock and SPEC-221's stall
   ladder still bound it. Named honestly in `## Design`.
4. `QUEUE_PR_READY=1` and a ceiling both set: independent. The PR is normal, the ceiling
   still applies.
5. The per-row ceiling and the wall-clock trip on the same poll: the ceiling is checked
   first, so the more specific reason (`spend_ceiling`) wins over the generic stall.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| An unattended run opens a review-ready-looking PR nobody saw | a normal PR with no machine marker | the draft clause opens it as a draft with a provenance footer; a human clicks "Ready for review" |
| A single row burns huge spend inside one attempt | the row runs long but never stalls | the per-row tool-call ceiling stops it with reason `spend_ceiling` |
| A whole batch overruns effort | many rows each near the ceiling | the queue-wide ceiling aborts the remaining rows after the current one ships |
| A run under-reports its tool-call count | the ceiling never trips on a clearly expensive row | NOT DEFENDED, named honestly: self-report is a guardrail. The wall-clock timeout is the non-gameable backstop, composed OR-style |
| Junk ceiling config errors a comparison | a run refuses to launch or a `[ ]` error prints | the values are coerced to 0 at parse; a bad ceiling is simply disabled |
| The draft clause changes interactive shipping | `/kit:ship` opens drafts for a human | it cannot: the clause lives only in `_goal_line`, which the interactive path never calls |

## Out of Scope

- **Claim-leases.** SPEC-221's beat-file presence + reaper already are the lease. See
  the scope decision in `## Design`. Building a second `claimed_at` lock is the exact
  thing SPEC-221 DEC-003 rejected.
- **A real token or dollar feed.** None exists at the bash queue layer. The proxy is a
  self-reported call count; a real feed would slot into the same gate later.
- **Interrupting a tool call mid-execution.** The per-row ceiling stops a row only
  between observed turns; the launched run is `--dangerously-skip-permissions` and no
  bash wrapper can interrupt it mid-call.
- **Enforcing the draft at the `gh` layer.** The queue never runs `gh`; the draft
  default is an instruction to the run, exactly as OpenHands' `draft=True` is a
  model-overridable default, not a hard gate.

## Decision Log

- DEC-001: claim-leases are OUT of scope. Rationale: SPEC-221's `<slug>.beat` presence
  IS the in-flight claim and its reaper IS the lazy expiry, so a separate `claimed_at`
  lease is the redundant second lock SPEC-221 DEC-003 already rejected. SPEC-221's Out
  of Scope hands the ceiling work to this row by name. Decided from the merged code, not
  the survey's guess.
- DEC-002: the proxy is a SELF-REPORTED tool-call count, not a pane-scraped count or a
  token feed. Rationale: no cost feed exists at the bash layer, and `capture-pane` is a
  viewport that loses scrolled-off turns. The run already writes a status file; a count
  is the one effort number it knows cheaply. Rejected: pane scraping (unreliable),
  tokens/dollars (no feed).
- DEC-003: a spend stop reuses the `stalled` verdict and adds a distinct REASON
  (`spend_ceiling`), rather than a new verdict word. Rationale: SPEC-221's reason column
  is the shared stop-reason field; extending its values keeps every journal reader
  unchanged. This is the "EXTEND the field, do not add a second" rule.
- DEC-004: both ceilings default 0 (disabled), matching SWE-agent's
  `per_instance_call_limit=0`. Rationale: the shipped overnight behavior must not change
  until an operator opts in; a self-reported ceiling on by default would be a soft gate
  firing on a channel most runs do not fill.
- DEC-005: `_status_num` reads the MAX value, not the first (unlike `_status_get`).
  Rationale: `TOOL_CALLS` is a monotonic counter the run updates repeatedly; MAX is its
  latest value whether the run appends or rewrites. `_status_get`'s first-wins stays for
  EXIT_SIGNAL's anti-false-completion property.
- DEC-006: the per-row ceiling caps ONE ATTEMPT, not a slug's cumulative spend, and a
  `spend_ceiling` stall inherits SPEC-221's stall-ladder semantics (a real repo delta
  resets the backoff, so a progressing-but-expensive row can be re-picked on a later
  tick). Rationale: this matches SWE-agent's `per_instance_call_limit`, which is
  per-instance and stops THAT attempt, not the task's total across restarts. The
  cumulative bound within one run is `QUEUE_MAX_TOTAL_TOOL_CALLS`. A per-slug
  cumulative-across-nights ledger is deliberately out of scope: it would need the same
  persistent per-slug spend record a claim-lease needs, the scope this row avoided.
  Flagged by the security review as a design question; answered here, not code-changed.
- DEC-007: `_status_num` clamps the self-reported value to 9 digits before any compare
  (security review, MEDIUM). Rationale: the value is written by an untrusted run. An
  oversized number would otherwise error the `-ge` compare (disabling the per-row
  ceiling) and overflow the 64-bit queue-wide accumulator (spuriously aborting the whole
  batch). A 9-digit cap keeps every comparison and the summed total inside safe integer
  range while staying far above any sane ceiling.

## Open questions

(none)
