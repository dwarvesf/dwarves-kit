# Proof of done: board-sync id-collision guard (ID-309)
Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `next_id` mints above the max id seen in RAW board text, even when a row never parses via `parse_board` | PASS | R1 |
| 2 | At link time, a spoke item whose id matches an existing board row but whose title disagrees (beyond whitespace/case) is refused: not linked, board row untouched, a collision note is emitted naming both titles | PASS | R1, R2 |
| 3 | Existing `lib/sync/tests/` suite stays green | PASS | R1 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `plan_sync`'s title-prefix link step (`lib/sync/sync_core.py`) now checks `titles_agree(it_title, rows[bid].item)` before adopting a spoke item into `linked[bid]`; on mismatch it appends an `id collision: ...` note and skips instead of linking. |
| Where | `lib/sync/sync_core.py`: new `titles_agree()` helper (near `parse_title`), guard added in `plan_sync`'s title-prefix link loop. `next_id()` needed no change: it already regexes the raw board `text` for `<prefix>-NNN` tokens, not the parsed `rows` dict, so a pipe-broken row that `parse_board` cannot see is still counted. |
| How it runs | Pure function, no I/O; exercised by `lib/sync/tests/test_core.py`. |
| Reversibility | `git revert` the commit; no persistent state touched (planner is pure, board writes happen only via `apply_board` on a separate, unaffected plan field). |

Root cause: the title-prefix link (`plan_sync`, the "snapshot map first, then title prefix" adoption loop) trusted `bid in rows` alone as proof of identity. When a board row is repaired after having been invisible to `parse_board` (so its id got reused by a spoke-born item), the id now matches but the titles never did. The fix adds the one missing check at the single link site all downstream status/title flow depends on, rather than patching the individual write sites (`board_edit_item`, `board_set_status`) that the bad link fanned out into.

## 3. Confirmation (runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-08-02 | `uv run --python 3.12 --with pytest pytest lib/sync/tests/ -q` | 0 | PASS (173/173, incl. 2 new tests) |
| R2 | 2026-08-02 | `git stash push -- lib/sync/sync_core.py && uv run --python 3.12 --with pytest pytest lib/sync/tests/test_core.py -k collision -v` (then `git stash pop`) | 1 | RED-as-expected |

## 4. Run detail

### R1 GREEN
- Command: `uv run --python 3.12 --with pytest pytest lib/sync/tests/ -q`
- Exit: 0
- Output (excerpt):
  ```
  ........................................................................ [ 41%]
  ........................................................................ [ 83%]
  .............................                                            [100%]
  173 passed in 0.14s
  ```
- Verdict: PASS
- Note: covers AC1-AC3. 171 pre-existing tests + `test_next_id_skips_id_in_malformed_row` (AC1) + `test_link_skips_title_mismatched_id_collision` (AC2).

### R2 NEGATIVE CONTROL
- Command: `git stash push -- lib/sync/sync_core.py` (reverts only the fix, keeps the new test), then `uv run --python 3.12 --with pytest pytest lib/sync/tests/test_core.py -k collision -v`, then `git stash pop` to restore.
- Exit: 1
- Output (excerpt):
  ```
  lib/sync/tests/test_core.py::test_link_skips_title_mismatched_id_collision FAILED [100%]
  >       assert any("id collision" in n and "ID-309" in n and "done" in n
                    for n in p.notes)
  E       assert False
  ======================= 1 failed, 31 deselected in 0.02s =======================
  ```
- Verdict: RED-as-expected
- Note: confirms the test actually exercises the fix (without the `titles_agree` guard, ID-309's spoke item would have linked silently, no collision note, and downstream `board_edit_item`/`board_set_status` writes for ID-309 would have fired, reproducing the 2026-07-21 incident). `titles_agree` and the guard were restored via `git stash pop` immediately after (verified byte-identical via `git diff`).

## 5. Reproduce

```
uv run --python 3.12 --with pytest pytest lib/sync/tests/ -q
```

## Before/after

**Before** (link loop trusted `bid in rows` alone):
```python
if bid in rows:
    linked[bid] = it
    claimed_rids.add(it["rid"])
```
A spoke item titled `ID-309 · done` would silently adopt the real `ID-309` row ("Queue-watcher pilot widening"), then flow through the field-sync section and flip the board row's item text to "done" and its status to shipped, on the very next sync round after the row was repaired.

**After** (title must agree beyond the shared id prefix):
```python
if bid in rows:
    if not titles_agree(it_title, rows[bid].item):
        p.notes.append(
            f"id collision: {bid} title mismatch, not linked "
            f"(board={rows[bid].item!r} spoke={it_title!r})")
        continue
    linked[bid] = it
    claimed_rids.add(it["rid"])
```
The mismatched item is never linked; the board row is never touched by it; a warning names both titles so a human can see the collision and resolve it (e.g. re-title the spoke item, or manually re-mint its id).
