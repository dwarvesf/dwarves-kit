# config

The kit's configuration layer. One resolver reads layered `kit.toml` values, one module table says which hooks and commands each module owns, and a read-only command shows what every knob resolves to and why.

**Entry points**
- `bin/config {list|get|explain|seams|data}` forwards to `lib/config/config.sh`. `list` shows every declared knob, `get <key>` prints the resolved value, `explain <key>` shows the env, project, kit-root and default chain, `seams [--check]` reports cross-kit seams.
- `lib/config/kit-config.sh`: source it for `kit_config_get <section.key> [default]`, `kit_config_root`, `kit_config_operator` and `kit_config_project`. Project beats operator beats kit-root beats default. It is the only reader of TOML.
- `lib/config/merge-command.sh`: source it for `kit_merge_command <repo> [<default>]`, `kit_merge_command_slug`, `kit_merge_exec` and `kit_merge_verify`, the project's own PR merge command (`[merge] command`) that `wrap land`, `wrap merge`, `mega-merge` and `stack-merge` run in place of the plain squash. Tests: `tests/test-merge-command.sh`.
- `lib/config/modules.sh`: source it for `kit_modules_known`, `kit_modules_core`, `kit_module_default`, `kit_module_hooks`, `kit_module_hook_events` and `kit_module_clis`.
- `lib/config/hook-module.sh off <hook-script-basename>`: exit 0 when the hook's module is switched off. `hooks/anchor-root.sh` calls it before every non-spine hook.
- `bin/config data [where|path <kind> <name>|move [--apply]]` (`lib/config/data.sh`): where the kit keeps its runtime state, cache and config, how each path resolved (`new`, `legacy`, `pinned`), and the opt-in move of old data to the new root (dry run unless `--apply`).
- `lib/config/data-path.sh`: source it for `kit_data_path <kind> <name>` (kind: state, cache or config). It is the only place a runtime data path is spelled; Python tools use `lib/config/kit_data.py`. Order: the entry's own env var, `KIT_DATA_ROOT`, the operator `kit.toml` `[data] root`, the old path while it holds data, then the XDG default. `boundary-lint` fails when another file spells an old path.
- `bash lib/config/kit-config.sh selftest`: a built-in precedence check for the resolver.
- `lib/config/safe-path.sh`: source it for `kit_refuse_symlink_path <root> <path>...`, which refuses a symlinked or escaping path.

**Layout**
- `lib/config/modules.tsv`: the one module table (module, default, hooks, clis). `install.sh` and `lib/adopt.sh` read it.
- `lib/config/module-registry.md`: the module-to-stage table and the env-to-key rows that `bin/config` enumerates.

**Tests**: `tests/test-data-root.sh`, `tests/test-config.sh`, `tests/test-config-registry.sh`, `tests/test-config-seams.sh`, `tests/test-config-find-row.sh`, `tests/test-modules-table.sh`, `tests/test-anchor-module-gate.sh`, `tests/test-reserved-config-guard.sh` and `tests/test-symlink-guard.sh`. Run one with `bash tests/run-all.sh --only config`.

**Spec and docs**: `docs/specs/SPEC-198-config-surface.md`, `docs/specs/SPEC-248-operator-config.md`, `docs/specs/SPEC-418-one-data-root.md`.
