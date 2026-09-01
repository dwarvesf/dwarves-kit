---
title: Claude Code plugin install source types, local-directory limitation, and the --plugin-dir author workflow (CC 2.1.148)
date: 2026-05-22
purpose: Reference for how Claude Code resolves plugin commands (namespace vs flat), which marketplace source types it can install, why a local directory-source plugin install fails on 2.1.148, and the supported way for a plugin AUTHOR to get the plugin namespace plus live edits. Use when authoring or distributing a CC plugin, deciding installer vs plugin distribution, or debugging "this plugin uses a source type your Claude Code version does not support".
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: as-needed
next_review: 2026-11-22
status: active
---

# CC plugin install: source types, local-dir limitation, --plugin-dir (CC 2.1.148)

Discovered while migrating dwarves-kit from its bash installer to plugin distribution. Verified on Claude Code 2.1.148 (native installer; also the latest on npm as of 2026-05-22).

## 1. How a command's source label is produced

A slash command shows up **namespaced** (`plugin-name:command`) when it is provided by an installed/loaded **plugin**. CC derives the namespace from the plugin's `plugin.json` `name`, automatically. It is NOT produced by a `(prefix)` in the command's `description:`.

- superpowers, ouroboros, etc. show as `superpowers:brainstorming`, `ouroboros:run` because they are plugins.
- A command copied flat into `~/.claude/commands/<name>.md` (the bash-installer pattern) resolves **bare**: `/<name>`. No namespace, because there is no plugin.
- `/user:<name>` is not a real resolution form in CC 2.x; it was stale doc convention. It returns "unknown command".

Implication: to get `/kit:kit-health`, the kit must be loaded *as a plugin*, not copied flat.

## 2. Marketplace source types CC 2.1.148 can install

`/plugin marketplace add <X>` registers a marketplace. `X` can be a github repo or a local directory; both register fine. The catch is at **install** time, gated on the plugin's `source` field in `marketplace.json`:

| Plugin `source` in marketplace.json | Installs on 2.1.148? |
|---|---|
| `{"source": "github", "repo": "owner/repo"}` | yes (all known working plugins use this) |
| `{"source": "git", "url": "..."}` | yes (documented) |
| `{"source": "directory", "path": "..."}` / bare `"."` from a local-directory marketplace | **NO** |

A local-directory marketplace whose plugin uses `source: "."` (plugin code = marketplace repo root) fails install with:

```
Failed to install: This plugin uses a source type your Claude Code version does not support.
Update Claude Code and try again.
```

The "Update Claude Code" advice is misleading: 2.1.148 was already the latest published version, so there was nothing to update to. Local directory-source plugin install simply is not supported in this version (may land in a future one).

## 3. GitHub-source installs are frozen at a commit SHA

Installing from a github-source marketplace pins the plugin to a commit SHA (recorded in `~/.claude/plugins/installed_plugins.json` as `gitCommitSha`). Local working-copy edits do NOT show up. To refresh: push, then `/plugin marketplace update` + `/plugin install` (or auto-update if enabled). Good for end users, bad for the plugin author who edits constantly.

## 4. The author workflow: `--plugin-dir` (live edits + namespace)

CC 2.1.148 has `--plugin-dir <path>` ("Load a plugin from a directory or .zip for this session only"; repeatable). It loads the plugin from a working directory, giving:

- the `plugin-name:command` namespace (from `plugin.json` name), AND
- live edits: change a file, run `/reload-plugins`, no restart, no git push.

Limitation: it is a per-session flag. No `settings.json` key persists it across sessions in 2.1.148 (no `localPluginDirs` equivalent). Make it stick with a shell wrapper. fish example (override `claude` globally, with a guard + plain-claude escape via `command claude`):

```fish
function claude --wraps claude --description 'claude + <plugin> (live; `command claude` for plain)'
    set -l kit /abs/path/to/plugin-repo
    if test -f $kit/.claude-plugin/plugin.json
        command claude --plugin-dir $kit $argv
    else
        command claude $argv
    end
end
```

Related flags from `--help`: `--plugin-url <url>` (fetch a .zip per session), `--bare` (skip plugin sync; can still take explicit `--plugin-dir`).

## 5. Decision matrix: author who wants namespace AND live edits

| Path | Namespace | Live edits | Persistence | Use for |
|---|---|---|---|---|
| `--plugin-dir` + shell wrapper | yes | yes | per-session (wrap it) | plugin AUTHOR / maintainer |
| github-source marketplace install | yes | no (frozen at SHA) | persistent | END USERS |
| flat copy into `~/.claude/commands/` (bash installer) | no, bare `/cmd` | yes (if symlinked) | persistent | legacy; drops the namespace |
| local directory-source marketplace install | n/a | n/a | BLOCKED on 2.1.148 | not available |

On 2.1.148, an author cannot get namespace + live edits + cross-session persistence without a shell wrapper. There is no native persistent local-plugin mode yet.

## Applied to dwarves-kit (2026-05-22)

- Bash installer uninstalled (`bash install.sh --uninstall`; clean, verified it only stripped kit-owned artifacts and left personal hooks intact).
- Local directory marketplace `dwarves-marketplace` add succeeded but `/plugin install` failed per section 2.
- Plugin `name` set to `kit` in `plugin.json` + `marketplace.json` (so the namespace is `/kit:`), shortened from `dwarves-kit`; the github repo / project name stays `dwarves-kit`. Install: `/plugin install kit@dwarves-marketplace`. Note `user` was rejected as a name: reserved prefix, collides with personal-command resolution.
- Resolution: `~/.config/fish/functions/claude.fish` wrapper applies `--plugin-dir ~/workspace/<owner>/dwarves-kit` globally. Gives `/kit:<cmd>` + live edits.
- End-user distribution for the kit should be the github-source marketplace (`dwarvesf/dwarves-kit`).
- Folded into dwarves-kit backlog ID-031 (the original "add a `(dwarves-kit)` description prefix" task is obsolete: plugin auto-namespaces).
