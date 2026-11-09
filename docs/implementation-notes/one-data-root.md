# one-data-root: implementation notes

Spec: `docs/specs/SPEC-418-one-data-root.md`. This file is the delta only.

## Decisions not in the brief

- `KIT_DATA_ROOT` (an env var, per process) beats the legacy path; the operator `kit.toml` key `[data] root` does not. The brief's rule ("legacy wins when the new path does not exist") would otherwise let a test that pins `KIT_DATA_ROOT` reach a real host's cursors, so the env root wins and `config data where` warns about old data it hides. The key is persistent: an operator who writes it ahead of the move must not reset a cursor, so old data keeps winning until the key's root holds data (the design critique found this footgun).
- "Holds data" means exists and is not an empty directory, so a stray `mkdir` of the new path cannot orphan the old cursor. The old side only has to exist (a dangling symlink counts).
- Entries are paths, not dirs: `money-gate.log` and the `*.json` config files are files. The registry stores the legacy full path and the entry's own env var, which holds the same kind of path.
- Python asks the shell resolver (`lib/config/kit_data.py`) instead of keeping a twin. One bash start per call; `harvest_lib` keeps the answer for its process.
- The verb lives under the existing `bin/config` (`config data`), so `bin/` gains no entry.
- `backlog-sync` is state although it lives under `~/.cache`: its link state prevents duplicate board items.
- Found beyond the scout list: `skill-curator` state dir, `context-budget` cache, `harvest-sweep` config dir (launcher env and bridge), `tool-policy.json` in `lib/bench/dashboard.py`.

## Review round (independent reviewer, then fixes)

- Fixed: a dangling legacy symlink counts as data (an unmounted disk must not reset a cursor); `move` refuses `--apply` while `XDG_STATE_HOME` or `XDG_CACHE_HOME` is set and no root is pinned (a hook or launchd job without them would look elsewhere); `move` goes through a `.part` name and skips a leftover one; `where` prints a WARNING when an explicit root hides old data; `move` tells the operator to re-run `deploy/macos/install` after moving intel (the kit-weekly plist bakes the log path).
- Fixed: boundary-lint catches path pieces (`".claude", "intel"`, `Path.home() / ".cache" / "backlog-sync"`) and scans integrations, agents and templates prose.
- Fixed: helpers return through globals, so one lookup costs the outer `$(...)` only; `tool-policy-guard` resolves lazily and a copy without lib/ still honors `KIT_TOOL_POLICY`.
- Design critique (second round): `hermes-links.json` is state, not config (the kit writes it; it joins the state root); the key sits below old data; an empty new dir does not hide old data; roots must be absolute; `move` is one rename on a single disk (no moment with neither path) and goes through `.part` only across disks. Dropped, not worth: refusing `move --apply` unless a root is pinned in `kit.toml` (the XDG stop covers the shell it runs in), reading the key in a bare env with HOME unset, a umask for state dirs, a doctor check for a partial install.
- Kept: `board.json` keeps `~/.config/dwarves-kit` as legacy home. Honoring `XDG_CONFIG_HOME` is new; dropping the old home would hide the file on a host where the two differ.
- Dropped, not worth: lazy resolution of the Python module-level paths. Each costs one bash start (about 10 ms) per run, and bash is a hard dependency of the kit.
- Found while testing: a suite that sets only HOME still sees the real `XDG_*` dirs. `test-context-budget` wrote into the real `~/.cache/dwarves-kit` until it pinned them. `test-context-budget` and `test-board-brief` now unset the XDG dirs and pin `KIT_CONFIG_OPERATOR`; the four hook parity suites run under `env -i` and only needed their expected default paths updated (fresh HOME now means XDG).
- Operator note: `XDG_CACHE_HOME` and `XDG_CONFIG_HOME` are exported in the Mini's shell at the same value as the defaults, so nothing differs there today.
