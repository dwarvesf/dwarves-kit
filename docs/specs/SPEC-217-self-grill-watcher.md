# SPEC-217: self-answer mode + the backlog watcher (manager-loop pilot)

Status: Draft · 2026-07-31 · Owner: Han
Lane: full (classifier said `normal`; taken heavier because the watcher feeds an
unattended `--dangerously-skip-permissions` runner, the same trust boundary
`lib/board/parse-board.sh` hardened)
Relates-to: docs/briefs/DECISION-BRIEF-factory-legibility.md §5 (board row ID-457,
the two named gaps), SPEC-146 (`board queue` + parse-board allow-list), SPEC-148
(`queue run`, the journal), ADR-0031 + SPEC-126 (the debt ledger and its weekend
reader), SPEC-207 (`/kit:wayfind`, whose "the agent never answers its own grill
questions" rule this reconciles with), ID-394 (ordering graph) and ID-401
(greenlight PR loop), both out of scope here

## Problem

A queued board row that is already understood still waits for a human to sit
down and drive the lane. Two organs are missing between the board and the
shipped PR. First, nothing enqueues a row: `queue run --from-boards` consumes
what `board queue` emits, but that emit fires only when a human runs it, and it
cannot tell an operator-approved autonomous row from any other queued row.
Second, `/kit:grill` is human-in-the-loop by contract, so an unattended run
either stalls at the first question or answers it silently. Silent answers are
the real hazard: a wrong requirement builds the wrong thing at full speed and
leaves no trace.

## Solution

### Approaches considered

1. **A new queue that reads the board directly.** Rejected: it forks the
   pointer allow-list, the journal, and the launch policy that
   `lib/board/parse-board.sh` + `lib/queue/queue.sh` already own and harden.
2. **A grill flag with no ledger write.** Rejected: it violates ID-450's rule
   outright instead of reconciling with it, and it produces exactly the silent
   answers the problem statement names.
3. **A filter in front of the shipped emit, plus a grill mode that pays for
   each self-answer with a ledger row.** Chosen.

### Chosen approach + why

The watcher is a FILTER, not a queue. It reads the board through
`lib/board/parse-board.sh` (both verbs: `rows` for the marker, `queue-rows` for
the allow-listed pointer), intersects the two on row id, dedups against the
queue's own journal, and hands the result to `queue run` in the TSV contract
that command already consumes. Nothing about pointer confinement, launch
policy, or the journal is re-implemented.

Self-answer mode is prose in `commands/grill.md`, not code, because the
interview is prose. What IS mechanical is the price: one
`gate-ledger.sh debt` row per self-answered question, `verdict=wave`, which is
the disposition `lib/learn/weekend-batch.sh` already collects.

### The reconciliation with ID-450

SPEC-207 pins "the agent NEVER answers its own grill questions" and that rule
holds unchanged for every interactive lane. Self-answer mode does not weaken
it; it pays for the exception. Three conditions make the exception auditable
rather than silent:

1. It activates only on a row the OPERATOR tagged `#auto`. The agent never
   tags a row, so it never grants itself the exception.
2. Every self-answered question lands on the debt ledger as a waved item:
   question, chosen answer, and why. `learn debt collect` surfaces it at the
   weekend paydown like any other conscious debt.
3. Nothing is answered silently. A wrong call becomes a ledgered decision the
   operator reviews, not a hidden one.

### Extensibility & boundaries

The load-bearing dimension is ROWS PER RUN, and it is capped, not scaled:
`--max` (default 1) forwards to the queue's own `--max-megas`. Widening the
pilot is an operator decision, one flag, no code change. The watcher owns one
board file; a cross-repo sweep is `board queue`'s existing job and stays there.

### Architecture

See `## Design`.

## Design

```
  _meta/BACKLOG.md
        |
        |  queued rows
        v
  +-------------------------------+
  | lib/board/parse-board.sh      |   (shipped, untouched)
  |   rows        -> id/status/text|
  |   queue-rows  -> allow-listed  |
  |                  pointer       |
  +-------------------------------+
        |                 |
        | rows            | queue-rows
        v                 v
  +-------------------------------+
  | lib/queue/watch-board.sh      |   (NEW)
  |   keep rows carrying #auto     |
  |   intersect on row id          |
  |   drop terminal slugs (journal)|
  +-------------------------------+
        |
        |  slug <TAB> repo <TAB> pointer     (the shipped TSV contract)
        v
  +-------------------------------+
  | lib/queue/queue.sh run        |   (shipped, untouched)
  |   --max-megas <cap>            |
  +-------------------------------+
        |
        v
  one /goal session per row -> the lane
        |
        |  grill runs in SELF-ANSWER mode (row carries #auto)
        v
  +-------------------------------+
  | gate-ledger.sh debt <rid>      |
  |   verdict=wave, one per Q      |
  +-------------------------------+
        |
        v
  learn debt collect  ->  weekend paydown
```

### Approaches considered + chosen

Point at `## Solution`. The design view adds no new tradeoff.

### ADR link(s)

No new ADR. The exception to ID-450 is recorded in this spec and restated in
`commands/grill.md`; it is reversible (delete the mode section, untag the row)
and therefore under the three-criteria ADR bar.

### Boundaries & failure modes

See `## Failure modes`. The watcher never writes to any BACKLOG.md, never
promotes a staged suggestion, and never merges.

## Technical Design

### Interfaces (I/O contract)

- **Inputs**: `<repo-root>/_meta/BACKLOG.md`; the queue journal resolved by
  `lib/telemetry/kit-log-dir.sh` (same file `queue run` writes).
- **Outputs**: a plan on stdout (human-readable) and, under `--apply`, a plan
  TSV at `<log-dir>/watch-board-plan.tsv` handed to `queue run`. Exit is 0 for
  an empty plan (honest-empty is a result, matching `board queue`).
- **Invariants**: the watcher never mutates a board; a row reaches the plan
  only if it is `queued` AND carries `#auto` AND passes parse-board's existing
  allow-list; dry-run never invokes the queue.

### The marker and the mode name

- Marker: **`#auto`**, an inline tag in the row's Notes cell, matching the
  board's existing `#queue` / `#u-hi` / `#f-mid` tag convention. Matched on
  word boundaries, so `#automation` is not `#auto`.
- Mode name: **self-answer mode**. Both are everyday words: an operator reading
  the row or the grill doc needs no glossary.

### Guardrails encoded in the defaults

| Guardrail | How it is enforced here |
|---|---|
| Per-run budget cap | `--max N` (default 1) forwards to `queue run --max-megas N`, the shipped knob |
| Dry-run first | dry-run is the default; `--apply` is required to enqueue |
| Full-auto is per-row opt-in | only an operator-tagged `#auto` row is ever planned |
| Gated-final merge stays default | untouched: `queue run` already treats `RUNNER_GATED:` as a terminal verdict |
| The loop never invents work | the watcher reads `queued` rows only; staging promotion stays `board promote`, a human |

### Data model changes

None. One new marker token in an existing free-text cell; one new consumer of
the existing journal and the existing debt ledger.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: `lib/queue/watch-board.sh`, plan build (parse-board reuse, marker filter, journal dedup), dry-run default, `--apply` handoff to `queue run`. AC: dry-run over a fixture board lists only the auto-tagged queued rows.
- [ ] TASK-002: wire `queue watch` into `lib/queue/queue.sh`'s dispatcher + usage. AC: `queue watch --help` reaches the new script.

### Phase 2: Core
- [ ] TASK-003: `commands/grill.md` self-answer mode section (activation, the per-question ledger write, the ID-450 reconciliation). AC: the greps in `## Verification` all hit.

### Phase 3: Polish
- [ ] TASK-004: `tests/test-self-grill-watcher.sh`. AC: green, including the empty-board negative control.

## After state

- [ ] An operator can tag one queued row `#auto` and drain it with two commands, `queue watch` then `queue watch --apply`. (Today: no path from a board row to the queue without hand-writing a TSV.)
- [ ] Every question an unattended grill answers for itself is collectible by `bash bin/learn debt collect`. (Today: an unattended grill either stalls or answers silently.)
- [ ] `bash lib/queue/watch-board.sh` over a board with no `#auto` rows prints an empty plan and exits 0.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover the happy path, the four skip classes, and the empty-board negative control
- [ ] No regressions: `bash tests/test-meta.sh`, `bash tests/test-docs-wiring.sh`

## Verification

- `bash lib/queue/watch-board.sh` (no flags, over this repo's real
  `_meta/BACKLOG.md`) lists the auto-tagged queued rows and nothing else, and
  exits 0. Today the real board carries zero `#auto` rows, so the honest real
  output is an empty plan; the positive case is proven on the fixture board in
  the test below, which mirrors the real board's row shape.
- Negative control: `bash lib/queue/watch-board.sh --board <fixture with zero
  #auto rows>` prints an empty plan and exits 0.
- `bash tests/test-self-grill-watcher.sh` (exit 0 = all checks green).
- The self-answer contract's mechanical half: `grep -n 'self-answer\|#auto\|gate-ledger.sh debt\|never answers its own' commands/grill.md` hits all four.
- `bash tests/test-meta.sh && bash tests/test-docs-wiring.sh` show no NEW
  failures versus master.

## Test plan

Tiered per the repo's behavioral-test doctrine (`docs/specs/SPEC-201`), because
the two gaps have different testable substance.

| Case | Tier | Why |
|---|---|---|
| auto-tagged queued row with a valid pointer is planned | script | real bash logic |
| auto-tagged row with no `#queue{}` pointer is skipped | script | real bash logic |
| non-auto queued row is skipped | script | real bash logic |
| auto-tagged row that is `claimed`, not `queued`, is skipped | script | real bash logic |
| `#automation` does not match `#auto` | script | word-boundary regex |
| slug whose last journal verdict is `done` or `gated` is skipped | script | dedup logic |
| slug whose last journal verdict is `error` is re-planned | script | dedup logic |
| board with zero `#auto` rows yields an empty plan, exit 0 | script | negative control |
| dry-run is the default: the queue is never invoked | script | mock seam |
| `--apply` invokes the queue with the plan file and the cap | script | mock seam |
| self-answer mode's activation, question quality, and answer quality | DOCUMENTED CONTRACT, not tested | it is model behavior in a prompt file; a fake test would assert the prose, not the behavior. The kit already documents this limit for prompt-text logic (`tests/test-grill-conditioning.sh` section B, `tests/test-design-record.sh`). Its MECHANICAL half (the doc carries the mode, the marker, the ledger verb, the reconciliation) IS grep-tested. |

## Edge Cases

1. Board file missing: print a reason to stderr, exit 0 with an empty plan (a cron must not page on a repo without a board).
2. A row carries `#auto` and a `#queue{}` token whose pointer file does not exist: parse-board skips it with a reason; the watcher reports it as skipped, never plans it.
3. Run from a git worktree: the repo identity used for the slug and for parse-board's repo self-consistency check comes from the git COMMON dir, so a worktree run produces the same slug as a main-checkout run and dedups against the same journal rows.
4. The journal does not exist yet: every eligible row is planned (nothing has run).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A self-answer is wrong and the build goes the wrong way | the weekend paydown reads a debt row the operator disagrees with | the row names question, answer, and why; the run is one row (cap 1) and its final merge is gated |
| A gated row is re-launched forever | the same slug appears in the plan after every gated run | dedup treats `done` AND `gated` as terminal; only `error`/`stalled`/`skipped` are re-planned |
| A hand-edited Notes cell smuggles a path into an unattended session | a pointer outside the allow-listed dirs | unchanged: parse-board's charset, repo self-consistency, containment, and existence gates all still apply, plus `queue run`'s own second allow-list pass |
| The watcher drains more than intended | more than one window opens | `--max` default 1, forwarded to `--max-megas` |

## Out of Scope

- ID-394 (the ordering graph) and ID-401 (the greenlight PR loop): named deps of the umbrella, built on their own rows.
- Any cron, launchd, or daemon wiring. The pilot is manual invocation.
- Cross-repo scanning (`board queue` already does that).
- Auto-promotion of retro suggestions. `board promote` stays a human.
- Any change to the interactive grill contract.

## Decision Log

- DEC-001: the marker is `#auto` in the Notes cell, not a new column or a separate registry file. Rationale: the board already carries inline tags (`#queue{}`, `#u-hi`) and every reader parses them; a new column breaks every existing parser. Rejected: a `_meta/auto-rows.txt` registry (a second source of truth that drifts from the board).
- DEC-002: dedup keys on the LAST journal verdict, not merely on the presence of a `done` row. Rationale: gated-final merge is the DEFAULT, so a `gated` row is the common terminal state; a `done`-only rule would re-launch every gated row on every watcher run. Rejected: skipping any slug with any journal row at all (an `error` row would then never be retried).
- DEC-003: self-answer mode ships as prose in `commands/grill.md` with a mechanical ledger obligation, not as a flag on a new script. Rationale: the interview is a prompt; the only part a machine can enforce is the debt row, and `gate-ledger.sh debt` already exists. Rejected: a `--self-answer` CLI wrapper (a second surface that cannot make the model behave anyway).
- DEC-004: `learn debt collect` reads the LAST debt line per rid, so a run that self-answers five questions surfaces once in the digest, with the full five in that rid's run ledger file. Accepted rather than changing the reader: the collect digest is an index into the ledger, and every row is `verdict=wave` so the last line is always collectible.

## Open questions

(none)
