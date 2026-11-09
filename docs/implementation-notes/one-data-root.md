# one-data-root: implementation notes

Spec: `docs/specs/SPEC-418-one-data-root.md`. This file is the delta only.

## Decisions not in the brief

- An explicit root (`KIT_DATA_ROOT`, the operator key) beats the legacy path. The brief's rule ("legacy wins when the new path does not exist") would otherwise let a test that pins `KIT_DATA_ROOT` reach a real host's cursors. `config data where` flags old data left behind.
- Entries are paths, not dirs: `money-gate.log` and the `*.json` config files are files. The registry stores the legacy full path and the entry's own env var, which holds the same kind of path.
- Python asks the shell resolver (`lib/config/kit_data.py`) instead of keeping a twin. One bash start per call; `harvest_lib` keeps the answer for its process.
- The verb lives under the existing `bin/config` (`config data`), so `bin/` gains no entry.
- `backlog-sync` is state although it lives under `~/.cache`: its link state prevents duplicate board items.
- Found beyond the scout list: `skill-curator` state dir, `context-budget` cache, `harvest-sweep` config dir (launcher env and bridge), `tool-policy.json` in `lib/bench/dashboard.py`.
