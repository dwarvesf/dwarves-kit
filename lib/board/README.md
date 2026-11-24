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
- `board.sh state-check`: check the state values a repo stores in its OWN registry file (default `_meta/states.toml`) with `--all [--strict]`, `--staged` (a pre-commit hook blocks NEW drift only) or `--fix` (`state_check.py`). Exit 0 clean, 1 blocked, 2 internal error. See "State check" below.
- `board.sh sweep|health|brief|hermes`: forwarders to the scripts in `lib/sync/sweep/`.
- `board.sh init|capture|sync|publish|promote`: scaffold board files, file one item, run the sync engine, commit and push the board file, review staged candidates.

**Layout**
- `parse-board.sh`: the one structured BACKLOG parser that `queue` and the mirror reuse.
- `lib/board/bin/add-backlog`, `lib/board/bin/board-normalize`: Python helpers behind `promote` and `normalize`.

**State check**

`board state-check` is a generic engine: the kit holds no registry, a consumer repo keeps its own TOML file and calls the engine. It never touches the board's own `states.tsv` (the board stays permissive by design, see `docs/briefs/DECISION-BRIEF-declared-state-machines.md`); a repo opts in by writing a registry and wiring the call.

```bash
bin/board state-check --all [--strict]    # report every checked machine; --strict exits 1 on undeclared values or drift
bin/board state-check --staged            # pre-commit: block NEW drift; ALLOW_STATE_CHANGE="<reason>" lets one through
bin/board state-check --fix               # rewrite the leading token of each drifted projection row to match its store
# flags: --repo-root DIR (default STATES_ROOT, else the git root of cwd), --states-file PATH (default STATES_REGISTRY, else <repo>/_meta/states.toml)
```

A registry holds one table per machine: `kind` (`frontmatter`, `toml` or `table`), `glob`, `field`, `states`, optional `transitions`, `legacy`, `projections`, `append_only`, `ignore_case`, `body_fallback`; `check = false` marks a machine owned elsewhere. Fixture: `tests/fixtures/state-check/states.toml`. A stored value is its leading token (a trailing `# comment` and a trailing parenthetical are dropped); a `<state>:` entry in `states` matches `<state>:<ref>`. Existing data is grandfathered: `--staged` blocks only a new undeclared value, a newly written legacy value, an undeclared transition, an edit or removal of a past append-only row, and new projection drift. Env: `STATES_BASE` (compare the index against another commit), `STATES_PROG` (the command name printed in hints, default `board state-check`), `STATES_TOML=mini` (force the built-in TOML reader). Python 3.9 works: without `tomllib` the engine reads the registry with a small built-in reader (tables, strings, integers, booleans, arrays, inline tables) and reads each stored TOML file's top-level field line by line. A wrapper can `import state_check` and reuse `ROOT`, `REGISTRY`, `norm`, `classify`, `move_problem`, `values`, `parse_table`, `retoken` and `retoken_row`.

**Tests**: `tests/test-board*.sh` and `tests/test-state-check.sh` in the repo-root `tests/` directory, plus `tests/test-backlog-stage-parity.sh`. Run `bash tests/run-all.sh --only board`.

**Spec and docs**: `docs/specs/SPEC-146-cockpit-board-tool.md`, `docs/specs/SPEC-147-board-bridge-mirror.md`, `docs/specs/SPEC-149-board-bridge-writeback.md`.
