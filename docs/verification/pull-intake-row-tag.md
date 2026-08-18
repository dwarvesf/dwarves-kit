# Proof of done: pull-intake rows carry an identifying tag

Change: every row `notion-taskboard-pull` adds carries `#notion-intake` in its
notes cell, so `extract_tags` sees it and `in_scope` filters on it.

## Why

A hub board holds work from many origins. The intake rows carried nothing to
tell them apart, so a consumer relaying them onward could relay the whole board
or relay nothing. Measured on the first consumer, dfoundation, before this
change:

| Check | Command | Result |
|---|---|---|
| what an unfiltered relay would create | `plan_sync(parse_board(BACKLOG, prefix='DF'), [], {})` | `src_create` = **133** kanban tasks, on a board whose intake set was 0 |

133 unrelated tasks on the first tick is not a filter problem the consumer can
solve, because there was no property to filter on.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Whole sync suite | `bash tests/test-sync.sh` | 232 passed in 0.21s | PASS |
| 2 | An intake row is in scope for the tag and out of scope for another | `test_intake_row_carries_the_intake_tag` | passed | PASS |
| 3 | The source board cannot forge the tag | `test_the_source_board_cannot_forge_the_intake_tag` | passed; `#notion-intake` in an untrusted field becomes `# notion-intake` | PASS |

## Negative control

| Control | What was reverted | Result |
|---|---|---|
| A | the tag dropped from the emitted body, every other line kept | `test_intake_row_carries_the_intake_tag` FAILED, 50 passed | RED |
| restore | `git checkout HEAD -- lib/sync/sources/notion_taskboard_pull.py` | 232 passed | GREEN |

## Reproduce

```
git checkout feat/pull-intake-row-tag
bash tests/test-sync.sh

python3 - <<'PY'
import pathlib
p = pathlib.Path("lib/sync/sources/notion_taskboard_pull.py")
p.write_text(p.read_text().replace(
    'f"From Notion Task Board: https://www.notion.so/{pid} #{INTAKE_TAG}"',
    'f"From Notion Task Board: https://www.notion.so/{pid}"'))
PY
uv run --no-project --with pytest -- pytest lib/sync/tests/test_notion_taskboard_pull.py -q
git checkout HEAD -- lib/sync/sources/notion_taskboard_pull.py
```
