# config

The kit's configuration layer. One resolver reads layered `kit.toml` values, one module table says which hooks and commands each module owns, and a read-only command shows what every knob resolves to and why.

**Entry points**
- `bin/config {list|get|explain|seams}` forwards to `lib/config/config.sh`. `list` shows every declared knob, `get <key>` prints the resolved value, `explain <key>` shows the env, project, kit-root and default chain, `seams [--check]` reports cross-kit seams.
- `lib/config/kit-config.sh`: source it for `kit_config_get <section.key> [default]`, `kit_config_root`, `kit_config_operator` and `kit_config_project`. Project beats operator beats kit-root beats default. It is the only reader of TOML.
- `lib/config/modules.sh`: source it for `kit_modules_known`, `kit_modules_core`, `kit_module_default`, `kit_module_hooks`, `kit_module_hook_events` and `kit_module_clis`.
- `lib/config/hook-module.sh off <hook-script-basename>`: exit 0 when the hook's module is switched off. `hooks/anchor-root.sh` calls it before every non-spine hook.
- `bash lib/config/kit-config.sh selftest`: a built-in precedence check for the resolver.
- `lib/config/safe-path.sh`: source it for `kit_refuse_symlink_path <root> <path>...`, which refuses a symlinked or escaping path.

**Layout**
- `lib/config/modules.tsv`: the one module table (module, default, hooks, clis). `install.sh` and `lib/adopt.sh` read it.
- `lib/config/module-registry.md`: the module-to-stage table and the env-to-key rows that `bin/config` enumerates.

**Tests**: `tests/test-config.sh`, `tests/test-config-registry.sh`, `tests/test-config-seams.sh`, `tests/test-config-find-row.sh`, `tests/test-modules-table.sh`, `tests/test-anchor-module-gate.sh`, `tests/test-reserved-config-guard.sh` and `tests/test-symlink-guard.sh`. Run one with `bash tests/run-all.sh --only config`.

**Spec and docs**: `docs/specs/SPEC-198-config-surface.md`, `docs/specs/SPEC-248-operator-config.md`.
