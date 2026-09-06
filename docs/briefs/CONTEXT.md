# Context for implementation (SPEC-245, precedent inventory surface)

## Stack
Bash entry scripts under `lib/<subsystem>/<subsystem>.sh` with a `bin/<subsystem>` forwarder; stdlib-only Python 3 beside the bash entry when the logic outgrows grep (`lib/learn/drain.py`, `lib/session/recall/session_recall.py`). Python is invoked as `python3 <file>.py` with env vars as the only IPC. Tests are raw bash (`tests/test-*.sh`, mktemp fixtures), discovered by `tests/run-workflow.sh` from `.github/workflows/test.yml`. Config: `kit_config_get <section.key> [default]` from `lib/config/kit-config.sh` (kit.toml, per-project `.kit.toml` overrides). Ledger root: `lib/telemetry/kit-log-dir.sh::kit_resolve_log_dir`, redirectable with `KIT_LEDGER_DIR` in tests.

## Conventions
- ADR-0034 grammar: `bin/<subsystem> <verb>`; the shim is a 3-line `exec bash "$SELF_DIR/../lib/<sub>/<sub>.sh" "$@"`; the lib entry owns the verb grammar. `tests/test-bin-forwarders.sh` is the census; a new bin entry registers there.
- Exit 64 on usage errors (CLIs). Hooks always exit 0; hooks are bash only (PHILOSOPHY). Python under `lib/` is allowed and common.
- `docs/FEATURES.md` is generated (`bash lib/registry/feature-registry.sh generate`), never hand-edited; it covers commands, agents, skills, hooks, not `bin/`.
- Consumer paths never hardcoded: repo root resolves flag > `REPO_ROOT` > `git rev-parse --show-toplevel` > cwd (`lib/board/board.sh`, `hooks/harvest.py`).
- Fold-in naming: bare function name, no host-agent prefix (`harvest`, not `cc-harvest`).
- STE-lite prose, no em dashes, no spec IDs in commit subjects.

## Key files
- `lib/precedent.sh`: today's records-surface finder (73 lines, bash grep, no tests, no bin entry). Moves to `lib/precedent/precedent.sh`.
- `commands/assign.md:115`, `commands/grill.md:67`: the two callers; both pinned by `tests/test-meta.sh:2079-2087` on the literal `precedent.sh find` and `-x lib/precedent.sh`.
- `lib/README.md:23,41`, `lib/mega/mega.sh:19`: name precedent.sh a root-level orphan; update wording.
- `lib/session/recall/session_recall.py:189-211`: the redaction regex, DATA marker, line cap already ported from whathas.
- `bin/learn`, `lib/learn/learn.sh`: the shim + entry shape to copy.
- `tests/test-board.sh`, `tests/test-mega.sh:24-50`: fixture patterns (temp repo, env overrides).
- Reference source (read-only, outside this repo): ops-toolkit `tools/repo-sweep/bin/repo-sweep` lines 625-660 (`_score`), 667-1290 (`_iter_*`), 1295-1520 (`_whathas_*`, `cmd_whathas`).

## External dependencies
None new. python3, grep, git, jq already required by tests.
