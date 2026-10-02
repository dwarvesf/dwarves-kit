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

Press an item row (or its digit hotkey, 1 to 9) to put `Work on <ID>` (`Work on <ID> in <repo>` in `all` mode) in the prompt box; nothing runs until you press Enter. `Esc` returns focus to the prompt, `q` closes the pane, `r` refreshes, and the pane re-renders itself every 60 seconds while it is open. In `all` mode a repo whose checkout lags upstream is dimmed with a trailing `?`, repos with nothing queued fold into one `+N idle` row, and a header shows the refresh time. In repo mode `executing:` items carry a cyan marker and `claimed:` items a yellow one.

A one-line summary band sits above the prompt: `tasks 14 queued · 3 executing  ·  9 handoffs  ·  15 worktrees  ·  1 PR open`, all for the session's repo. Counts come from `bin/board board`, the `.claude/handoffs/` folder, `git worktree list` and `gh pr list --author @me`. A segment whose source is missing or fails is skipped, and the band disappears when every one is. It refreshes on session start and after each main-loop turn; the PR count is cached for five minutes. Press `tasks` to open the pane.

The CLI resolves as `$DWARVES_KIT/bin/board`, falling back to `~/.claude/dwarves-kit/bin/board`. A non-zero exit shows the CLI's stderr, dimmed, in the pane.

## Develop

```bash
claude plugin validate integrations/claude-code/board-pane
claude plugin test integrations/claude-code/board-pane
```

Claude Code writes `.claude-plugin/types/` beside the mod when it loads it. That folder is gitignored; `tsc -p` needs it.
