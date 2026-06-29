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
