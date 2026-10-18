# Implementation notes: one writer for the board and the staging buffer

No spec: a normal-lane fix on drift rows 27, 28, 29, 32 and 34 and two ranked risks (the board has no single writer; staging has two lock domains). This log records the choices the brief left open.

## Choices

- **One row verb, one Python core.** `backlog.sh add` is a thin shell over `lib/board/board_add.py`. The lock, the id mint and the write share one Python process, because `board_lock` is a flock on a Python-held fd: a shell cannot hold it across a mint. `add_rows_locked` is the form a caller that already holds the lock uses (promote); calling `add_rows` from inside a hold would deadlock against itself, since flock is per open file description.
- **Column count comes from the table header, per table.** The kit's own board has a 6-column Active queue and a 4-column intake section, so "the board's column count" is a per-table fact. `--section` targets the table under a heading; with no section the row lands in the first `| ID |` table. A missing section is created with a copy of that first header.
- **Middle cells are positional (`--mid`), `--notes` is the first one.** No column-name mapping: header names differ across consumer boards (`Notes & source`, `Source`), and a name lookup would be a second schema. Too many values is an error; too few leaves the cells empty.
- **Id format follows the board.** Prefix by `detect_prefix`, zero-pad to the widest padded id the board already carries (the kit board has `ID-006`), bare numbers otherwise, three digits on an empty board. This keeps `capture` output (`ID-4`) and `promote` output (`ID-004`) each valid on the boards they were written for.
- **Promote's mint floor is computed once per batch**, not per row: `history_max_id` runs `git log -p --all`, and the old promote already hoisted it for the same reason.
- **Staging lock lives in the tmpdir**, keyed by the realpath of the buffer, the same scheme as the board lock. The first draft kept drain's `<staging>.lock` beside the file; the parity suites caught it, because every hook run then left a stray lock file in the consumer checkout. The cost is the board lock's existing weakness: two processes with different `TMPDIR` values hold different locks. A lock file that cannot be opened degrades to an unlocked write with a warning, since losing the caller's block is worse than the race.
- **Lock order is board, then staging.** Only promote holds both. Nothing takes them in the other order.
- **Promote re-reads staging inside the hold and relabels by block text.** A block that no longer matches (expired by drain, promoted by another session) is skipped with a note and mints no row. Before, promote wrote back the text it read at start, which dropped any block appended meanwhile and could mint a row for an already-expired candidate.
- **`add-backlog` reads blocks through `staging-format.parse_blocks`.** Its private `parse_staging` was the third copy of the grammar; the jq twin is now the only other one (drift row 34).
- **The bash hooks go through `lib/reflect/staging-format.sh` (`sf_append`).** With python3 it calls `staging-format.py append`. Without python3 it is a plain append: the hooks were ported to run on bash plus jq alone, and a host with no python3 also has no promote, drain or anomalies run, so nothing rewrites the buffer. Requiring python3 for the hook would undo that port for no gain.
- **Lint judges each table against its own header.** On the kit's own board this now reports 259 four-cell rows under the six-column Active queue header. They are real: promote and capture wrote them. The old lint hid them by expecting 4 cells everywhere and reported two false findings instead. Normalising the board is a separate change and is left to the board's owner.

## Not routed

- `board run` only reads a row (`backlog.sh row`) and scaffolds a mega-goal directory; it writes nothing to the board, so there was nothing to route through `add`.
- `sync intake` still mints in `sync_core.apply_board`. It runs under the same `board_lock`, writes a bulk batch with provenance and the `#inbox` quarantine, and reads only 4-cell rows. Folding it into `add` is a separate change in the sync module.

## Known gaps, for the owners of those files

- `lib/reflect/propose.py` (`run_retro`), `lib/session/audit/bin/session-audit` and `lib/session/intel/bin/session-intel` still open the buffer for append themselves. They need `staging_format.append_blocks(staging, blocks, header=...)`. `tests/test-staging-one-writer.sh` names them in `KNOWN_RAW` so a fourth raw writer fails the test, and each one comes off the list when it moves.
- `skills/backlog-reconcile/SKILL.md` (drift row 32) still describes the board shape as 4 cells.
- `sync_core.split_row` returns None for anything but a 4-cell row, so `board sync` cannot see the kit board's 6-column rows.
- Two hooks that dedupe against a snapshot and then append can still both stage one title. The append is safe; the dedupe-then-append pair is not atomic. Pre-existing, and the title key would have to move inside the lock.
