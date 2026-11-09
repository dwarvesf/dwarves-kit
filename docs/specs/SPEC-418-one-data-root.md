# Spec: one resolver for the kit's runtime data paths

Status: APPROVED
Lane: normal

## Problem

Only the run ledger has a path resolver (`lib/telemetry/kit-log-dir.sh`). Every other runtime write path is hardcoded in the feature that writes it: about 15 places under `~/.claude/dwarves-kit/state`, `~/.claude/intel`, `~/.claude/skill-proposals`, `~/.claude/skill-curator`, `~/.claude/logs`, `~/.cache`, and `~/.config`. A plugin reinstall can wipe `~/.claude/dwarves-kit`, a user cannot answer "where is my data", and a second install cannot be pointed at its own data.

Live hosts hold state at the old paths, and some of it is a poller cursor. A reset cursor replays history and floods; lost board link state creates duplicate items. So the move must never be automatic.

## Solution

### Approaches considered

| Approach | Verdict |
|---|---|
| A. One resolver with a table of entries; the old path wins while it holds data and the new one does not; an opt-in `move` | chosen |
| B. Point every site at the XDG path and migrate at install | rejected: install-time moves race a running sweep and a reset cursor floods |
| C. Copy the ledger resolver once per feature | rejected: that is the drift this removes |

### Chosen approach + why

A. Nothing changes for a live host after merge, a new user gets a clean XDG layout, and one command moves old data when the operator chooses.

## Technical Design

### Interfaces (I/O contract)

- `lib/config/data-path.sh`: `kit_data_path <kind> <name>` prints the path (a dir, or a file for `money-gate.log`, `tool-policy.json`, `board.json`, `hermes-links.json`); `kit_data_source` says how it resolved (`env`, `root-env`, `root-key`, `legacy`, `default`). Also runnable: `bash data-path.sh path <kind> <name>`. The table is `_kit_data_lookup`: legacy path, own env var and one-line note per entry.
- Order, first hit wins:
  1. The entry's own env var, when non-empty (only entries that have one: harvest, intake-sweep, skill-proposals, skill-curator, money-gate.log, backlog-stage, context-hints, update-notice, tool-policy.json, board.json, hermes-links.json).
  2. State and cache only: `KIT_DATA_ROOT`. An explicit per-process root beats old data on purpose, so a test that pins it never reaches a real host's state; `where` warns about old data it hides.
  3. The old path, when it exists (a dangling symlink counts) and the target from step 4 or 5 holds nothing (missing, or an empty dir).
  4. State and cache only: the operator `kit.toml` key `[data] root`, read from the operator file only and only when it has a `[data]` section. It sits below step 3: writing the key ahead of the move must not hide a cursor.
  5. The default: `$XDG_STATE_HOME` or `~/.local/state` for state, `$XDG_CACHE_HOME` or `~/.cache` for cache, the operator config dir for config, each under `dwarves-kit/<name>`.
  Config entries skip steps 2 and 4. A root must be an absolute path (`~/` expands); a relative one is ignored and `where` says so. An empty env var is ignored. With HOME unset the key is not read.
- `lib/config/kit_data.py`: `kit_data.path(kind, name)` asks the shell file. One source of truth beats a Python twin that must be kept in step.
- `config data [where]`: a table of kind, name, how it resolved (`pinned`, `new`, `legacy`), whether data is there, and the path; a `WARNING` when an explicit root hides old data or both paths hold data; a `note` when the key is set but the entry has not moved; the ledger root as a `logs` row; the root line.
- `config data path <kind> <name>`: one path, for scripts and skills.
- `config data move [--apply]`: dry run by default. Per entry it skips when the entry's env var pins it, when the old path is a symlink, when both paths exist, or when a `<target>.part` is left over. On one disk the move is a single rename; across disks it copies into `<target>.part` and renames. `--apply` stops (exit 1) while `XDG_STATE_HOME` or `XDG_CACHE_HOME` is set and no root is pinned, because a hook or launchd job without them would look elsewhere; a dry run only warns. After moving `intel` it says to re-run `deploy/macos/install` (the kit-weekly plist bakes the log path). A bad flag exits 64.
- Hooks resolve through the shell file and never read `kit.toml` themselves; the file does it, and only when the operator `kit.toml` has a `[data]` section.
- A new `boundary-lint` check fails when a legacy data path is spelled outside `lib/config/data-path.sh`, including as path pieces (`".claude", "intel"`), in lib, hooks, bin, deploy, install.sh and the prose of commands, skills, agents, integrations and templates.

### Classification

| Kind | Entries |
|---|---|
| state (lost for good if deleted) | harvest, intake-sweep, backlog-sync, intel, hermes-links.json, skill-proposals, skill-curator, money-gate.log |
| cache (safe to delete) | backlog-stage, context-hints, update-notice, context-budget |
| config (operator edits) | tool-policy.json, board.json, harvest-sweep |

`backlog-sync` lives under `~/.cache` today but holds link state, so it is state. `hermes-links.json` lives under `~/.config` today but the kit writes it, so it is state (its old path is still its legacy home). A root moves state and cache; config files stay in the operator config dir (`KIT_CONFIG_OPERATOR` pins that for a second install). Legacy path and env var per entry: `_kit_data_lookup` in `data-path.sh`.

### Out of scope

`~/.local/state/worker-launch/launches.jsonl` is another tool's output that the sweep reads; it keeps its env override. Repo-local paths (`.claude/`, `_meta/`, `docs/`) are per-project data. The run logs keep the ledger resolver (`where` lists them). Python tools use `lib/config/kit_data.py`; there is no second Python door.

### Data model changes

None. Paths only.

## Task Breakdown

1. Resolver, Python door, `config data` verbs, registry rows.
2. Point every site at it: the hooks `harvest`, `intake-sweep`, `backlog-stage`, `context-hints`, `context-budget`, `kit-update-notice`, `money-gate` and `tool-policy-guard`; `harvest_lib`; session intel and audit; skill-curator; sync and board scripts; the weekly plist; the harvest-sweep launcher and installer; the dashboard.
3. Docs and skills name `config data path` instead of a literal path.
4. `tests/test-data-root.sh`; a boundary-lint check that fails on a new hardcoded legacy path.

## After state

A live host resolves every entry to its legacy path and moves nothing, until the operator runs `config data move --apply` or sets `KIT_DATA_ROOT`. A fresh HOME gets XDG paths. A second `move --apply` is a no-op.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 an entry's own env var wins (each entry that has one; `_kit_data_lookup` is the list) | `tests/test-data-root.sh` section 2 |
| AC2 `KIT_DATA_ROOT` wins over legacy and XDG; the `[data] root` key wins over XDG and, once it holds data, over legacy; env beats key; relative roots are ignored | sections 3 and 4 |
| AC3 the old path wins while the target holds nothing; a dangling symlink counts; an empty target dir does not hide it; config files keep their old home | section 5 |
| AC4 a fresh HOME gets XDG paths only | section 1 |
| AC5 `move` dry run changes nothing; `--apply` moves and a rerun is a no-op; both-exist, pinned, symlinked and `.part` entries are skipped; the XDG stop; the intel hint | section 7 |
| AC6 a hardcoded legacy path in code or prose fails boundary-lint | `tests/test-boundary-lint.sh` section AC7 and its negative controls |
| AC7 a fresh HOME lands under XDG and a HOME with old data keeps using it, per entry at the resolver and for context-hints at the hook; the other hooks' fresh-HOME default dirs are pinned by the four parity suites and the money-gate parity suite | sections 1, 5, 9 and the parity suites |
| AC8 `config data` and `config data path` report how each entry resolved and warn on a hidden or doubled path | section 6 |
| AC9 the Python door agrees with the shell resolver and raises on an unknown entry | section 8 |
| AC10 a clean-room install writes only into the install and data dirs | `tests/test-clean-room.sh` |

Accepted gap: only context-hints has a hook-level legacy-keeps-working case; the other hooks share the resolver call, so the resolver cases cover them.

## Verification

```bash
bash tests/test-data-root.sh
bash tests/test-boundary-lint.sh
bash tests/test-clean-room.sh
bash tests/run-all.sh --changed
```
