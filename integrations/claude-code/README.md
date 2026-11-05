# Claude Code integration

Mods for Claude Code, loaded by `bash install.sh`. `board-pane` is the kit's own display mod: it shells out to the kit's `bin/board` and draws the output in a side pane. It writes nothing. The other four are vendored third-party mods, each pinned to a source commit with its local patches listed in its `VENDORED.md`.

- `board-pane/` , a function-hook plugin that adds `/board`: a side pane over every repo in your board registry, plus a one-line summary band above the prompt.
- `secrets-veil/` , masks secret values in tool results before the model reads them.
- `memory-lens/` , recalls the few memories related to each prompt.
- `loop-detective/` , flags repeated Bash failures.
- `context-inspector/` , shows what fills the context window.

## Enable

The bash installer loads all five mods in every session. `bash install.sh` copies each mod into `~/.claude/dwarves-kit/integrations/claude-code/<name>` (the manifest, hooks, `src`, `LICENSE` and `VENDORED.md`; tests stay in the checkout) and appends that path to `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` (joined with `:`, never duplicated, other entries kept). Pass `--no-mods` to skip them all. `bash install.sh --uninstall` removes only the kit's paths (the copies and the checkout paths) and the copied files.

**Duplicate guard.** If `env.CLAUDE_CODE_PLUGIN_DIRS` already holds an entry that loads a plugin of the same name, the installer skips that mod and prints `[skip] <name> already loaded from <entry>`. The name is the `name` in the entry's `.claude-plugin/plugin.json` (the folder name when there is no manifest), and a leading `~` is your home folder. A kit entry for that mod added earlier is removed from the list, so one plugin never loads twice.

On a machine that also has the Claude Code plugin, `bash install.sh` runs in compat mode and registers the checkout's own `integrations/claude-code/<name>` paths instead, so the mods run live from the checkout like the `bin` and `lib` links. The duplicate guard applies there too. A pure marketplace install with no checkout cannot register a second plugin dir, so it does not load the mods. Enable one by hand with either:

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

## Vendored mods

Each folder carries the upstream `LICENSE` and a `VENDORED.md` with the source, the pinned commit, what was read before vendoring, and every local patch. To update one, re-read the upstream diff against the pin, copy the same files, and re-apply the patches.

### secrets-veil

Masks secret values in tool results before the model reads them: 21 named vendor variables, value shapes (vendor prefixes, `Bearer` tokens, PEM private keys) and high-entropy tokens. There is no reveal path. A toast says when a value was masked. No commands. It writes nothing. Source: orchestkit `mods/secrets-veil`, commit `1cf7bb4`, MIT.

### memory-lens

Adds the top three memories related to each prompt to the model's context and logs one line for you (to the debug log). Command: `/memory-lens` (`stats`, `reload`, `show <n>`). It reads memory files and writes nothing. It indexes `~/.claude/projects/<key>/memory/` and, only for a repo you list, the repo's `.claude/memory/`. List trusted repo prefixes, one absolute path per line, in `~/.claude/memory-lens/trusted-roots`; with no such file no repo store is read. An optional `~/.claude/memory-lens/private.json` (`{"clientTerms": [...]}`) is read if present. Source: orchestkit `mods/memory-lens`, commit `badfc82999e424b0445ba9db6a1e9aa2aed9e20f`, MIT.

### loop-detective

Opens a case when the same Bash command fails the same way three times in a row (or after repeated edit and retry cycles). Commands: `/loop-report [--agents] [--history]`, `/loop-pane`, `/loop-reset`. One toast per case. State stays in memory; it writes nothing. Failure output feeds a hash only and is never kept or shown. Source: YeonwooSung/my-claude-code-mods `loop-detective`, commit `f7da140f3fc63aa5c083f75cd48700517e882c68`, Apache-2.0.

### context-inspector

Shows what fills the context window, re-reads, near-duplicate outputs and what compaction kept, with advice. Commands: `/context-inspect [overview|occupants|rereads|similar|compactions|efficiency|advice] [--agents]`, `/context-pane`, `/context-export`. `/context-export` writes metadata-only JSONL to `~/.claude/context-inspector/<sessionId>/` (the `outputDir` plugin option changes it); file paths stay, every command, pattern, URL and agent description is a content hash. One toast per session at most. Source: YeonwooSung/my-claude-code-mods `context-inspector`, commit `f7da140f3fc63aa5c083f75cd48700517e882c68`, Apache-2.0.

## Develop

```bash
for mod in board-pane secrets-veil memory-lens loop-detective context-inspector; do
  claude plugin validate integrations/claude-code/$mod
  claude plugin test integrations/claude-code/$mod
done
```

Claude Code writes `.claude-plugin/types/` beside the mod when it loads it. That folder is gitignored; `tsc -p` needs it.
