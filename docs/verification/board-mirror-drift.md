# Proof of done: the Hermes mirror archives closed rows and moves drifted cards

## What changed

The mirror (`lib/board/board-mirror.sh`) closed a removed row with `hermes kanban complete`. Hermes refuses `complete` on a `triage` card ("unknown id or terminal state"), and `cmd_apply_plan` read that refusal as "already terminal": it reported `done` and dropped the snapshot line. The card stayed open and never re-entered the diff. On the live `ops-toolkit` board that left 251 of 329 open cards on rows that were shipped, dropped, or archived.

A CHANGE also recorded the new status without moving the card, so a row later parked or claimed kept its card in `triage` while the snapshot said otherwise (20 live cards).

Now a card leaves the board by `archive` (works from every live state, parents or not), a status move is its own op (`block`, `promote`, or archive plus create across `triage`), a failed move is recorded as not moved and planned again, and a create that hits a card an older mirror completed archives it first. `lib/sync/cockpit.py` carries the same plan.

## Gate table

| Claim | Evidence |
|---|---|
| a shipped, dropped, or vanished row plans an `archive`, never `complete` | NC5, NC9 in the run table |
| a card in the wrong state is moved: block, promote, or replace across triage | NC9 |
| a refused move is recorded as not moved and retried next tick | NC9b |
| a refused `complete` is an error, not "already terminal" | NC8 |
| second tick plans nothing; archived rows never come back | NC9 |
| a create that hits an old done card archives it and creates a fresh one | NC9c |
| the suite catches the old behavior | negative control below |
| the whole flow works on the real `hermes` CLI | rehearsal below |

## Run table

```
Command: bash tests/test-board-mirror.sh
Exit: 0
TOTAL: 107   PASS: 107   FAIL: 0   SKIP: 0
Verdict: PASS
```

```
Command: bash tests/test-board-writeback.sh
Exit: 0
TOTAL: 70   PASS: 69   FAIL: 0   SKIP: 1
Verdict: PASS
```

```
Command: uv run --with pytest python -m pytest lib/sync/tests/test_cockpit.py -q
Exit: 0
73 passed in 0.21s
Verdict: PASS
```

```
Command: bash tests/test-no-scattered-ids.sh
Exit: 0
test-no-scattered-ids: all 9 passed
Verdict: PASS
```

`bash tests/run-all.sh --changed` runs 28 suites and fails one, `test-config-registry` ("0 orphans on the live tree", "declared root-only keys"). It fails the same way on an untouched master checkout, so it is not caused by this branch.

## Negative control

The new suite run against the previous `board-mirror.sh` and `board.sh` (checked out from master over the branch, then restored):

```
Command: git checkout master -- lib/board/board-mirror.sh lib/board/board.sh && bash tests/test-board-mirror.sh
Exit: 1 (RED expected)
TOTAL: 107   PASS: 73   FAIL: 34   SKIP: 0
Restore: git checkout HEAD -- lib/board/board-mirror.sh lib/board/board.sh
Verdict: PASS
```

The 34 failures cover NC5 (archive, not complete), NC8 (a refused complete stays an error), and every NC9 case (moves, replace, retry, idempotence, no resurrection, ghost done card).

## Rehearsal on the real CLI

`tools/board-sync/tests/rehearse-board-mirror-drift.sh` in ops-toolkit runs the old mirror, moves rows in the hub, runs the old mirror again, runs the cleanup, then runs this branch's mirror twice, all against the real `hermes kanban` on a throwaway home.

```
Command: KIT_OLD=<master checkout> KIT_NEW=<this worktree> bash tools/board-sync/tests/rehearse-board-mirror-drift.sh
Exit: 0
old tick: board-mirror: complete fixR:R-4 (t_7c460583): card gone or already terminal, recording done
old tick: open cards R-1 triage, R-2 triage, R-3 ready, R-4 triage, R-5 blocked, R-6 triage
new tick: mirror: plan 3 ops (3 create, 0 change, 0 move, 0 archive), 1 unchanged
hub wants: R-1:ready R-2:blocked R-3:blocked R-5:blocked
board has: R-1:ready R-2:blocked R-3:blocked R-5:blocked
second new tick: mirror: plan 0 ops (0 create, 0 change, 0 move, 0 archive), 4 unchanged
Verdict: PASS
```

R-4 and R-6 were shipped and dropped in the hub; the old mirror left both open in `triage`. R-1, R-2, R-3 had moved in the hub; the old mirror recorded the moves and did none of them.
