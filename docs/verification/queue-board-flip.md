# Verification -- queue-board-flip

Two changes to the overnight queue. A run that ends `done` or `gated` now moves its BACKLOG row (`done` to `executing`, `gated` to `parked`, only from `queued`). The stale-window reaper now reuses the conductor's `_run_delta`, so a dead beat with `EXIT_SIGNAL: true` and a real delta records `done`. Both touch stored board state, so this is a stateful change (see Rollback).

## Green run

New suites, written first and run red before the code (33 of 50 passed on the first run, 17 red), then green:

```
Command: bash tests/test-queue-board-flip.sh
Exit: 0
Output:
  PASS F13: a later run is not skipped by the earlier flip's dirty board
  PASS F13 NC: a human edit on top of the flip is still a dirty tree
  === 34/34 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-reaper-delta.sh
Exit: 0
Output:
  PASS C1: the conductor removes the launch record when the run ends
  === 18/18 passed, 0 failed ===
Verdict: PASS
```

Every suite that references the touched files (`bin/test-affected --list`), plus the two guards a new suite can trip:

```
Command: bash tests/test-queue.sh; bash tests/test-runaway-guards.sh; bash tests/test-self-grill-watcher.sh
Exit: 0
Output:
  test-queue: all 31 passed
  === 48/48 passed, 0 failed ===
  === 38/38 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/test-cheap-guards.sh; bash tests/test-notes-sanitization.sh; bash tests/test-operator-pin.sh; bash tests/test-config-registry.sh
Exit: 0
Output:
  === 23/23 passed, 0 failed ===
  === 52/52 passed, 0 failed ===
  operator-pin: 4 passed, 0 failed
  === 60/60 passed ===
Verdict: PASS
```

```
Command: bash lib/registry/feature-registry.sh check
Exit: 0
Output:
  feature-registry: docs/reference/FEATURES.md is fresh
Verdict: PASS
```

The new cases drive the real `queue.sh run` through the stub mux against a real git repo with a real `_meta/BACKLOG.md`, and read the row back through `backlog.sh get`. Part 2 drives the real `watch-board.sh` reaper over a dead beat.

## Negative control

Each mutation applied to the committed code, the new suite run, then restored with `git checkout --`:

```
Command: remove the _board_flip_terminal call in cmd_run; bash tests/test-queue-board-flip.sh
Exit: 1 (RED expected)
Output:
  FAIL F1: a done run moves the queued row to executing (expected 'executing', got 'queued')
  FAIL F2: a gated run moves the queued row to parked (expected 'parked', got 'queued')
  === 23/34 passed, 11 failed ===
Verdict: PASS (RED under mutation)
```

```
Command: make _status_porcelain ignore the recorded flip hash; bash tests/test-queue-board-flip.sh
Exit: 1 (RED expected)
Output:
  FAIL F11: row 2 is NOT gated by row 1's board edit (expected 'done', got 'skipped')
  FAIL F13: a later run is not skipped by the earlier flip's dirty board (expected 'done', got 'skipped')
  === 29/34 passed, 5 failed ===
Verdict: PASS (RED under mutation)
```

```
Command: stop the reaper calling _run_delta (if false && ...); bash tests/test-reaper-delta.sh
Exit: 1 (RED expected)
Output:
  FAIL R1: dead beat + EXIT_SIGNAL true + real delta journals done (expected 'done', got 'gated')
  FAIL R1: the board row follows to executing (expected 'executing', got 'parked')
  === 15/18 passed, 3 failed ===
Verdict: PASS (RED under mutation)
```

```
Command: drop the reaper's _protected_touched check; bash tests/test-reaper-delta.sh
Exit: 1 (RED expected)
Output:
  FAIL R6: a protected-path delta is gated, not done (expected 'gated', got 'done')
  === 16/18 passed, 2 failed ===
Verdict: PASS (RED under mutation)
```

The healthy-case controls stay green in the unmutated run: a row a human moved to `claimed` is left alone (F4), `stalled` and `skipped` leave the row `queued` (F5, F6), a hand-authored slug makes no noise (F7), a dead beat with no delta, no launch record, a REASON, or no EXIT_SIGNAL keeps today's verdict (R2 to R5).

## Measurement

Old logic against the real journal under `~/.local/state/dwarves-kit/logs` (counts only; the Mini resolves to the same host and shows the same file):

```
Command: awk over queue-journal.tsv (rows, verdict, board-shaped slug count)
Exit: 0
Output:
  journal rows: 1
  stalled: 1   (board-shaped slugs: 0)
  terminal verdicts left on a queued row: 0 (old), rows the new logic would flip: 0
  queued rows carrying #queue{} on the ops-toolkit and dwarves-kit boards: 0 and 0
Verdict: PASS (no stored state changes on this host; the journal is a single hand-run stalled row)
```

## Rollback

The change writes one new kind of stored state: BACKLOG rows moved to `executing` or `parked` with a note, plus `board-flips.tsv` and `<slug>.launch` under the queue run dir.

- Code: revert the three commits; the flip, the launch record and the reaper delta all go away together. The journal format is unchanged, so a journal written by the new code reads fine on the old code.
- Rows: a flipped row is a normal board row. Move it back with `bash lib/board/backlog.sh set <ID> queued` (a flip note stays in the cell; delete it by hand if unwanted). The journal still holds the terminal verdict, so a row set back to `queued` is not relaunched; clear its journal row to re-run it.
- Sidecars: `board-flips.tsv` and `*.launch` under `<log-dir>/queue-runs/` are safe to delete. Without `board-flips.tsv` the queue goes back to treating a flipped, uncommitted board as a dirty tree.
