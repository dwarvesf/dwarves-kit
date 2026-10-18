# Implementation notes: one writer for the board and the staging buffer

No spec: a normal-lane fix on drift rows 27, 28, 29, 32 and 34 and two ranked risks (the board has no single writer; staging has two lock domains). This log records the choices the brief left open.

## Choices

- **One row verb, one Python core.** `backlog.sh add` is a thin shell over `lib/board/board_add.py`. The lock, the id mint and the write share one Python process, because `board_lock` is a flock on a Python-held fd: a shell cannot hold it across a mint. `add_rows_locked` is the form a caller that already holds the lock uses (promote); calling `add_rows` from inside a hold would deadlock against itself, since flock is per open file description.
- **Column count comes from the table header, per table.** The kit's own board has a 6-column Active queue and a 4-column intake section, so "the board's column count" is a per-table fact. `--section` targets the table under a heading; with no section the row lands in the first `| ID |` table. A missing section is created with a copy of that first header.
- **Middle cells are positional (`--mid`), `--notes` is the first one.** No column-name mapping: header names differ across consumer boards (`Notes & source`, `Source`), and a name lookup would be a second schema. Too many values is an error; too few leaves the cells empty.
- **Id format follows the board.** Prefix by `detect_prefix`, zero-pad to the widest padded id the board already carries (the kit board has `ID-006`), bare numbers otherwise, three digits on an empty board. This keeps `capture` output (`ID-4`) and `promote` output (`ID-004`) each valid on the boards they were written for.
- **Promote's mint floor is computed once per batch, before the staging lock.** `history_max_id` runs a fetch and `git log -p --all`; holding the staging lock across that would stall a hook's append for seconds. The board lock is held across it, which the old promote also did.
- **Status and section are validated in `board_add.py`, the one flag parser.** A status is one word and, when `backlog.sh` passes `BOARD_ADD_STATES`, a legal state; a section is a one-line `#` heading with no pipe. The first draft validated the status in bash with `grep -qx`, which a newline walked past, and a forged row landed. The prose commands pass freeform text in single quotes after `--`.
- **A batch lands newest on top**, as every earlier writer left it (promote inserted each row right after the header).
- **Staging lock lives in the tmpdir**, keyed by the realpath of the buffer, the same scheme as the board lock (opened `O_NOFOLLOW`, mode 0600). The first draft kept drain's `<staging>.lock` beside the file; the parity suites caught it, because every hook run then left a stray lock file in the consumer checkout. The cost is the board lock's existing weakness: two processes with different `TMPDIR` values hold different locks. A lock file that cannot be opened degrades an append to an unlocked write with a warning (losing the caller's block is worse than the rare race) but makes `rewrite` fail, since an unlocked whole-file rewrite is what drops appends.
- **Lock order is board, then staging.** Only promote holds both. Nothing takes them in the other order.
- **Promote re-reads staging inside the hold and relabels by block text.** A block that no longer matches (expired by drain, promoted by another session) is skipped with a note and mints no row. Rows are minted only for blocks a dry relabel pass proved reachable, so two byte-identical twins cannot leave a row with no relabel. Before, promote wrote back the text it read at start, which dropped any block appended meanwhile and could mint a row for an already-expired candidate. Behaviour changes a caller can see: promote exits 1 when nothing was promoted, and ids on a board with no padded id are bare numbers (`ID-7`), padded to the widest padded id otherwise (`ID-007`), where capture was always bare and promote always padded.
- **`add-backlog` reads blocks through `staging-format.parse_blocks`.** Its private `parse_staging` was the third copy of the grammar; the jq twin is now the only other one (drift row 34).
- **The bash hooks go through `lib/reflect/staging-format.sh` (`sf_append`).** With python3 it calls `staging-format.py append`. Without python3 it is a plain append: the hooks were ported to run on bash plus jq alone, and a host with no python3 also has no promote, drain or anomalies run, so nothing rewrites the buffer. Requiring python3 for the hook would undo that port for no gain.
- **Lint judges each table against its own header.** On the kit's own board this now reports 259 four-cell rows under the six-column Active queue header. They are real: promote and capture wrote them. The old lint hid them by expecting 4 cells everywhere and reported two false findings instead. `lib/board/bin/board-normalize` (`board normalize`) padded them to six cells in a later commit: the item keeps its slot, the notes cell moves to Source, Target artifact and Lane stay empty, and the row-id multiset is checked before and after (280 and 280).

## Not routed

- `board run` only reads a row (`backlog.sh row`) and scaffolds a mega-goal directory; it writes nothing to the board, so there was nothing to route through `add`.
- `sync intake` still mints in `sync_core.apply_board`. It runs under the same `board_lock`, writes a bulk batch with provenance and the `#inbox` quarantine, and reads only 4-cell rows. Folding it into `add` is a separate change in the sync module.

## Known gaps

`propose.py`, `session-audit` and `session-intel` now append through `append_blocks`, and `sync_core.split_row` reads a row by its table's header width; the guard in `tests/test-staging-one-writer.sh` has an empty allow-list.

- `skills/backlog-reconcile/SKILL.md` (drift row 32) still describes the board shape as 4 cells.
- Dedupe-then-append is not atomic for the hooks and for `stats anomalies --propose`: two concurrent runs can both stage one title. The append is safe; the title check would have to move inside the lock (`staging-format.py stage` already does).
- A promote that writes the board and then dies before the staging relabel leaves rows whose blocks stay `[staged]`; the next promote mints them again. Board first is the right order (the reverse loses candidates), and the old promote had the same window. A title check against the board would close it.
- An older installed `drain.py` still locks `<staging>.lock`, which the new code does not use, so the two exclude nothing until every consumer upgrades.
- `append` and `rewrite` follow a symlinked buffer, as the old `>>` did; only `stage` refuses one.
