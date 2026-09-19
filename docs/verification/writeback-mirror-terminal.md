# Proof of done: writeback skips a card whose `done` state the mirror itself produced

## The defect

A live `board writeback --dry-run` proposed moving ops-toolkit rows ID-650 and ID-538 to
`shipped`. Both rows are still live on main. The moves came from cards the MIRROR itself
completed: its COMPLETE op ran `kanban complete <id> --result "board-mirror: origin removed
from <repo> board"` after a stale feed made the git rows look gone, and a later re-create
upsert left the snapshot pointing at the done cards with an intended column. live=done vs
snapshot=<intent> looked exactly like a human finishing the work, so the reverse map's
`done -> shipped` proposed writing it back.

## The fix

The provenance marker already exists: the mirror stamps its COMPLETE `--result` with the
`board-mirror:` prefix, and hermes stores that text verbatim on the task (`.task.result`)
plus its first line on the `completed` event's `payload.summary`. No new marker was invented.

`lib/board/board-writeback.sh` now fetches the card's `kanban show --json` document ONCE per
candidate row (`_card_show`, previously `_created_native` made its own call) and derives both
provenance checks from it. `_mirror_terminal` exits true when the card's recorded result or
completion summary starts with `board-mirror:`; a `done` card that matches is skipped with a
named reason, after the blocked rule and before the reverse map. Hermes unable to answer
degrades to the prior behavior, same as the create-state check.

## Gate table

| Claim | Evidence |
|---|---|
| a mirror-completed `done` card yields zero changes and one named skip | AC8, run table below |
| a human-completed `done` card still yields one change | AC8, run table below |
| the skip is reported per card and counted as skipped, not as a change | AC8, run table below |
| the whole suite still holds | run table below |
| the guard is load-bearing | negative control below |

## Run table

```
Command: bash tests/test-board-writeback.sh
Exit: 0
TOTAL: 70   PASS: 69   FAIL: 0   SKIP: 1
Verdict: PASS
```

```
Command: bash tests/test-board-mirror.sh && bash tests/test-board.sh
Exit: 0 both
mirror: TOTAL: 76  PASS: 76   board: TOTAL: 51  PASS: 50  SKIP: 1
Verdict: PASS
```

## Negative control

```
Command: bash tests/test-board-writeback.sh, with the lib fix stashed
         (git stash push -- lib/board/board-writeback.sh)
Exit: 1
TOTAL: 70   PASS: 65   FAIL: 4   SKIP: 1
  FAIL AC8: exactly ONE changeset entry (the human-completed card only)
  FAIL AC8: the mirror-completed cards (ID-001, ID-003) produce ZERO changeset entries
  FAIL AC8: the mirror-terminal skip is reported by name for BOTH mirror-completed cards
  FAIL AC8: the summary counts the two mirror-completed rows as skipped, not as changes
  PASS AC8: the human-completed card (ID-002) still writes back claimed -> shipped
Restore: git stash pop
Exit: 0 (green after restore)
Verdict: PASS
```

The case that stays green under the mutation is the control on the control: the fix must not
suppress a genuine human completion.

## Live run

Deliberately NOT run here: `board writeback` resolves the mirror snapshot and every target
BACKLOG.md against the MAIN checkouts, so the verifying dry-run and the apply both belong to
the lead session, not a worker worktree. The fixture in AC8 reproduces the phantom's exact
data shape (snapshot records an intended column, live card is `done`, `.task.result` carries
`board-mirror: origin removed from <repo> board`).

## Not fixed here

- The mirror still completes a card when a stale feed makes a live git row look gone. That is
  the feed problem (ops-toolkit ID-943), not a writeback problem; this fix only stops the
  phantom from landing on git.
- A human who literally writes a `board-mirror:`-prefixed result text, or who edits the
  result of a mirror-completed card via `edit-result`, changes what the marker says. The
  `completed` event's `payload.summary` is checked alongside `task.result` so an edited
  result still reads as mirror-originated; a hand-forged marker is accepted as a known edge.
- A card the mirror completed and a human later REOPENED is not skipped (live status is not
  `done`): a reopen is real human intent and still writes back.
