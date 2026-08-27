# ID-480: mint next_id from parsed row ids, not a raw-text regex

## Claim

`sync_core.next_id` used to match `<PREFIX>-<digits>` against the whole raw board
text, so a token equal to that shape counted wherever it appeared, including a
notes cell or a prose paragraph. `next_id` now unions the numeric ids from
`parse_board`'s rows with a narrower raw-text floor limited to row-SHAPED lines
(`| <prefix>-N |` at line start), which still blocks reuse from a row that fails
to fully parse without scanning arbitrary prose.

## Run table

| # | Action | Result |
|---|---|---|
| 1 | `uv run --no-project --with pytest -- pytest lib/sync/tests -q` (before fix) | 237 passed, 1 failed (the new regression test) |
| 2 | `uv run --no-project --with pytest -- pytest lib/sync/tests -q` (after fix) | 238 passed |
| 3 | `test_next_id_ignores_id_token_in_notes_prose` (new) | a row with `ID-99999999` mentioned in its notes cell no longer inflates the mint; `next_id` returns 15 (one past the board's real `ID-14`) |
| 4 | `test_next_id_skips_id_in_malformed_row` (existing, unchanged assertion) | still passes: a pipe-broken row (`| ID-309 | ... | notes` with no closing cells) still blocks reuse via the row-shaped line floor |

## Negative control

Checked out the pre-fix `sync_core.py` (commit `f9b8874`, the parent of this
fix) over the working tree, keeping the new test, and re-ran the full suite:

```
$ git checkout f9b8874 -- lib/sync/sync_core.py
$ uv run --no-project --with pytest -- pytest lib/sync/tests -q
AssertionError: assert 100000000 == 15
 +  where 100000000 = next_id('...| ID-14 | Demo row | mentions ID-99999999 in prose, not a row | queued |\n')
1 failed, 237 passed
$ git checkout HEAD -- lib/sync/sync_core.py
$ uv run --no-project --with pytest -- pytest lib/sync/tests -q
238 passed
```

RED, exactly reproducing the reported failure mode (the eight-digit prose
token pushed the mint to 100000000). Restored the fix; the suite is green
again.

## Review

- **Root cause fix, not a patch on one caller:** `next_id` has exactly one
  production call site (`apply_board`); fixing the shared function closes the
  gap for every current and future intake path, not just the one SPEC-004
  already neutralized at the source-adapter layer.
- **Scope:** `next_id`'s signature is unchanged (`text: str, prefix: str`), so
  `apply_board` and every test caller needed no changes beyond the one new
  test.
- **Existing invariant preserved:** the malformed-row floor
  (`test_next_id_skips_id_in_malformed_row`) still passes; the fix narrows
  what counts as "raw text" evidence (row-shaped lines only) rather than
  removing the floor.

No blockers.
