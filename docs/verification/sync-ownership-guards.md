# Verification -- sync-ownership-guards

The board sync planner stops reopening closed rows, reads item-cell tags in its filters, dedupes intake against rows still in play, and lets `intake_skip_re` see the title.

## Green run
```
Command: bash tests/test-sync.sh
Exit: 0
Output:
  ........................................................................ [ 27%]
  ........................................................................ [ 54%]
  ........................................................................ [ 81%]
  ................................................                         [100%]
  264 passed in 0.95s
Verdict: PASS (251 before; 13 new tests, one old assertion inverted)
```

Live what-if dry-run (the worktree engine against the real dfoundation Reminders list; board copy with DF-611 dropped, snapshot dropped, item still open):

```
Command: backlog_sync.py --apps reminders --list "Backlog · dfoundation" --filter reminders:only_tags=u-hi --dry-run
Exit: 0
Output:
  dry-run reminders: 70 spoke items, 362 board rows
    ~ spoke     x-apple-reminder://<id> -> dropped
    · note      DF-611: board is dropped, reminders shows it open; closing it there (board wins)
Verdict: PASS (before the fix this planned a board flip `DF-611 -> queued`)
```

## Negative control
```
Command: bash tests/test-sync.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAILED lib/sync/tests/test_core.py::test_definitive_active_status_never_reopens_a_terminal_row
  FAILED lib/sync/tests/test_core.py::test_tag_filters_read_the_item_cell_too
  FAILED lib/sync/tests/test_core.py::test_item_tag_scope_exit_closes_the_spoke_item
  FAILED lib/sync/tests/test_core.py::test_item_tags_do_not_churn_a_linked_spoke_title
  FAILED lib/sync/tests/test_core.py::test_real_spoke_retitle_keeps_the_item_tags
  FAILED lib/sync/tests/test_core.py::test_intake_dedupe_ignores_closed_rows
  FAILED lib/sync/tests/test_core.py::test_intake_skip_re_also_sees_the_title
  FAILED lib/sync/tests/test_prefix.py::test_binary_spoke_reopen_never_reopens_a_dropped_row
  FAILED lib/sync/tests/test_reminders.py::test_item_tag_is_not_doubled_by_the_body_suffix
  11 failed, 253 passed in 1.05s
Verdict: PASS (pre-fix sync_core.py and reminders.py restored from the parent commit; restored with git checkout HEAD, 264 green again)
```

Per-fix control (each fix reverted alone, suite run, restored):

| Fix reverted | Red tests |
|---|---|
| terminal guard | 4 (dropped, shipped, explicit-status, binary-spoke) |
| filters read notes only | 3 (filter read, scope exit, no title churn) |
| tag-blind planner title compare | 1 (no title churn) |
| reminders keeps item tags in title | 1 (no doubled tag) |
| dedupe against closed rows | 1 |
| `intake_skip_re` body only | 1 |

## Not proven
- The first live sweep after merge: only `--dry-run` ran against real boards, nothing wrote to Reminders, Notion or Hermes.
- `notion-taskboard` priority and weight maps still read the notes cell only; an item-cell `#u-hi` does not set a Task Board priority.
- A Reminders title no longer shows item-cell tags (only notes tags); the filter and scope still use them.
