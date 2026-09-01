# notion sync: rich_text chunking by UTF-16 units

Claim: `_rich` chunks never exceed 2000 UTF-16 code units, so a Notes
body holding an emoji no longer 400s the Notion `v1/pages` request.
Incident: the dfoundation hourly board-sync exited rc=1 on every run
(2026-08-18) with `validation_error ... length should be <= 2000,
instead was 2001`; the board carried Notes cells with one astral char
inside their first 2000 codepoints.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `uv run --with pytest pytest tests/test_notion.py tests/test_notion_taskboard.py -q` (lib/sync) | 0 | PASS: 40 passed, including the two new `test_rich_chunks_by_utf16_units_not_codepoints` |
| `uv run --with pytest pytest tests/ -q` (lib/sync) | 0 | PASS: 175 passed, full sync suite |

## Negative control (revert -> RED -> restore)

| Command | Exit | Verdict |
|---|---|---|
| `git stash push -- lib/sync/sources/notion.py lib/sync/sources/notion_taskboard.py`, then run the two new tests | 1 | RED: both fail on the old `len()`-based slicing (`2 failed`) |
| `git stash pop` | 0 | fix restored; suite green again |

## Reproduce

```bash
cd lib/sync && uv run --with pytest pytest \
  tests/test_notion.py::test_rich_chunks_by_utf16_units_not_codepoints \
  tests/test_notion_taskboard.py::test_rich_chunks_by_utf16_units_not_codepoints -q
```
