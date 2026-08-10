# SPEC-229: checker-first gauntlet rounds for #auto rows

Status: Draft · 2026-08-10 · Owner: Han
Lane: full (feeds the unattended `--dangerously-skip-permissions` runner, same
trust boundary as SPEC-217)
Relates-to: SPEC-217 (the watcher this extends), SPEC-148 (`queue run`, the
journal, the verdict grammar), `commands/gauntlet.md` + `docs/patterns/gauntlet.md`
(the engine whose round shape moves inboard), `commands/assign.md` (the intake
step that gains checker drafting), `commands/test-plan.md` + `commands/test-write.md`
(the existing checker-authorship organs this reuses), ADR-0031 (debt ledger,
unchanged)

## Problem

An `#auto` row runs one `/goal` pass and its done-line is prose. The pointer
carries acceptance criteria and a verification command, but both are interpreted
by the model at run time, inside the window. Three costs follow.

First, auto-eligibility is only the operator tag. Nothing structural separates a
row that is safe to run unattended from one that is not. The operator decides
from taste each time.

Second, the done-line is not falsifiable before work starts. The run can end
`done` on the model's own reading of prose criteria. The gated merge catches a
bad reading, but at the most expensive point: a full PR review.

Third, a failed run teaches nothing. The journal records `error` or `stalled`
with one reason string. The transcript that explains WHY is discarded.

The gauntlet already solved this shape for its own domain: a deterministic
checker defines the done-line before the run, the probe iterates against it in
bounded rounds, and every round persists a record. This spec moves that round
shape inboard, so it becomes the middle loop for every `#auto` row.

## Solution

### Approaches considered

1. **Wrap each row in the full `/kit:gauntlet` command.** Rejected: the
   onboarding gauntlet's clean room, probe fiction, and never-coach rules are
   wrong for real work in the real repo. Only the round shape transfers.
2. **Keep the single `/goal` pass and bolt a post-hoc checker onto the verdict.**
   Rejected: a checker consulted only at the end cannot gate dispatch, so the
   auto-eligibility problem stays, and a red result wastes the whole window
   instead of bounding it into rounds.
3. **A checker-first gate at the watcher plus a bounded round loop in
   `queue run`, checker authored and approved at tagging time.** Chosen.

### Chosen approach + why

The row's done-line becomes an executable checker, and the checker is not a new
artifact: it is the goal draft's own verification section, made machine-run.
The goal contract already mandates a named verification command in every
`.claude/goals/<slug>.md` draft; today the model reads and interprets it inside
the window. This spec has the machinery extract it (a labeled fenced block, see
Technical Design) and execute it: at plan time as the red-first gate, at round
scoring as the verdict. The operator approves it together with the `#auto` tag.

A row whose draft has no extractable verify block, or whose block runs green at
HEAD, is not auto-eligible and is skipped with a reason. The run is then "make
the block green" in at most 3 fresh rounds. Test-first, lifted to the row
level, with zero new files.

This converts the operator's "we already know the output we want" moment from
prose into a red test, captured once at tagging, at the cheapest possible human
touchpoint.

The checker-can-be-written test IS the auto-eligibility test. A doc-drift row
gets a trivial grep checker. A judgment row gets no honest checker, so it is
structurally excluded rather than excluded by operator vigilance.

### Extensibility & boundaries

The round cap (3) and the per-run row cap (`--max`, default 1) are the only
scale knobs, both existing. The harvest layer (mining halt transcripts to
converge the factory surface) is deliberately out of scope; this spec only
guarantees the findings it would consume are persisted, not discarded.

### Architecture

See `## Design`.

## Design

```
  _meta/BACKLOG.md row, #auto, queued
        |
        v
  +--------------------------------------+
  | watch-board.sh            (extended)  |
  |   existing gates: marker, allow-list, |
  |   journal dedup, 4000-char pre-flight |
  |   NEW gate: checker-first             |
  |     the pointer's ```check block      |
  |     extracts AND exits non-zero at    |
  |     HEAD                              |
  |     missing -> skip "no checker"      |
  |     green   -> skip "checker already  |
  |                green (done or vacuous)"|
  +--------------------------------------+
        |  slug TAB repo TAB pointer   (TSV contract unchanged;
        v                              checker found by convention)
  +--------------------------------------+
  | queue.sh run              (extended)  |
  |   per row: ROUND loop, cap 3          |
  |     round N: fresh /goal session      |
  |       (same pointer; no state carried |
  |        across rounds)                 |
  |     score: run the checker            |
  |       green -> verdict done/gated,    |
  |                exit loop              |
  |       red   -> persist round record,  |
  |                round N+1              |
  |   cap hit -> verdict stalled, reason  |
  |     "checker red after 3 rounds";     |
  |     round records persist             |
  +--------------------------------------+
        |
        v
  gated PR -> operator merge      (unchanged)
  debt ledger, journal            (unchanged)
```

### ADR link(s)

No new ADR. The change is reversible (delete the checker gate, rows fall back
to the single-pass behavior) and recorded here plus in the two command docs.

### Boundaries & failure modes

See `## Failure modes`. The round loop never edits the checker, never edits the
row, and never merges. The checker is operator-approved content; the run only
executes it.

## Technical Design

### The checker contract

- Location: INSIDE the goal draft. The pointer file (`.claude/goals/<slug>.md`)
  carries one fenced code block tagged `check` (```` ```check ````); its body
  is the checker script, run under `bash -e` from the repo root. No sibling
  file, no TSV change. This reuses the goal contract's existing mandate that
  every draft names a verification command; the delta is that the machinery
  now executes it instead of the model interpreting it.
- Extraction is the same labeled-token pattern the board already uses for
  `#queue{}`: first ```` ```check ```` fence wins; zero or two-plus fences
  means no checker (ambiguity fails safe to skip).
- Shape: exit 0 means the row's outcome holds; non-zero means it does not.
  Stdout/stderr are evidence, not protocol. Multi-line is fine; the block can
  simply run one new failing test.
- Authored at intake: `/kit:assign` writes the block into the draft for a row
  intended for `#auto`; `/kit:test-plan` + `/kit:test-write` are the organs for
  a behavioral checker.
- Approved with the tag: the operator reviews the block in the same moment
  they write `#auto` on the row. A draft without the block means the tag is
  inert, which fails safe.
- Red-first is mandatory: the watcher runs the block at plan time and refuses
  a green one. Green at HEAD means the row is already done or the checker
  asserts nothing; both are operator problems, surfaced as a skip reason, never
  burned as a paid window.
- Trust note: the block is executed unattended, but this adds no new trust
  level. The pointer already had to pass parse-board's allow-list (charset,
  repo containment, existence) to be fed verbatim into an unattended
  `--dangerously-skip-permissions` session; an operator-authored, committed,
  allow-listed file is already the trust root. The 4000-char pre-flight budget
  now includes the block, which also keeps checkers small by construction.

### The round loop

- Lives in `queue.sh` where the per-mega launch already happens; the round is a
  re-launch of the same pointer in a fresh session when the checker stays red.
- Cap 3 rounds per slug per run. No fix-agent continuation across rounds: a
  fresh session per round keeps the failure signal clean of contaminated
  context (the lane's own internal retries are unchanged and inside one round).
- Scoring is only the checker's exit code. The existing marker grammar
  (`RUNNER_DONE` / `RUNNER_GATED:`) still ends a round early, but a `done`
  marker with a red checker is scored RED and recorded as a self-report
  mismatch (this is the Goodhart tripwire, see Failure modes).
- Round record: `<log-dir>/rounds/<slug>/round-N/` holding the checker output,
  the session transcript pointer, and the verdict line. Persisted every round,
  pass or fail, same ethos as the gauntlet run-record contract.
- Terminal verdicts keep the existing journal vocabulary: `done`, `gated:*`,
  `stalled` (reason `checker-red-after-3`), `error`. No new verdict tokens, so
  the breaker, cooldown, and dedup logic need no change.

### Data model changes

None. One new fenced-block convention inside an existing file, one new log
subtree (`rounds/`), zero schema changes to the board, the TSV, or the
journal.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: checker gate in `lib/queue/watch-board.sh`: ```check block
  extraction + red-first execution, three new skip reasons (missing, green,
  ambiguous). AC: fixture rows with missing / green / red / double blocks plan
  only the red one.
- [ ] TASK-002: round loop in `lib/queue/queue.sh`: cap 3, fresh session per
  round, checker scoring, round-record persistence, `stalled` on cap. AC: a stub
  checker that goes green on round 2 yields `done` with 2 round records; one
  that never goes green yields `stalled` with 3.

### Phase 2: Core
- [ ] TASK-003: `commands/assign.md`: write the ```check block into the goal
  draft for auto-intended rows (delegating behavioral checkers to
  test-plan/test-write); state the approve-with-tag contract. AC: the greps in
  `## Verification` hit.
- [ ] TASK-004: `commands/grill.md` self-answer mode cross-reference: a
  self-answered question that would change the DONE-LINE is out of bounds; the
  checker is operator-approved content the run may not reinterpret. AC: grep
  hits.

### Phase 3: Polish
- [ ] TASK-005: `tests/test-checker-rounds.sh` covering the test plan below.
  AC: green, including both negative controls.
- [ ] TASK-006: `docs/patterns/gauntlet.md` gains a short "the round shape
  inboard" section naming this spec, so the pattern doc stays the map. AC: grep
  hits.

## After state

- [ ] An `#auto` row is dispatched only when its committed checker runs red at
  HEAD; rows without one are skipped with a reason naming this spec's gate.
  (Today: the tag alone dispatches.)
- [ ] A dispatched row runs up to 3 fresh rounds against its checker and ends
  `done`/`gated` only on a green checker. (Today: one pass, self-reported
  verdict.)
- [ ] A cap-hit row leaves 3 round records an operator (or a future harvest
  layer) can read. (Today: one journal line.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] No regressions: `bash tests/test-self-grill-watcher.sh`,
  `bash tests/test-queue-run.sh` (or the queue suite's current entry),
  `bash tests/test-meta.sh`, `bash tests/test-docs-wiring.sh`

## Verification

- `bash tests/test-checker-rounds.sh` exits 0.
- Negative control 1: a fixture `#auto` row whose draft has NO ```check
  block is skipped with the no-checker reason and never reaches the plan.
- Negative control 2: a fixture checker that exits 0 at plan time is skipped
  with the already-green reason.
- `grep -n 'checker' commands/assign.md commands/grill.md docs/patterns/gauntlet.md`
  hits all three files.
- `bash tests/test-meta.sh && bash tests/test-docs-wiring.sh` show no NEW
  failures versus master.

## Test plan

| Case | Tier | Why |
|---|---|---|
| red checker + valid pointer is planned | script | the happy gate |
| missing checker: row skipped, reason names the gate | script | negative control 1 |
| green-at-HEAD checker: row skipped, reason names vacuity | script | negative control 2 |
| two ```check blocks in one draft: row skipped, ambiguity reason | script | fail-safe extraction |
| round loop: green on round 2 ends `done`, 2 records | script | convergence path |
| round loop: red through cap ends `stalled`, 3 records | script | honest halt |
| `RUNNER_DONE` marker + red checker scores RED, mismatch recorded | script | the Goodhart tripwire |
| round records survive a `stalled` verdict | script | evidence is the point |
| checker draft quality at intake | DOCUMENTED CONTRACT, not tested | model behavior in a prompt file; its mechanical half (the doc carries the contract) is grep-tested, same limit the kit documents for grill prose |

## Edge Cases

1. Checker exists but the pointer is refused by the allow-list: the existing
   skip wins; the checker is never executed (order: cheap lexical gates first).
2. Checker mutates state (writes a temp file, starts a server): out of
   contract. The gate runs it as-is; a checker that cannot run twice
   idempotently will strand its own row at round scoring. Named in assign.md's
   drafting guidance, not defended in code.
3. Checker is slow: plan-time execution happens once per watcher run per row.
   A checker slower than ~60s is a drafting smell; guidance, not enforcement.
4. The block needs repo state to assert against (a fixture, seed data): it
   sets that up and tears it down itself, or asserts on committed state only.
   Drafting guidance in assign.md, not defended in code.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Worker games the checker instead of the intent (Goodhart) | checker green but the diff is wrong | gated merge is unchanged: the operator reviews every PR; the self-report-mismatch record flags runs whose `RUNNER_DONE` disagreed with the checker |
| Vacuous checker (always green) approved by mistake | red-first gate refuses it at plan time | the skip reason names vacuity; the row never burns a window |
| Checker red for an environmental reason (flaky test, network) | 3 rounds of identical failure output | round records carry checker output; the operator reads 3 identical logs and fixes the checker, not the row |
| Fresh rounds triple the cost of a doomed row | wall-clock per round in the round record | cap 3 bounds it; the 4000-char pre-flight and red-first gate keep known-doomed rows from launching at all |
| A self-answer rewrites the done-line mid-run | grill debt row proposing a scope change | TASK-004's rule: the checker is not reinterpretable; a run that cannot satisfy it halts honest instead of arguing with it |

## Out of Scope

- The harvest layer (mining halt records to converge pointer templates, lane
  docs, and the row-writing guide). A later spec; this one only persists what
  it would read.
- Parallel fan-out (`--max` > 1 semantics, worktree-per-row enforcement).
  Existing knob, separate hardening.
- Any change to the interactive (non-`#auto`) lanes: checker-first binds only
  where the watcher dispatches.
- The onboarding gauntlet command: unchanged; it stays the campaign-mode
  instance with its clean room and verdict semantics.

## Decision Log

- DEC-001: the checker is approved at TAGGING time, together with `#auto`, not
  lazily at dispatch. Rationale: tagging is the operator's "I know the output I
  want" moment; approving the executable form of that statement in the same
  gesture costs seconds and makes the tag mean something. Rejected: dispatch-time
  approval (re-introduces a human in the unattended path).
- DEC-002: the checker is a plain executable and its exit code is the whole
  protocol. Rationale: any framework choice would leak into every repo the
  queue serves; exit codes are universal and the gauntlet's submission checker
  already proved the shape. Rejected: a YAML assertion schema.
- DEC-003: red-first is a hard gate, not a warning. Rationale: a green checker
  at HEAD means done-already or asserts-nothing; both are free to detect and
  expensive to discover mid-window. Rejected: warn-and-run.
- DEC-004: rounds are fresh sessions with no cross-round continuation.
  Rationale: a contaminated context doubling down on a wrong approach is the
  known unattended failure mode; the gauntlet's teardown rule exists for the
  same reason. The lane's internal fix-agent retries stay, inside one round.
  Rejected: fix-agent continuation across rounds.
- DEC-005: checker scoring overrides the run's self-reported marker. Rationale:
  `RUNNER_DONE` is self-reported by an untrusted run (queue.sh already treats
  it as such); the checker is operator-approved. Disagreement is recorded, and
  the checker wins. Rejected: marker wins (re-opens the prose done-line hole).
- DEC-006: the checker lives INSIDE the goal draft as a ```check fenced
  block, not as a sibling `.check` file. Rationale (operator call 2026-08-10):
  the goal contract already mandates a verification command in every draft, so
  a sibling file would duplicate that field and drift from it; one artifact
  means one approval and the pointer stays the single unit the operator
  reviews. Extraction by labeled token matches the board's own `#queue{}`
  pattern, and the existing 4000-char pre-flight naturally bounds checker
  size. Rejected: a sibling `.check` file (second artifact, drift); a fourth
  TSV column (breaks every consumer).

## Open questions

(none)
