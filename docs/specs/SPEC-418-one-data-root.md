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
| A. One resolver with a table of entries; legacy path wins while it holds data and the new one does not; an opt-in `move` | chosen |
| B. Point every site at the XDG path and migrate at install | rejected: install-time moves race a running sweep and a reset cursor floods |
| C. Copy the ledger resolver once per feature | rejected: that is the drift this removes |

### Chosen approach + why

A. Nothing changes for a live host after merge, a new user gets a clean XDG layout, and one command moves old data when the operator chooses.

## Technical Design

### Interfaces (I/O contract)

- `lib/config/data-path.sh`: `kit_data_path <kind> <name>` prints the path; `kit_data_source` says how it resolved (`env`, `root-env`, `root-key`, `legacy`, `default`). Also runnable: `bash data-path.sh path <kind> <name>`.
- Order: the entry's own env var; for state and cache, `KIT_DATA_ROOT` then the operator `kit.toml` key `[data] root`; the legacy path when it exists and the default path does not; the default (XDG state, XDG cache, or the operator config dir).
- `lib/config/kit_data.py`: `kit_data.path(kind, name)` asks the shell file. One source of truth beats a Python twin that must be kept in step.
- `config data [where]`, `config data path <kind> <name>`, `config data move [--apply]` (dry run by default).
- Hooks resolve through the shell file and never read `kit.toml` themselves; the file does it, and only when the operator `kit.toml` exists.

### Classification

| Kind | Entries |
|---|---|
| state (lost for good if deleted) | harvest, intake-sweep, backlog-sync, intel, skill-proposals, skill-curator, money-gate.log |
| cache (safe to delete) | backlog-stage, context-hints, update-notice, context-budget |
| config (operator edits) | tool-policy.json, board.json, hermes-links.json, harvest-sweep |

`backlog-sync` lives under `~/.cache` today but holds link state, so it is state.

### Out of scope

`~/.local/state/worker-launch/launches.jsonl` is another tool's output that the sweep reads; it keeps its env override. Repo-local paths (`.claude/`, `_meta/`, `docs/`) are per-project data. The run logs keep the ledger resolver.

### Data model changes

None. Paths only.

## Task Breakdown

1. Resolver, Python door, `config data` verbs, registry rows.
2. Point every site at it: five hooks, money-gate, tool-policy guard, harvest python, session intel and audit, skill-curator, sync and board scripts, the weekly plist, the harvest-sweep launcher and installer, the dashboard.
3. Docs and skills name `config data path` instead of a literal path.
4. `tests/test-data-root.sh`; a boundary-lint check that fails on a new hardcoded legacy literal.

## After state

A live host resolves every entry to its legacy path and moves nothing. A fresh HOME gets XDG paths. `config data move --apply` moves legacy data and a second run is a no-op.

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 entry env wins | `tests/test-data-root.sh` env case |
| AC2 `KIT_DATA_ROOT` and the operator key win over XDG; env beats the key | root cases |
| AC3 legacy wins when it exists and the new path does not | legacy case |
| AC4 a fresh HOME gets XDG paths only | fresh case |
| AC5 `move` dry run changes nothing; `--apply` moves; a rerun is a no-op; both-exist and pinned entries are skipped | move cases |
| AC6 a hardcoded legacy literal in code fails boundary-lint | `tests/test-boundary-lint.sh` + negative control |
| AC7 each rewired hook keeps its behavior | existing suites via `tests/run-all.sh --changed` |

## Verification

```bash
bash tests/test-data-root.sh
bash tests/test-boundary-lint.sh
bash tests/run-all.sh --changed
```
