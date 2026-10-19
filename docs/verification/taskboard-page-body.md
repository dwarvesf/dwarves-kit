# Proof of done: a hermes task carries the Notion page body

## What changed

A task created from a Notion Task Board intake row read only the Title and Notes properties, so the
page body, where a ticket's raw context lives, never reached the agent that picks the task up.

`expand_body` (in `lib/sync/sources/notion_taskboard_pull.py`) reads the page's block children
through `ntn`, paginated, one level of nesting, and turns paragraph, heading, list, to-do, callout
and quote blocks into plain text. It splices that text into the row's untrusted fence under
`Page body:`, clipped at 8000 characters and passed through the same defang and redaction as the
other fields. `HermesSource` runs it on each created card's body, through an optional
`body_expander` that `build_source` wires.

The fetch happens at create, not at intake. The board row is never touched, so it stays one line.
A failed read still creates the task, and the fence says `(page body unavailable)`.

## Gate table

| Claim | Evidence |
|---|---|
| the body lands inside the fence, after the notes | `test_page_body_lands_inside_the_fence_after_notes` |
| block types convert, nesting stops at one level | `test_block_types_become_plain_text_one_level_deep` |
| block children paginate | `test_block_children_are_paginated` |
| the cap holds and a marker shows the cut | `test_oversized_page_body_is_capped_and_marked_truncated` |
| a failed fetch keeps the old body and says so | `test_failed_block_fetch_keeps_the_old_body_and_says_so` |
| the fence stays intact against a hostile body | `test_page_body_cannot_forge_the_fence_or_leak_tokens` |
| the row stays one line, intake reads no blocks | `test_intake_never_reads_blocks_and_the_row_stays_one_line` |
| the hermes create carries it, and survives a failure | `test_hermes_create_carries_the_page_body_and_the_row_does_not`, `test_hermes_create_survives_a_failed_page_fetch` |
| a read call never inherits stdin | `test_a_read_call_never_inherits_stdin` |
| each new test goes red on the old behavior | negative controls below |

## Run table

```
Command: bash tests/test-sync.sh
Exit: 0
Output:
...................................                                      [100%]
251 passed in 0.90s
Verdict: PASS
```

```
Command: bash lib/registry/feature-registry.sh check docs/FEATURES.md
Exit: 0
Output:
feature-registry: docs/FEATURES.md is fresh
Verdict: PASS
```

A read-only run against a real workspace, with the real `ntn` transport and no write call: 25 open
cards fetched through `fetch_page_body`, 0 errors, bodies from 569 to 5353 characters.

## Negative control

```
Command: bash tests/test-sync.sh   (expand_body reduced to "return body", the old behavior)
Exit: 1
Output:
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_page_body_lands_inside_the_fence_after_notes
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_block_types_become_plain_text_one_level_deep
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_block_children_are_paginated
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_oversized_page_body_is_capped_and_marked_truncated
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_failed_block_fetch_keeps_the_old_body_and_says_so
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_page_body_cannot_forge_the_fence_or_leak_tokens
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_hermes_create_carries_the_page_body_and_the_row_does_not
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_hermes_create_survives_a_failed_page_fetch
8 failed, 243 passed in 0.90s
Verdict: RED as expected
```

```
Command: bash tests/test-sync.sh   (cap raised to 10**9)
Exit: 1
Output:
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_oversized_page_body_is_capped_and_marked_truncated
1 failed, 250 passed in 2.89s
Verdict: RED as expected
```

```
Command: bash tests/test-sync.sh   (fetch failure handler narrowed to KeyError)
Exit: 1
Output:
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_failed_block_fetch_keeps_the_old_body_and_says_so
FAILED lib/sync/tests/test_notion_taskboard_pull.py::test_hermes_create_survives_a_failed_page_fetch
2 failed, 249 passed in 1.59s
Verdict: RED as expected
```

Each break was made after the change was committed, then restored with `git checkout HEAD --`. The
tree was clean afterwards and the suite returned to 251 passed.

## Not proven

- The unit tests use a fake `ntn` transport. The live read above covers the real transport for
  `fetch_page_body`, not a full relay through a running Hermes instance.
- Blocks outside the listed types (toggle, table, code, child page) contribute no text.
