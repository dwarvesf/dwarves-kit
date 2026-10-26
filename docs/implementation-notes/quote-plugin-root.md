# Implementation notes -- quote-plugin-root

No spec: a mechanical fix, quoting every `${CLAUDE_PLUGIN_ROOT}` path in `hooks/hooks.json`. It rides the full lane only because `hooks/hooks.json` is a hard path.

- The hook-command parsers also changed: `lib/registry/feature-registry.sh` (`hook_events` would list every hook with no event), `tests/test-hook-anchor.sh`, `tests/test-hooks.sh`, `tests/test-meta-plugin-hooks.sh`, `tests/test-modules-table.sh`. Each strips or tolerates the double quote and checks the same thing as before.
- `settings.json`, `install.sh`, `lib/adopt.sh` and `lib/wrap/wrap-adopt.sh` are untouched: they write `$HOME/.claude/dwarves-kit/...`, which breaks only for a home directory with a space. `hooks/codex-hooks.json` already quotes `${PLUGIN_ROOT}`.
- `docs/reference/FEATURES.md` regenerated: the new suite names `safety-gate.sh` and `ship-gate.sh`, which bumps their test counts.
