# Verification: `set` refuses a duplicate id, `dedupe` collapses it

`lib/board/backlog.sh` `set_state` matched every row whose first cell was the given id (`^\| *${id} *\|`), so a duplicate row for the same id got both copies flipped on one `set` call. Seen live on ops-toolkit ID-871: flipping the row also flipped its duplicate mirror row, and a union merge on `_meta/BACKLOG.md` (`merge=union`, `.gitattributes`) routinely re-adds a stale duplicate after both branches touch the same append-only log. PR #596 stops NEW duplicates from publishing; the `set` verb itself still wrote through both.

## Change

- `set` counts matching rows before writing. Exactly one: unchanged. More than one: refuses (exit 1), prints `board set: <ID> matches N rows (lines a, b, ...); dedupe first` to stderr, writes nothing. Zero: unchanged (`no Active-queue row for <id>`).
- New `dedupe <ID>` verb: more than one matching row keeps the shipped copy, else dropped, else parked, else the last occurrence in the file; deletes the rest and prints `board dedupe: <ID> kept line N, dropped lines a, b`. Exactly one row: `nothing to dedupe`, exit 0.
- `board.sh`/`bin/board` need no dispatch change: unrecognized subcommands already fall through `cmd_board_single` to `backlog.sh "$@"`, so `board dedupe <ID>` and `board set <ID> <state>` both route there unchanged. Only the header usage comment (and its `sed -n` line-range in `usage()`) picked up the new verb.

## Green run

```
$ bash tests/test-board-set-note.sh
PASS in-flight keeps stacking, newest first: executing [second] [first]
PASS shipped supersedes the in-flight note: shipped [done, PR #1]
PASS dropped supersedes the in-flight note: dropped [superseded by ID-002]
PASS terminal with no note preserves the existing note: shipped [the only record]
PASS parked keeps stacking: parked [waiting on review] [context to resume from]
PASS the ID-834 shape lands a single current note: shipped [proven under matched load]
PASS row still has its original field count (6)
PASS set refuses the duplicate id: board set: ID-871 matches 2 rows (lines 5, 6); dedupe first
PASS set on a duplicate id wrote nothing
PASS set on a unique id is unaffected: shipped [done]
PASS dedupe kept the shipped row, dropped the queued one: board dedupe: ID-871 kept line 6, dropped lines 5
PASS dedupe on a unique id is a no-op
ALL PASS
Exit: 0
```

Cases 8-11 (added by this change): 8 proves `set` refuses a 2-row id and touches nothing; 9 proves `set` still works on a unique id (no regression); 10 proves `dedupe` keeps the `shipped` copy over the `queued` one and collapses to exactly one row; 11 proves `dedupe` is a no-op on a unique id.

`bash tests/test-board.sh` (the wider `board.sh`/`parse-board.sh` suite, AC5 exercises `set` through the `board.sh` wrapper) still runs 48/48 green, 1 expected skip (NC-e, needs a sibling ops-toolkit checkout not present here):

```
TOTAL: 49   PASS: 48   FAIL: 0   SKIP: 1
```

## Negative control

```
Command: bash tests/test-board-set-note.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/if \[ "$match_count" -gt 1 \]; then/if [ "$match_count" -gt 99 ]; then/' lib/board/backlog.sh
Changed: lib/board/backlog.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/board/backlog.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation raises the refuse threshold from 2 to 100 rows, so the 2-row duplicate case (8) no longer refuses and case 9's expectations on the write path go red with it, exactly the behavior this change is meant to lock in.

## Reproduce

```bash
bash tests/test-board-set-note.sh
bash tests/test-board.sh
```

`tests/run-all.sh` globs `tests/test-*.sh`, so both are picked up by the full run.

## Scope

`set_state` is `lib/board/backlog.sh`'s only writer of the status cell; `dedupe` is the only other writer, added by this change. `lib/board/board.sh`, `bin/board`, and every `commands/*.md` call site route through `backlog.sh` unchanged (unrecognized subcommands fall through `cmd_board_single`), so no caller needed a code change beyond the header usage comment.
