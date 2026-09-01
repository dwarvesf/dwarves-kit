# Verification: board cell repair (`_meta/BACKLOG.md`)

Scope: `_meta/BACKLOG.md` content only. No code change; the sync engine
(`lib/sync/sync_core.py`, `lib/sync/backlog_sync.py`) was already correct,
the board content violated its 4-cell contract.

Trigger: every `_meta/board-sync-all` sweep in ops-toolkit logged, for this
repo, a duplicate-row warning (`ID-488`) and a malformed-row warning (99
rows, `not 4 cells, invisible to sync`). `sync_core.split_row` requires
`CELL_SPLIT = (?<!\\)\|` to yield exactly 6 raw parts (leading empty, 4
cells, trailing empty); any row with a stray unescaped `|` inside a cell
(shell operators like `` `>|` ``/`||`, code-span pipes, an old 3-column
row shape) failed that shape and silently dropped out of every downstream
sync (Reminders, Notion, Hermes kanban, `next_id` minting).

## Run table

| Check | Command | Verdict |
|---|---|---|
| Unit suite (all spokes + core, regression) | `uv run --with pytest python -m pytest lib/sync/tests/ -q` | PASS, 248 passed, 0 failed |
| Green run (real engine, post-fix) | `parse_board()` + the exact `warn_duplicate_ids` logic from `backlog_sync.py`, imported directly (not reimplemented) | PASS: 213 ID-shaped rows, 0 duplicates, 0 malformed |
| Board's own renderer | `./bin/board board --backlog-file _meta/BACKLOG.md` | exit 0; every row renders under its real status bucket |
| Negative control | `git stash` (restores the pre-fix content) -> same import-and-run check -> `git stash pop` | RED reproduced: 213 rows, `dups: ['ID-488']`, 99 malformed (`ID-002, ID-003, ID-012, ... ID-478, ID-479, ID-492`), then restored to green |

## Fix mechanism

1. **Stray-pipe escape.** Any unescaped `|` that is not the row's own
   leading/trailing pipe and not a real, single-space-padded column
   delimiter (` | `) gets backslash-escaped (`\|`), matching
   `sync_core.escape`/`unescape` and `CELL_SPLIT`'s own contract. This
   folds a handful of literal shell-operator/code-span pipes back into
   their cell (e.g. `` `context onboard\|audit\|refresh` ``, `\|\| exit 0`).
2. **Column-count reflow.** The Active queue table's original header
   declared 6 columns (`ID | Title | Source | Target artifact | Lane |
   Status`), but the sync contract is 4 (`ID | Item | Notes & source |
   Status`). For rows still carrying real delimiters for all 6 columns
   after step 1, the 3 extra columns (Source / Target artifact / Lane)
   are folded into one Notes & source cell by re-escaping the delimiters
   between them, keeping cell 1 (Item) and the final cell (Status)
   untouched. No word was dropped or reworded; only which pipes are
   markdown-escaped changed. A handful of very old rows (`ID-050`..`059`)
   had only 3 real cells (no separate Notes field ever existed for them);
   those got one empty Notes cell inserted, adding no content.
3. **Duplicate `ID-488`.** Two unrelated work items shared the id (a
   `shipped` gauntlet-generalization row and a `speccing` `/kit:pack` row).
   Kept the first (file-order) occurrence's id/status; folded the second
   row's Item/Notes/Status text into the first row's Notes cell tagged
   `[ID-488 duplicate merged from a second board row , ...]`, then removed
   the second row.

Row count: 214 -> 213 (the ID-488 duplicate row removed, its content
preserved inline in the surviving row).

## Known residual (not fixed, separate tool, pre-existing)

`lib/board/backlog.sh`'s `_rows()` and `lib/board/parse-board.sh`'s
`pb_rows()` (the `bin/board board`/`queue` render path) use a plain
`awk -F'|'` with **no escape support at all** (`status=$(NF-1)` grabs
whatever is between the line's last two raw `|` characters, full stop).
For 3 rows whose STATUS cell itself still contains a raw, unescaped pipe
character inside bracketed commentary (`ID-021`, `ID-420`, `ID-445`, e.g.
a repeated `` `>|` `` mention in a status annotation), that awk parser
extracts a garbled status fragment and buckets them under `UNRECOGNIZED`
in `./bin/board board`'s output. This is a pre-existing fragility of that
separate, non-backslash-aware tool (it already misparsed these same rows
before this fix, since it has never respected `\|`) and is orthogonal to
the `board-sync-all` contract this task scopes to; `./bin/board` still
exits 0. Flagged here rather than silently fixed, since actually fixing it
would mean stripping literal pipe characters out of Status-cell prose,
which risks rewording content this task's contract forbids touching
without a separate, scoped decision.

## Reproduce

```bash
uv run --with pytest python -m pytest lib/sync/tests/ -q
python3 - <<'EOF'
import sys, re
sys.path.insert(0, 'lib/sync')
from sync_core import parse_board, ID_TOKEN, detect_prefix
text = open('_meta/BACKLOG.md').read()
ids = re.findall(r"^\| (" + ID_TOKEN + r") \|", text, flags=re.M)
dups = sorted({i for i in ids if ids.count(i) > 1})
parsed = set(parse_board(text, strict_id=False, prefix=detect_prefix(text)))
broken = sorted(set(ids) - parsed - set(dups))
print("rows:", len(set(ids)), "dups:", dups, "malformed:", len(broken))
EOF
./bin/board board --backlog-file _meta/BACKLOG.md
```
