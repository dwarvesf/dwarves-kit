# Verification -- sync-close-archived-rows

`board sync` closes a linked spoke card when an archive pass moved its board row out of
`BACKLOG.md`, and only when the archive carries that id with a closed status.

Two independent guards stand between an archive pass and a mass close: the evidence rule
(no archive row with a closed status, no close) and the bulk cap (more than
`MAX_ARCHIVED_CLOSES` closes in one tick refuses the whole batch).

## Green run

```
Command: bash tests/test-sync.sh
Exit: 0
Verdict: 290 passed in 0.92s (274 before this branch)
```

Cases: archived `shipped` closes; archived `dropped` closes; absent from board and archive
plans no close and keeps the orphan note; an archive row with an open status plans no
close; a missing archive file plans no close and does not crash; an EMPTY board with a
50-entry state map plans zero closes; tombstoned / scoped-out / already-done cards
untouched; a live active row still flows from the row rather than a stale archive copy;
`shipped:`, `shipped/dropped`, and `shipped [#12]` all read as closed; closes at the cap
pass, one over the cap plans none and prints the refusal, the override plans them all; an
id in BOTH the archive and the active board closes nothing; a duplicate id inside the
archive takes the first occurrence; a relative archive path resolves against the board's
directory; an archive that is a directory or a binary file degrades to no evidence.

## Negative control 1: drop the evidence rule

```
Command: bash tests/test-sync.sh, with the archive-evidence check replaced by
         `arch = (archived or {}).get(bid) or Row(bid, "", "shipped", 0)`
Exit: 1
Verdict: 3 failed, 287 passed

FAILED lib/sync/tests/test_core.py::test_absent_from_board_and_archive_never_closes
FAILED lib/sync/tests/test_core.py::test_archived_row_with_an_open_status_never_closes
FAILED lib/sync/tests/test_core.py::test_missing_archive_file_closes_nothing_and_does_not_crash
```

The 50-id mass-complete case now PASSES with the evidence rule broken, because the bulk
cap refuses the batch on its own. That is the second guard doing its job; before the cap
existed the same edit failed that test with 50 planned closes. Restored by the reverse
edit, back to 290 passed.

## Negative control 2: drop the bulk cap

```
Command: bash tests/test-sync.sh, with the cap condition forced off
         (`if False and len(closes) > close_cap:`)
Exit: 1
Verdict: 1 failed, 289 passed

FAILED lib/sync/tests/test_core.py::test_archived_closes_one_over_the_cap_plan_none
       AssertionError: Left contains 21 more items, first extra item: ('r0', 'shipped')
```

Restored by the reverse edit, back to 290 passed.

## Live dry run (read-only)

```
Command: python3 lib/sync/backlog_sync.py \
           --backlog <a consumer repo>/_meta/BACKLOG.md \
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
- A card whose id was NEVER linked in the state map still stays open. Left out of this
  change deliberately; it would reuse this cap but needs its own identity check, since no
  board row survives to compare the card's title against.
- The bulk cap was exercised by unit cases only. No live run has yet crossed it, because
  the live board plans zero archive-driven closes today.
- Notion, Hermes, Multica, and GitHub spokes share the planner and therefore the rule, but
  only the Reminders spoke was exercised live.
