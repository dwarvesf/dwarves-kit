# Claude Code integration

Opt-in mod for Claude Code. Display only: it shells out to the kit's `bin/board` and draws the output in a side pane. It writes nothing and installs nothing.

- `board-pane/` , a function-hook plugin that adds `/board`: a side pane over every repo in your board registry, plus a one-line summary band above the prompt.

## Enable

The bash installer loads the board pane in every session. `bash install.sh` copies the mod into `~/.claude/dwarves-kit/integrations/claude-code/board-pane` and appends that path to `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` (joined with `:`, never duplicated, other entries kept). Pass `--no-mods` to skip it. `bash install.sh --uninstall` removes only that path (the copy or the checkout path) and the copied files.

On a machine that also has the Claude Code plugin, `bash install.sh` runs in compat mode and registers the checkout's own `integrations/claude-code/board-pane` instead, so the mod runs live from the checkout like the `bin` and `lib` links. A pure marketplace install with no checkout cannot register a second plugin dir, so it does not load the pane. Enable it by hand with either:

```bash
claude --plugin-dir /path/to/dwarves-kit/integrations/claude-code/board-pane
```

```json
{ "env": { "CLAUDE_CODE_PLUGIN_DIRS": "/path/to/dwarves-kit/integrations/claude-code/board-pane" } }
```

## Use

One call feeds the pane: `bin/board all board --registry <registry> --repo-root <cwd>`. The registry is `$BOARD_REGISTRY` (an absolute path, `~` expanded) or else `<cwd>/_meta/boards.txt`. Each registry row is `<name> <BACKLOG path> ...`, and an optional `rail=<x>` token in any column groups the repo.

| Command | Opens |
|---|---|
| `/board` | the overview: repos grouped by rail, the current repo first and marked `◉` |
| `/board here` | the view of the repo you are in |
| `/board <name>` | the view of that registry repo |

The overview header counts repos, in-flight and queued items. Below the filter, NEXT lists up to five picks across repos from `bin/board all priority overview`: DO NOW (`!`) first, then URGENT (`▲`), then QUICK WINS (`+`), each as `<glyph> <ID> <title>  <repo>`. NEXT rows take hotkeys 1 to 5 and the repo rows follow, so 1 to 9 always match the visible rows in order. NEXT is hidden when the priority view has no rows or fails; the rest of the pane still renders. Each repo row shows its active and queued counts, `↓N` when its checkout is behind upstream, and its first in-flight (else first queued) item when the pane is 70 columns or wider. Repos with nothing in flight or queued fold into one dim `idle` row. A repo view lists in-flight work first (executing, validated, speccing, claimed), then the first eight queued items with a `+ N more` button for the rest. Shipped, parked and dropped items are hidden.

| Key | Does |
|---|---|
| `1` to `9` | open that repo (overview) or fill the prompt for that item (repo view) |
| `b` | back to the overview |
| `r` | refresh now; the pane also re-runs itself every 60 seconds while open |
| `q` | close the pane |

Pressing an item puts `Work on <ID> in <repo>` in the prompt box (`Work on <ID>` for the current repo). Nothing runs until you press Enter. The filter box narrows repos or items as you type. With no readable registry, or when `all board` fails, the pane falls back to the current repo alone with a dim hint to set `BOARD_REGISTRY`.

A one-line summary band sits above the prompt: `tasks 14q 3act · 9ho · 15wt (12 stale) · 1pr` (q queued, act in flight, ho handoff files, wt worktrees, pr open PRs), all for the session's repo. A worktree is stale when its branch is merged into the default branch or its tip is older than 14 days (a detached one counts by its HEAD commit age; the main checkout is never counted). The stale part drops when the git lookups fail, and the count stays. Counts come from `bin/board board`, the `.claude/handoffs/` folder, `git worktree list` and `gh pr list --author @me`. A segment whose source is missing or fails is skipped, and the band disappears when every one is. It refreshes on session start and after each main-loop turn; the PR count is cached for five minutes. Each segment is a button; a press fills the prompt and never submits.

| Key (after `ctrl+x tab`) | Segment | Fills the prompt with |
|---|---|---|
| `b` | `tasks` | opens the current repo's view; a second press closes the pane |
| `h` | `ho` | a request to list the open handoffs, oldest first |
| `w` | `wt` | a request to tidy the stale worktrees |
| `p` | `pr` | a request to review the open PRs |

The CLI resolves as `$DWARVES_KIT/bin/board`, falling back to `~/.claude/dwarves-kit/bin/board`. A non-zero exit shows the CLI's stderr, dimmed, in the pane.

## Develop

```bash
claude plugin validate integrations/claude-code/board-pane
claude plugin test integrations/claude-code/board-pane
```

Claude Code writes `.claude-plugin/types/` beside the mod when it loads it. That folder is gitignored; `tsc -p` needs it.
