# Proof of done: lib/orchestrate.sh (SPEC-087 phase 1)

## Acceptance criteria (SPEC-087 phase 1)

| # | Criterion | Met |
|---|---|---|
| AC1 | Parses a mega-goal ROADMAP, finds next unchecked sub-goal + policy; real mode runs it via a fresh `claude -p`; driver holds no LLM context | yes (`lib/orchestrate.sh`; driver is bash, never an LLM) |
| AC2 | `--dry-run` prints the ordered plan + stop point without invoking `claude` | yes (test 2; no side effects) |
| AC3 | Stops at the first `gate` sub-goal; advances past `auto` only when the box flipped to `[x]` | yes (tests 3, 4) |
| AC4 | Previous `HANDOFF.md` injected into the next session's prompt; fresh run with no handoff works | yes (test 3b) |
| AC5 | `tests/test-orchestrate.sh` exercises the above incl. a negative control | yes (12 assertions) |

## Implementation

`lib/orchestrate.sh` (bash, matching the other `lib/` drivers): subcommands `next` and
`run <megagoal-dir> [--dry-run]`. It reads `ROADMAP.md` sub-goal lines
(`- [ ] SG-NN ... , auto|gate , ...`), runs each `auto` sub-goal in a fresh
`$CLAUDE_CMD -p` session (the `/clear` is free), injects the prior `HANDOFF.md`, and stops at
the first `gate`. Completion is grounded: it advances only when the sub-goal flipped its
ROADMAP checkbox. `CLAUDE_CMD` is injected so the test mocks `claude` (no real sessions).

## Confirmation run-table

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate.sh` | 0 | 12/12 PASS (`ALL PASS`) |
| `bash lib/orchestrate.sh next <real-megagoal>` | 0 | `SG-04	gate` (the real token-hygiene state) |
| `bash lib/orchestrate.sh run <real-megagoal> --dry-run` | 0 | plan: `SG-04 (gate)` then `STOP at SG-04` |
| `bash tests/test-meta.sh` | 0 | 500/500 (README lib row did not break parity) |
| (negative control) mock session that does NOT check its box | 1 | loop halts: "did not check its ROADMAP box" |

Verdict: PASS (Exit: 0 on the suite; the negative control is RED-by-design at Exit: 1).

## Run detail (captured 2026-06-29)

```
$ bash tests/test-orchestrate.sh
PASS next -> SG-01 auto
PASS dry-run lists SG-01, SG-02, STOP at gate SG-03
PASS dry-run did not execute anything
PASS run exited 0
PASS auto SG-01 + SG-02 boxes flipped
PASS gate SG-03 left unchecked (stopped)
PASS stopped at gate with message
PASS HANDOFF.md written for the next sub-goal
PASS handoff injected into SG-02's prompt but not SG-01's
PASS negative control: run halts nonzero when box not flipped
PASS negative control: explains the halt
PASS negative control: SG-01 stays unchecked
----
ALL PASS                                         # Exit: 0
```

## NEGATIVE CONTROL

Test 4 injects a mock `claude` that does work but does NOT flip the sub-goal's ROADMAP box.
The orchestrator detects the unflipped box and halts with Exit: 1
("did not check its ROADMAP box; halting (no self-claim)"), leaving SG-01 unchecked. So the
grounded-completion check actually gates advancement rather than trusting a session's word; a
session that silently no-ops cannot make the loop march on.

## Reproduce

```
cd <dwarves-kit>
bash tests/test-orchestrate.sh
bash lib/orchestrate.sh run ~/workspace/tieubao/ops-toolkit/_meta/megagoals/token-hygiene --dry-run
```

## Review-fix addendum (2026-06-29, PR #81 review)

Applied the review findings; the suite grew from 12 to 15 assertions, all green; shellcheck clean.

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate.sh` | 0 | 15/15 PASS (`ALL PASS`) |
| `shellcheck lib/orchestrate.sh` | 0 | CLEAN |

New coverage: permission posture default + override (2 assertions); goal-file CONTENT injection
into the prompt (1 assertion, closes the path-vs-content gap); policy parser hardened to
exact-field match, unknown fail-safes to `gate`. NEGATIVE CONTROL still green. Verdict: PASS.

## SG-01 addendum: run-modes `--step` + `--stream` (2026-06-29, token-optim-v2)

Adds two opt-in observability mechanisms (SPEC-087 Mechanism A): `--step` (pause for the operator
after each completed auto sub-goal, resume on Enter / `q` to stop) and `--stream` (stream each
session as stream-json, tee'd to `.orchestrate/<id>.stream.jsonl` for a live tail + capture).
Both off by default => the default invocation is byte-identical.

### Acceptance criteria (SG-01)

| # | Criterion | Met |
|---|---|---|
| AC1 | `--step` pauses after each sub-goal, resumes on Enter, `q` stops cleanly (exit 0) | yes (tests 9b, 9c) |
| AC2 | `--step --dry-run` plan shows the pause points, no claude invoked | yes (test 9a) |
| AC3 | `--stream` streams live AND captures to `.orchestrate/<id>.stream.jsonl` | yes (test 10) |
| AC4 | default (no `--step`/`--stream`) behavior unchanged; the `/goal` loop + Stop hook untouched | yes (test 9d, all prior tests green) |
| AC5 | unknown `--flag` rejected (exit 64) | yes (test 10) |

### Confirmation run-table

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate.sh` | 0 | 34/34 PASS (`ALL PASS`; was 15, +19 for run-modes) |
| `shellcheck lib/orchestrate.sh` | 0 | CLEAN |
| `bash tests/test-meta.sh` | 0 | 500/500 (README lib row parity held) |
| `bash lib/orchestrate.sh run <megagoal> --step --dry-run` | 0 | plan annotated with `(--step: pause ...)` |
| (negative control) default run, stdin closed | 0 | no pause prompt; auto chain runs unchanged |

### Run detail: captured `--step` + `--stream` terminal slice (2026-06-29)

```
[orchestrate] running SG-01 in a fresh session (... -p, model: inherit, effort: inherit) ...
[orchestrate] streaming SG-01 -> .../.orchestrate/SG-01.stream.jsonl (live tail + captured)
{"type":"assistant","text":"working on SG-01"}
{"type":"result","sg":"SG-01"}
[orchestrate] SG-01 complete (box checked); advancing.
[orchestrate] --step: SG-01 done. [Enter]=continue  q=stop:        # <- PAUSED here; operator hits Enter
[orchestrate] running SG-02 in a fresh session ...                 # <- RESUMED
[orchestrate] streaming SG-02 -> .../.orchestrate/SG-02.stream.jsonl (live tail + captured)
{"type":"assistant","text":"working on SG-02"}
{"type":"result","sg":"SG-02"}
[orchestrate] SG-02 complete (box checked); advancing.
[orchestrate] STOP: SG-03 is a gate sub-goal; ...                  # <- gate-stop, no redundant pause
```

Captured `.orchestrate/SG-01.stream.jsonl`:
```
{"type":"assistant","text":"working on SG-01"}
{"type":"result","sg":"SG-01"}
```

### NEGATIVE CONTROL (SG-01)

Test 9d runs the default loop (no `--step`, stdin closed via `</dev/null`) and asserts NO `--step:`
prompt appears while the auto chain still completes (SG-02 box flips). So the pause is genuinely
gated on the flag, not always-on; an unattended `run` cannot deadlock waiting on a keypress.

Verdict: PASS (Exit: 0 on the suite; pause-gating proven by the default-mode negative control).

## SG-10 addendum: board-view / event-sourced status (2026-06-29, token-optim-v2)

Adds `--board=roadmap|kanban|both` (default detects: `backlog.sh` present -> `both`, else
`roadmap`). In kanban/both the loop emits append-only status EVENTS to
`<dir>/.orchestrate/events.log` and DERIVES a per-mega-goal `<dir>/BOARD.md` by replay (last
event per sub-goal wins, never mutated in place). `BOARD.md` is a `backlog.sh`-format kanban
table, rendered via `lib/backlog.sh`. ROADMAP.md + the goal files stay canonical; the repo-wide
BACKLOG cockpit is never touched. Stacked on SG-01 (`feat/orchestrator-run-modes`).

### Acceptance criteria (SG-10)

| # | Criterion | Met |
|---|---|---|
| AC1 | `--board=roadmap\|kanban\|both`, default detects (backlog.sh -> both, else roadmap) | yes (tests 11a, 11b) |
| AC2 | kanban/both derives `<dir>/BOARD.md` via `backlog.sh`; repo BACKLOG untouched | yes (11a, 11d) |
| AC3 | Status is event-sourced: events appended, board derived by replay (never mutated) | yes (11e) |
| AC4 | States distinguish shipped / ready / blocked(reason) [+ stalled, emitted by SG-11] | yes (11d) |
| AC5 | roadmap-only fallback when no kanban tooling; explicit `--board=roadmap` suppresses | yes (11b, 11c) |
| AC6 | ROADMAP.md stays canonical (no Done=/close-the-loop in board rows) | yes (board carries id/title/notes/status only) |

### Confirmation run-table

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate.sh` | 0 | 43/43 PASS (+9 for board-view) |
| `shellcheck lib/orchestrate.sh` | 0 | CLEAN |
| `bash tests/test-meta.sh` | 0 | 500/500 |
| `bash lib/orchestrate.sh run <fixture> --board=both --dry-run` | 0 | both surfaces; no repo BACKLOG / events written |

### Run detail: `--board=both --dry-run` (deps fixture, captured 2026-06-29)

ROADMAP: SG-01 `[x]`; SG-02 `[ ]` (no deps); SG-03 `[ ]` depends SG-01+SG-02; SG-04 `[ ]`
depends SG-09.

```
[plan] mega-goal: <fixture>
  -> SG-02 (auto)  ...
  -> SG-03 (gate)  ...
  == STOP at SG-03 (gate: human review) ==

[board mode: both]
[board] derived per-mega-goal view -> <fixture>/BOARD.md (ROADMAP stays canonical)
queued:
  SG-02  second lever
shipped:
  SG-01  first lever
parked:
  SG-03  needs the first two
  SG-04  blocked on missing
```

Derived `BOARD.md` (event-replay falls back to ROADMAP + dep-analysis when no events yet):
```
| ID | Item | Notes & source | Status |
|----|------|----------------|--------|
| SG-01 | first lever         | auto | shipped |
| SG-02 | second lever        | auto | queued [ready] |
| SG-03 | needs the first two | gate | parked [blocked: needs SG-02] |
| SG-04 | blocked on missing  | auto | parked [blocked: needs SG-09] |
```

Note SG-03 blocks only on the ONE unchecked dep (SG-02), not the checked SG-01 -- dep-analysis
reads the ROADMAP checkboxes. dry-run wrote NO `.orchestrate/events.log` (no execution).

### Event-replay detail (real run via the good mock, `--board=both`)

```
$ cat <dir>/.orchestrate/events.log
<ts>  SG-01  executing  model=inherit effort=inherit
<ts>  SG-01  shipped    box checked
<ts>  SG-02  blocked    gate: human review
```
The derived `BOARD.md` then shows `SG-01 ... shipped` by replay. The append-only log is the
progress signal SG-11's watchdog reuses (goal 11 "reuse SG-10's event log").

### NEGATIVE CONTROL (SG-10)

Test 11b points `BACKLOG_LIB` at a non-existent path: detection fail-safes to `roadmap`, no
`BOARD.md` is written, and no board output appears. So the board is genuinely gated on the
tooling being present (a kit without `backlog.sh` still runs), and `--board=roadmap` (11c)
suppresses it even when present. Unknown `--board=bogus` is rejected (exit 64, test 11f).

Verdict: PASS (Exit: 0 on the suite; tooling-gating + ROADMAP-canonical proven by 11b/11c).

## SG-11 addendum: loop robustness (2026-06-29, token-optim-v2)

Adds an advisory stall-watchdog + PID-liveness + a tool-baked guardrail to `lib/orchestrate.sh`.
`WATCHDOG_STALL_SECS=0` (default) keeps the synchronous run path UNCHANGED; `>0` backgrounds each
session and polls liveness (`kill -0`, no daemon) + the session-log mtime. A session with no
output for `WATCHDOG_STALL_SECS` while its process is alive is flagged `stalled` (event + WARN)
and NOT killed (advisory). A dead/incomplete session never advances its box. Branched off master
after SG-01 (#86) + SG-10 (#87) merged; reuses SG-10's event log.

### Acceptance criteria (SG-11)

| # | Criterion | Met |
|---|---|---|
| AC1 | Stalled-watchdog: no progress in N -> flagged `stalled` (event + advisory WARN, no kill) | yes (test 12a) |
| AC2 | PID-liveness probe (no daemon); dead session reconciled -> box not advanced | yes (test 12b) |
| AC3 | Tool-baked guardrail warns on a wrong move (sub-goal with no goal file) | yes (test 12c) |
| AC4 | Watchdog advisory/reversible by default; default (off) behavior unchanged | yes (test 12d) |

### Confirmation run-table

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate.sh` | 0 | 48/48 PASS (+5 for robustness) |
| `shellcheck lib/orchestrate.sh` | 0 | CLEAN |
| `bash tests/test-meta.sh` | 0 | 500/500 |

### Run detail: watchdog flags a stall but does not kill (captured 2026-06-29)

Mock emits nothing for ~3s (pid alive) then flips its box; `WATCHDOG_STALL_SECS=1`:

```
[orchestrate] [guardrail] WARN: SG-01 has no goals/ file; session runs without its contract ...
[orchestrate] [watchdog] SG-01: output -> .../.orchestrate/SG-01.session.log (stall=1s, poll=1s; advisory, never kills)
[orchestrate] [watchdog] WARN: SG-01 stalled -- no output for 1s, pid 86522 still alive. Not killing (advisory); ...
[orchestrate] SG-01 complete (box checked); advancing.

$ cat .orchestrate/events.log
<ts>  SG-01  executing  model=inherit effort=inherit
<ts>  SG-01  stalled    no output for 1s (pid 86522 alive)
<ts>  SG-01  shipped    box checked
```

The `stalled` event is recorded AND the session is left to recover (advisory). The event log is
the SG-10 record SG-11 appends to (goal 11 "reuse SG-10's event log").

### NEGATIVE CONTROL (SG-11)

Test 12b runs a session that exits nonzero under the watchdog: the loop halts (rc!=0), the box is
NOT advanced, and a `blocked` event is recorded -- a dead session cannot self-claim completion.
Test 12d proves the watchdog is genuinely gated: with `WATCHDOG_STALL_SECS` unset (0), no
`[watchdog]` line appears and the synchronous chain runs unchanged, so an interactive run pays no
background-process cost.

Verdict: PASS (Exit: 0 on the suite; advisory-not-fatal proven by 12a recovery, dead-session
reconciliation by 12b, default-off by 12d).
