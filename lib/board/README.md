# board

The cockpit board: a kanban over each repo's `_meta/BACKLOG.md`. The markdown file stays the single source of truth, and this module makes its Status column scriptable instead of hand-edited.

**Entry points**
- `bin/board` forwards to `lib/board/board.sh`, the one dispatcher. Consumers call `bin/board`, never a deep `lib/board/` path.
- `board.sh board|next|get|set|states`: render the kanban, pick the first queued row, read or flip one row's state (delegates to `backlog.sh`).
- `board.sh add <title>`: mint the next id and write one new row under the board lock (`lib/board/board_add.py`). `capture` and `promote` call it too.
- `board.sh dedupe|lint|normalize`: collapse duplicate ids, enumerate malformed rows, pad short rows to the table's column count.
- `board.sh priority` and `board.sh all ...`: the urgency quadrant for one repo, and the cross-repo render over a `boards.txt` registry.
- `board.sh queue`: emit the allow-listed overnight queue rows that `lib/queue/queue.sh` consumes.
- `board.sh run <ID>`: scaffold a one-row mega-goal dir and print the `orchestrate.sh run` command (`board-run.sh`). It never launches a session.
- `board.sh work`: read-only table of who is on what, joined from board, git, Orca and the run ledger (`work.sh`).
- `board.sh mirror|status|writeback|mirror-cleanup`: the git to Hermes kanban bridge and its reverse leg (`board-mirror.sh`, `board-writeback.sh`, `board-mirror-cleanup.py`).
- `board.sh sweep|health|brief|hermes`: forwarders to the scripts in `lib/sync/sweep/`.
- `board.sh init|capture|sync|publish|promote`: scaffold board files, file one item, run the sync engine, commit and push the board file, review staged candidates.

**Layout**
- `parse-board.sh`: the one structured BACKLOG parser that `queue` and the mirror reuse.
- `lib/board/bin/add-backlog`, `lib/board/bin/board-normalize`: Python helpers behind `promote` and `normalize`.

**Tests**: `tests/test-board*.sh` in the repo-root `tests/` directory, plus `tests/test-backlog-stage-parity.sh`. Run `bash tests/run-all.sh --only board`.

**Spec and docs**: `docs/specs/SPEC-146-cockpit-board-tool.md`, `docs/specs/SPEC-147-board-bridge-mirror.md`, `docs/specs/SPEC-149-board-bridge-writeback.md`.
