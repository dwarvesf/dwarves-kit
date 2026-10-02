# Claude Code integration

Opt-in mod for Claude Code. Display only: it shells out to the kit's `bin/board` and draws the output in a side pane. It writes nothing and installs nothing.

- `board-pane/` , a function-hook plugin that adds `/board`. The pane has a Refresh button that re-runs the same view.

## Enable

Pass the folder for one session:

```bash
claude --plugin-dir /path/to/dwarves-kit/integrations/claude-code/board-pane
```

Or load it every session through `~/.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_PLUGIN_DIRS": "/path/to/dwarves-kit/integrations/claude-code/board-pane" } }
```

## Use

| Command | Runs | Shows |
|---|---|---|
| `/board` | `bin/board board --backlog-file <cwd>/_meta/BACKLOG.md` | the kanban of the session's repo |
| `/board all` | `bin/board all next --repo-root <cwd>` | the cross-repo view, from the `boards.txt` registry in that repo |

The CLI resolves as `$DWARVES_KIT/bin/board`, falling back to `~/.claude/dwarves-kit/bin/board`. A non-zero exit shows the CLI's stderr, dimmed, in the pane.

## Develop

```bash
claude plugin validate integrations/claude-code/board-pane
claude plugin test integrations/claude-code/board-pane
```

Claude Code writes `.claude-plugin/types/` beside the mod when it loads it. That folder is gitignored; `tsc -p` needs it.
