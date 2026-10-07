# Proof of done: spoke cards of archived rows close or go quiet after the first tick

## What changed

`build_state` drops a card's snapshot map entry once its row leaves `BACKLOG.md`. The archive-driven close (dwarves-kit #686) only looked at map-linked cards, so it ran on exactly one tick. After that, every card for an archived row logged `orphan item (no board row)` on every tick, and an open card whose close was missed or refused stayed open for good.

`plan_sync` now resolves title-prefix orphans against the archive as well:

| Card | Archive row | Result |
|---|---|---|
| done | closed (`shipped`, `dropped`, `done`, `resolved`) | settled: no write, no note |
| open | closed, title text agrees | closes on the spoke, under the same 20-per-tick cap |
| open | closed, title text disagrees | orphan note, no close |
| any | missing, or still open | orphan note, no close (absence is never evidence) |

The page stays in the spoke with its closed status. The sync never trashes a page.

## Gate table

| Claim | Evidence |
|---|---|
| a done card for an archived closed row plans nothing and notes nothing | `test_done_card_for_an_archived_closed_row_is_quiet` |
| an open card closes after its map entry is gone | `test_open_card_for_an_archived_row_closes_after_the_map_entry_is_gone` |
| a prefix-only close needs the archive title to agree | `test_prefix_only_close_needs_the_archive_title_to_agree` |
| true orphans keep exactly one note | `test_true_orphans_keep_their_note` |
| prefix-only closes share the bulk close cap | `test_prefix_only_closes_share_the_archive_close_cap` |
| the guard is load-bearing | negative control below |
| the live estate drops ~520 notes and plans 3 Notion closes | live dry-run below |

## Run table

```
Command: bash tests/test-sync.sh
Exit: 0
303 passed in 2.18s
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
run-all: all 11 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

The fix commit was in place first. Then `lib/sync/sync_core.py` was restored from `HEAD~1`, the suite run, and the file restored with `git checkout --`.

```
Command: git show HEAD~1:lib/sync/sync_core.py >| lib/sync/sync_core.py && bash tests/test-sync.sh
Exit: 1
FAILED lib/sync/tests/test_core.py::test_done_card_for_an_archived_closed_row_is_quiet
FAILED lib/sync/tests/test_core.py::test_open_card_for_an_archived_row_closes_after_the_map_entry_is_gone
FAILED lib/sync/tests/test_core.py::test_prefix_only_closes_share_the_archive_close_cap
3 failed, 300 passed in 3.63s
Verdict: RED as expected
```

After the restore: `303 passed in 6.41s`.

## Live dry-run

The consumer estate's hourly sweep, dry-run against this branch's `bin/board` (no Notion or Reminders write, no publish):

```
Command: BOARD_CMD=<worktree>/bin/board tools/board-sync/bin/board-sync-all --dry-run
```

| Repo, spoke | Orphan notes before (last live tick) | Orphan notes after | Planned spoke writes |
|---|---|---|---|
| ops-toolkit, notion | 474 | 3 (the 3 being closed) | 3 status writes, `queued` to `shipped` |
| ops-toolkit, reminders | 53 | 4 (ids in neither board nor archive) | 0 |
| dfoundation, reminders | 20 | 20 (no archive file in that repo) | 0 |

A read-only census of the 474 ops-toolkit Notion orphans before the fix: 471 were already `shipped` or `dropped` in Notion, and 3 were still `queued` although their rows sit in the archive as `shipped`. Under the 20-per-tick cap, so no `--allow-archived-closes` override is needed.
