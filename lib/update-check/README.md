# update-check

A `SessionStart` (matcher `startup`) hook that tells the user when a newer dwarves-kit release exists. One line, once per session. It never installs anything: updating stays an explicit command.

**Hook-only module.** The code lives in `hooks/kit-update-notice.sh` (bash + jq + curl). This directory is the module's doc home: `SPEC.md` is the contract, `docs/proof-of-done.md` is the acceptance record. The module is `core`: on for a fresh install and a fresh adopt.

| What | Where |
|---|---|
| The hook | `hooks/kit-update-notice.sh` |
| Module -> hook map | `lib/config/modules.tsv` (`update_check`) |
| Registration | `hooks/hooks.json` (plugin) and `settings.json` (install.sh), both matcher `startup`, timeout 5 |
| Test | `tests/test-update-check-notice.sh` |

## What the user sees

```
dwarves-kit 2.4.0 is available (installed: 2.3.0). Run: claude plugin marketplace update dwarves-marketplace && claude plugin update kit@dwarves-marketplace, then restart Claude Code.
```

Outside plugin mode (`CLAUDE_PLUGIN_ROOT` unset) the command part reads `Pull the dwarves-kit checkout and re-run install.sh, then restart Claude Code.`

## Turning it off

| Knob | Effect |
|---|---|
| `KIT_UPDATE_CHECK=0` | the hook exits at once, no fetch, no cache |
| `[modules] update_check = false` in a project `.kit.toml`, the operator `kit.toml`, or the kit-root `kit.toml` | `hooks/anchor-root.sh` skips the hook, the same toggle every non-spine hook honors |
