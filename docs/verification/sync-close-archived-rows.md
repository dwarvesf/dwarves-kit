# Verification -- sync-close-archived-rows

`board sync` closes a linked spoke card when an archive pass moved its board row out of
`BACKLOG.md`, and only when the archive carries that id with a closed status.

## Green run

```
Command: bash tests/test-sync.sh
Exit: 0
Verdict: 282 passed in 4.74s (274 before this branch, 8 new cases plus a read_archive case)
```

New cases: archived `shipped` closes, archived `dropped` closes, absent from board and
archive plans no close and keeps the orphan note, an archive row with an open status
plans no close, a missing archive file plans no close and does not crash, an EMPTY board
with a 50-entry state map plans zero closes, a tombstoned / scoped-out / already-done
card is untouched, and a live active row still flows from the row rather than a stale
archive copy.

## Negative control

```
Command: bash tests/test-sync.sh, with the archive-evidence check replaced by
         `arch = (archived or {}).get(bid) or Row(bid, "", "shipped", 0)`
Exit: 1
Verdict: 4 failed, 278 passed
```

Failures with the evidence requirement dropped:

```
FAILED lib/sync/tests/test_core.py::test_absent_from_board_and_archive_never_closes
FAILED lib/sync/tests/test_core.py::test_archived_row_with_an_open_status_never_closes
FAILED lib/sync/tests/test_core.py::test_missing_archive_file_closes_nothing_and_does_not_crash
FAILED lib/sync/tests/test_core.py::test_empty_board_with_a_full_state_map_plans_zero_closes
       AssertionError: Left contains 50 more items, first extra item: ('r0', 'shipped')
```

The mass-complete case is the load-bearing one: an empty board with a full state map
planned 50 card closes without the evidence rule. The check was restored by the reverse
edit, and the suite went back to 282 passed.

## Live dry run (read-only)

```
Command: python3 lib/sync/backlog_sync.py \
           --backlog ~/workspace/tieubao/ops-toolkit/_meta/BACKLOG.md \
           --apps reminders --dry-run
Exit: 0
Verdict: dry-run reminders: 56 spoke items, 128 board rows; 0 archive-driven closes
```

The archive resolved and parsed (752 rows from `_meta/BACKLOG-archive.md`), and 175 of
the 180 state-map ids sit there with a closed status. None closed, because every one of
those map entries points at a Reminders card that no longer exists, so the planner never
reaches the close branch. The 53 cards the run still reports as orphans were never linked
in the map at all.

## Not proven

- No apply run. Nothing was written to any Reminders list, board file, or state file.
- A card whose id was NEVER linked in the state map still stays open. That case wants its
  own bulk cap, since one tick would close every such card at once, so it is left out of
  this change deliberately.
- Notion, Hermes, Multica, and GitHub spokes share the planner and therefore the rule, but
  only the Reminders spoke was exercised live.
