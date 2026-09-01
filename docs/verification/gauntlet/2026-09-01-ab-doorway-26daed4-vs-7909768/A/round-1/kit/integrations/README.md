# Terminal integrations

Discoverability wrappers over the kit's runtime-agnostic `<subsystem> <verb>` CLI (`bin/board`,
`bin/spec`, ...) and its two entry-point slash commands (`/kit:start`, `/kit:ship`). Static files
only; nothing here installs itself.

- `warp/workflows/*.yaml` , drop into `~/.warp/workflows/` (or submit to
  [warpdotdev/workflows](https://github.com/warpdotdev/workflows)) for `start`, `board`, `spec`,
  `ship` as Warp Workflows.
- `raycast/` , a Raycast extension manifest + commands for the same four verbs. Open the folder
  with `ray develop` (Raycast CLI, `npm install -g @raycast/api`) to run it locally, or `ray build`
  before submitting to the Raycast Store.

`board` and `spec` shell out straight to `$DWARVES_KIT/bin/<verb>` (falls back to
`~/.claude/dwarves-kit`, the default bash-install path). `start` and `ship` are Claude Code slash
commands with no standalone CLI, so their wrappers launch `claude "/kit:<verb>"` in a terminal.
